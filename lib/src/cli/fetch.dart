import 'dart:io';

import 'package:artisanal/args.dart';
import 'package:path/path.dart' as p;

import '../archive/archive_entry.dart';
import '../archive/archive_reader.dart';
import '../binary/library_name.dart';
import '../download/http_downloader.dart';
import '../manifest/prebuilt_artifact.dart';
import '../config/native_prebuilt_config.dart';
import 'cli_config.dart';
import 'shared.dart';

class FetchCommand extends Command<void> {
  FetchCommand() {
    argParser.addOption('config', abbr: 'c', help: 'Path to YAML config file.');
    argParser.addOption(
      'platform',
      abbr: 'p',
      help: 'Platform label to fetch.',
    );
    argParser.addOption('out', abbr: 'o', help: 'Output directory.');
  }

  @override
  String get name => 'fetch';

  @override
  String get description => 'Fetch one prebuilt artifact to a local cache.';

  @override
  Future<void> run() async {
    final configFile = resolveConfigFile(option('config') as String?) ??
        (throw UsageException(
          'Could not find native_prebuilt.yaml. Pass --config explicitly.',
          usage,
        ));
    final platform = option('platform') as String?;
    final outPath = option('out') as String? ?? '.prebuilt';
    if (platform == null) {
      throw UsageException('fetch requires --platform', usage);
    }

    final config = await loadNativePrebuiltConfig(configFile);
    final artifact = config.artifacts[platform];
    if (artifact == null) {
      throw UsageException('Unknown platform: $platform', usage);
    }

    final target = targetFromPlatformLabel(platform);
    final payload = artifact.payload.toArtifactPayload(config.libraryStem);
    final canonicalName = canonicalLibraryName(
      target: target,
      libraryStem: config.libraryStem,
      payload: payload,
    );

    final downloader = HttpDownloader();
    final release = config.release.toReleaseSource();
    final tmpDir = await Directory.systemTemp.createTemp(
      'native_prebuilt_fetch_',
    );
    try {
      final archivePath = File(p.join(tmpDir.path, artifact.archive));
      await downloader.downloadReleaseArtifact(
        source: release,
        archiveName: artifact.archive,
        targetPath: archivePath,
      );

      final extracted = ArchiveReader().extractMatchingEntry(
        archiveFile: archivePath,
        outputDir: Directory(p.join(outPath, platform)),
        selection: ArchiveSelectionContext(
          canonicalName: canonicalName,
          acceptVersionedNames: payload is DynamicLibraryPayload,
        ),
      );
      if (extracted == null) {
        throw StateError(
          'No matching payload found in ${artifact.archive}',
        );
      }
      io.info(extracted.path);
    } finally {
      tmpDir.deleteSync(recursive: true);
    }
  }
}
