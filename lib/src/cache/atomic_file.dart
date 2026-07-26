import 'dart:io';

/// Utility for writing files atomically using a temporary file + rename.
///
/// This prevents partial files from being visible to other processes
/// during writes.
final class AtomicFile {
  /// Writes [content] to [target] atomically.
  ///
  /// Writes to a `.partial` file in the same directory, then renames
  /// to the final path. The rename is atomic on POSIX systems and
  /// effectively atomic on Windows (best-effort).
  static Future<void> writeBytes(File target, List<int> content) async {
    final tmp = File('${target.path}.partial');
    try {
      await tmp.writeAsBytes(content, flush: true);
      tmp.renameSync(target.path);
    } finally {
      if (tmp.existsSync()) tmp.deleteSync();
    }
  }

  /// Writes [content] as text to [target] atomically.
  static Future<void> writeString(File target, String content) async {
    final tmp = File('${target.path}.partial');
    try {
      await tmp.writeAsString(content, flush: true);
      tmp.renameSync(target.path);
    } finally {
      if (tmp.existsSync()) tmp.deleteSync();
    }
  }
}
