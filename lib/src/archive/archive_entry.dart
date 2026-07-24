/// Describes an entry within a tar/gz archive.
final class ArchiveEntry {
  const ArchiveEntry({
    required this.name,
    required this.size,
    required this.isFile,
    this.isSymlink = false,
    this.isHardLink = false,
  });

  /// The full path of the entry within the archive.
  final String name;

  /// The uncompressed size in bytes.
  final int size;

  /// Whether the entry is a regular file.
  final bool isFile;

  /// Whether the entry is a symbolic link.
  final bool isSymlink;

  /// Whether the entry is a hard link.
  final bool isHardLink;

  /// The basename (final component) of the entry path.
  String get basename {
    final normalized = name.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/');
    return idx == -1 ? normalized : normalized.substring(idx + 1);
  }

  /// Whether the entry path is safe (no absolute paths, no traversal).
  bool get isSafePath {
    if (name.startsWith('/') || name.startsWith('\\')) return false;
    if (name.contains('..')) return false;
    return true;
  }

  @override
  String toString() => 'ArchiveEntry($name, size: $size, isFile: $isFile)';
}

/// Context for selecting an entry from an archive.
final class ArchiveSelectionContext {
  const ArchiveSelectionContext({
    required this.canonicalName,
    this.acceptVersionedNames = true,
  });

  /// The expected canonical filename of the library.
  final String canonicalName;

  /// Whether versioned library names are acceptable.
  final bool acceptVersionedNames;
}
