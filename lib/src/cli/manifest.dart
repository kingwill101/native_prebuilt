import 'dart:io';

import 'package:artisanal/args.dart';

import 'native_prebuilt_config.dart';
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
    final configPath = option('config') as String?;
    final outputPath = option('output') as String?;
    if (configPath == null || outputPath == null) {
      throw UsageException('update requires --config and --output', usage);
    }

    final config = NativePrebuiltConfig.loadFile(configPath);
    final tag = (option('tag') as String?) ?? config.release.tag;
    final allowMissing = (option('allow-missing') as bool?) ?? false;
    final builtLibraryDirPath = option('built-library-dir') as String?;
    final builtLibraryDir = builtLibraryDirPath == null
        ? null
        : Directory(builtLibraryDirPath);
    final releaseAssetsDirPath = option('release-assets-dir') as String?;
    final releaseAssetsDir = releaseAssetsDirPath == null
        ? null
        : Directory(releaseAssetsDirPath);

    final manifest = await generateManifest(
      config: config,
      tag: tag,
      allowMissing: allowMissing,
      builtLibraryDir: builtLibraryDir,
      releaseAssetsDir: releaseAssetsDir,
    );

    final content = renderManifest(config, manifest, tag);
    File(outputPath).writeAsStringSync(content);
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
    final configPath = option('config') as String?;
    final outputPath = option('output') as String?;
    if (configPath == null || outputPath == null) {
      throw UsageException('verify requires --config and --output', usage);
    }

    final config = NativePrebuiltConfig.loadFile(configPath);
    final tag = (option('tag') as String?) ?? config.release.tag;
    final allowMissing = (option('allow-missing') as bool?) ?? false;
    final builtLibraryDirPath = option('built-library-dir') as String?;
    final builtLibraryDir = builtLibraryDirPath == null
        ? null
        : Directory(builtLibraryDirPath);
    final releaseAssetsDirPath = option('release-assets-dir') as String?;
    final releaseAssetsDir = releaseAssetsDirPath == null
        ? null
        : Directory(releaseAssetsDirPath);

    final manifest = await generateManifest(
      config: config,
      tag: tag,
      allowMissing: allowMissing,
      builtLibraryDir: builtLibraryDir,
      releaseAssetsDir: releaseAssetsDir,
    );

    final expected = renderManifest(config, manifest, tag);
    final actual = File(outputPath).readAsStringSync();
    if (actual != expected) {
      stderr.writeln('Manifest mismatch: $outputPath');
      exitCode = 1;
      return;
    }
    io.info('OK: $outputPath');
  }
}
