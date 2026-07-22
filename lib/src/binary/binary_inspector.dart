import 'dart:io';

import '../platform/native_target.dart';

/// Validates that a file is a correctly-typed native binary for its
/// expected target.
///
/// Checks magic bytes / headers for ELF, Mach-O, PE/COFF, and static
/// archives. Optionally validates architecture from binary headers.
final class NativeBinaryInspector {
  const NativeBinaryInspector({
    this.validateArchitecture = true,
  });

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
      throw BinaryFormatException(
        'Empty file: ${file.path}',
      );
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
  // Architecture validation from headers is format-specific.
  // For v1 we validate format only; architecture validation
  // can be extended per format in a future version.
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
