import 'dart:async';
import 'dart:io';

import '../manifest/release_source.dart';
import 'retry_policy.dart';

/// Downloads files from HTTP(S) URLs with retry, proxy support, and
/// redirect following.
///
/// All downloads are written to a temporary file first, then atomically
/// renamed to the target path.
final class HttpDownloader {
  const HttpDownloader({
    this.policy = const HttpDownloadPolicy(),
    this.onProgress,
  });

  /// Download policy (timeouts, retries, size limits).
  final HttpDownloadPolicy policy;

  /// Optional progress callback: `(bytesDownloaded, totalBytes)`.
  final void Function(int bytesReceived, int? totalBytes)? onProgress;

  /// Downloads the file at [url] to [targetPath].
  ///
  /// Follows up to 5 redirects. Writes to a `.partial` file first,
  /// then renames atomically. Verifies maximum size if configured.
  Future<void> download(Uri url, File targetPath) async {
    final tmpFile = File('${targetPath.path}.partial');
    try {
      await _downloadWithRetry(url, tmpFile);
      tmpFile.renameSync(targetPath.path);
    } finally {
      if (tmpFile.existsSync()) tmpFile.deleteSync();
    }
  }

  /// Downloads a release artifact from a [GitHubReleaseSource].
  Future<void> downloadReleaseArtifact({
    required GitHubReleaseSource source,
    required String archiveName,
    required File targetPath,
  }) {
    final url = source.artifactUrl(archiveName);
    return download(url, targetPath);
  }

  Future<void> _downloadWithRetry(Uri url, File targetFile) async {
    Object? lastError;
    for (var attempt = 0; attempt < policy.maxAttempts; attempt++) {
      if (attempt > 0) {
        final delay = retryBackoff(attempt - 1);
        await Future<void>.delayed(delay);
      }
      try {
        await _downloadOnce(url, targetFile);
        return;
      } on Object catch (e) {
        lastError = e;
        if (!isTransientError(e)) rethrow;
      }
    }
    throw HttpDownloadException(
      'Download failed after ${policy.maxAttempts} attempts: $lastError',
      uri: url,
    );
  }

  Future<void> _downloadOnce(Uri url, File targetFile) async {
    final client = HttpClient()
      ..findProxy = HttpClient.findProxyFromEnvironment
      ..connectionTimeout = policy.connectionTimeout;

    try {
      final request = await client.getUrl(url);
      request
        ..followRedirects = true
        ..maxRedirects = 5;

      final response = await request.close().timeout(policy.responseTimeout);

      if (response.statusCode != 200) {
        if (response.statusCode == 302 ||
            response.statusCode == 301) {
          final location = response.headers.value('location');
          if (location != null) {
            await response.drain<void>();
            return _downloadOnce(Uri.parse(location), targetFile);
          }
        }
        await response.drain<void>();
        throw HttpDownloadException(
          'HTTP ${response.statusCode} for $url',
          statusCode: response.statusCode,
          uri: url,
        );
      }

      final totalBytes = response.contentLength;
      var received = 0;

      final sink = targetFile.openWrite();
      try {
        await for (final chunk in response) {
          received += chunk.length;
          if (policy.maximumBytes != null &&
              received > policy.maximumBytes!) {
            throw HttpDownloadException(
              'Download exceeds maximum size of ${policy.maximumBytes} bytes',
              uri: url,
            );
          }
          sink.add(chunk);
          onProgress?.call(received, totalBytes);
        }
      } finally {
        await sink.close();
      }
    } finally {
      client.close();
    }
  }
}
