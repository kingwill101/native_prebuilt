import 'dart:io';

import 'package:path/path.dart' as p;

/// Describes where source code comes from.
///
/// Subclasses represent different acquisition strategies: local paths,
/// Git repositories, or immutable source archives.
sealed class SourceSpecification {
  const SourceSpecification();

  /// A short label for logging.
  String get label;

  /// Serializes this source specification to JSON.
  Map<String, dynamic> toJson();

  /// Deserializes a source specification from JSON.
  factory SourceSpecification.fromJson(Map<String, dynamic> json) {
    return switch (json['type'] as String?) {
      'local' => LocalSource(
        paths: (json['paths'] as List? ?? const [])
            .map((e) => e as String)
            .toList(),
      ),
      'git' => GitSource(
        repository: Uri.parse(json['repository'] as String),
        revision: json['revision'] as String,
        subdirectory: json['subdirectory'] as String?,
        submodules: json['submodules'] as bool? ?? false,
      ),
      'archive' => ArchiveSource(
        uri: Uri.parse(json['uri'] as String),
        sha256: json['sha256'] as String,
        subdirectory: json['subdirectory'] as String?,
      ),
      final type => throw FormatException('Unknown source type: $type'),
    };
  }
}

/// Source code already present in the workspace.
///
/// Use this for vendored or monorepo layouts where the source
/// is checked out alongside the Dart package.
final class LocalSource extends SourceSpecification {
  const LocalSource({required this.paths});

  /// Relative paths to search, in priority order.
  ///
  /// Each path is resolved relative to the package root.
  final List<String> paths;

  @override
  String get label => 'local';

  @override
  Map<String, dynamic> toJson() => {'type': 'local', 'paths': paths};

  /// Resolve the first existing path against [packageRoot].
  Directory? resolve(Directory packageRoot) {
    for (final path in paths) {
      // Normalize the path to handle mixed separators (e.g., 'vendor/lib' on Windows)
      final normalizedPath = p.normalize(path);
      final candidate = Directory(p.join(packageRoot.path, normalizedPath));
      if (candidate.existsSync()) return candidate;
    }
    return null;
  }
}

/// Source code fetched from a Git repository.
///
/// Always pin to a full commit SHA for reproducible builds.
final class GitSource extends SourceSpecification {
  const GitSource({
    required this.repository,
    required this.revision,
    this.subdirectory,
    this.submodules = false,
  });

  /// Repository URL (e.g. `https://github.com/org/repo.git`).
  final Uri repository;

  /// Immutable commit SHA. Do not use branches or mutable tags.
  final String revision;

  /// Subdirectory within the repo containing the buildable source.
  final String? subdirectory;

  /// Whether to initialize and update Git submodules.
  final bool submodules;

  @override
  String get label => 'git ${p.basename(repository.path)}';

  /// Cache key components for this source.
  String get cacheKey => '${repository}_$revision';

  @override
  Map<String, dynamic> toJson() => {
    'type': 'git',
    'repository': repository.toString(),
    'revision': revision,
    if (subdirectory != null) 'subdirectory': subdirectory,
    'submodules': submodules,
  };
}

/// Source code downloaded as an immutable archive.
///
/// Archives are preferred over Git clones inside build hooks because
/// they are downloadable with standard HTTP, verifiable before extraction,
/// independent of a local `git` installation, and easier to cache
/// deterministically.
final class ArchiveSource extends SourceSpecification {
  const ArchiveSource({
    required this.uri,
    required this.sha256,
    this.subdirectory,
  });

  /// URL of the archive (`.tar.gz`, `.zip`, etc.).
  final Uri uri;

  /// Expected SHA-256 hash of the downloaded archive.
  final String sha256;

  /// Subdirectory within the extracted archive containing the buildable source.
  final String? subdirectory;

  @override
  String get label => 'archive ${p.basename(uri.path)}';

  @override
  Map<String, dynamic> toJson() => {
    'type': 'archive',
    'uri': uri.toString(),
    'sha256': sha256,
    if (subdirectory != null) 'subdirectory': subdirectory,
  };
}
