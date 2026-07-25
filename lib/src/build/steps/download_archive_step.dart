import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../fingerprint.dart';
import '../native_build_context.dart';
import '../native_build_recipe.dart';
import '../process_runner.dart';
import '../../source/resolved_source.dart';

/// Download and extract an archive step.
///
/// Downloads an archive from a URL and extracts it.
final class DownloadArchiveStep implements NativeBuildStep {
  const DownloadArchiveStep({
    required this.id,
    required this.url,
    this.sha256,
    this.outputDirectory,
    this.runner,
  });

  /// Step identifier.
  @override
  final String id;

  /// URL of the archive to download.
  final String url;

  /// Expected SHA-256 hash of the archive.
  final String? sha256;

  /// Directory to extract into. Defaults to `<work>/<id>`.
  final String? outputDirectory;

  /// Optional process runner.
  final ProcessRunnerInterface? runner;

  @override
  Future<NativeStepFingerprint> fingerprint(NativeStepContext context) async {
    final buffer = StringBuffer();
    buffer.write('download_archive');
    buffer.write(url);
    buffer.write(sha256);
    return NativeStepFingerprint(
      id: id,
      hash: fingerprintHash(buffer.toString()),
    );
  }

  @override
  Future<NativeStepResult> execute(
    NativeBuildContext context,
    ResolvedSource source,
  ) async {
    final logger = context.logger;
    logger?.info('[download_archive] Downloading archive from $url');
    final r = runner ?? ProcessRunner(logger: logger);
    final outputDir = outputDirectory != null
        ? p.isAbsolute(outputDirectory!)
              ? outputDirectory!
              : p.join(context.directories.work.path, outputDirectory!)
        : p.join(context.directories.work.path, id);
    final archivePath = p.join(
      outputDir,
      'archive${_extensionFromUrl(Uri.parse(url))}',
    );

    Directory(outputDir).createSync(recursive: true);

    // Download using curl
    await r.runStreaming('curl', ['-L', '-o', archivePath, url]);

    // Verify SHA-256 if provided
    if (sha256 != null) {
      final result = await r.runStreaming('shasum', ['-a', '256', archivePath]);
      final hash = result.stdout.split(' ').first;
      if (hash != sha256) {
        throw StateError('SHA-256 mismatch: expected $sha256, got $hash');
      }
    }

    logger?.info('[download_archive] Archive downloaded to $archivePath');

    return const NativeStepResult();
  }

  String _extensionFromUrl(Uri url) {
    final path = url.path.toLowerCase();
    if (path.endsWith('.tar.gz') || path.endsWith('.tgz')) return '.tar.gz';
    if (path.endsWith('.tar.bz2') || path.endsWith('.tbz2')) return '.tar.bz2';
    if (path.endsWith('.tar.xz') || path.endsWith('.txz')) return '.tar.xz';
    if (path.endsWith('.zip')) return '.zip';
    return '';
  }
}
