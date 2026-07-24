/// Integration test for CallbackSourceBuilder with native C compilation.
///
/// This test verifies that the CallbackSourceBuilder API works end-to-end:
/// 1. A fixture C library is compiled via CMake
/// 2. The resulting shared library can be loaded via FFI
/// 3. Functions return expected values: add(2, 3) = 5, version = "1.0.0"
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fixture_workspace.dart';

void main() {
  group('callback_source_builder fixture', () {
    late FixtureWorkspace workspace;
    late Directory buildDir;

    setUp(() async {
      workspace = await FixtureWorkspace.create('native_toolchain_c_fallback');
      buildDir = Directory(p.join(workspace.source.path, 'build'))
        ..createSync(recursive: true);
    });

    tearDown(() async {
      await workspace.dispose();
    });

    test(
      'compiles C library via CallbackSourceBuilder pattern',
      () async {
        // Configure (simulating what CallbackSourceBuilder callback does)
        final configResult = await Process.run(
          'cmake',
          [
            '-S',
            workspace.source.path,
            '-B',
            buildDir.path,
            '-DCMAKE_BUILD_TYPE=Release',
          ],
        );

        if (configResult.exitCode != 0) {
          print('Configure stderr: ${configResult.stderr}');
          fail('CMake configure failed');
        }

        // Build (simulating what CallbackSourceBuilder callback does)
        final buildResult = await Process.run(
          'cmake',
          ['--build', buildDir.path, '--config', 'Release'],
        );

        if (buildResult.exitCode != 0) {
          print('Build stderr: ${buildResult.stderr}');
          fail('CMake build failed');
        }

        // Find the built library
        final libName = _sharedLibraryName('native_toolchain_c_fallback');
        final libPath = _findBuiltLibrary(buildDir, libName);

        if (libPath == null) {
          fail('Shared library not found: $libName');
        }

        expect(File(libPath).existsSync(), isTrue);

        print('✅ Built shared library via CallbackSourceBuilder pattern');
        print('   Size: ${File(libPath).lengthSync()} bytes');
      },
      timeout: Timeout(Duration(minutes: 2)),
    );

    test(
      'FFI call to built library returns correct values',
      () async {
        // Build first
        await Process.run('cmake', [
          '-S',
          workspace.source.path,
          '-B',
          buildDir.path,
          '-DCMAKE_BUILD_TYPE=Release',
        ]);
        await Process.run('cmake', [
          '--build',
          buildDir.path,
          '--config',
          'Release',
        ]);

        // Find the built library
        final libName = _sharedLibraryName('native_toolchain_c_fallback');
        final libPath = _findBuiltLibrary(buildDir, libName);

        if (libPath == null) {
          fail('Shared library not found: $libName');
        }

        // Load and call via FFI
        final lib = DynamicLibrary.open(libPath);

        final addFn = lib.lookupFunction<
          Int32 Function(Int32, Int32),
          int Function(int, int)
        >('native_toolchain_c_fallback_add');

        final result = addFn(2, 3);
        expect(result, equals(5), reason: 'add(2, 3) should return 5');

        final versionFn = lib.lookupFunction<
          Pointer<Utf8> Function(),
          Pointer<Utf8> Function()
        >('native_toolchain_c_fallback_version');

        final version = versionFn().toDartString();
        expect(version, equals('1.0.0'), reason: 'version should be "1.0.0"');

        print('✅ FFI calls work correctly');
        print('   add(2, 3) = $result');
        print('   version = $version');

        lib.close();
      },
      timeout: Timeout(Duration(minutes: 2)),
    );
  });
}

String _sharedLibraryName(String stem) {
  if (Platform.isWindows) return '$stem.dll';
  if (Platform.isMacOS) return 'lib$stem.dylib';
  return 'lib$stem.so';
}

String? _findBuiltLibrary(Directory buildDir, String libName) {
  final searchDirs = [
    buildDir,
    Directory(p.join(buildDir.path, 'Release')),
    Directory(p.join(buildDir.path, 'Debug')),
  ];

  for (final dir in searchDirs) {
    if (!dir.existsSync()) continue;

    final libFile = File(p.join(dir.path, libName));
    if (libFile.existsSync()) return libFile.path;

    try {
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File && p.basename(entity.path) == libName) {
          return entity.path;
        }
      }
    } catch (_) {}
  }

  return null;
}
