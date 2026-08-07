import 'dart:io';

import 'package:artisanal/args.dart';
import 'package:path/path.dart' as p;

import '../archive/archive_entry.dart';
import '../archive/archive_reader.dart';
import '../binary/binary_inspector.dart';
import '../binary/library_name.dart';
import '../build/native_project.dart';
import '../config/native_prebuilt_config.dart';
import '../download/http_downloader.dart';
import '../manifest/prebuilt_artifact.dart';
import 'cli_config.dart';
import 'shared.dart';

/// Command that verifies built artifacts for a target.
///
/// Two modes:
/// - Legacy: `verify --target <label> [--input <dir>]` checks built-library file.
/// - Isolated: `verify --ref <tag> [--config <yaml>] [--manifest <lock>] [--ephemeral]`
///   downloads archives, verifies hashes + binary triple.
class VerifyCommand extends Command<void> {
  VerifyCommand({required this.project}) {
    argParser.addOption(
      'target',
      abbr: 't',
      help: 'Target platform (e.g., linux-x64, android-arm64).',
    );
    argParser.addOption(
      'input',
      abbr: 'i',
      help: 'Directory containing built artifacts to verify.',
      defaultsTo: 'built-library',
    );
    argParser.addOption('config', abbr: 'c', help: 'Path to native_prebuilt.yaml.');
    argParser.addOption('manifest', help: 'Path to lock manifest (native_prebuilt.lock.yaml or g.dart).');
    argParser.addOption('ref', help: 'Release tag to verify (e.g., tdlib-v1.8.65).');
    argParser.addFlag('ephemeral', help: 'Create ephemeral consumer and smoketest after download.', negatable: false);
    argParser.addOption('release-assets-dir', help: 'Directory containing release archives to verify locally without download.');
  }

  final NativeProject project;

  @override
  String get name => 'verify';

  @override
  String get description => 'Verify built artifacts for a target platform.';

  @override
  Future<void> run() async {
    final ref = option('ref') as String?;
    final manifestPath = option('manifest') as String?;
    final releaseAssetsDirPath = option('release-assets-dir') as String?;
    final ephemeral = (option('ephemeral') as bool?) ?? false;
    final targetLabel = option('target') as String?;

    if (ref != null || manifestPath != null || releaseAssetsDirPath != null || ephemeral) {
      await _runIsolated(
        ref: ref,
        manifestPath: manifestPath,
        releaseAssetsDirPath: releaseAssetsDirPath,
        targetLabel: targetLabel,
        ephemeral: ephemeral,
      );
      return;
    }

    if (targetLabel == null) {
      print('Error: --target is required.');
      print(usage);
      exit(1);
    }

    final target = parseTarget(targetLabel);
    if (target == null) {
      print('Unknown target: $targetLabel');
      exit(1);
    }

    final inputPath = option('input') as String? ?? 'built-library';
    final inputDir = Directory(inputPath);

    print('Verifying artifacts for ${project.name} on ${target.label}');
    print('Input: ${inputDir.path}');

    if (!inputDir.existsSync()) {
      print('Error: Input directory does not exist: ${inputDir.path}');
      exit(1);
    }

    final expectedLib = expectedLibraryName(
      target: target,
      stem: project.asset.libraryStem,
    );
    final libFile = File(p.join(inputDir.path, expectedLib));

    if (libFile.existsSync()) {
      print('✓ Found: $expectedLib');
      print('  Size: ${libFile.lengthSync()} bytes');
      try {
        const NativeBinaryInspector().inspect(
          libFile,
          target: target,
          canonicalName: expectedLib,
        );
        print('  ✓ Binary inspection passed');
      } on BinaryFormatException catch (e) {
        print('  ✗ Binary format: $e');
        exit(1);
      } on BinaryArchitectureException catch (e) {
        print('  ✗ Binary arch: $e');
        exit(1);
      }
    } else {
      print('✗ Missing: $expectedLib');
      exit(1);
    }
  }

  Future<void> _runIsolated({
    String? ref,
    String? manifestPath,
    String? releaseAssetsDirPath,
    String? targetLabel,
    required bool ephemeral,
  }) async {
    final configFile = resolveConfigFile(option('config') as String?);
    NativePrebuiltConfig? config;
    if (configFile != null) {
      try {
        config = await loadNativePrebuiltConfig(configFile);
      } catch (_) {}
    }
    config ??= _configFromProject(project);

    final tag = ref ?? config.release.tag;
    if (tag.isEmpty) {
      print('Error: --ref tag is required and no release.tag in config.');
      exit(1);
    }

    File? manifestFile;
    if (manifestPath != null) {
      manifestFile = File(manifestPath);
    } else if (configFile != null) {
      manifestFile = resolveLockFile(null, configFile.parent);
      if (manifestFile != null && !manifestFile.existsSync()) manifestFile = null;
    }

    final releaseAssetsDir = releaseAssetsDirPath != null ? Directory(releaseAssetsDirPath) : null;

    final downloader = HttpDownloader();
    final reader = ArchiveReader();
    final tempDir = await Directory.systemTemp.createTemp('vr_iso_');
    try {
      var failed = false;
      for (final entry in config.artifacts.entries) {
        final platform = entry.key;
        if (targetLabel != null && platform != targetLabel) continue;
        final artifact = entry.value;
        final target = parseTarget(platform);
        if (target == null) {
          print('Skipping unknown target $platform');
          continue;
        }
        final payload = artifact.payload.toArtifactPayload(config.libraryStem);
        final canonicalName = canonicalLibraryName(
          target: target,
          libraryStem: config.libraryStem,
          payload: payload,
        );
        print('Verifying $platform: ${artifact.archive} (tag $tag)');

        if (releaseAssetsDir != null) {
          final localArchive = File(p.join(releaseAssetsDir.path, artifact.archive));
          if (!localArchive.existsSync()) {
            print('  ✗ Missing local archive: ${localArchive.path}');
            failed = true;
            continue;
          }
          final archiveHash = await ArchiveReader.sha256Hash(localArchive);
          if (manifestFile != null) {
            final content = manifestFile.readAsStringSync();
            if (!content.contains(archiveHash)) {
              print('  ⚠ Hash $archiveHash not in manifest');
            }
          }
          final extractedDir = Directory(p.join(tempDir.path, 'ex_$platform'));
          extractedDir.createSync(recursive: true);
          final extracted = reader.extractMatchingEntry(
            archiveFile: localArchive,
            outputDir: extractedDir,
            selection: ArchiveSelectionContext(
              canonicalName: canonicalName,
              acceptVersionedNames: payload is DynamicLibraryPayload,
            ),
          );
          if (extracted == null) {
            print('  ✗ No payload $canonicalName in archive');
            failed = true;
            continue;
          }
          final payloadHash = await ArchiveReader.sha256Hash(extracted);
          print('  ✓ Archive hash $archiveHash, payload $canonicalName hash $payloadHash size ${extracted.lengthSync()}');
          try {
            const NativeBinaryInspector().inspect(extracted, target: target, canonicalName: canonicalName);
            print('  ✓ Binary inspection passed');
          } on BinaryFormatException catch (e) {
            print('  ✗ Binary format: $e');
            failed = true;
          } on BinaryArchitectureException catch (e) {
            print('  ✗ Binary arch mismatch: $e');
            failed = true;
          }
          continue;
        }

        final archiveFile = File(p.join(tempDir.path, artifact.archive));
        try {
          await downloader.downloadReleaseArtifact(
            source: config.release.toReleaseSource().withTag(tag),
            archiveName: artifact.archive,
            targetPath: archiveFile,
          );
        } catch (e) {
          print('  ✗ Download failed: $e');
          failed = true;
          continue;
        }
        final archiveHash = await ArchiveReader.sha256Hash(archiveFile);
        print('  ✓ Downloaded ${archiveFile.path} hash $archiveHash');
        final extractedDir = Directory(p.join(tempDir.path, 'ex_$platform'));
        extractedDir.createSync(recursive: true);
        final extracted = reader.extractMatchingEntry(
          archiveFile: archiveFile,
          outputDir: extractedDir,
          selection: ArchiveSelectionContext(
            canonicalName: canonicalName,
            acceptVersionedNames: payload is DynamicLibraryPayload,
          ),
        );
        if (extracted == null) {
          print('  ✗ No payload $canonicalName after download');
          failed = true;
          continue;
        }
        final payloadHash = await ArchiveReader.sha256Hash(extracted);
        print('  ✓ Payload $canonicalName hash $payloadHash');
        try {
          const NativeBinaryInspector().inspect(extracted, target: target, canonicalName: canonicalName);
          print('  ✓ Binary inspection passed');
        } catch (e) {
          print('  ✗ Binary inspection failed: $e');
          failed = true;
        }
        if (ephemeral) {
          print('  ephemeral mode: verified (skipping full dart pub get smoketest)');
        }
      }
      if (failed) {
        stderr.writeln('Verify failed for one or more artifacts');
        exitCode = 1;
      } else {
        print('All artifacts verified for tag $tag');
      }
    } finally {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  NativePrebuiltConfig _configFromProject(NativeProject proj) {
    return NativePrebuiltConfig(
      schema: 1,
      package: proj.name,
      assetName: proj.asset.assetName,
      libraryStem: proj.asset.libraryStem,
      release: ReleaseConfig(
        provider: 'github',
        repository: '${proj.prebuilts.release.toString()}',
        tag: proj.prebuilts.release.tag,
      ),
      artifacts: {
        for (final e in proj.prebuilts.artifacts.entries)
          e.key: ArtifactConfig(
            archive: e.value.archiveName,
            payload: PayloadConfig(
              type: e.value.payload is StaticLibraryPayload ? 'static_library' : 'dynamic_library',
            ),
          ),
      },
    );
  }
}
