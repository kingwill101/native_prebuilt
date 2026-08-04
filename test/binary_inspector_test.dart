import 'dart:io';

import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  test('detects ELF shared libraries', () {
    final dir = Directory.systemTemp.createTempSync('native_prebuilt_elf_');
    try {
      final f = File('${dir.path}/libdemo.so')
        ..writeAsBytesSync(makeElfBytes(arch: 'x64'));
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

  test('accepts ELF with matching architecture', () {
    final dir = Directory.systemTemp.createTempSync(
      'native_prebuilt_elf_arch_',
    );
    try {
      final f = File('${dir.path}/libdemo.so')
        ..writeAsBytesSync(makeElfBytes(arch: 'arm64'));
      final info = const NativeBinaryInspector().inspect(
        f,
        target: const NativeTarget(
          os: OS.android,
          architecture: Architecture.arm64,
        ),
        canonicalName: 'libdemo.so',
      );
      expect(info.sizeBytes, greaterThan(0));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('rejects ELF with wrong architecture', () {
    final dir = Directory.systemTemp.createTempSync('native_prebuilt_elf_bad_');
    try {
      // x86-64 binary labeled as arm64
      final f = File('${dir.path}/libdemo.so')
        ..writeAsBytesSync(makeElfBytes(arch: 'x64'));
      expect(
        () => const NativeBinaryInspector().inspect(
          f,
          target: const NativeTarget(
            os: OS.android,
            architecture: Architecture.arm64,
          ),
          canonicalName: 'libdemo.so',
        ),
        throwsA(
          isA<BinaryArchitectureException>().having(
            (e) => e.message,
            'message',
            contains('EM_X86_64'),
          ),
        ),
      );
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('rejects ARM binary labeled as AArch64', () {
    final dir = Directory.systemTemp.createTempSync('native_prebuilt_elf_arm_');
    try {
      final f = File('${dir.path}/libdemo.so')
        ..writeAsBytesSync(makeElfBytes(arch: 'arm'));
      expect(
        () => const NativeBinaryInspector().inspect(
          f,
          target: const NativeTarget(
            os: OS.android,
            architecture: Architecture.arm64,
          ),
          canonicalName: 'libdemo.so',
        ),
        throwsA(
          isA<BinaryArchitectureException>().having(
            (e) => e.message,
            'message',
            contains('EM_ARM'),
          ),
        ),
      );
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('skips architecture validation when disabled', () {
    final dir = Directory.systemTemp.createTempSync(
      'native_prebuilt_elf_noarch_',
    );
    try {
      // x86-64 binary, but architecture validation is disabled
      final f = File('${dir.path}/libdemo.so')
        ..writeAsBytesSync(makeElfBytes(arch: 'x64'));
      final info = const NativeBinaryInspector(validateArchitecture: false)
          .inspect(
            f,
            target: const NativeTarget(
              os: OS.android,
              architecture: Architecture.arm64,
            ),
            canonicalName: 'libdemo.so',
          );
      // Should not throw, even though architecture is wrong
      expect(info.sizeBytes, greaterThan(0));
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
        ..writeAsBytesSync(makeMachOBytes(arch: 'arm64'));
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
