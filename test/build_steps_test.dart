import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('CommandStep', () {
    test('executes a simple command', () async {
      final tempDir = Directory.systemTemp.createTempSync('cmd_test');
      try {
        final step = CommandStep(
          id: 'test_cmd',
          commands: [
            ['echo', 'hello'],
          ],
        );

        final context = _createBuildContext(tempDir);
        final source = _createSource(tempDir);

        // Should not throw
        await step.execute(context, source);

        final fp = await step.fingerprint(_createStepContext(context, source));
        expect(fp.id, 'test_cmd');
        expect(fp.hash, isNotEmpty);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('executes commands in order', () async {
      final tempDir = Directory.systemTemp.createTempSync('cmd_test');
      final outputFile = File(p.join(tempDir.path, 'output.txt'));
      try {
        final step = CommandStep(
          id: 'test_ordered',
          commands: [
            ['touch', outputFile.path],
            ['ls', tempDir.path],
          ],
        );

        final context = _createBuildContext(tempDir);
        final source = _createSource(tempDir);

        await step.execute(context, source);
        expect(outputFile.existsSync(), isTrue);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('GitCheckoutStep', () {
    test('fingerprints correctly', () async {
      final step = GitCheckoutStep(
        id: 'git_test',
        repository: 'https://github.com/example/repo.git',
        revision: 'abc123',
      );

      final tempDir = Directory.systemTemp.createTempSync('git_test');
      try {
        final context = _createBuildContext(tempDir);
        final source = _createSource(tempDir);
        final fp = await step.fingerprint(_createStepContext(context, source));

        expect(fp.id, 'git_test');
        expect(fp.hash, isNotEmpty);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('DownloadArchiveStep', () {
    test('fingerprints correctly', () async {
      final step = DownloadArchiveStep(
        id: 'dl_test',
        url: 'https://example.com/archive.tar.gz',
        sha256: 'abc123',
      );

      final tempDir = Directory.systemTemp.createTempSync('dl_test');
      try {
        final context = _createBuildContext(tempDir);
        final source = _createSource(tempDir);
        final fp = await step.fingerprint(_createStepContext(context, source));

        expect(fp.id, 'dl_test');
        expect(fp.hash, isNotEmpty);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('ExportArtifactStep', () {
    test('copies artifact to output directory', () async {
      final tempDir = Directory.systemTemp.createTempSync('export_test');
      final outputDir = Directory(p.join(tempDir.path, 'output'));
      final sourceDir = Directory(p.join(tempDir.path, 'source'));
      final buildDir = Directory(p.join(sourceDir.path, 'build'));
      buildDir.createSync(recursive: true);

      // Create a fake library file
      final libFile = File(p.join(buildDir.path, 'libdemo.so'));
      libFile.writeAsBytesSync([0x7F, 0x45, 0x4C, 0x46]);

      try {
        final step = ExportArtifactStep(
          artifactPath: 'build/libdemo.so',
          outputName: 'libdemo.so',
        );

        final context = NativeBuildContext(
          target: const NativeTarget(
            os: OS.linux,
            architecture: Architecture.x64,
          ),
          hook: NativeHookConfiguration(
            packageName: 'test',
            assetName: 'test.dart',
            libraryStem: 'demo',
            linkMode: DynamicLoadingBundled(),
          ),
          directories: NativeBuildDirectories(
            source: sourceDir,
            output: outputDir,
            cache: Directory(p.join(tempDir.path, 'cache')),
            work: sourceDir,
          ),
          toolchains: ToolchainRegistry(),
          environment: {},
        );

        final source = ResolvedSource(
          directory: sourceDir,
          origin: SourceOrigin.local,
        );

        await step.execute(context, source);

        final outputFile = File(p.join(outputDir.path, 'libdemo.so'));
        expect(outputFile.existsSync(), isTrue);
        expect(outputFile.readAsBytesSync(), [0x7F, 0x45, 0x4C, 0x46]);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('CopyStep', () {
    test('copies a file', () async {
      final tempDir = Directory.systemTemp.createTempSync('copy_test');
      final srcFile = File(p.join(tempDir.path, 'src.txt'));
      srcFile.writeAsStringSync('hello');
      final destFile = File(p.join(tempDir.path, 'dest.txt'));

      try {
        final step = CopyStep(
          id: 'copy_test',
          sourcePath: srcFile.path,
          destinationPath: destFile.path,
        );

        final context = _createBuildContext(tempDir);
        final source = _createSource(tempDir);

        await step.execute(context, source);

        expect(destFile.existsSync(), isTrue);
        expect(destFile.readAsStringSync(), 'hello');
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('copies a directory recursively', () async {
      final tempDir = Directory.systemTemp.createTempSync('copy_test');
      final srcDir = Directory(p.join(tempDir.path, 'src_dir'));
      srcDir.createSync(recursive: true);
      final srcFile = File(p.join(srcDir.path, 'sub/file.txt'));
      srcFile.parent.createSync(recursive: true);
      srcFile.writeAsStringSync('nested');
      final destDir = Directory(p.join(tempDir.path, 'dest_dir'));

      try {
        final step = CopyStep(
          id: 'copy_dir_test',
          sourcePath: srcDir.path,
          destinationPath: destDir.path,
        );

        final context = _createBuildContext(tempDir);
        final source = _createSource(tempDir);

        await step.execute(context, source);

        final destFile = File(p.join(destDir.path, 'sub/file.txt'));
        expect(destFile.existsSync(), isTrue);
        expect(destFile.readAsStringSync(), 'nested');
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('FindArtifactStep', () {
    test('finds and copies artifact by filename', () async {
      final tempDir = Directory.systemTemp.createTempSync('find_test');
      final sourceDir = Directory(p.join(tempDir.path, 'source'));
      final buildDir = Directory(p.join(sourceDir.path, 'build'));
      buildDir.createSync(recursive: true);
      final outputDir = Directory(p.join(tempDir.path, 'output'));

      // Create a fake library
      final libFile = File(p.join(buildDir.path, 'libfoo.so'));
      libFile.writeAsBytesSync([0x7F, 0x45]);

      try {
        final step = FindArtifactStep(
          id: 'find_test',
          fileName: 'libfoo.so',
          searchDirectory: buildDir.path,
        );

        final context = NativeBuildContext(
          target: const NativeTarget(
            os: OS.linux,
            architecture: Architecture.x64,
          ),
          hook: NativeHookConfiguration(
            packageName: 'test',
            assetName: 'test.dart',
            libraryStem: 'foo',
            linkMode: DynamicLoadingBundled(),
          ),
          directories: NativeBuildDirectories(
            source: sourceDir,
            output: outputDir,
            cache: Directory(p.join(tempDir.path, 'cache')),
            work: sourceDir,
          ),
          toolchains: ToolchainRegistry(),
          environment: {},
        );

        final source = ResolvedSource(
          directory: sourceDir,
          origin: SourceOrigin.local,
        );

        await step.execute(context, source);

        final outputFile = File(p.join(outputDir.path, 'libfoo.so'));
        expect(outputFile.existsSync(), isTrue);
        expect(outputFile.readAsBytesSync(), [0x7F, 0x45]);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('StripStep', () {
    test('fingerprints correctly', () async {
      final step = StripStep(id: 'strip_test', inputPath: '/path/to/lib.so');

      final tempDir = Directory.systemTemp.createTempSync('strip_test');
      try {
        final context = _createBuildContext(tempDir);
        final source = _createSource(tempDir);
        final fp = await step.fingerprint(_createStepContext(context, source));

        expect(fp.id, 'strip_test');
        expect(fp.hash, isNotEmpty);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('CmakeConfigureStep', () {
    test('generates correct fingerprint', () async {
      final step = CmakeConfigureStep(
        sourceDirectory: '.',
        defines: {'CMAKE_BUILD_TYPE': 'Release'},
      );

      final tempDir = Directory.systemTemp.createTempSync('cmake_test');
      try {
        final context = _createBuildContext(tempDir);
        final source = _createSource(tempDir);
        final fp = await step.fingerprint(_createStepContext(context, source));

        expect(fp.id, 'cmake_configure');
        expect(fp.hash, isNotEmpty);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('StepBuildRecipe', () {
    test('executes steps in order', () async {
      final tempDir = Directory.systemTemp.createTempSync('recipe_test');
      final logFile = File(p.join(tempDir.path, 'build.log'));

      try {
        final step1 = CommandStep(
          id: 'step1',
          commands: [
            ['touch', logFile.path],
          ],
        );

        final step2 = CommandStep(
          id: 'step2',
          commands: [
            ['sh', '-c', 'echo "step2" >> ${logFile.path}'],
          ],
        );

        final recipe = StepBuildRecipe(steps: [step1, step2]);

        final context = _createBuildContext(tempDir);
        final source = _createSource(tempDir);

        final result = await recipe.execute(context, source);

        expect(result.artifacts, isEmpty);
        expect(logFile.existsSync(), isTrue);
        expect(logFile.readAsStringSync(), contains('step2'));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}

NativeBuildContext _createBuildContext(Directory tempDir) {
  final sourceDir = Directory(p.join(tempDir.path, 'source'));
  sourceDir.createSync(recursive: true);
  final outputDir = Directory(p.join(tempDir.path, 'output'));
  outputDir.createSync(recursive: true);

  return NativeBuildContext(
    target: const NativeTarget(os: OS.linux, architecture: Architecture.x64),
    hook: NativeHookConfiguration(
      packageName: 'test',
      assetName: 'test.dart',
      libraryStem: 'test',
      linkMode: DynamicLoadingBundled(),
    ),
    directories: NativeBuildDirectories(
      source: sourceDir,
      output: outputDir,
      cache: Directory(p.join(tempDir.path, 'cache')),
      work: sourceDir,
    ),
    toolchains: ToolchainRegistry(),
    environment: {},
  );
}

ResolvedSource _createSource(Directory tempDir) {
  final sourceDir = Directory(p.join(tempDir.path, 'source'));
  sourceDir.createSync(recursive: true);
  return ResolvedSource(directory: sourceDir, origin: SourceOrigin.local);
}

NativeStepContext _createStepContext(
  NativeBuildContext context,
  ResolvedSource source,
) {
  return NativeStepContext(
    buildContext: context,
    source: source,
    stepId: 'test',
  );
}
