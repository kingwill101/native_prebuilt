import 'dart:io';

import 'package:artisanal/args.dart';
import 'package:path/path.dart' as p;

import '../archive/archive_reader.dart';
import '../binary/binary_inspector.dart';
import '../binary/library_name.dart';
import '../config/native_prebuilt_config.dart';
import '../manifest/prebuilt_manifest.dart';
import 'cli_config.dart';
import 'shared.dart';

class ManifestCommand extends Command<void> {
  ManifestCommand() {
    argParser.addOption('config', abbr: 'c', help: 'Path to YAML config file.');
    argParser.addOption('output', abbr: 'o', help: 'Output Dart file.');
    argParser.addOption('tag', help: 'Override the release tag.');
    argParser.addFlag('allow-missing', help: 'Allow missing artifacts.');
    addSubcommand(_ManifestUpdateCommand());
    addSubcommand(_ManifestVerifyCommand());
    addSubcommand(_ManifestVerifyReleaseCommand());
  }

  @override
  String get name => 'manifest';

  @override
  String get description => 'Generate or verify the Dart manifest.';

  @override
  Future<void> run() async {
    io.info(usage);
  }
}

class _ManifestUpdateCommand extends Command<void> {
  @override
  String get name => 'update';

  @override
  String get description => 'Generate the Dart manifest from the release.';

  _ManifestUpdateCommand() {
    argParser.addOption('config', abbr: 'c', help: 'Path to YAML config file.');
    argParser.addOption('output', abbr: 'o', help: 'Output Dart file.');
    argParser.addOption('tag', help: 'Override the release tag.');
    argParser.addOption(
      'built-library-dir',
      help: 'Path to built native libraries to package before release.',
    );
    argParser.addOption(
      'release-assets-dir',
      help: 'Optional output directory for release asset archives.',
    );
    argParser.addFlag('allow-missing', help: 'Allow missing artifacts.');
    argParser.addFlag(
      'strict',
      help:
          'Reject flat built-library layout; require <dir>/<platform>/<canonicalName>.',
    );
  }

  @override
  Future<void> run() async {
    final configFile =
        resolveConfigFile(option('config') as String?) ??
        (throw UsageException(
          'Could not find native_prebuilt.yaml. Pass --config explicitly.',
          usage,
        ));
    final config = await loadNativePrebuiltConfig(configFile);
    final outputPath = _resolveOutputPath(
      option('output') as String?,
      configFile,
      config,
    );
    final tag = (option('tag') as String?) ?? config.release.tag;
    final builtLibraryDirPath = option('built-library-dir') as String?;
    final builtLibraryDir = builtLibraryDirPath != null
        ? Directory(builtLibraryDirPath)
        : (config.build != null
              ? Directory(p.join(configFile.parent.path, 'built-library'))
              : null);

    final inferredLocalBuild =
        builtLibraryDirPath == null &&
        builtLibraryDir != null &&
        builtLibraryDir.existsSync();
    final allowMissing =
        (option('allow-missing') as bool?) ?? inferredLocalBuild;

    final releaseAssetsDirPath = option('release-assets-dir') as String?;
    final releaseAssetsDir = releaseAssetsDirPath != null
        ? Directory(releaseAssetsDirPath)
        : (config.build != null
              ? Directory(p.join(configFile.parent.path, 'release-assets'))
              : null);

    final strict = (option('strict') as bool?) ?? false;
    final manifest = await generateManifest(
      config: config,
      tag: tag,
      allowMissing: allowMissing,
      builtLibraryDir: builtLibraryDir,
      releaseAssetsDir: releaseAssetsDir,
      toleratePartialBuiltLibrary: inferredLocalBuild,
      strict: strict,
      logger: (m) => io.info(m),
    );

    final outputFile = File(outputPath);
    outputFile.parent.createSync(recursive: true);
    final content = renderManifestOutput(config, manifest, tag, outputPath);
    outputFile.writeAsStringSync(content);
    io.info('Wrote $outputPath');
  }
}

class _ManifestVerifyCommand extends Command<void> {
  @override
  String get name => 'verify';

  @override
  String get description => 'Verify the generated Dart manifest.';

  _ManifestVerifyCommand() {
    argParser.addOption('config', abbr: 'c', help: 'Path to YAML config file.');
    argParser.addOption('output', abbr: 'o', help: 'Output Dart file.');
    argParser.addOption('tag', help: 'Override the release tag.');
    argParser.addOption(
      'built-library-dir',
      help: 'Path to built native libraries to package before release.',
    );
    argParser.addOption(
      'release-assets-dir',
      help: 'Optional output directory for release asset archives.',
    );
    argParser.addFlag('allow-missing', help: 'Allow missing artifacts.');
    argParser.addFlag(
      'strict',
      help:
          'Reject flat built-library layout; require <dir>/<platform>/<canonicalName>.',
    );
  }

  @override
  Future<void> run() async {
    final configFile =
        resolveConfigFile(option('config') as String?) ??
        (throw UsageException(
          'Could not find native_prebuilt.yaml. Pass --config explicitly.',
          usage,
        ));
    final config = await loadNativePrebuiltConfig(configFile);
    final outputPath = _resolveOutputPath(
      option('output') as String?,
      configFile,
      config,
    );
    final tag = (option('tag') as String?) ?? config.release.tag;

    final builtLibraryDirPath = option('built-library-dir') as String?;
    final builtLibraryDir = builtLibraryDirPath != null
        ? Directory(builtLibraryDirPath)
        : (config.build != null
              ? Directory(p.join(configFile.parent.path, 'built-library'))
              : null);

    final releaseAssetsDirPath = option('release-assets-dir') as String?;
    final releaseAssetsDir = releaseAssetsDirPath != null
        ? Directory(releaseAssetsDirPath)
        : (config.build != null
              ? Directory(p.join(configFile.parent.path, 'release-assets'))
              : null);

    final inferredLocalBuild =
        builtLibraryDirPath == null &&
        builtLibraryDir != null &&
        builtLibraryDir.existsSync();
    final allowMissing =
        (option('allow-missing') as bool?) ?? inferredLocalBuild;
    final strict = (option('strict') as bool?) ?? false;
    final manifest = await generateManifest(
      config: config,
      tag: tag,
      allowMissing: allowMissing,
      builtLibraryDir: builtLibraryDir,
      releaseAssetsDir: releaseAssetsDir,
      toleratePartialBuiltLibrary: inferredLocalBuild,
      strict: strict,
      logger: (m) => io.info(m),
    );

    final actual = File(outputPath).readAsStringSync();
    if (inferredLocalBuild) {
      if (isLockManifestOutput(outputPath)) {
        final expected = renderManifestOutput(
          config,
          manifest,
          tag,
          outputPath,
        );
        if (actual != expected) {
          stderr.writeln('Manifest mismatch: $outputPath');
          exitCode = 1;
          return;
        }
        io.info('OK: $outputPath');
        return;
      }
      if (!_verifyManifestSubset(actual, config, manifest, tag)) {
        stderr.writeln('Manifest mismatch: $outputPath');
        exitCode = 1;
        return;
      }
      io.info('OK: $outputPath (partial local verification)');
      return;
    }

    final expected = renderManifestOutput(config, manifest, tag, outputPath);
    if (actual != expected) {
      stderr.writeln('Manifest mismatch: $outputPath');
      exitCode = 1;
      return;
    }
    io.info('OK: $outputPath');
  }
}

bool _verifyManifestSubset(
  String actual,
  NativePrebuiltConfig config,
  PrebuiltManifest manifest,
  String tag,
) {
  try {
    final snapshot = parseManifestSnapshot(actual, path: 'manifest.g.dart');
    if (snapshot.releaseTag != tag) return false;
    for (final entry in manifest.artifacts.entries) {
      final actualArtifact = snapshot.artifacts[entry.key];
      final expectedArtifact = entry.value;
      if (actualArtifact == null ||
          actualArtifact.archiveSha256 != expectedArtifact.archiveSha256 ||
          actualArtifact.payloadSha256 != expectedArtifact.payloadSha256 ||
          (actualArtifact.archiveName != null &&
              actualArtifact.archiveName != expectedArtifact.archiveName)) {
        return false;
      }
    }
    return true;
  } on FormatException {
    return false;
  }
}

String _resolveOutputPath(
  String? outputPath,
  File configFile,
  NativePrebuiltConfig config,
) {
  if (outputPath != null) return outputPath;
  return p.join(
    configFile.parent.path,
    'lib',
    'src',
    'hook',
    '${config.package}_prebuilts.g.dart',
  );
}

class _ManifestVerifyReleaseCommand extends Command<void> {
  @override
  String get name => 'verify-release';

  @override
  String get description =>
      'Verify release assets against the manifest (hash + binary triple).';

  _ManifestVerifyReleaseCommand() {
    argParser.addOption('config', abbr: 'c', help: 'Path to YAML config file.');
    argParser.addOption(
      'manifest',
      help: 'Path to lock manifest (native_prebuilt.lock.yaml or g.dart).',
    );
    argParser.addOption(
      'release-assets-dir',
      help: 'Directory containing release archives.',
    );
    argParser.addOption(
      'built-library-dir',
      help: 'Directory containing built libraries.',
    );
    argParser.addFlag('strict', help: 'Reject flat built-library layout.');
  }

  @override
  Future<void> run() async {
    final configFile =
        resolveConfigFile(option('config') as String?) ??
        (throw UsageException(
          'Could not find native_prebuilt.yaml. Pass --config explicitly.',
          usage,
        ));
    final config = await loadNativePrebuiltConfig(configFile);
    final manifestPath = option('manifest') as String?;
    File? manifestFile;
    if (manifestPath != null) {
      manifestFile = File(manifestPath);
    } else {
      manifestFile = resolveLockFile(null, configFile.parent);
      if (manifestFile != null && !manifestFile.existsSync())
        manifestFile = null;
      // fallback to generated g.dart
      if (manifestFile == null) {
        final gDart = File(_resolveOutputPath(null, configFile, config));
        if (gDart.existsSync()) manifestFile = gDart;
      }
    }
    if (manifestFile == null || !manifestFile.existsSync()) {
      stderr.writeln(
        'Manifest not found (lock.yaml or g.dart). Pass --manifest explicitly.',
      );
      exitCode = 1;
      return;
    }
    late final ManifestSnapshot manifest;
    try {
      manifest = readManifestSnapshot(manifestFile);
    } on FormatException catch (error) {
      stderr.writeln('Unable to parse ${manifestFile.path}: $error');
      exitCode = 1;
      return;
    }
    var failed = false;
    if (manifest.releaseTag != config.release.tag) {
      stderr.writeln(
        'Manifest tag mismatch: expected ${config.release.tag}, '
        'found ${manifest.releaseTag}',
      );
      failed = true;
    }

    final builtLibraryDirPath = option('built-library-dir') as String?;
    final releaseAssetsDirPath = option('release-assets-dir') as String?;
    final strict = (option('strict') as bool?) ?? false;

    if (builtLibraryDirPath != null) {
      final builtDir = Directory(builtLibraryDirPath);
      for (final entry in config.artifacts.entries) {
        final platform = entry.key;
        final artifact = entry.value;
        final target = parseTarget(platform);
        if (target == null) {
          stderr.writeln('Unknown artifact platform: $platform');
          failed = true;
          continue;
        }
        final payload = artifact.payload.toArtifactPayload(config.libraryStem);
        final canonicalName = canonicalLibraryName(
          target: target,
          libraryStem: config.libraryStem,
          payload: payload,
        );
        final searchResult = findBuiltLibraryFileWithMeta(
          builtLibraryDir: builtDir,
          platform: platform,
          canonicalName: canonicalName,
        );
        if (searchResult == null) {
          stderr.writeln(
            'Missing built library for $platform. Expected '
            '${p.join(builtDir.path, platform, canonicalName)} '
            '(or a nested platform build output).',
          );
          failed = true;
          continue;
        }
        if (searchResult.isFlatFallback && strict) {
          stderr.writeln(
            'Strict mode: rejected flat layout for $platform at '
            '${searchResult.file.path}. Expected '
            '${p.join(builtDir.path, platform, canonicalName)}',
          );
          failed = true;
          continue;
        }

        final hash = await ArchiveReader.sha256Hash(searchResult.file);
        final expected = manifest.artifacts[platform];
        if (expected == null || expected.payloadSha256 != hash) {
          stderr.writeln(
            'Payload hash mismatch for $platform: $hash does not match '
            'the manifest record',
          );
          failed = true;
        }
        try {
          const NativeBinaryInspector().inspect(
            searchResult.file,
            target: target,
            canonicalName: canonicalName,
          );
        } catch (e) {
          stderr.writeln('Binary inspection failed for $platform: $e');
          failed = true;
        }
      }
    }

    if (releaseAssetsDirPath != null) {
      final assetsDir = Directory(releaseAssetsDirPath);
      for (final entry in config.artifacts.entries) {
        final archive = File(p.join(assetsDir.path, entry.value.archive));
        if (!archive.existsSync()) {
          stderr.writeln('Missing archive: ${archive.path}');
          failed = true;
          continue;
        }
        final hash = await ArchiveReader.sha256Hash(archive);
        final expected = manifest.artifacts[entry.key];
        if (expected == null || expected.archiveSha256 != hash) {
          stderr.writeln(
            'Archive hash mismatch for ${entry.key}: $hash does not match '
            'the manifest record',
          );
          failed = true;
        }
      }
    }

    if (failed) {
      exitCode = 1;
    } else {
      io.info('verify-release OK: $manifestFile');
    }
  }
}
