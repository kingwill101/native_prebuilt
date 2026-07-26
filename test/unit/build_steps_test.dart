import 'dart:io';

import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/recording_process_runner.dart';
import '../support/test_build_input.dart';

void main() {
  group('CmakeConfigureStep', () {
    late RecordingProcessRunner runner;

    setUp(() {
      runner = RecordingProcessRunner();
    });

    test('builds correct cmake command with defines', () async {
      final step = CmakeConfigureStep(
        sourceDirectory: '.',
        buildDirectory: 'build',
        defines: {
          'CMAKE_BUILD_TYPE': 'Release',
          'CMAKE_C_COMPILER_LAUNCHER': 'sccache',
        },
        runner: runner,
      );

      final (context, source) = createTestContext();
      await step.execute(context, source);

      expect(runner.commands, hasLength(1));
      final cmd = runner.commands.first;

      expect(cmd.executable, contains('cmake'));
      expect(
        cmd.arguments,
        containsAll([
          '-DCMAKE_BUILD_TYPE=Release',
          '-DCMAKE_C_COMPILER_LAUNCHER=sccache',
        ]),
      );
    });

    test('builds correct cmake command with generator', () async {
      final step = CmakeConfigureStep(
        sourceDirectory: '.',
        buildDirectory: 'build',
        generator: 'Ninja',
        runner: runner,
      );

      final (context, source) = createTestContext();
      await step.execute(context, source);

      expect(runner.commands, hasLength(1));
      final cmd = runner.commands.first;

      expect(cmd.arguments, containsAll(['-G', 'Ninja']));
    });

    test('builds correct cmake command with toolchain file', () async {
      final step = CmakeConfigureStep(
        sourceDirectory: '.',
        buildDirectory: 'build',
        toolchainFile: 'CMake/iOS.cmake',
        runner: runner,
      );

      final (context, source) = createTestContext();
      await step.execute(context, source);

      expect(runner.commands, hasLength(1));
      final cmd = runner.commands.first;

      expect(
        cmd.arguments,
        containsAll(['-DCMAKE_TOOLCHAIN_FILE=CMake/iOS.cmake']),
      );
    });

    test('throws on non-zero exit code', () async {
      runner.enqueueFailure(exitCode: 1, stderr: 'CMake error');

      final step = CmakeConfigureStep(
        sourceDirectory: '.',
        buildDirectory: 'build',
        runner: runner,
      );

      final (context, source) = createTestContext();
      await expectLater(
        step.execute(context, source),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('CmakeBuildStep', () {
    late RecordingProcessRunner runner;

    setUp(() {
      runner = RecordingProcessRunner();
    });

    test('builds correct cmake build command', () async {
      final step = CmakeBuildStep(
        buildDirectory: 'build',
        targets: ['tdjson'],
        runner: runner,
      );

      final (context, source) = createTestContext();
      await step.execute(context, source);

      expect(runner.commands, hasLength(1));
      final cmd = runner.commands.first;

      expect(cmd.executable, contains('cmake'));
      expect(
        cmd.arguments,
        containsAll(['--build', contains('build'), '--target', 'tdjson']),
      );
    });

    test('adds parallel flag by default', () async {
      final step = CmakeBuildStep(buildDirectory: 'build', runner: runner);

      final (context, source) = createTestContext();
      await step.execute(context, source);

      expect(runner.commands, hasLength(1));
      final cmd = runner.commands.first;

      expect(cmd.arguments, contains('--parallel'));
    });

    test('omits parallel flag when disabled', () async {
      final step = CmakeBuildStep(
        buildDirectory: 'build',
        parallel: false,
        runner: runner,
      );

      final (context, source) = createTestContext();
      await step.execute(context, source);

      expect(runner.commands, hasLength(1));
      final cmd = runner.commands.first;

      expect(cmd.arguments, isNot(contains('--parallel')));
    });
  });

  group('CommandStep', () {
    late RecordingProcessRunner runner;

    setUp(() {
      runner = RecordingProcessRunner();
    });

    test('executes single command', () async {
      final step = CommandStep(
        id: 'test-command',
        commands: [
          ['echo', 'hello'],
        ],
        runner: runner,
      );

      final (context, source) = createTestContext();
      await step.execute(context, source);

      expect(runner.commands, hasLength(1));
      final cmd = runner.commands.first;

      expect(cmd.executable, 'echo');
      expect(cmd.arguments, ['hello']);
    });

    test('executes multiple commands in order', () async {
      final step = CommandStep(
        id: 'test-commands',
        commands: [
          ['echo', 'first'],
          ['echo', 'second'],
          ['echo', 'third'],
        ],
        runner: runner,
      );

      final (context, source) = createTestContext();
      await step.execute(context, source);

      expect(runner.commands, hasLength(3));
      expect(runner.commands[0].arguments, ['first']);
      expect(runner.commands[1].arguments, ['second']);
      expect(runner.commands[2].arguments, ['third']);
    });

    test('passes working directory', () async {
      final step = CommandStep(
        id: 'test-working-dir',
        commands: [
          ['ls'],
        ],
        workingDirectory: 'my/project',
        runner: runner,
      );

      final (context, source) = createTestContext();
      await step.execute(context, source);

      expect(runner.commands, hasLength(1));
      expect(
        runner.commands.first.workingDirectory,
        p.join(context.directories.work.path, 'my/project'),
      );
    });

    test('passes environment variables', () async {
      final step = CommandStep(
        id: 'test-env',
        commands: [
          ['env'],
        ],
        environment: {'MY_VAR': 'my_value', 'OTHER_VAR': 'other_value'},
        runner: runner,
      );

      final (context, source) = createTestContext();
      await step.execute(context, source);

      expect(runner.commands, hasLength(1));
      expect(runner.commands.first.environment, {
        'MY_VAR': 'my_value',
        'OTHER_VAR': 'other_value',
      });
    });

    test('expands environment variables in cmake arguments', () async {
      final step = CmakeConfigureStep(
        sourceDirectory: '.',
        buildDirectory: 'build',
        toolchainFile: 'VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake',
        runner: runner,
      );

      final (context, source) = createTestContext(
        environment: {'VCPKG_ROOT': 'D:/a/tdlib/tdlib/vcpkg'},
      );
      await step.execute(context, source);

      expect(runner.commands, hasLength(1));
      expect(
        runner.commands.first.arguments,
        contains(
          '-DCMAKE_TOOLCHAIN_FILE=D:/a/tdlib/tdlib/vcpkg/scripts/buildsystems/vcpkg.cmake',
        ),
      );
    });

    test('stops on first failure', () async {
      runner.enqueueResults([
        const ProcessResult(exitCode: 1, stdout: '', stderr: 'Failed'),
        const ProcessResult(exitCode: 0, stdout: '', stderr: ''),
      ]);

      final step = CommandStep(
        id: 'test-fail-stop',
        commands: [
          ['false'],
          ['echo', 'should not run'],
        ],
        runner: runner,
      );

      final (context, source) = createTestContext();
      await expectLater(
        step.execute(context, source),
        throwsA(isA<Exception>()),
      );

      // Only first command should have been executed
      expect(runner.commands, hasLength(1));
    });
  });

  group('StripStep', () {
    late RecordingProcessRunner runner;
    late Directory tempDir;

    setUp(() async {
      runner = RecordingProcessRunner();
      tempDir = await Directory.systemTemp.createTemp('strip_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('calls strip with correct arguments', () async {
      final inputPath = p.join(tempDir.path, 'lib.so');
      final outputPath = p.join(tempDir.path, 'lib-stripped.so');

      // Create a dummy input file
      await File(inputPath).writeAsBytes([0, 0, 0, 0]);

      final step = StripStep(
        id: 'test-strip',
        inputPath: inputPath,
        outputPath: outputPath,
        runner: runner,
      );

      final (context, source) = createTestContext(workDir: tempDir);
      await step.execute(context, source);

      expect(runner.commands, hasLength(1));
      final cmd = runner.commands.first;

      // Accept either 'strip' or 'llvm-strip'
      expect(cmd.executable, anyOf('strip', 'llvm-strip'));
      expect(cmd.arguments, containsAll(['-o', outputPath, inputPath]));
    });
  });

  group('ExportArtifactStep', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('export_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('finds and copies artifact', () async {
      // Create a fake artifact in the work directory
      final artifactFile = File(p.join(tempDir.path, 'libtdjson.so'));
      await artifactFile.writeAsBytes([0, 1, 2]);

      final step = ExportArtifactStep(
        id: 'export_tdjson',
        declaration: NativeArtifactDeclaration(
          id: 'tdjson',
          kind: NativeArtifactKind.dynamicLibrary,
          primaryPath: 'libtdjson.so',
        ),
      );

      final (context, source) = createTestContext(workDir: tempDir);
      final result = await step.execute(context, source);

      // Verify the artifact was produced
      expect(result.artifacts, hasLength(1));
      final artifact = result.artifacts.first;
      expect(artifact.id, 'tdjson');
      expect(artifact.kind, NativeArtifactKind.dynamicLibrary);

      // Verify the artifact file was copied to the output directory
      final outputDir = context.directories.output;
      final outputFile = File(p.join(outputDir.path, 'libtdjson.so'));
      expect(outputFile.existsSync(), isTrue);
    });

    test('finds fallback shared library paths', () async {
      final artifactFile = File(
        p.join(tempDir.path, 'build', 'libtdjson.dylib'),
      );
      await artifactFile.parent.create(recursive: true);
      await artifactFile.writeAsBytes([0, 1, 2]);

      final step = ExportArtifactStep(
        id: 'export_tdjson',
        declaration: NativeArtifactDeclaration(
          id: 'tdjson',
          kind: NativeArtifactKind.dynamicLibrary,
          primaryPath: 'build/libtdjson.so',
        ),
      );

      final (context, source) = createTestContext(workDir: tempDir);
      final result = await step.execute(context, source);

      expect(result.artifacts, hasLength(1));
      expect(result.artifacts.single.primary.source.path, artifactFile.path);
      expect(
        File(
          p.join(context.directories.output.path, 'build', 'libtdjson.so'),
        ).existsSync(),
        isTrue,
      );
    });

    test('throws when artifact not found', () async {
      final step = ExportArtifactStep(
        id: 'export_missing',
        declaration: NativeArtifactDeclaration(
          id: 'missing',
          kind: NativeArtifactKind.dynamicLibrary,
          primaryPath: 'nonexistent.so',
        ),
      );

      final (context, source) = createTestContext(workDir: tempDir);
      await expectLater(
        step.execute(context, source),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('StepBuildRecipe', () {
    late RecordingProcessRunner runner;
    late Directory tempDir;

    setUp(() async {
      runner = RecordingProcessRunner();
      tempDir = await Directory.systemTemp.createTemp('recipe_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('executes steps in order', () async {
      final recipe = StepBuildRecipe(
        steps: [
          CommandStep(
            id: 'first',
            commands: [
              ['echo', 'first'],
            ],
            runner: runner,
          ),
          CommandStep(
            id: 'second',
            commands: [
              ['echo', 'second'],
            ],
            runner: runner,
          ),
          CommandStep(
            id: 'third',
            commands: [
              ['echo', 'third'],
            ],
            runner: runner,
          ),
        ],
      );

      final (context, source) = createTestContext(workDir: tempDir);
      await recipe.execute(context, source);

      expect(runner.commands, hasLength(3));
      expect(runner.commands[0].arguments, ['first']);
      expect(runner.commands[1].arguments, ['second']);
      expect(runner.commands[2].arguments, ['third']);
    });

    test('executes steps after their needs even if listed later', () async {
      final recipe = StepBuildRecipe(
        steps: [
          CommandStep(
            id: 'build',
            commands: [
              ['echo', 'build'],
            ],
            runner: runner,
          ),
          CommandStep(
            id: 'prepare',
            commands: [
              ['echo', 'prepare'],
            ],
            runner: runner,
          ),
        ],
        needsById: const {
          'build': ['prepare'],
        },
      );

      final (context, source) = createTestContext(workDir: tempDir);
      await recipe.execute(context, source);

      expect(runner.commands, hasLength(2));
      expect(runner.commands[0].arguments, ['prepare']);
      expect(runner.commands[1].arguments, ['build']);
    });

    test('stops on step failure', () async {
      runner.enqueueFailure();

      final recipe = StepBuildRecipe(
        steps: [
          CommandStep(
            id: 'fail',
            commands: [
              ['false'],
            ],
            runner: runner,
          ),
          CommandStep(
            id: 'should-not-run',
            commands: [
              ['echo', 'skipped'],
            ],
            runner: runner,
          ),
        ],
      );

      final (context, source) = createTestContext(workDir: tempDir);
      await expectLater(
        recipe.execute(context, source),
        throwsA(isA<Exception>()),
      );

      expect(runner.commands, hasLength(1));
    });
  });
}
