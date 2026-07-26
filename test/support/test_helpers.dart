/// Shared test helpers for integration and unit tests.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Returns the platform-specific shared library name for [stem].
String sharedLibraryName(String stem) {
  if (Platform.isWindows) return '$stem.dll';
  if (Platform.isMacOS) return 'lib$stem.dylib';
  return 'lib$stem.so';
}

/// Returns the platform-specific static library name for [stem].
String staticLibraryName(String stem) {
  if (Platform.isWindows) return '$stem.lib';
  return 'lib$stem.a';
}

/// Recursively copies [source] directory to [destination].
Future<void> copyDirectory(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await for (final entity in source.list(recursive: true)) {
    final rel = p.relative(entity.path, from: source.path);
    final dest = p.join(destination.path, rel);
    if (entity is File) {
      await Directory(p.dirname(dest)).create(recursive: true);
      await entity.copy(dest);
    } else if (entity is Directory) {
      await Directory(dest).create(recursive: true);
    }
  }
}

/// Configures CMake for the given source and build directories.
Future<void> cmakeConfigure(String sourceDir, String buildDir) async {
  final result = await Process.run('cmake', [
    '-S',
    sourceDir,
    '-B',
    buildDir,
    '-DCMAKE_BUILD_TYPE=Release',
  ], workingDirectory: sourceDir);

  if (result.exitCode != 0) {
    print('Configure stderr: ${result.stderr}');
    throw StateError('CMake configure failed: ${result.exitCode}');
  }
}

/// Builds with CMake for the given build directory.
Future<void> cmakeBuild(String buildDir, {List<String>? targets}) async {
  final args = ['--build', buildDir, '--config', 'Release'];
  if (targets != null) {
    for (final target in targets) {
      args.addAll(['--target', target]);
    }
  }

  final result = await Process.run('cmake', args);

  if (result.exitCode != 0) {
    print('Build stderr: ${result.stderr}');
    throw StateError('CMake build failed: ${result.exitCode}');
  }
}
