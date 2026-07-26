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

  /// Creates a [DownloadArchiveStep] from a YAML-derived map.
  factory DownloadArchiveStep.fromMap(Map<String, dynamic> map) {
    return DownloadArchiveStep(
      id: map['id'] as String,
      url: map['url'] as String,
      sha256: map['sha256'] as String?,
      outputDirectory: map['output_directory'] as String?,
    );
  }

  /// Serializes this step to a map suitable for YAML output.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'type': 'download_archive',
      'id': id,
      'url': url,
      if (sha256 != null) 'sha256': sha256,
      if (outputDirectory != null) 'output_directory': outputDirectory,
    };
  }

  @override
  Map<String, dynamic> toJson() => toMap();

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

    await _extractArchive(r, archivePath, outputDir);

    logger?.info('[download_archive] Archive downloaded to $archivePath');

    return const NativeStepResult();
  }

  Future<void> _extractArchive(
    ProcessRunnerInterface runner,
    String archivePath,
    String outputDir,
  ) async {
    final lower = archivePath.toLowerCase();
    if (lower.endsWith('.zip')) {
      final result = await runner.runStreaming('unzip', [
        '-q',
        archivePath,
        '-d',
        outputDir,
      ], requireSuccess: false);
      if (result.exitCode != 0) {
        throw StateError('Failed to extract archive: ${result.stderr.trim()}');
      }
      return;
    }

    final tarArgs = <String>['-C', outputDir];
    if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) {
      tarArgs.insertAll(0, ['-xzf', archivePath]);
    } else if (lower.endsWith('.tar.bz2') || lower.endsWith('.tbz2')) {
      tarArgs.insertAll(0, ['-xjf', archivePath]);
    } else if (lower.endsWith('.tar.xz') || lower.endsWith('.txz')) {
      tarArgs.insertAll(0, ['-xJf', archivePath]);
    } else {
      return;
    }

    final result = await runner.runStreaming(
      'tar',
      tarArgs,
      requireSuccess: false,
    );
    if (result.exitCode != 0) {
      throw StateError('Failed to extract archive: ${result.stderr.trim()}');
    }
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
