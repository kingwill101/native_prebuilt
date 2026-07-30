import 'dart:io';

import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Directory _findPackageDirectory(String packageName) {
  var dir = Directory.current.absolute;
  while (true) {
    final candidate = Directory(p.join(dir.path, packageName));
    if (File(p.join(candidate.path, 'native_prebuilt.yaml')).existsSync()) {
      return candidate;
    }
    if (dir.parent.path == dir.path) {
      throw StateError('Could not find $packageName in parent directories');
    }
    dir = dir.parent;
  }
}

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

    test(
      'keeps placeholder artifacts without hashes until a lock file is present',
      () {
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
          final project = detect(dir);
          expect(project, isNotNull);
          final artifact = project!.prebuilts.artifacts['linux-x64'];
          expect(artifact, isNotNull);
          expect(artifact!.archiveName, 'parent-linux-x64.tar.gz');
          expect(artifact.archiveSha256, isEmpty);
          expect(artifact.payloadSha256, isEmpty);
        } finally {
          dir.deleteSync(recursive: true);
        }
      },
    );

    test('overlays native_prebuilt.lock.yaml hashes when present', () {
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
        File('${dir.path}/native_prebuilt.lock.yaml').writeAsStringSync('''
schema: 1
release:
  tag: 'v2.0.0'
artifacts:
  'linux-x64':
    archive_sha256: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
    payload_sha256: 'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210'
''');
        final project = detect(dir);
        expect(project, isNotNull);
        final artifact = project!.prebuilts.artifacts['linux-x64'];
        expect(artifact, isNotNull);
        expect(
          artifact!.archiveSha256,
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        );
        expect(
          artifact.payloadSha256,
          'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210',
        );
        expect(project.prebuilts.release.tag, 'v2.0.0');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('parses the TDLib desktop manifest recipes', () {
      final project = detect(_findPackageDirectory('tdlib'));
      expect(project, isNotNull);

      for (final target in [
        const NativeTarget(os: OS.macOS, architecture: Architecture.arm64),
        const NativeTarget(os: OS.windows, architecture: Architecture.x64),
      ]) {
        final recipe = project!.build.recipeFor(target);
        expect(recipe, isA<StepBuildRecipe>(), reason: target.label);
        final steps = (recipe as StepBuildRecipe).steps;
        expect(steps, hasLength(3), reason: target.label);
        expect(steps[0], isA<CmakeConfigureStep>(), reason: target.label);
        expect(steps[1], isA<CmakeBuildStep>(), reason: target.label);
        expect(steps[2], isA<ExportArtifactStep>(), reason: target.label);
        expect(steps.map((s) => s.id).toList(), [
          'configure',
          'build',
          'export_tdjson',
        ], reason: target.label);
      }
    });

    test('parses the TDLib iOS manifest recipe', () {
      final project = detect(_findPackageDirectory('tdlib'));
      expect(project, isNotNull);

      final recipe = project!.build.recipeFor(
        const NativeTarget(os: OS.iOS, architecture: Architecture.arm64),
      );
      expect(recipe, isA<StepBuildRecipe>());
      final steps = (recipe as StepBuildRecipe).steps;
      expect(steps, hasLength(9));
      expect(steps[0], isA<CmakeConfigureStep>());
      expect(steps[1], isA<CmakeBuildStep>());
      expect(steps[2], isA<GitCheckoutStep>());
      expect(steps[3], isA<GitApplyPatchStep>());
      expect(steps[4], isA<CommandStep>());
      expect(steps[5], isA<CmakeConfigureStep>());
      expect(steps[6], isA<CmakeBuildStep>());
      expect(steps[7], isA<CommandStep>());
      expect(steps[8], isA<ExportArtifactStep>());
      expect((steps[4] as CommandStep).commands, [
        ['/usr/bin/make', 'OpenSSL-iOS'],
      ]);
      expect((steps[7] as CommandStep).commands, [
        [
          'install_name_tool',
          '-id',
          '@rpath/libtdjson.dylib',
          '{{ work }}/install/lib/libtdjson.dylib',
        ],
      ]);
    });

    test('returns no build recipes when no build section is present', () {
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
        expect(project!.build.recipes, isEmpty);
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

    test('returns no build recipes for unknown step types', () {
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
        expect(project!.build.recipes, isEmpty);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}
