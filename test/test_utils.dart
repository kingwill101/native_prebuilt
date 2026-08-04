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
///
/// If [arch] is provided, sets the e_machine field appropriately:
/// - 'x86_64' or 'x64': EM_X86_64 (62)
/// - 'arm64' or 'aarch64': EM_AArch64 (183)
/// - 'arm': EM_ARM (40)
/// - 'ia32' or 'x86': EM_386 (3)
///
/// If [arch] is null, uses a minimal ELF header without a valid e_machine.
List<int> makeElfBytes({String? arch, String marker = 'elf'}) {
  // Build a minimal 64-bit ELF header
  // bytes 0-3:   e_ident[0..3] = 0x7F 'E' 'L' 'F'
  // byte  4:     e_ident[4] = EI_CLASS = 2 (ELFCLASS64)
  // byte  5:     e_ident[5] = EI_DATA = 1 (ELFDATA2LSB, little-endian)
  // bytes 6-15:  e_ident[6..15] = padding
  // bytes 16-17: e_type = ET_DYN (3) for shared library
  // bytes 18-19: e_machine
  final eMachine = switch (arch) {
    'x86_64' || 'x64' => [0x3E, 0x00], // EM_X86_64 = 62
    'arm64' || 'aarch64' => [0xB7, 0x00], // EM_AArch64 = 183
    'arm' => [0x28, 0x00], // EM_ARM = 40
    'ia32' || 'x86' => [0x03, 0x00], // EM_386 = 3
    _ => [0x00, 0x00], // EM_NONE
  };

  return [
    0x7F, 0x45, 0x4C, 0x46, // e_ident[0..3]: magic
    0x02, // e_ident[4]: ELFCLASS64
    0x01, // e_ident[5]: ELFDATA2LSB
    ...List<int>.filled(10, 0), // e_ident[6..15]: padding
    0x03, 0x00, // e_type: ET_DYN
    ...eMachine, // e_machine
    ...marker.codeUnits,
  ];
}

/// Creates bytes that look like a Windows PE binary.
List<int> makePeBytes([String marker = 'pe']) => [
  0x4D,
  0x5A,
  ...marker.codeUnits,
];

/// Creates bytes that look like a Mach-O binary.
///
/// If [arch] is provided, sets the cputype field appropriately.
List<int> makeMachOBytes({String? arch, String marker = 'macho'}) {
  // Mach-O 64-bit header layout:
  //   bytes 0-3:  magic = 0xFEEDFACF (64-bit, little-endian)
  //   bytes 4-7:  cputype
  //   bytes 8-11: cpusubtype
  final cpuType = switch (arch) {
    'x86_64' || 'x64' => [0x07, 0x00, 0x00, 0x01], // CPU_TYPE_X86_64
    'arm64' || 'aarch64' => [0x0C, 0x00, 0x00, 0x01], // CPU_TYPE_ARM64
    'arm' => [0x0C, 0x00, 0x00, 0x00], // CPU_TYPE_ARM
    'x86' || 'ia32' => [0x07, 0x00, 0x00, 0x00], // CPU_TYPE_X86
    _ => [0x00, 0x00, 0x00, 0x00], // unknown
  };

  return [
    0xCF, 0xFA, 0xED, 0xFE, // magic: MH_MAGIC_64
    ...cpuType, // cputype
    0x00, 0x00, 0x00, 0x00, // cpusubtype
    ...marker.codeUnits,
  ];
}

Future<Directory> tempPackageRoot(String prefix) async {
  final dir = await Directory.systemTemp.createTemp(prefix);
  File('${dir.path}/pubspec.yaml').writeAsStringSync('name: $prefix\n');
  return dir;
}

String sha256Hash(List<int> bytes) => sha256.convert(bytes).toString();
