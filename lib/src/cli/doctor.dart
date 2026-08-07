import 'dart:io';

import 'package:artisanal/args.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'package:code_assets/code_assets.dart';

import '../archive/archive_reader.dart';
import '../binary/binary_inspector.dart';
import '../binary/library_name.dart';
import '../build/toolchains/toolchain_registry.dart';
import '../config/native_prebuilt_config.dart';
import '../platform/native_target.dart';
import 'cli_config.dart';
import 'shared.dart';

class DoctorCommand extends Command<void> {
  DoctorCommand() {
    argParser.addOption('config', abbr: 'c', help: 'Path to YAML config file.');
    argParser.addOption('manifest', help: 'Path to generated manifest (g.dart or lock.yaml).');
    argParser.addOption('built-library-dir', help: 'Path to built-library directory.');
    argParser.addOption('release-assets-dir', help: 'Path to release-assets directory.');
    argParser.addOption('target', help: 'Check toolchain readiness for target (e.g., android-arm64).');
    argParser.addFlag('strict', help: 'Fail on flat built-library layout.');
  }

  @override
  String get name => 'doctor';

  @override
  String get description => 'Validate configuration and io.info a summary.';

  @override
  Future<void> run() async {
    final configFile =
        resolveConfigFile(option('config') as String?) ??
        (throw UsageException(
          'Could not find native_prebuilt.yaml. Pass --config explicitly.',
          usage,
        ));
    final config = await loadNativePrebuiltConfig(configFile);
    io.info(renderDoctorSummary(config));

    final manifestPath = option('manifest') as String?;
    final builtLibraryDirPath = option('built-library-dir') as String?;
    final releaseAssetsDirPath = option('release-assets-dir') as String?;
    final targetLabel = option('target') as String?;
    final strict = (option('strict') as bool?) ?? false;

    var hasError = false;
    var hasDrift = false;

    // Pubspec version drift check
    final pubspecFile = _findPubspec(configFile.parent);
    if (pubspecFile != null) {
      final drift = _checkPubspecDrift(pubspecFile, config);
      if (drift != null) {
        io.info(drift);
        hasDrift = true;
      }
    }

    // Manifest validation if provided
    if (manifestPath != null) {
      final mFile = File(manifestPath);
      if (!mFile.existsSync()) {
        stderr.writeln('Manifest not found: $manifestPath');
        exitCode = 1;
        hasError = true;
      } else {
        final manifestDrift = await _checkManifestDrift(
          mFile,
          config,
          builtLibraryDirPath != null ? Directory(builtLibraryDirPath) : null,
          releaseAssetsDirPath != null ? Directory(releaseAssetsDirPath) : null,
          strict: strict,
        );
        if (manifestDrift.isNotEmpty) {
          for (final line in manifestDrift) {
            stderr.writeln(line);
          }
          hasDrift = true;
        }
      }
    } else if (builtLibraryDirPath != null || releaseAssetsDirPath != null) {
      // Even without explicit manifest, check built-library / release-assets vs lock if present
      final lockFile = resolveLockFile(null, configFile.parent);
      if (lockFile != null && lockFile.existsSync()) {
        final drift = await _checkManifestDrift(
          lockFile,
          config,
          builtLibraryDirPath != null ? Directory(builtLibraryDirPath) : null,
          releaseAssetsDirPath != null ? Directory(releaseAssetsDirPath) : null,
          strict: strict,
        );
        if (drift.isNotEmpty) {
          for (final line in drift) {
            stderr.writeln(line);
          }
          hasDrift = true;
        }
      }
    }

    // Target toolchain readiness
    if (targetLabel != null) {
      final target = parseTarget(targetLabel);
      if (target == null) {
        stderr.writeln('Unknown target: $targetLabel');
        exitCode = 1;
        hasError = true;
      } else {
        final readiness = _checkTargetReadiness(target);
        io.info(readiness);
        if (readiness.contains('missing')) {
          hasError = true;
        }
      }
    }

    if (hasDrift) {
      stderr.writeln(
        'Drift detected. Run: dart run native_prebuilt manifest update --tag ${config.release.tag}',
      );
      exitCode = 2;
    } else if (hasError) {
      exitCode = 1;
    }
  }
}

String renderDoctorSummary(NativePrebuiltConfig config) {
  final b = StringBuffer()
    ..writeln('package: ${config.package}')
    ..writeln('release: ${config.release.toReleaseSource()}')
    ..writeln('artifacts: ${config.artifacts.length}');
  for (final entry in config.artifacts.entries) {
    b.writeln(
      '  - ${entry.key}: archive=${entry.value.archive}, payload=${entry.value.payload.type}',
    );
  }
  return b.toString().trimRight();
}

File? _findPubspec(Directory dir) {
  var cur = dir.absolute;
  while (true) {
    final candidate = File(p.join(cur.path, 'pubspec.yaml'));
    if (candidate.existsSync()) return candidate;
    final parent = cur.parent;
    if (parent.path == cur.path) return null;
    cur = parent;
  }
}

String? _checkPubspecDrift(File pubspecFile, NativePrebuiltConfig config) {
  try {
    final yaml = loadYaml(pubspecFile.readAsStringSync());
    if (yaml is! YamlMap) return null;
    final version = yaml['version'] as String?;
    if (version == null) return null;
    final tag = config.release.tag;
    // Check if version appears as suffix of tag (e.g., tag tdlib-v1.8.65 vs version 1.8.65)
    if (tag.isNotEmpty && !tag.endsWith(version)) {
      // Only report if tag looks versioned
      final versionPattern = RegExp(r'v?\d+\.\d+\.\d+');
      if (versionPattern.hasMatch(tag)) {
        return 'Pubspec drift: version $version != tag $tag (expected tag to end with version)';
      }
    }
  } catch (_) {}
  return null;
}

Future<List<String>> _checkManifestDrift(
  File manifestFile,
  NativePrebuiltConfig config,
  Directory? builtLibraryDir,
  Directory? releaseAssetsDir, {
  required bool strict,
}) async {
  final issues = <String>[];
  final content = manifestFile.readAsStringSync();
  // Check tag drift
  if (!content.contains(config.release.tag)) {
    issues.add('Manifest tag drift: ${manifestFile.path} does not contain ${config.release.tag}');
  }
  // Check built-library hashes if dir provided
  if (builtLibraryDir != null && builtLibraryDir.existsSync()) {
    for (final entry in config.artifacts.entries) {
      final platform = entry.key;
      final artifact = entry.value;
      final target = targetFromPlatformLabel(platform);
      final payload = artifact.payload.toArtifactPayload(config.libraryStem);
      final canonicalName = canonicalLibraryName(
        target: target,
        libraryStem: config.libraryStem,
        payload: payload,
      );
      final builtFile = File(p.join(builtLibraryDir.path, platform, canonicalName));
      final flatFile = File(p.join(builtLibraryDir.path, canonicalName));
      File? candidate;
      if (builtFile.existsSync()) {
        candidate = builtFile;
      } else if (!strict && flatFile.existsSync()) {
        candidate = flatFile;
        issues.add('Flat layout for $platform at ${flatFile.path} (prefer ${builtFile.path})');
      }
      if (candidate != null) {
        try {
          final hash = await ArchiveReader.sha256Hash(candidate);
          if (!content.contains(hash) && !content.contains(hash.substring(0, 16))) {
            issues.add('Built-library hash mismatch for $platform: $hash not in manifest');
          }
          // Binary triple check
          try {
            const NativeBinaryInspector().inspect(
              candidate,
              target: target,
              canonicalName: canonicalName,
            );
          } on BinaryFormatException catch (e) {
            issues.add('Binary format mismatch for $platform: $e');
          } on BinaryArchitectureException catch (e) {
            issues.add('Binary architecture mismatch for $platform: $e');
          }
        } catch (e) {
          issues.add('Failed to hash $platform: $e');
        }
      }
    }
  }
  if (releaseAssetsDir != null && releaseAssetsDir.existsSync()) {
    for (final entry in config.artifacts.entries) {
      final archiveFile = File(p.join(releaseAssetsDir.path, entry.value.archive));
      if (archiveFile.existsSync()) {
        final hash = await ArchiveReader.sha256Hash(archiveFile);
        if (!content.contains(hash)) {
          issues.add('Release asset hash mismatch for ${entry.key}: $hash not in manifest');
        }
      }
    }
  }
  return issues;
}

String _checkTargetReadiness(NativeTarget target) {
  final resolver = const NativeToolchainResolver();
  final b = StringBuffer()..writeln('Target: ${target.label}');
  if (target.os == OS.android) {
    final hasNdk = resolver.hasAndroidNdk;
    b.writeln('  Android NDK: ${hasNdk ? "found" : "missing (set ANDROID_NDK_HOME)"}');
    final toolchain = resolver.cmakeToolchainFile(target);
    b.writeln('  Toolchain: ${toolchain ?? "missing"}');
    final strip = resolver.stripCommand(target);
    b.writeln('  Strip: ${strip.join(" ")}');
    if (!hasNdk) b.writeln('  -> missing NDK');
  } else if (target.os == OS.iOS || target.os == OS.macOS) {
    b.writeln('  Apple SDK: xcrun available check skipped');
    b.writeln('  Strip: ${resolver.stripCommand(target).join(" ")}');
  } else if (target.os == OS.windows) {
    b.writeln('  MSVC: check skipped');
    b.writeln('  Strip: ${resolver.stripCommand(target).join(" ")}');
  } else {
    b.writeln('  Strip: ${resolver.stripCommand(target).join(" ")}');
  }
  return b.toString().trimRight();
}
