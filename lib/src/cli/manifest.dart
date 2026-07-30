import 'dart:io';

import 'package:artisanal/args.dart';
import 'package:path/path.dart' as p;

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

    final manifest = await generateManifest(
      config: config,
      tag: tag,
      allowMissing: allowMissing,
      builtLibraryDir: builtLibraryDir,
      releaseAssetsDir: releaseAssetsDir,
      toleratePartialBuiltLibrary: inferredLocalBuild,
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
    final manifest = await generateManifest(
      config: config,
      tag: tag,
      allowMissing: allowMissing,
      builtLibraryDir: builtLibraryDir,
      releaseAssetsDir: releaseAssetsDir,
      toleratePartialBuiltLibrary: inferredLocalBuild,
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
  final header = 'const ${config.package}Prebuilts = PrebuiltManifest(';
  if (!actual.contains(header)) return false;
  if (!actual.contains("  schemaVersion: ${manifest.schemaVersion},"))
    return false;
  if (!actual.contains(
    "  release: ${renderReleaseSource(config.release.toReleaseSource().withTag(tag))},",
  )) {
    return false;
  }

  for (final entry in manifest.artifacts.entries) {
    final platform = entry.key;
    final artifact = entry.value;
    final artifactBlock = [
      "    '$platform': PrebuiltArtifact(",
      "      archiveName: '${artifact.archiveName}',",
      "      archiveSha256: '${artifact.archiveSha256}',",
      "      payloadSha256: '${artifact.payloadSha256}',",
      '      payload: ${renderPayload(artifact.payload)},',
      '    ),',
    ].join('\n');

    if (!actual.contains(artifactBlock)) {
      return false;
    }
  }

  return true;
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
