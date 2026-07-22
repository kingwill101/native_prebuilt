import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../archive/archive_entry.dart';
import '../archive/archive_reader.dart';
import '../binary/binary_inspector.dart';
import '../binary/library_name.dart';
import '../download/http_downloader.dart';
import '../download/retry_policy.dart';
import '../manifest/prebuilt_artifact.dart';
import '../manifest/prebuilt_manifest.dart';
import '../manifest/release_source.dart';
import '../platform/native_target.dart';
import 'cache_lock.dart';

/// Installs a prebuilt artifact into a cache directory.
abstract interface class ArtifactInstaller {
  Future<File?> install({
    required PrebuiltManifest manifest,
    required NativeTarget target,
    required String libraryStem,
    required ArtifactPayload payload,
    required Directory cacheDirectory,
  });
}

/// Default implementation for downloading, verifying, extracting, and
/// validating prebuilt artifacts.
final class DefaultArtifactInstaller implements ArtifactInstaller {
  DefaultArtifactInstaller({
    this.downloader = const HttpDownloader(),
    this.archiveReader = const ArchiveReader(),
    this.inspector = const NativeBinaryInspector(),
  });

  final HttpDownloader downloader;
  final ArchiveReader archiveReader;
  final NativeBinaryInspector inspector;

  @override
  Future<File?> install({
    required PrebuiltManifest manifest,
    required NativeTarget target,
    required String libraryStem,
    required ArtifactPayload payload,
    required Directory cacheDirectory,
  }) async {
    final artifact = manifest.artifacts[target.label];
    if (artifact == null) return null;

    final canonicalName = canonicalLibraryName(
      target: target,
      libraryStem: libraryStem,
      payload: payload,
    );

    final cacheDirForArtifact = _artifactCacheDirectory(
      cacheDirectory,
      manifest.release,
      target.label,
      artifact,
      canonicalName,
    );
    final cachedFile = File(p.join(cacheDirForArtifact.path, canonicalName));

    final lock = CacheLock(
      File(p.join(cacheDirectory.path, '.locks', _cacheKey(
        manifest.release,
        target.label,
        artifact,
        canonicalName,
      ) + '.lock')),
    );

    return lock.withLock(() async {
      if (cachedFile.existsSync()) {
        final actualHash = await ArchiveReader.sha256Hash(cachedFile);
        if (actualHash == artifact.payloadSha256) {
          try {
            inspector.inspect(
              cachedFile,
              target: target,
              canonicalName: canonicalName,
            );
            return cachedFile;
          } on BinaryFormatException {
            cachedFile.deleteSync();
          }
        } else {
          cachedFile.deleteSync();
        }
      }

      final source = manifest.release;
      if (source is! GitHubReleaseSource) return null;

      final archiveFile = File(
        p.join(cacheDirForArtifact.path, artifact.archiveName),
      );

      try {
        await downloader.downloadReleaseArtifact(
          source: source,
          archiveName: artifact.archiveName,
          targetPath: archiveFile,
        );
      } on HttpDownloadException {
        return null;
      }

      final archiveHash = await ArchiveReader.sha256Hash(archiveFile);
      if (archiveHash != artifact.archiveSha256) {
        archiveFile.deleteSync();
        throw StateError(
          'Archive hash mismatch for ${artifact.archiveName}:\n'
          '  expected: ${artifact.archiveSha256}\n'
          '  actual:   $archiveHash',
        );
      }

      final acceptVersioned = switch (artifact.payload) {
        DynamicLibraryPayload(:final acceptVersionedNames) =>
          acceptVersionedNames,
        StaticLibraryPayload() => false,
      };

      final extracted = archiveReader.extractMatchingEntry(
        archiveFile: archiveFile,
        outputDir: cacheDirForArtifact,
        selection: ArchiveSelectionContext(
          canonicalName: canonicalName,
          acceptVersionedNames: acceptVersioned,
        ),
      );
      archiveFile.deleteSync();

      if (extracted == null) return null;

      final payloadHash = await ArchiveReader.sha256Hash(extracted);
      if (payloadHash != artifact.payloadSha256) {
        extracted.deleteSync();
        throw StateError(
          'Payload hash mismatch for $canonicalName:\n'
          '  expected: ${artifact.payloadSha256}\n'
          '  actual:   $payloadHash',
        );
      }

      inspector.inspect(
        extracted,
        target: target,
        canonicalName: canonicalName,
      );
      return extracted;
    });
  }

  Directory _artifactCacheDirectory(
    Directory cacheDirectory,
    ReleaseSource source,
    String platformLabel,
    PrebuiltArtifact artifact,
    String canonicalName,
  ) {
    final dir = Directory(p.join(
      cacheDirectory.path,
      _cacheKey(source, platformLabel, artifact, canonicalName),
    ));
    dir.createSync(recursive: true);
    return dir;
  }

  String _cacheKey(
    ReleaseSource source,
    String platformLabel,
    PrebuiltArtifact artifact,
    String canonicalName,
  ) {
    final data = [
      source.toString(),
      platformLabel,
      artifact.archiveName,
      artifact.archiveSha256,
      artifact.payloadSha256,
      canonicalName,
    ].join('\n');
    return sha256.convert(utf8.encode(data)).toString();
  }
}
