import 'dart:io';

import 'package:native_prebuilt/src/cli/cli_config.dart';
import 'package:test/test.dart';

void main() {
  group('detect() with build recipes', () {
    test('finds native_prebuilt.yaml in a parent directory', () {
      final dir = Directory.systemTemp.createTempSync('npb_test_');
      try {
        File('${dir.path}/native_prebuilt.yaml').writeAsStringSync('''
schema: 1
package: parent_pkg
asset_name: parent.dart
library_stem: parent
release:
  provider: github
  repository: owner/repo
  tag: v1.0.0
artifacts:
  linux-x64:
    archive: parent-linux-x64.tar.gz
    payload:
      type: dynamic_library
''');
        final child = Directory('${dir.path}/child')..createSync();
        final previousDir = Directory.current;
        try {
          Directory.current = child;
          final project = detect();
          expect(project, isNotNull);
          expect(project!.name, 'parent_pkg');
        } finally {
          Directory.current = previousDir;
        }
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('falls back to generic CMake when no build section present', () {
      final dir = Directory.systemTemp.createTempSync('npb_test_');
      try {
        File('${dir.path}/native_prebuilt.yaml').writeAsStringSync('''
schema: 2
package: my_pkg
asset_name: my_pkg.dart
library_stem: my_pkg
release:
  provider: github
  repository: owner/repo
  tag: my_pkg-v1.0.0
artifacts:
  linux-x64:
    archive: my-pkg.tar.gz
    payload:
      type: dynamic_library
''');
        final project = detect(dir);
        expect(project, isNotNull);
        expect(project!.build.recipes, isNotEmpty);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('parses YAML-defined build recipes with target patterns', () {
      final dir = Directory.systemTemp.createTempSync('npb_test_');
      try {
        File('${dir.path}/native_prebuilt.yaml').writeAsStringSync('''
schema: 2
package: tdlib
asset_name: src/tdlib.g.dart
library_stem: tdjson
release:
  provider: github
  repository: kingwill101/tdlib
  tag: tdlib-v1.8.64
build:
  recipes:
    - target:
        os: linux
      steps:
        - id: configure
          type: cmake_configure
          source_directory: .
          build_directory: build
          definitions:
            CMAKE_BUILD_TYPE: Release
          generator: Ninja
        - id: build
          type: cmake_build
          build_directory: build
          targets:
            - tdjson
        - id: export
          type: export_artifact
          artifact: tdjson
          kind: dynamic_library
          primary: build/td/libtdjson.so
targets:
  linux-x64:
    enabled: true
artifacts:
  linux-x64:
    archive: tdlib-linux-x64.tar.gz
    payload:
      type: dynamic_library
''');
        final project = detect(dir);
        expect(project, isNotNull);

        final build = project!.build;
        expect(build.recipes, isNotEmpty);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('parses build recipes with target-specific steps', () {
      final dir = Directory.systemTemp.createTempSync('npb_test_');
      try {
        File('${dir.path}/native_prebuilt.yaml').writeAsStringSync('''
schema: 2
package: tdlib
asset_name: src/tdlib.g.dart
library_stem: tdjson
release:
  provider: github
  repository: kingwill101/tdlib
  tag: tdlib-v1.8.64
build:
  recipes:
    - target:
        os: linux
      steps:
        - id: configure
          type: cmake_configure
          source_directory: .
          build_directory: build
          generator: Ninja
        - id: build
          type: cmake_build
          build_directory: build
          targets:
            - tdjson
        - id: export
          type: export_artifact
          artifact: tdjson
          kind: dynamic_library
          primary: build/td/libtdjson.so
    - target:
        os: windows
      steps:
        - id: configure
          type: cmake_configure
          source_directory: .
          build_directory: build
          generator: Ninja
        - id: build
          type: cmake_build
          build_directory: build
          targets:
            - tdjson
        - id: export
          type: export_artifact
          artifact: tdjson
          kind: dynamic_library
          primary: build/td/tdjson.dll
targets:
  linux-x64:
    enabled: true
artifacts:
  linux-x64:
    archive: tdlib-linux-x64.tar.gz
    payload:
      type: dynamic_library
''');
        final project = detect(dir);
        expect(project, isNotNull);

        final build = project!.build;
        expect(build.recipes, isNotEmpty);
        expect(build.recipes.length, 2);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('parses build recipes with dependencies', () {
        final dir = Directory.systemTemp.createTempSync('npb_test_');
      try {
        File('${dir.path}/native_prebuilt.yaml').writeAsStringSync('''
schema: 2
package: tdlib
asset_name: src/tdlib.g.dart
library_stem: tdjson
release:
  provider: github
  repository: kingwill101/tdlib
  tag: tdlib-v1.8.64
build:
  recipes:
    - target:
        os: linux
      steps:
        - id: configure
          type: cmake_configure
          source_directory: .
          build_directory: build
          definitions:
            CMAKE_BUILD_TYPE: Release
  dependencies:
    openssl:
      version: 1.1.1w
      url: https://www.openssl.org/source/openssl-1.1.1w.tar.gz
      sha256: REPLACE_WITH_REAL_HASH

targets:
  linux-x64:
    enabled: true
artifacts:
  linux-x64:
    archive: tdlib-linux-x64.tar.gz
    payload:
      type: dynamic_library
''');
        final project = detect(dir);
        expect(project, isNotNull);

        final build = project!.build;
        expect(build.recipes, isNotEmpty);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('falls back to generic CMake for unknown step type', () {
      final dir = Directory.systemTemp.createTempSync('npb_test_');
      try {
        File('${dir.path}/native_prebuilt.yaml').writeAsStringSync('''
schema: 2
package: my_pkg
asset_name: my_pkg.dart
library_stem: my_pkg
release:
  provider: github
  repository: owner/repo
  tag: my_pkg-v1.0.0
artifacts:
  linux-x64:
    archive: my-pkg.tar.gz
    payload:
      type: dynamic_library
build:
  recipes:
    - target:
        os: linux
      steps:
        - id: step1
          type: nonexistent_step
          source: .
''');
        final project = detect(dir);
        expect(project, isNotNull);
        // Falls back to generic CMake when build parsing fails
        expect(project!.build.recipes, isNotEmpty);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}
