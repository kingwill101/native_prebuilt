import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/recording_process_runner.dart';

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

      final (context, source) = _createTestContext();
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

      final (context, source) = _createTestContext();
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

      final (context, source) = _createTestContext();
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

      final (context, source) = _createTestContext();
      expect(() => step.execute(context, source), throwsA(isA<Exception>()));
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

      final (context, source) = _createTestContext();
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

      final (context, source) = _createTestContext();
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

      final (context, source) = _createTestContext();
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

      final (context, source) = _createTestContext();
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

      final (context, source) = _createTestContext();
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

      final (context, source) = _createTestContext();
      await step.execute(context, source);

      expect(runner.commands, hasLength(1));
      expect(runner.commands.first.workingDirectory, 'my/project');
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

      final (context, source) = _createTestContext();
      await step.execute(context, source);

      expect(runner.commands, hasLength(1));
      expect(runner.commands.first.environment, {
        'MY_VAR': 'my_value',
        'OTHER_VAR': 'other_value',
      });
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

      final (context, source) = _createTestContext();
      expect(() => step.execute(context, source), throwsA(isA<Exception>()));

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

      final (context, source) = _createTestContext(workDir: tempDir);
      await step.execute(context, source);

      expect(runner.commands, hasLength(1));
      final cmd = runner.commands.first;

      // Accept either 'strip' or 'llvm-strip'
      expect(cmd.executable, anyOf('strip', 'llvm-strip'));
      expect(
        cmd.arguments,
        containsAll(['--strip-debug', '--strip-unneeded', outputPath]),
      );
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
      // Create a fake artifact
      final buildDir = Directory(p.join(tempDir.path, 'build', 'td'));
      await buildDir.create(recursive: true);
      await File(p.join(buildDir.path, 'libtdjson.so')).writeAsBytes([0, 1, 2]);

      final step = ExportArtifactStep(
        artifactPath: 'build/td/libtdjson.so',
        outputName: 'libtdjson.so',
      );

      final (context, source) = _createTestContext(workDir: tempDir);
      await step.execute(context, source);

      // Verify the artifact was copied to the output directory
      final outputDir = context.directories.output;
      final outputFile = File(p.join(outputDir.path, 'libtdjson.so'));
      expect(outputFile.existsSync(), isTrue);
    });

    test('throws when artifact not found', () async {
      final step = ExportArtifactStep(
        artifactPath: 'build/td/nonexistent.so',
        outputName: 'libtdjson.so',
      );

      final (context, source) = _createTestContext(workDir: tempDir);
      expect(() => step.execute(context, source), throwsA(isA<StateError>()));
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

      final (context, source) = _createTestContext(workDir: tempDir);
      await recipe.execute(context, source);

      expect(runner.commands, hasLength(3));
      expect(runner.commands[0].arguments, ['first']);
      expect(runner.commands[1].arguments, ['second']);
      expect(runner.commands[2].arguments, ['third']);
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

      final (context, source) = _createTestContext(workDir: tempDir);
      expect(() => recipe.execute(context, source), throwsA(isA<Exception>()));

      expect(runner.commands, hasLength(1));
    });
  });
}

(NativeBuildContext, ResolvedSource) _createTestContext({Directory? workDir}) {
  workDir ??= Directory.systemTemp.createTempSync('test_context_');

  final context = NativeBuildContext(
    target: const NativeTarget(os: OS.linux, architecture: Architecture.x64),
    hook: NativeHookConfiguration(
      packageName: 'test_package',
      assetName: 'test_asset',
      libraryStem: 'test_lib',
      linkMode: DynamicLoadingBundled(),
    ),
    directories: NativeBuildDirectories(
      source: workDir,
      output: Directory(p.join(workDir.path, 'output'))..createSync(),
      cache: Directory(p.join(workDir.path, 'cache'))..createSync(),
      work: workDir,
    ),
    toolchains: const ToolchainRegistry(),
    environment: {},
  );

  final source = ResolvedSource(directory: workDir, origin: SourceOrigin.local);

  return (context, source);
}
