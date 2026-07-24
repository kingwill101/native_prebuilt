/// Test support infrastructure for native_prebuilt tests.
///
/// This library provides utilities for creating isolated test workspaces,
/// recording process execution, and building test inputs.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// An isolated workspace for a single test.
///
/// Each test gets its own temporary directory with source, cache,
/// work, and output subdirectories. This prevents tests from interfering
/// with each other.
final class FixtureWorkspace {
  FixtureWorkspace._({
    required this.root,
    required this.source,
    required this.cache,
    required this.work,
    required this.output,
  });

  /// The root directory of the workspace.
  final Directory root;

  /// The source directory (copy of the fixture).
  final Directory source;

  /// The cache directory for build caches.
  final Directory cache;

  /// The work directory for intermediate files.
  final Directory work;

  /// The output directory for final artifacts.
  final Directory output;

  /// Creates a new workspace from a fixture.
  ///
  /// The fixture is copied to a temporary directory to prevent
  /// mutation of checked-in files.
  static Future<FixtureWorkspace> create(
    String fixtureName, {
    String? tempRoot,
  }) async {
    final root = await Directory.systemTemp.createTemp(
      tempRoot ?? 'native_prebuilt_test_',
    );

    final fixture = Directory(
      p.join(
        Directory.current.path,
        'test',
        'fixtures',
        'native_projects',
        fixtureName,
      ),
    );

    if (!fixture.existsSync()) {
      throw ArgumentError('Fixture not found: $fixtureName');
    }

    final source = Directory(p.join(root.path, 'source'));
    await _copyFixtureDirectory(fixture, source);

    final cache = Directory(p.join(root.path, 'cache'))
      ..createSync(recursive: true);
    final work = Directory(p.join(root.path, 'work'))
      ..createSync(recursive: true);
    final output = Directory(p.join(root.path, 'output'))
      ..createSync(recursive: true);

    return FixtureWorkspace._(
      root: root,
      source: source,
      cache: cache,
      work: work,
      output: output,
    );
  }

  /// Cleans up the workspace.
  Future<void> dispose() async {
    if (root.existsSync()) {
      await root.delete(recursive: true);
    }
  }

  static Future<void> _copyFixtureDirectory(
    Directory source,
    Directory destination,
  ) async {
    await destination.create(recursive: true);

    await for (final entity in source.list(recursive: true)) {
      final relativePath = p.relative(entity.path, from: source.path);
      final destPath = p.join(destination.path, relativePath);

      if (entity is File) {
        await entity.copy(destPath);
      } else if (entity is Directory) {
        await Directory(destPath).create(recursive: true);
      }
    }
  }
}
