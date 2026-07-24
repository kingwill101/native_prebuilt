/// Result of attempting to resolve a prebuilt artifact.
sealed class ResolvedPrebuilt {
  const ResolvedPrebuilt();
}

/// A prebuilt was found and installed successfully.
final class ResolvedPrebuiltFound extends ResolvedPrebuilt {
  const ResolvedPrebuiltFound({required this.file, required this.source});

  /// The installed native library file.
  final ResolvedFile file;

  /// Which resolver found the prebuilt.
  final PrebuiltSource source;
}

/// No prebuilt was found; the caller should fall back to building from source.
final class ResolvedPrebuiltNotFound extends ResolvedPrebuilt {
  const ResolvedPrebuiltNotFound({
    required this.reason,
    required this.attempts,
  });

  /// A human-readable summary of why resolution failed.
  final String reason;

  /// All resolution attempts made.
  final List<ResolutionAttempt> attempts;
}

/// A file that has been resolved and is ready to use.
final class ResolvedFile {
  const ResolvedFile({required this.path, required this.hash});

  /// Path to the native library file.
  final String path;

  /// SHA-256 hash of the file.
  final String hash;
}

/// Describes which resolver was used.
enum PrebuiltSource {
  userDefine('user define'),
  localCache('local .prebuilt'),
  sharedCache('shared cache'),
  download('download');

  const PrebuiltSource(this.label);
  final String label;
}

/// A single resolution attempt.
final class ResolutionAttempt {
  const ResolutionAttempt({
    required this.source,
    required this.success,
    this.path,
    this.error,
  });

  final PrebuiltSource source;
  final bool success;
  final String? path;
  final String? error;

  @override
  String toString() {
    final status = success ? 'found' : 'not found';
    final detail = path != null ? ' at $path' : '';
    final err = error != null ? ' ($error)' : '';
    return '${source.label}: $status$detail$err';
  }
}
