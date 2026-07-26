/// Integration tests that actually build native fixtures.
///
/// These tests require CMake and a C compiler to be installed.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fixture_workspace.dart';
import '../support/test_helpers.dart';

bool _cmakeAvailable = false;

void main() {
  setUpAll(() {
    final result = Process.runSync('cmake', ['--version']);
    _cmakeAvailable = result.exitCode == 0;
    if (!_cmakeAvailable) {
      print('Skipping integration tests: CMake not found');
    }
  });

  group('simple_shared fixture', () {
    late FixtureWorkspace workspace;
    late Directory buildDir;

    setUp(() async {
      workspace = await FixtureWorkspace.create('simple_shared');
      buildDir = Directory(p.join(workspace.work.path, 'build'))
        ..createSync(recursive: true);
    });

    tearDown(() async {
      await workspace.dispose();
    });

    test(
      'builds shared library on host platform',
      skip: _cmakeAvailable ? null : 'CMake not available',
      () async {
        await cmakeConfigure(workspace.source.path, buildDir.path);
        await cmakeBuild(buildDir.path);

        final libName = sharedLibraryName('native_prebuilt_fixture');
        final libPath = _findBuiltLibrary(buildDir, libName);

        expect(libPath, isNotNull, reason: 'Shared library not found');
        expect(
          File(libPath!).existsSync(),
          isTrue,
          reason: 'Shared library file does not exist',
        );

        print('Built shared library: $libPath');
        print('   Size: ${File(libPath).lengthSync()} bytes');
      },
      timeout: Timeout(Duration(minutes: 2)),
    );

    test(
      'shared library exports expected symbols',
      skip: _cmakeAvailable ? null : 'CMake not available',
      () async {
        if (Platform.isWindows) {
          markTestSkipped('Symbol loading is not available on Windows');
        }

        await cmakeConfigure(workspace.source.path, buildDir.path);
        await cmakeBuild(buildDir.path);

        final libName = sharedLibraryName('native_prebuilt_fixture');
        final libPath = _findBuiltLibrary(buildDir, libName);

        if (libPath == null) {
          fail('Library not found');
        }

        DynamicLibrary? lib;
        try {
          lib = DynamicLibrary.open(libPath);

          final addFn = lib
              .lookupFunction<
                Int32 Function(Int32, Int32),
                int Function(int, int)
              >('native_prebuilt_fixture_add');

          final result = addFn(2, 3);
          expect(result, equals(5), reason: 'add(2, 3) should return 5');

          final versionFn = lib
              .lookupFunction<
                Pointer<Utf8> Function(),
                Pointer<Utf8> Function()
              >('native_prebuilt_fixture_version');

          final versionPtr = versionFn();
          final version = versionPtr.toDartString();
          expect(version, isNotEmpty, reason: 'Version should not be empty');

          print('Library functions work correctly');
          print('   add(2, 3) = $result');
          print('   version = $version');
        } catch (e) {
          fail('Failed to load or call library: $e');
        } finally {
          lib?.close();
        }
      },
      timeout: Timeout(Duration(minutes: 2)),
    );
  });

  group('static_library fixture', () {
    late FixtureWorkspace workspace;
    late Directory buildDir;

    setUp(() async {
      workspace = await FixtureWorkspace.create('static_library');
      buildDir = Directory(p.join(workspace.work.path, 'build'))
        ..createSync(recursive: true);
    });

    tearDown(() async {
      await workspace.dispose();
    });

    test(
      'builds static library',
      skip: _cmakeAvailable ? null : 'CMake not available',
      () async {
        await cmakeConfigure(workspace.source.path, buildDir.path);
        await cmakeBuild(buildDir.path);

        final libName = staticLibraryName('native_prebuilt_fixture_static');
        final libPath = _findBuiltLibrary(buildDir, libName);

        expect(libPath, isNotNull, reason: 'Static library not found');
        expect(File(libPath!).existsSync(), isTrue);

        print('Built static library: $libPath');
        print('   Size: ${File(libPath).lengthSync()} bytes');
      },
      timeout: Timeout(Duration(minutes: 2)),
    );
  });

  group('dependency_graph fixture', () {
    late FixtureWorkspace workspace;
    late Directory buildDir;

    setUp(() async {
      workspace = await FixtureWorkspace.create('dependency_graph');
      buildDir = Directory(p.join(workspace.work.path, 'build'))
        ..createSync(recursive: true);
    });

    tearDown(() async {
      await workspace.dispose();
    });

    test(
      'builds library with dependencies',
      skip: _cmakeAvailable ? null : 'CMake not available',
      () async {
        await cmakeConfigure(workspace.source.path, buildDir.path);
        await cmakeBuild(buildDir.path);

        final libName = sharedLibraryName('native_prebuilt_dependency');
        final libPath = _findBuiltLibrary(buildDir, libName);

        print('Build directory contents:');
        for (final entity in buildDir.listSync(recursive: true)) {
          if (entity is File) print('  ${entity.path}');
        }

        expect(libPath, isNotNull);
        print('Built library with dependencies: $libPath');
      },
      timeout: Timeout(Duration(minutes: 2)),
    );
  });
}

String? _findBuiltLibrary(Directory buildDir, String libName) {
  final searchDirs = [
    buildDir,
    Directory(p.join(buildDir.path, 'Release')),
    Directory(p.join(buildDir.path, 'Debug')),
    Directory(p.join(buildDir.path, 'build')),
    Directory(p.join(buildDir.path, 'out')),
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
