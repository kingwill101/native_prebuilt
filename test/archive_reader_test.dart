import 'dart:io';

import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  test('extracts matching entry', () {
    final dir = Directory.systemTemp.createTempSync('native_prebuilt_archive_');
    try {
      final archiveFile = File('${dir.path}/fixture.tar.gz');
      archiveFile.writeAsBytesSync(
        makeTarGz({
          'libdemo.so': makeElfBytes(),
          'README.txt': 'hello'.codeUnits,
        }),
      );

      final outDir = Directory('${dir.path}/out');
      final extracted = const ArchiveReader().extractMatchingEntry(
        archiveFile: archiveFile,
        outputDir: outDir,
        selection: const ArchiveSelectionContext(
          canonicalName: 'libdemo.so',
          acceptVersionedNames: true,
        ),
      );

      expect(extracted, isNotNull);
      expect(extracted!.readAsBytesSync().sublist(0, 4), [
        0x7F,
        0x45,
        0x4C,
        0x46,
      ]);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('lists entries', () {
    final dir = Directory.systemTemp.createTempSync('native_prebuilt_archive_');
    try {
      final archiveFile = File('${dir.path}/fixture.tar.gz');
      archiveFile.writeAsBytesSync(makeTarGz({'libdemo.so': makeElfBytes()}));

      final entries = const ArchiveReader().listEntries(archiveFile);
      expect(entries, hasLength(1));
      expect(entries.single.basename, 'libdemo.so');
      expect(entries.single.isFile, isTrue);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('rejects unsafe paths', () {
    final dir = Directory.systemTemp.createTempSync('native_prebuilt_archive_');
    try {
      final archiveFile = File('${dir.path}/fixture.tar.gz');
      archiveFile.writeAsBytesSync(makeTarGz({'../escape.so': makeElfBytes()}));

      expect(
        () => const ArchiveReader().extractMatchingEntry(
          archiveFile: archiveFile,
          outputDir: Directory('${dir.path}/out'),
          selection: const ArchiveSelectionContext(
            canonicalName: 'escape.so',
            acceptVersionedNames: true,
          ),
        ),
        throwsStateError,
      );
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('rejects multiple matches', () {
    final dir = Directory.systemTemp.createTempSync('native_prebuilt_archive_');
    try {
      final archiveFile = File('${dir.path}/fixture.tar.gz');
      archiveFile.writeAsBytesSync(
        makeTarGz({
          'libdemo.so': makeElfBytes('one'),
          'nested/libdemo.so': makeElfBytes('two'),
        }),
      );

      expect(
        () => const ArchiveReader().extractMatchingEntry(
          archiveFile: archiveFile,
          outputDir: Directory('${dir.path}/out'),
          selection: const ArchiveSelectionContext(
            canonicalName: 'libdemo.so',
            acceptVersionedNames: true,
          ),
        ),
        throwsStateError,
      );
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
