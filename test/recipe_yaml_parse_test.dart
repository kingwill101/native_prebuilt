import 'dart:io';

import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:native_prebuilt/src/cli/cli_config.dart';
import 'package:test/test.dart';

void main() {
  group('detect() with build recipes', () {
    test('falls back to generic CMake when no build section present', () {
      final dir = Directory.systemTemp.createTempSync('npb_test_');
      try {
        File('${dir.path}/native_prebuilt.yaml').writeAsStringSync('''
schema: 1
package: my_pkg
asset_name: my_pkg.dart
library_stem: my_pkg
release:
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

    test('parses YAML-defined build recipes', () {
      final dir = Directory.systemTemp.createTempSync('npb_test_');
      try {
        File('${dir.path}/native_prebuilt.yaml').writeAsStringSync('''
schema: 1
package: tdlib
asset_name: src/tdlib.g.dart
library_stem: tdjson
link_mode: dynamic_library
release:
  repository: kingwill101/tdlib
  tag: tdlib-v1.8.64
artifacts:
  linux-x64:
    archive: tdlib-linux-x64.tar.gz
    payload:
      type: dynamic_library
build:
  linux-x64:
    steps:
      - type: cmake_configure
        source_directory: .
        build_directory: build
        defines:
          CMAKE_BUILD_TYPE: Release
      - type: cmake_build
        build_directory: build
      - type: export_artifact
        id: tdjson
        kind: dynamic_library
        primary_path: build/libtdjson.so
''');
        final project = detect(dir);
        expect(project, isNotNull);

        final build = project!.build;
        expect(build.recipes, hasLength(1));

        final linuxRecipe = build.recipes.first;
        expect(linuxRecipe.pattern.os, OS.linux);

        final stepBuild = linuxRecipe.recipe as StepBuildRecipe;
        expect(stepBuild.steps, hasLength(3));
        expect(stepBuild.steps[0].id, 'cmake_configure');
        expect(stepBuild.steps[1].id, 'cmake_build');
        expect(stepBuild.steps[2].id, 'tdjson');
        expect((stepBuild.steps[2] as ExportArtifactStep).declaration.id, 'tdjson');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('parses build recipes for multiple platforms', () {
      final dir = Directory.systemTemp.createTempSync('npb_test_');
      try {
        File('${dir.path}/native_prebuilt.yaml').writeAsStringSync('''
schema: 1
package: my_pkg
asset_name: my_pkg.dart
library_stem: my_pkg
release:
  repository: owner/repo
  tag: my_pkg-v1.0.0
artifacts:
  linux-x64:
    archive: my-pkg.tar.gz
    payload:
      type: dynamic_library
  macos-arm64:
    archive: my-pkg-macos.tar.gz
    payload:
      type: dynamic_library
build:
  linux-x64:
    steps:
      - type: cmake_configure
        source_directory: .
        build_directory: build
        defines:
          CMAKE_BUILD_TYPE: Release
  macos-arm64:
    steps:
      - type: cmake_configure
        source_directory: .
        build_directory: build
        generator: Xcode
        defines:
          CMAKE_BUILD_TYPE: Release
''');
        final project = detect(dir);
        expect(project, isNotNull);

        final build = project!.build;
        expect(build.recipes, hasLength(2));

        final linuxRecipe = build.recipes.firstWhere((r) => r.pattern.os == OS.linux);
        final macosRecipe = build.recipes.firstWhere((r) => r.pattern.os == OS.macOS);

        final linuxSteps = (linuxRecipe.recipe as StepBuildRecipe).steps;
        expect(linuxSteps, hasLength(1));
        expect(linuxSteps.first.id, 'cmake_configure');

        final macosSteps = (macosRecipe.recipe as StepBuildRecipe).steps;
        expect(macosSteps, hasLength(1));

        // macOS recipe should have Xcode generator
        final macosConfigure = macosSteps.first as CmakeConfigureStep;
        expect(macosConfigure.generator, 'Xcode');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('throws StateError for unknown step type', () {
      final dir = Directory.systemTemp.createTempSync('npb_test_');
      try {
        File('${dir.path}/native_prebuilt.yaml').writeAsStringSync('''
schema: 1
package: my_pkg
asset_name: my_pkg.dart
library_stem: my_pkg
release:
  repository: owner/repo
  tag: my_pkg-v1.0.0
artifacts:
  linux-x64:
    archive: my-pkg.tar.gz
    payload:
      type: dynamic_library
build:
  linux-x64:
    steps:
      - type: nonexistent_step
        foo: bar
''');
        expect(() => detect(dir), throwsStateError);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('throws StateError when step map is missing type key', () {
      final dir = Directory.systemTemp.createTempSync('npb_test_');
      try {
        File('${dir.path}/native_prebuilt.yaml').writeAsStringSync('''
schema: 1
package: my_pkg
asset_name: my_pkg.dart
library_stem: my_pkg
release:
  repository: owner/repo
  tag: my_pkg-v1.0.0
artifacts:
  linux-x64:
    archive: my-pkg.tar.gz
    payload:
      type: dynamic_library
build:
  linux-x64:
    steps:
      - source_directory: .
''');
        expect(() => detect(dir), throwsStateError);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}
