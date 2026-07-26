import 'dart:io';

import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  test('detects ELF shared libraries', () {
    final dir = Directory.systemTemp.createTempSync('native_prebuilt_elf_');
    try {
      final f = File('${dir.path}/libdemo.so')
        ..writeAsBytesSync(makeElfBytes());
      final info = const NativeBinaryInspector().inspect(
        f,
        target: const NativeTarget(
          os: OS.linux,
          architecture: Architecture.x64,
        ),
        canonicalName: 'libdemo.so',
      );
      expect(info.sizeBytes, greaterThan(0));
      expect(
        NativeBinaryInspector.formatDescription('libdemo.so'),
        contains('ELF'),
      );
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('detects PE DLLs', () {
    final dir = Directory.systemTemp.createTempSync('native_prebuilt_pe_');
    try {
      final f = File('${dir.path}/demo.dll')..writeAsBytesSync(makePeBytes());
      final info = const NativeBinaryInspector().inspect(
        f,
        target: const NativeTarget(
          os: OS.windows,
          architecture: Architecture.x64,
        ),
        canonicalName: 'demo.dll',
      );
      expect(info.sizeBytes, greaterThan(0));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('detects Mach-O dylibs', () {
    final dir = Directory.systemTemp.createTempSync('native_prebuilt_macho_');
    try {
      final f = File('${dir.path}/libdemo.dylib')
        ..writeAsBytesSync(makeMachOBytes());
      final info = const NativeBinaryInspector().inspect(
        f,
        target: const NativeTarget(
          os: OS.macOS,
          architecture: Architecture.arm64,
        ),
        canonicalName: 'libdemo.dylib',
      );
      expect(info.sizeBytes, greaterThan(0));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('accepts static archives', () {
    final dir = Directory.systemTemp.createTempSync('native_prebuilt_a_');
    try {
      final f = File('${dir.path}/libdemo.a')
        ..writeAsBytesSync(List<int>.filled(16, 0));
      final info = const NativeBinaryInspector().inspect(
        f,
        target: const NativeTarget(
          os: OS.linux,
          architecture: Architecture.x64,
        ),
        canonicalName: 'libdemo.a',
      );
      expect(info.sizeBytes, greaterThan(0));
      expect(
        NativeBinaryInspector.formatDescription('libdemo.a'),
        contains('archive'),
      );
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('rejects empty files', () {
    final dir = Directory.systemTemp.createTempSync('native_prebuilt_empty_');
    try {
      final f = File('${dir.path}/bad.so')..writeAsBytesSync([]);
      expect(
        () => const NativeBinaryInspector().inspect(
          f,
          target: const NativeTarget(
            os: OS.linux,
            architecture: Architecture.x64,
          ),
          canonicalName: 'bad.so',
        ),
        throwsA(isA<BinaryFormatException>()),
      );
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
