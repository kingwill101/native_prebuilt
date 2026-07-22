import 'dart:io';

/// Policy for configuring HTTP download behavior.
final class HttpDownloadPolicy {
  const HttpDownloadPolicy({
    this.maxAttempts = 4,
    this.connectionTimeout = const Duration(seconds: 15),
    this.responseTimeout = const Duration(minutes: 2),
    this.maximumBytes,
  });

  /// Maximum number of retry attempts for transient failures.
  final int maxAttempts;

  /// Timeout for establishing a TCP connection.
  final Duration connectionTimeout;

  /// Timeout for receiving the full response body.
  final Duration responseTimeout;

  /// Maximum allowed download size in bytes.
  ///
  /// Downloads exceeding this limit are aborted. `null` means unlimited.
  final int? maximumBytes;
}

/// Classifies whether an error is transient and worth retrying.
bool isTransientError(Object error) {
  if (error is SocketException) return true;
  if (error is HttpException) return true;
  if (error is TimeoutException) return true;
  if (error is HttpDownloadException) return error.isTransient;
  return false;
}

/// Computes a backoff delay for the given attempt number (0-indexed).
///
/// Returns a duration with jitter: roughly 300ms * 2^attempt + random jitter.
Duration retryBackoff(int attempt) {
  final baseMs = 300 * (1 << attempt);
  final jitterMs = (baseMs * 0.2).toInt();
  final random = DateTime.now().microsecondsSinceEpoch % jitterMs;
  return Duration(milliseconds: baseMs + random);
}

/// Whether the given HTTP status code should be retried.
bool isRetryableStatusCode(int statusCode) {
  return switch (statusCode) {
    408 || 429 || 500 || 502 || 503 || 504 => true,
    _ => false,
  };
}

/// Exception thrown when an HTTP download fails.
final class HttpDownloadException implements Exception {
  const HttpDownloadException(this.message, {this.statusCode, this.uri});

  final String message;
  final int? statusCode;
  final Uri? uri;

  bool get isTransient =>
      statusCode != null && isRetryableStatusCode(statusCode!);

  @override
  String toString() {
    final parts = ['HttpDownloadException: $message'];
    if (uri != null) parts.add('  URI: $uri');
    if (statusCode != null) parts.add('  Status: $statusCode');
    return parts.join('\n');
  }
}

/// Exception thrown when a timeout occurs during download.
final class TimeoutException implements Exception {
  const TimeoutException(this.message);
  final String message;

  @override
  String toString() => 'TimeoutException: $message';
}
