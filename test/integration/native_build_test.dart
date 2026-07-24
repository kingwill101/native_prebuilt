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

void main() {
  // Skip these tests if CMake is not available
  setUpAll(() {
    final result = Process.runSync('cmake', ['--version']);
    if (result.exitCode != 0) {
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
      () async {
        // Configure
        final configureResult = await Process.run('cmake', [
          '-S',
          workspace.source.path,
          '-B',
          buildDir.path,
          '-DCMAKE_BUILD_TYPE=Release',
        ], workingDirectory: workspace.source.path);

        if (configureResult.exitCode != 0) {
          print('Configure stderr: ${configureResult.stderr}');
          fail('CMake configure failed: ${configureResult.exitCode}');
        }

        // Build
        final buildResult = await Process.run('cmake', [
          '--build',
          buildDir.path,
          '--config',
          'Release',
        ]);

        if (buildResult.exitCode != 0) {
          print('Build stderr: ${buildResult.stderr}');
          fail('CMake build failed: ${buildResult.exitCode}');
        }

        // Find the built library
        final libName = _sharedLibraryName('native_prebuilt_fixture');
        final libPath = _findBuiltLibrary(buildDir, libName);

        expect(libPath, isNotNull, reason: 'Shared library not found');
        expect(
          File(libPath!).existsSync(),
          isTrue,
          reason: 'Shared library file does not exist',
        );

        print('✅ Built shared library: $libPath');
        print('   Size: ${File(libPath).lengthSync()} bytes');
      },
      timeout: Timeout(Duration(minutes: 2)),
    );

    test(
      'shared library exports expected symbols',
      () async {
        // Skip on Windows - different library naming
        if (Platform.isWindows) {
          print('Skipping symbol test on Windows');
          return;
        }

        // Build first
        await Process.run('cmake', [
          '-S',
          workspace.source.path,
          '-B',
          buildDir.path,
        ]);
        await Process.run('cmake', ['--build', buildDir.path]);

        final libName = _sharedLibraryName('native_prebuilt_fixture');
        final libPath = _findBuiltLibrary(buildDir, libName);

        if (libPath == null) {
          fail('Library not found');
        }

        // Try to load and call the library
        try {
          final lib = DynamicLibrary.open(libPath);

          // Look for the add function
          final addFn = lib
              .lookupFunction<
                Int32 Function(Int32, Int32),
                int Function(int, int)
              >('native_prebuilt_fixture_add');

          // Test the function
          final result = addFn(2, 3);
          expect(result, equals(5), reason: 'add(2, 3) should return 5');

          // Look for the version function
          final versionFn = lib
              .lookupFunction<
                Pointer<Utf8> Function(),
                Pointer<Utf8> Function()
              >('native_prebuilt_fixture_version');

          final versionPtr = versionFn();
          final version = versionPtr.toDartString();
          expect(version, isNotEmpty, reason: 'Version should not be empty');

          print('✅ Library functions work correctly');
          print('   add(2, 3) = $result');
          print('   version = $version');

          lib.close();
        } catch (e) {
          fail('Failed to load or call library: $e');
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

    test('builds static library', () async {
      final configureResult = await Process.run('cmake', [
        '-S',
        workspace.source.path,
        '-B',
        buildDir.path,
      ]);

      if (configureResult.exitCode != 0) {
        print('Configure error: ${configureResult.stderr}');
        fail('CMake configure failed');
      }

      final buildResult = await Process.run('cmake', [
        '--build',
        buildDir.path,
      ]);

      if (buildResult.exitCode != 0) {
        print('Build error: ${buildResult.stderr}');
        fail('CMake build failed');
      }

      // Find the static library
      final libName = _staticLibraryName('native_prebuilt_fixture_static');
      final libPath = _findBuiltLibrary(buildDir, libName);

      expect(libPath, isNotNull, reason: 'Static library not found');
      expect(File(libPath!).existsSync(), isTrue);

      print('✅ Built static library: $libPath');
      print('   Size: ${File(libPath).lengthSync()} bytes');
    }, timeout: Timeout(Duration(minutes: 2)));
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

    test('builds library with dependencies', () async {
      final configureResult = await Process.run('cmake', [
        '-S',
        workspace.source.path,
        '-B',
        buildDir.path,
      ]);

      if (configureResult.exitCode != 0) {
        print('Configure output: ${configureResult.stdout}');
        print('Configure error: ${configureResult.stderr}');
        fail('CMake configure failed');
      }

      final buildResult = await Process.run('cmake', [
        '--build',
        buildDir.path,
      ]);

      if (buildResult.exitCode != 0) {
        print('Build output: ${buildResult.stdout}');
        print('Build error: ${buildResult.stderr}');
        fail('CMake build failed');
      }

      final libName = _sharedLibraryName('native_prebuilt_dependency');
      final libPath = _findBuiltLibrary(buildDir, libName);

      // Debug: list what's in the build directory
      print('Build directory contents:');
      for (final entity in buildDir.listSync(recursive: true)) {
        if (entity is File) print('  ${entity.path}');
      }

      expect(libPath, isNotNull);
      print('✅ Built library with dependencies: $libPath');
    }, timeout: Timeout(Duration(minutes: 2)));
  });
}

// Helper functions
String _sharedLibraryName(String stem) {
  if (Platform.isWindows) return '$stem.dll';
  if (Platform.isMacOS) return 'lib$stem.dylib';
  return 'lib$stem.so';
}

String _staticLibraryName(String stem) {
  if (Platform.isWindows) return '$stem.lib';
  return 'lib$stem.a';
}

String? _findBuiltLibrary(Directory buildDir, String libName) {
  // Search common build output directories
  final searchDirs = [
    buildDir,
    Directory(p.join(buildDir.path, 'Release')),
    Directory(p.join(buildDir.path, 'Debug')),
    Directory(p.join(buildDir.path, 'build')),
    Directory(p.join(buildDir.path, 'out')),
  ];

  for (final dir in searchDirs) {
    if (!dir.existsSync()) continue;

    // Check the directory itself
    final libFile = File(p.join(dir.path, libName));
    if (libFile.existsSync()) return libFile.path;

    // Search recursively (limited depth)
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
