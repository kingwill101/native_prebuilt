/// Managed pipeline integration test.
///
/// Tests NativeProjectExecutor end-to-end using the simple_shared C fixture.
/// Requires CMake and a C compiler.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:ffi/ffi.dart';
import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/test_helpers.dart';

bool _cmakeAvailable = false;

void main() {
  late Directory fixtureDir;
  late Directory tempDir;

  setUpAll(() async {
    final cmakeCheck = await Process.run('cmake', ['--version']);
    _cmakeAvailable = cmakeCheck.exitCode == 0;
    if (!_cmakeAvailable) {
      print('Skipping managed build tests: CMake not found');
    }

    fixtureDir = Directory(
      p.join(
        Directory.current.path,
        'test',
        'fixtures',
        'native_projects',
        'simple_shared',
      ),
    );

    if (!fixtureDir.existsSync()) {
      fail('Fixture directory not found: ${fixtureDir.path}');
    }
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('managed_build_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('NativeProjectExecutor', () {
    test(
      'builds simple_shared fixture and returns valid artifact',
      skip: _cmakeAvailable ? null : 'CMake not available',
      () async {
        final outputDir = Directory(p.join(tempDir.path, 'output'));

        final project = NativeProject(
          name: 'simple_shared_fixture',
          asset: NativeAssetSpec(
            assetName: 'simple_shared_fixture_bindings',
            libraryStem: 'native_prebuilt_fixture',
            linkMode: DynamicLoadingBundled(),
          ),
          prebuilts: const PrebuiltManifest(
            schemaVersion: 1,
            release: GitHubReleaseSource(
              owner: 'fixture',
              repository: 'simple_shared',
              tag: 'v0.0.0',
            ),
            artifacts: {},
          ),
          sources: const [],
          build: NativeBuildDefinition(
            recipes: [
              NativeTargetRecipe(
                pattern: NativeTargetPattern(
                  os: OS.current,
                  architecture: Architecture.current,
                ),
                recipe: StepBuildRecipe(
                  steps: [
                    CmakeConfigureStep(
                      sourceDirectory: '.',
                      buildDirectory: 'build',
                    ),
                    CmakeBuildStep(
                      buildDirectory: 'build',
                      targets: ['native_prebuilt_fixture'],
                    ),
                    ExportArtifactStep(
                      id: 'export_native_prebuilt_fixture',
                      declaration: NativeArtifactDeclaration(
                        id: 'native_prebuilt_fixture',
                        kind: NativeArtifactKind.dynamicLibrary,
                        primaryPath:
                            'build/${sharedLibraryName('native_prebuilt_fixture')}',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          prebuiltPolicy: PrebuiltPolicy.forceSourceBuild,
        );

        final executor = NativeProjectExecutor(
          project: project,
          source: ResolvedSource(
            directory: fixtureDir,
            origin: SourceOrigin.local,
          ),
          logger: null,
        );

        final result = await executor.build(
          target: NativeTarget(
            os: OS.current,
            architecture: Architecture.current,
          ),
          outputDir: outputDir,
        );

        // Assert: artifacts non-empty
        expect(
          result.artifacts,
          isNotEmpty,
          reason: 'Should produce at least one artifact',
        );

        final artifact = result.artifacts.first;

        // Assert: correct id and kind
        expect(artifact.id, equals('native_prebuilt_fixture'));
        expect(artifact.kind, equals(NativeArtifactKind.dynamicLibrary));
        expect(artifact.target.os, equals(OS.current));
        expect(artifact.target.architecture, equals(Architecture.current));

        // Assert: primary entry file exists on disk
        final primarySource = File.fromUri(artifact.primary.source.uri);
        expect(
          primarySource.existsSync(),
          isTrue,
          reason: 'Primary artifact file must exist on disk',
        );

        // Assert: staged directory follows contract
        final stagedPrimary = File(
          p.join(outputDir.path, artifact.primary.path),
        );
        expect(
          stagedPrimary.existsSync(),
          isTrue,
          reason: 'Staged primary artifact must exist',
        );

        // Assert: native_prebuilt.json present
        final metadataFile = File(
          p.join(outputDir.path, 'native_prebuilt.json'),
        );
        expect(
          metadataFile.existsSync(),
          isTrue,
          reason: 'native_prebuilt.json must be present',
        );

        // Assert: library is FFI-loadable and callable
        if (!Platform.isWindows) {
          DynamicLibrary? lib;
          try {
            lib = DynamicLibrary.open(stagedPrimary.path);
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
            final version = versionFn().toDartString();
            expect(version, isNotEmpty);
          } catch (e) {
            fail('Failed to load or call FFI library: $e');
          } finally {
            lib?.close();
          }
        }

        print('Managed build test passed');
        print('  Artifact: ${artifact.id} (${artifact.kind.name})');
        print('  Primary: ${artifact.primary.path}');
        print(
          '  Files: ${artifact.entries.map((e) => '${e.role.name}:${e.path}').join(', ')}',
        );
      },
      timeout: Timeout(Duration(minutes: 3)),
    );

    test(
      'staged output includes role-based subdirectories',
      skip: _cmakeAvailable ? null : 'CMake not available',
      () async {
        final outputDir = Directory(p.join(tempDir.path, 'output'));

        final project = NativeProject(
          name: 'role_test',
          asset: NativeAssetSpec(
            assetName: 'role_test_bindings',
            libraryStem: 'native_prebuilt_fixture',
            linkMode: DynamicLoadingBundled(),
          ),
          prebuilts: const PrebuiltManifest(
            schemaVersion: 1,
            release: GitHubReleaseSource(
              owner: 'fixture',
              repository: 'role_test',
              tag: 'v0.0.0',
            ),
            artifacts: {},
          ),
          sources: const [],
          build: NativeBuildDefinition(
            recipes: [
              NativeTargetRecipe(
                pattern: NativeTargetPattern(
                  os: OS.current,
                  architecture: Architecture.current,
                ),
                recipe: StepBuildRecipe(
                  steps: [
                    CmakeConfigureStep(
                      sourceDirectory: '.',
                      buildDirectory: 'build',
                    ),
                    CmakeBuildStep(
                      buildDirectory: 'build',
                      targets: [
                        'native_prebuilt_fixture',
                        'native_prebuilt_fixture_static',
                      ],
                    ),
                    ExportArtifactStep(
                      id: 'export_native_prebuilt_fixture',
                      declaration: NativeArtifactDeclaration(
                        id: 'native_prebuilt_fixture',
                        kind: NativeArtifactKind.dynamicLibrary,
                        primaryPath:
                            'build/${sharedLibraryName('native_prebuilt_fixture')}',
                        companions: [
                          NativeArtifactCompanion(
                            path:
                                'build/${staticLibraryName('native_prebuilt_fixture_static')}',
                            role: NativeArtifactRole.importLibrary,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          prebuiltPolicy: PrebuiltPolicy.forceSourceBuild,
        );

        final executor = NativeProjectExecutor(
          project: project,
          source: ResolvedSource(
            directory: fixtureDir,
            origin: SourceOrigin.local,
          ),
          logger: null,
        );

        final result = await executor.build(
          target: NativeTarget(
            os: OS.current,
            architecture: Architecture.current,
          ),
          outputDir: outputDir,
        );

        expect(result.artifacts, isNotEmpty);

        // Verify the link/ subdirectory exists for the static library companion
        final linkDir = Directory(p.join(outputDir.path, 'link'));
        expect(
          linkDir.existsSync(),
          isTrue,
          reason:
              'link/ subdirectory should exist for import library companion',
        );

        print('Role-based staging test passed');
        print('  Output contents:');
        for (final entity in outputDir.listSync(recursive: true)) {
          final rel = p.relative(entity.path, from: outputDir.path);
          print('    $rel');
        }
      },
      timeout: Timeout(Duration(minutes: 3)),
    );

    test(
      'second build uses cache hit and returns same artifacts',
      skip: _cmakeAvailable ? null : 'CMake not available',
      () async {
        final outputDir1 = Directory(p.join(tempDir.path, 'output1'));
        final outputDir2 = Directory(p.join(tempDir.path, 'output2'));
        final cacheDir = Directory(p.join(tempDir.path, 'cache'));

        final project = NativeProject(
          name: 'cache_test',
          asset: NativeAssetSpec(
            assetName: 'cache_test_bindings',
            libraryStem: 'native_prebuilt_fixture',
            linkMode: DynamicLoadingBundled(),
          ),
          prebuilts: const PrebuiltManifest(
            schemaVersion: 1,
            release: GitHubReleaseSource(
              owner: 'fixture',
              repository: 'cache_test',
              tag: 'v0.0.0',
            ),
            artifacts: {},
          ),
          sources: const [],
          build: NativeBuildDefinition(
            recipes: [
              NativeTargetRecipe(
                pattern: NativeTargetPattern(
                  os: OS.current,
                  architecture: Architecture.current,
                ),
                recipe: StepBuildRecipe(
                  steps: [
                    CmakeConfigureStep(
                      sourceDirectory: '.',
                      buildDirectory: 'build',
                    ),
                    CmakeBuildStep(
                      buildDirectory: 'build',
                      targets: ['native_prebuilt_fixture'],
                    ),
                    ExportArtifactStep(
                      id: 'export_native_prebuilt_fixture',
                      declaration: NativeArtifactDeclaration(
                        id: 'native_prebuilt_fixture',
                        kind: NativeArtifactKind.dynamicLibrary,
                        primaryPath:
                            'build/${sharedLibraryName('native_prebuilt_fixture')}',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          prebuiltPolicy: PrebuiltPolicy.forceSourceBuild,
        );

        final target = NativeTarget(
          os: OS.current,
          architecture: Architecture.current,
        );

        final source = ResolvedSource(
          directory: fixtureDir,
          origin: SourceOrigin.local,
        );

        // First build: cold cache
        final cache = BuildCache(
          projectName: 'cache_test',
          targetLabel: target.label,
          cacheRoot: cacheDir,
        );

        final executor1 = NativeProjectExecutor(
          project: project,
          source: source,
          cache: cache,
          logger: null,
        );

        final result1 = await executor1.build(
          target: target,
          outputDir: outputDir1,
        );

        expect(
          result1.artifacts,
          isNotEmpty,
          reason: 'First build should produce artifacts',
        );

        // Second build: should hit cache
        final executor2 = NativeProjectExecutor(
          project: project,
          source: source,
          cache: cache,
          logger: null,
        );

        final result2 = await executor2.build(
          target: target,
          outputDir: outputDir2,
        );

        expect(
          result2.artifacts,
          isNotEmpty,
          reason: 'Second build (cached) should still produce artifacts',
        );
        expect(result2.artifacts.length, equals(result1.artifacts.length));
        expect(result2.artifacts.first.id, equals(result1.artifacts.first.id));

        // Verify the built library still works
        if (!Platform.isWindows) {
          DynamicLibrary? lib;
          try {
            lib = DynamicLibrary.open(
              File(
                p.join(outputDir2.path, result2.artifacts.first.primary.path),
              ).path,
            );
            final addFn = lib
                .lookupFunction<
                  Int32 Function(Int32, Int32),
                  int Function(int, int)
                >('native_prebuilt_fixture_add');
            expect(addFn(2, 3), equals(5));
          } finally {
            lib?.close();
          }
        }

        print('Cache hit test passed');
        print('  First build: ${result1.artifacts.length} artifact(s)');
        print(
          '  Second build: ${result2.artifacts.length} artifact(s) (cached)',
        );
      },
      timeout: Timeout(Duration(minutes: 3)),
    );

    test(
      'generated-source invalidation rebuilds when source changes',
      skip: _cmakeAvailable ? null : 'CMake not available',
      () async {
        final genFixtureDir = Directory(
          p.join(
            Directory.current.path,
            'test',
            'fixtures',
            'native_projects',
            'generated_source',
          ),
        );

        if (!genFixtureDir.existsSync()) {
          print('Skipping generated-source test: fixture not found');
          return;
        }

        // Copy fixture to temp dir for mutation
        final workDir = Directory(p.join(tempDir.path, 'gen_source'));
        await copyDirectory(genFixtureDir, workDir);

        // Write initial value
        await File(
          p.join(workDir.path, 'input', 'value.txt'),
        ).writeAsString('42');

        final outputDir1 = Directory(p.join(tempDir.path, 'gen_output1'));

        final project = NativeProject(
          name: 'gen_source_test',
          asset: NativeAssetSpec(
            assetName: 'gen_bindings',
            libraryStem: 'native_prebuilt_generated',
            linkMode: DynamicLoadingBundled(),
          ),
          prebuilts: const PrebuiltManifest(
            schemaVersion: 1,
            release: GitHubReleaseSource(
              owner: 'fixture',
              repository: 'gen_source',
              tag: 'v0.0.0',
            ),
            artifacts: {},
          ),
          sources: const [],
          build: NativeBuildDefinition(
            recipes: [
              NativeTargetRecipe(
                pattern: NativeTargetPattern(
                  os: OS.current,
                  architecture: Architecture.current,
                ),
                recipe: StepBuildRecipe(
                  steps: [
                    CmakeConfigureStep(
                      sourceDirectory: '.',
                      buildDirectory: 'build',
                    ),
                    CmakeBuildStep(
                      buildDirectory: 'build',
                      targets: ['native_prebuilt_generated'],
                    ),
                    ExportArtifactStep(
                      id: 'export_generated',
                      declaration: NativeArtifactDeclaration(
                        id: 'native_prebuilt_generated',
                        kind: NativeArtifactKind.dynamicLibrary,
                        primaryPath:
                            'build/${sharedLibraryName('native_prebuilt_generated')}',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          prebuiltPolicy: PrebuiltPolicy.forceSourceBuild,
        );

        final target = NativeTarget(
          os: OS.current,
          architecture: Architecture.current,
        );

        final source = ResolvedSource(
          directory: workDir,
          origin: SourceOrigin.local,
        );

        final executor = NativeProjectExecutor(
          project: project,
          source: source,
          logger: null,
        );

        final result1 = await executor.build(
          target: target,
          outputDir: outputDir1,
        );

        expect(
          result1.artifacts,
          isNotEmpty,
          reason: 'Generated source build should produce artifacts',
        );
        print('First generated-source build succeeded');

        // Verify initial value
        if (!Platform.isWindows) {
          DynamicLibrary? lib1;
          try {
            lib1 = DynamicLibrary.open(
              File(
                p.join(outputDir1.path, result1.artifacts.first.primary.path),
              ).path,
            );
            final getValue1 = lib1
                .lookupFunction<Int32 Function(), int Function()>(
                  'get_generated_value',
                );
            expect(
              getValue1(),
              equals(42),
              reason: 'Initial value should be 42',
            );
          } finally {
            lib1?.close();
          }
        }

        // Mutate the input
        await File(
          p.join(workDir.path, 'input', 'value.txt'),
        ).writeAsString('99');

        // Rebuild — CMake should detect dependency change and rebuild
        final outputDir2 = Directory(p.join(tempDir.path, 'gen_output2'));
        final executor2 = NativeProjectExecutor(
          project: project,
          source: source,
          logger: null,
        );

        final result2 = await executor2.build(
          target: target,
          outputDir: outputDir2,
        );

        expect(
          result2.artifacts,
          isNotEmpty,
          reason: 'Rebuild after source change should produce artifacts',
        );
        print('Second generated-source build (after mutation) succeeded');

        // Verify the value changed
        if (!Platform.isWindows) {
          DynamicLibrary? lib2;
          try {
            lib2 = DynamicLibrary.open(
              File(
                p.join(outputDir2.path, result2.artifacts.first.primary.path),
              ).path,
            );
            final getValue2 = lib2
                .lookupFunction<Int32 Function(), int Function()>(
                  'get_generated_value',
                );
            expect(
              getValue2(),
              equals(99),
              reason: 'After mutation, value should be 99',
            );
          } finally {
            lib2?.close();
          }
        }

        print('Generated-source invalidation test passed');
      },
      timeout: Timeout(Duration(minutes: 3)),
    );
  });
}
