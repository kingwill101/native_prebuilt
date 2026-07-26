import 'package:native_prebuilt/build.dart';
import 'package:test/test.dart';

void main() {
  group('CmakeConfigureStep fromMap / toMap', () {
    test('round-trip through fromMap and toMap', () {
      final original = CmakeConfigureStep(
        sourceDirectory: '.',
        buildDirectory: 'build',
        defines: {'CMAKE_BUILD_TYPE': 'Release'},
        generator: 'Ninja',
        toolchainFile: 'CMake/toolchain.cmake',
      );

      final map = original.toMap();
      final restored = CmakeConfigureStep.fromMap(map);

      expect(restored.sourceDirectory, original.sourceDirectory);
      expect(restored.buildDirectory, original.buildDirectory);
      expect(restored.defines, original.defines);
      expect(restored.generator, original.generator);
      expect(restored.toolchainFile, original.toolchainFile);
    });

    test('fromMap parses required fields', () {
      final step = CmakeConfigureStep.fromMap({
        'source_directory': '.',
        'build_directory': 'build',
        'defines': {'CMAKE_BUILD_TYPE': 'Release'},
      });

      expect(step.sourceDirectory, '.');
      expect(step.buildDirectory, 'build');
      expect(step.defines, {'CMAKE_BUILD_TYPE': 'Release'});
    });

    test('fromMap uses defaults for optional fields', () {
      final step = CmakeConfigureStep.fromMap({'source_directory': '.'});

      expect(step.sourceDirectory, '.');
      expect(step.buildDirectory, isNull);
      expect(step.defines, isEmpty);
      expect(step.generator, isNull);
      expect(step.toolchainFile, isNull);
    });

    test('toMap includes type tag', () {
      final step = CmakeConfigureStep(sourceDirectory: '.');
      final map = step.toMap();
      expect(map['type'], 'cmake_configure');
    });

    test('toMap omits null optional fields', () {
      final step = CmakeConfigureStep(sourceDirectory: '.');
      final map = step.toMap();
      expect(map.containsKey('build_directory'), isFalse);
      expect(map.containsKey('generator'), isFalse);
      expect(map.containsKey('toolchain_file'), isFalse);
    });
  });

  group('CmakeBuildStep fromMap / toMap', () {
    test('round-trip through fromMap and toMap', () {
      final original = CmakeBuildStep(
        buildDirectory: 'build',
        targets: ['mylib'],
        parallel: true,
      );

      final map = original.toMap();
      final restored = CmakeBuildStep.fromMap(map);

      expect(restored.buildDirectory, original.buildDirectory);
      expect(restored.targets, original.targets);
      expect(restored.parallel, original.parallel);
    });

    test('fromMap parses required and optional fields', () {
      final step = CmakeBuildStep.fromMap({
        'build_directory': 'build',
        'targets': ['mylib', 'helper'],
        'parallel': false,
      });

      expect(step.buildDirectory, 'build');
      expect(step.targets, ['mylib', 'helper']);
      expect(step.parallel, false);
    });

    test('fromMap defaults targets to empty and parallel to true', () {
      final step = CmakeBuildStep.fromMap({'build_directory': 'build'});

      expect(step.targets, isEmpty);
      expect(step.parallel, isTrue);
    });

    test('toMap includes type tag', () {
      final step = CmakeBuildStep(buildDirectory: 'build');
      final map = step.toMap();
      expect(map['type'], 'cmake_build');
    });
  });

  group('ExportArtifactStep fromMap / toMap', () {
    test('round-trip through fromMap and toMap', () {
      final original = ExportArtifactStep(
        id: 'export_mylib',
        declaration: NativeArtifactDeclaration(
          id: 'mylib',
          kind: NativeArtifactKind.dynamicLibrary,
          primaryPath: 'build/libmylib.so',
        ),
      );

      final map = original.toMap();
      final restored = ExportArtifactStep.fromMap(map);

      expect(map['id'], 'export_mylib');
      expect(map['artifact'], 'mylib');
      expect(restored.id, original.id);
      expect(restored.declaration.id, original.declaration.id);
      expect(restored.declaration.kind, original.declaration.kind);
      expect(
        restored.declaration.primaryPath,
        original.declaration.primaryPath,
      );
    });

    test('fromMap parses all fields including companions', () {
      final step = ExportArtifactStep.fromMap({
        'id': 'mylib',
        'kind': 'dynamic_library',
        'primary_path': 'build/libmylib.so',
        'companions': [
          {'path': 'build/libmylib.a', 'role': 'primary', 'optional': false},
        ],
      });

      expect(step.declaration.primaryPath, 'build/libmylib.so');
      expect(step.declaration.companions, hasLength(1));
      expect(step.declaration.companions.first.path, 'build/libmylib.a');
    });

    test('fromMap defaults kind to dynamic_library', () {
      final step = ExportArtifactStep.fromMap({
        'id': 'mylib',
        'primary_path': 'build/libmylib.so',
      });

      expect(step.declaration.kind, NativeArtifactKind.dynamicLibrary);
    });

    test('toMap includes type tag', () {
      final step = ExportArtifactStep(
        id: 'mylib',
        declaration: NativeArtifactDeclaration(
          id: 'mylib',
          kind: NativeArtifactKind.dynamicLibrary,
          primaryPath: 'build/libmylib.so',
        ),
      );
      final map = step.toMap();
      expect(map['type'], 'export_artifact');
    });
  });
}
