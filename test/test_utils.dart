import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';

/// Creates a gzipped tar archive in memory.
Uint8List makeTarGz(Map<String, List<int>> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  final tarBytes = TarEncoder().encodeBytes(archive);
  return GZipEncoder().encodeBytes(tarBytes);
}

/// Creates bytes that look like an ELF binary.
List<int> makeElfBytes([String marker = 'elf']) => [
  0x7F,
  0x45,
  0x4C,
  0x46,
  ...marker.codeUnits,
];

/// Creates bytes that look like a Windows PE binary.
List<int> makePeBytes([String marker = 'pe']) => [
  0x4D,
  0x5A,
  ...marker.codeUnits,
];

/// Creates bytes that look like a Mach-O binary.
List<int> makeMachOBytes([String marker = 'macho']) => [
  0xFE,
  0xED,
  0xFA,
  0xCE,
  ...marker.codeUnits,
];

Future<Directory> tempPackageRoot(String prefix) async {
  final dir = await Directory.systemTemp.createTemp(prefix);
  File('${dir.path}/pubspec.yaml').writeAsStringSync('name: $prefix\n');
  return dir;
}

String sha256Hash(List<int> bytes) => sha256.convert(bytes).toString();
