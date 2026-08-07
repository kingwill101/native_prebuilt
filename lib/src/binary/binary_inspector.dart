import 'dart:io';

import 'package:code_assets/code_assets.dart';

import '../platform/native_target.dart';

/// Validates that a file is a correctly-typed native binary for its
/// expected target.
///
/// Checks magic bytes / headers for ELF, Mach-O, PE/COFF, and static
/// archives. Optionally validates architecture from binary headers.
final class NativeBinaryInspector {
  const NativeBinaryInspector({this.validateArchitecture = true});

  /// Whether to read architecture information from binary headers and
  /// compare it against the expected target.
  final bool validateArchitecture;

  /// Inspects a file and returns validation results.
  ///
  /// Throws [BinaryFormatException] if the file does not match the
  /// expected format, or [BinaryArchitectureException] if the
  /// architecture is wrong.
  NativeBinaryInfo inspect(
    File file, {
    required NativeTarget target,
    required String canonicalName,
  }) {
    if (!file.existsSync()) {
      throw BinaryFormatException('File not found: ${file.path}');
    }

    final raf = file.openSync();
    List<int> header;
    try {
      header = raf.readSync(32);
    } finally {
      raf.closeSync();
    }

    if (header.isEmpty) {
      throw BinaryFormatException('Empty file: ${file.path}');
    }

    final format = _detectFormat(canonicalName, header);

    if (validateArchitecture && format != _BinaryFormat.staticArchive) {
      _validateArchitecture(header, format, target, file.path);
    }

    return NativeBinaryInfo(
      path: file.path,
      format: format,
      sizeBytes: file.lengthSync(),
    );
  }

  /// Returns a human-readable description of the expected binary format.
  static String formatDescription(String canonicalName) {
    if (canonicalName.endsWith('.so')) return 'ELF shared library';
    if (canonicalName.endsWith('.dylib')) return 'Mach-O dynamic library';
    if (canonicalName.endsWith('.dll')) return 'PE/COFF DLL';
    if (canonicalName.endsWith('.a')) return 'static archive';
    if (canonicalName.endsWith('.wasm')) return 'WebAssembly module';
    return 'native binary';
  }
}

/// Information about an inspected binary.
class NativeBinaryInfo {
  const NativeBinaryInfo({
    required this.path,
    required this.format,
    required this.sizeBytes,
  });

  final String path;
  final _BinaryFormat format;
  final int sizeBytes;

  @override
  String toString() =>
      'NativeBinaryInfo(${format.name}, $sizeBytes bytes, $path)';
}

enum _BinaryFormat { elf, machO, pe, staticArchive, wasm }

_BinaryFormat _detectFormat(String canonicalName, List<int> header) {
  if (canonicalName.endsWith('.a')) return _BinaryFormat.staticArchive;
  if (canonicalName.endsWith('.wasm')) return _BinaryFormat.wasm;
  if (canonicalName.endsWith('.dll')) return _BinaryFormat.pe;

  if (_isElf(header)) return _BinaryFormat.elf;
  if (_isMachO(header)) return _BinaryFormat.machO;
  if (_isPE(header)) return _BinaryFormat.pe;
  if (_isStaticArchive(header)) return _BinaryFormat.staticArchive;

  // Fall back to format implied by filename.
  if (canonicalName.endsWith('.so')) return _BinaryFormat.elf;
  if (canonicalName.endsWith('.dylib')) return _BinaryFormat.machO;

  throw BinaryFormatException(
    'Unrecognized binary format for $canonicalName. '
    'Header: ${_hex(header.take(8).toList())}',
  );
}

bool _isElf(List<int> bytes) =>
    bytes.length >= 4 &&
    bytes[0] == 0x7F &&
    bytes[1] == 0x45 && // 'E'
    bytes[2] == 0x4C && // 'L'
    bytes[3] == 0x46; // 'F'

bool _isMachO(List<int> bytes) {
  if (bytes.length < 4) return false;
  const prefixes = [
    [0xFE, 0xED, 0xFA, 0xCE],
    [0xCE, 0xFA, 0xED, 0xFE],
    [0xFE, 0xED, 0xFA, 0xCF],
    [0xCF, 0xFA, 0xED, 0xFE],
    [0xCA, 0xFE, 0xBA, 0xBE],
    [0xBE, 0xBA, 0xFE, 0xCA],
    [0xCA, 0xFE, 0xBA, 0xBF],
    [0xBF, 0xBA, 0xFE, 0xCA],
  ];
  return prefixes.any((prefix) => _startsWith(bytes, prefix));
}

bool _isPE(List<int> bytes) =>
    bytes.length >= 2 && bytes[0] == 0x4D && bytes[1] == 0x5A;

bool _isStaticArchive(List<int> bytes) =>
    bytes.length >= 8 &&
    bytes[0] == 0x21 && // '!'
    bytes[1] == 0x3C && // '<'
    bytes[2] == 0x61 && // 'a'
    bytes[3] == 0x72 && // 'r'
    bytes[4] == 0x63 && // 'c'
    bytes[5] == 0x68 && // 'h'
    bytes[6] == 0x3E && // '>'
    bytes[7] == 0x0A; // '\n'

bool _startsWith(List<int> bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

void _validateArchitecture(
  List<int> header,
  _BinaryFormat format,
  NativeTarget target,
  String path,
) {
  switch (format) {
    case _BinaryFormat.elf:
      _validateElfArchitecture(header, target, path);
    case _BinaryFormat.machO:
      _validateMachOArchitecture(header, target, path);
    case _BinaryFormat.pe:
      _validatePeArchitecture(header, target, path);
    case _BinaryFormat.staticArchive:
    case _BinaryFormat.wasm:
      // static archive/WASM architecture validation not yet implemented.
      break;
  }
}

/// ELF e_machine values.
const int _emNone = 0;
const int _em386 = 3;
const int _emArm = 40;
const int _emX86_64 = 62;
const int _emAArch64 = 183;

/// Maps an [Architecture] to the expected ELF e_machine value.
///
/// Returns `null` for architectures where validation is not yet implemented.
int? _expectedElfMachine(Architecture architecture) {
  return switch (architecture) {
    Architecture.ia32 => _em386,
    Architecture.arm => _emArm,
    Architecture.x64 => _emX86_64,
    Architecture.arm64 => _emAArch64,
    _ => null, // riscv32, riscv64, etc. - no validation available
  };
}

/// Returns a human-readable name for an ELF e_machine value.
String _elfMachineName(int machine) {
  return switch (machine) {
    _emNone => 'EM_NONE (0)',
    _em386 => 'IA-32 / EM_386 (3)',
    _emArm => 'ARM / EM_ARM (40)',
    _emX86_64 => 'x86-64 / EM_X86_64 (62)',
    _emAArch64 => 'AArch64 / EM_AArch64 (183)',
    _ => 'unknown ($machine)',
  };
}

/// Validates that an ELF binary matches the expected target architecture.
///
/// Reads the ELF header to extract the `e_machine` field and compares it
/// against the expected value for the target architecture.
void _validateElfArchitecture(
  List<int> header,
  NativeTarget target,
  String path,
) {
  // ELF header layout:
  //   bytes 0-3:   e_ident[0..3] = 0x7F 'E' 'L' 'F'
  //   byte  4:     e_ident[4] = EI_CLASS (1=32-bit, 2=64-bit)
  //   byte  5:     e_ident[5] = EI_DATA (1=LE, 2=BE)
  //   bytes 18-19: e_machine (for both 32-bit and 64-bit ELF)
  if (header.length < 20) {
    throw BinaryArchitectureException(
      'ELF header too short to read e_machine: $path',
    );
  }

  final eiData = header[5]; // Endianness: 1 = little-endian, 2 = big-endian
  final eMachineBytes = header.sublist(18, 20);

  int eMachine;
  if (eiData == 2) {
    // Big-endian
    eMachine = (eMachineBytes[0] << 8) | eMachineBytes[1];
  } else {
    // Little-endian (default for most targets)
    eMachine = eMachineBytes[0] | (eMachineBytes[1] << 8);
  }

  final expected = _expectedElfMachine(target.architecture);

  // Skip validation for unsupported architectures.
  if (expected == null) return;

  if (eMachine != expected) {
    throw BinaryArchitectureException(
      'Binary architecture mismatch for ${target.label}:\n'
      '  expected: ${_elfMachineName(expected)}\n'
      '  actual:   ${_elfMachineName(eMachine)}\n'
      '  file:     $path',
    );
  }
}

/// Maps an [Architecture] to the expected Mach-O CPU type.
///
/// Returns `null` for architectures where validation is not yet implemented.
int? _expectedMachOCpuType(Architecture architecture) {
  return switch (architecture) {
    Architecture.arm => 12, // CPU_TYPE_ARM
    Architecture.arm64 => 0x0100000C, // CPU_TYPE_ARM64
    Architecture.x64 => 0x01000007, // CPU_TYPE_X86_64
    Architecture.ia32 => 7, // CPU_TYPE_X86
    _ => null, // riscv32, riscv64, etc. - no validation available
  };
}

/// Returns a human-readable name for a Mach-O CPU type.
String _machOCpuTypeName(int cpuType) {
  return switch (cpuType) {
    7 => 'x86 (CPU_TYPE_X86)',
    12 => 'ARM (CPU_TYPE_ARM)',
    0x01000007 => 'x86_64 (CPU_TYPE_X86_64)',
    0x0100000C => 'ARM64 (CPU_TYPE_ARM64)',
    _ => 'unknown (0x${cpuType.toRadixString(16)})',
  };
}

/// Validates that a Mach-O binary matches the expected target architecture.
///
/// Reads the Mach-O header to extract the `cputype` field and compares it
/// against the expected value for the target architecture.
void _validateMachOArchitecture(
  List<int> header,
  NativeTarget target,
  String path,
) {
  // Mach-O header layout (both 32-bit and 64-bit):
  //   bytes 0-3:  magic
  //   bytes 4-7:  cputype
  //   bytes 8-11: cpusubtype
  if (header.length < 12) {
    throw BinaryArchitectureException(
      'Mach-O header too short to read cputype: $path',
    );
  }

  // Detect endianness from magic.
  // Valid Mach-O magics: 0xFEEDFACE (32-bit), 0xFEEDFACF (64-bit)
  // when composed as big-endian from the raw bytes.
  final magic =
      (header[0] << 24) | (header[1] << 16) | (header[2] << 8) | header[3];
  final isBigEndian = magic == 0xFEEDFACE || magic == 0xFEEDFACF;

  int cpuType;
  if (isBigEndian) {
    cpuType =
        (header[4] << 24) | (header[5] << 16) | (header[6] << 8) | header[7];
  } else {
    cpuType =
        header[4] | (header[5] << 8) | (header[6] << 16) | (header[7] << 24);
  }

  final expected = _expectedMachOCpuType(target.architecture);

  // Skip validation for unsupported architectures.
  if (expected == null) return;

  // CPU_ARCH_ABI64 distinguishes arm64 from arm and x86_64 from x86, so it
  // must take part in the comparison.
  if (cpuType != expected) {
    throw BinaryArchitectureException(
      'Binary architecture mismatch for ${target.label}:\n'
      '  expected: ${_machOCpuTypeName(expected)}\n'
      '  actual:   ${_machOCpuTypeName(cpuType)}\n'
      '  file:     $path',
    );
  }
}

const int _peMachineI386 = 0x014c;
const int _peMachineAmd64 = 0x8664;
const int _peMachineArm64 = 0xAA64;
const int _peMachineArm = 0x01c0;

int? _expectedPeMachine(Architecture architecture) {
  return switch (architecture) {
    Architecture.ia32 => _peMachineI386,
    Architecture.x64 => _peMachineAmd64,
    Architecture.arm64 => _peMachineArm64,
    Architecture.arm => _peMachineArm,
    _ => null,
  };
}

String _peMachineName(int machine) {
  return switch (machine) {
    _peMachineI386 => 'i386 / IMAGE_FILE_MACHINE_I386 (0x014c)',
    _peMachineAmd64 => 'x86_64 / IMAGE_FILE_MACHINE_AMD64 (0x8664)',
    _peMachineArm64 => 'ARM64 / IMAGE_FILE_MACHINE_ARM64 (0xAA64)',
    _peMachineArm => 'ARM / IMAGE_FILE_MACHINE_ARM (0x01c0)',
    _ => 'unknown (0x${machine.toRadixString(16)})',
  };
}

void _validatePeArchitecture(
  List<int> header,
  NativeTarget target,
  String path,
) {
  // PE header: DOS header e_lfanew at offset 0x3c (4 bytes LE), then PE signature + COFF header
  // COFF Machine at offset e_lfanew+4 (2 bytes LE)
  if (header.length < 0x40) {
    // Need to read more bytes for PE
    try {
      final file = File(path);
      final raf = file.openSync();
      try {
        final full = raf.readSync(512);
        if (full.length >= 0x40) {
          final eLfanew = full[0x3c] | (full[0x3d] << 8) | (full[0x3e] << 16) | (full[0x3f] << 24);
          if (eLfanew + 6 <= full.length) {
            final machine = full[eLfanew + 4] | (full[eLfanew + 5] << 8);
            final expected = _expectedPeMachine(target.architecture);
            if (expected != null && machine != expected) {
              throw BinaryArchitectureException(
                'Binary architecture mismatch for ${target.label}:\n'
                '  expected: ${_peMachineName(expected)}\n'
                '  actual:   ${_peMachineName(machine)}\n'
                '  file:     $path',
              );
            }
          }
        }
      } finally {
        raf.closeSync();
      }
    } catch (e) {
      if (e is BinaryArchitectureException) rethrow;
    }
    return;
  }
  final eLfanew = header[0x3c] | (header[0x3d] << 8) | (header[0x3e] << 16) | (header[0x3f] << 24);
  if (header.length < eLfanew + 6) return;
  final machine = header[eLfanew + 4] | (header[eLfanew + 5] << 8);
  final expected = _expectedPeMachine(target.architecture);
  if (expected == null) return;
  if (machine != expected) {
    throw BinaryArchitectureException(
      'Binary architecture mismatch for ${target.label}:\n'
      '  expected: ${_peMachineName(expected)}\n'
      '  actual:   ${_peMachineName(machine)}\n'
      '  file:     $path',
    );
  }
}

/// Thrown when a binary does not match the expected format.
final class BinaryFormatException implements Exception {
  const BinaryFormatException(this.message);
  final String message;

  @override
  String toString() => 'BinaryFormatException: $message';
}

/// Thrown when a binary has the wrong architecture for its target.
final class BinaryArchitectureException implements Exception {
  const BinaryArchitectureException(this.message);
  final String message;

  @override
  String toString() => 'BinaryArchitectureException: $message';
}
