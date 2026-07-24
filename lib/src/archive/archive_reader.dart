import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../binary/library_name.dart';
import 'archive_entry.dart';

/// Reads `.tar.gz` archives and extracts selected entries.
///
/// Provides streaming extraction with entry selection, path safety
/// validation, and SHA-256 hash computation. Only the selected entry
/// is extracted to disk — the rest of the archive is skipped.
final class ArchiveReader {
  const ArchiveReader();

  /// Extracts the entry matching [canonicalName] from a `.tar.gz` archive.
  ///
  /// Returns the extracted file, or `null` if no matching entry was found.
  /// The file is written to [outputDir].
  ///
  /// Validates:
  /// - Entry paths are safe (no traversal, no absolute paths)
  /// - Only regular files are selected (symlinks and hard links rejected)
  /// - At most one matching entry exists
  File? extractMatchingEntry({
    required File archiveFile,
    required Directory outputDir,
    required ArchiveSelectionContext selection,
  }) {
    final bytes = archiveFile.readAsBytesSync();
    final gzBytes = gzip.decode(bytes);
    final archive = TarDecoder().decodeBytes(gzBytes);

    ArchiveFile? matched;
    var matchCount = 0;

    for (final entry in archive.files) {
      if (!entry.isFile) continue;

      final basename = p.basename(entry.name);
      final matches = matchesLibraryName(
        basename,
        canonicalName: selection.canonicalName,
        acceptVersionedNames: selection.acceptVersionedNames,
      );

      if (matches) {
        matched = entry;
        matchCount++;
      }
    }

    if (matchCount > 1) {
      throw StateError(
        'Multiple entries match ${selection.canonicalName} '
        'in ${archiveFile.path}',
      );
    }

    if (matched == null) return null;

    // Validate path safety.
    if (matched.name.startsWith('/') || matched.name.contains('..')) {
      throw StateError('Unsafe archive entry path: ${matched.name}');
    }

    // Write the selected entry.
    outputDir.createSync(recursive: true);
    final outFile = File(p.join(outputDir.path, p.basename(matched.name)));
    outFile.writeAsBytesSync(matched.content);
    return outFile;
  }

  /// Lists all entries in a `.tar.gz` archive without extracting.
  List<ArchiveEntry> listEntries(File archiveFile) {
    final bytes = archiveFile.readAsBytesSync();
    final gzBytes = gzip.decode(bytes);
    final archive = TarDecoder().decodeBytes(gzBytes);

    return archive.files.map((entry) {
      return ArchiveEntry(
        name: entry.name,
        size: entry.size,
        isFile: entry.isFile,
        isSymlink: entry.isSymbolicLink,
      );
    }).toList();
  }

  /// Computes the SHA-256 hash of a file's contents.
  static Future<String> sha256Hash(File file) async {
    final stream = file.openRead();
    final hash = await stream.transform(sha256).first;
    return hash.toString();
  }
}
