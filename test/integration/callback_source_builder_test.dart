/// Integration test for CallbackSourceBuilder with CBuilder fixture.
///
/// This test verifies that the PrebuiltCodeAssetBuilder + CallbackSourceBuilder
/// path works end-to-end by running the native_toolchain_c_fallback fixture
/// and confirming FFI calls succeed.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fixture_workspace.dart';

void main() {
  group('native_toolchain_c_fallback fixture (CallbackSourceBuilder)', () {
    late FixtureWorkspace workspace;

    setUp(() async {
      workspace = await FixtureWorkspace.create('native_toolchain_c_fallback');
    });

    tearDown(() async {
      await workspace.dispose();
    });

    test(
      'CallbackSourceBuilder compilation with CBuilder succeeds and FFI works',
      () async {
        final fixtureDir = workspace.source;

        // Run pub get to fetch dependencies (native_toolchain_c, etc.)
        final pubGetResult = await Process.run('dart', [
          'pub',
          'get',
        ], workingDirectory: fixtureDir.path);

        if (pubGetResult.exitCode != 0) {
          print('pub get stderr: ${pubGetResult.stderr}');
          // If pub get fails (e.g., native_toolchain_c not on pub.dev),
          // skip this test gracefully.
          if (pubGetResult.stderr.toString().contains('hosted')) {
            print('Skipping: native_toolchain_c package not available');
            return;
          }
          fail('dart pub get failed');
        }

        // Run the hook build (this exercises PrebuiltCodeAssetBuilder →
        // CallbackSourceBuilder → CBuilder → compile C → register CodeAsset)
        final buildResult = await Process.run('dart', [
          'run',
          'hook/build.dart',
        ], workingDirectory: fixtureDir.path);

        if (buildResult.exitCode != 0) {
          print('Build stdout: ${buildResult.stdout}');
          print('Build stderr: ${buildResult.stderr}');
          fail('Hook build failed');
        }

        // Find the built library
        final libName = _sharedLibraryName('native_toolchain_c_fallback');
        final buildOutputDir = Directory(p.join(fixtureDir.path, 'build'));
        final libPath =
            _findBuiltLibrary(buildOutputDir, libName) ??
            _findBuiltLibrary(fixtureDir, libName);

        if (libPath == null) {
          // List files for debugging
          print('Fixture dir contents:');
          for (final entity in fixtureDir.listSync(recursive: true)) {
            print('  ${entity.path}');
          }
          fail('Built library not found: $libName');
        }

        expect(File(libPath).existsSync(), isTrue);
        print('✅ Built library: $libPath');
        print('   Size: ${File(libPath).lengthSync()} bytes');

        // FFI call: add(2, 3) should return 5
        final lib = DynamicLibrary.open(libPath);

        final addFn = lib
            .lookupFunction<
              Int32 Function(Int32, Int32),
              int Function(int, int)
            >('native_toolchain_c_fallback_add');

        final result = addFn(2, 3);
        expect(result, equals(5), reason: 'add(2, 3) should return 5');

        final versionFn = lib
            .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
              'native_toolchain_c_fallback_version',
            );

        final version = versionFn().toDartString();
        expect(version, equals('1.0.0'), reason: 'version should be "1.0.0"');

        print('✅ FFI calls work correctly');
        print('   add(2, 3) = $result');
        print('   version = $version');

        lib.close();
      },
      timeout: Timeout(Duration(minutes: 5)),
    );
  });
}

String _sharedLibraryName(String stem) {
  if (Platform.isWindows) return '$stem.dll';
  if (Platform.isMacOS) return 'lib$stem.dylib';
  return 'lib$stem.so';
}

String? _findBuiltLibrary(Directory dir, String libName) {
  if (!dir.existsSync()) return null;

  // Check the directory itself
  final libFile = File(p.join(dir.path, libName));
  if (libFile.existsSync()) return libFile.path;

  // Search recursively for the library
  try {
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File && p.basename(entity.path) == libName) {
        return entity.path;
      }
    }
  } catch (_) {}

  return null;
}
