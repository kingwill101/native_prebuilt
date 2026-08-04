import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'falls back to hook/build.dart when no declarative recipe exists',
    () async {
      final packageRoot = await Directory.systemTemp.createTemp(
        'native_prebuilt_hook_fallback_',
      );
      final outputDir = Directory(p.join(packageRoot.path, 'output'));
      try {
        Directory(p.join(packageRoot.path, 'hook')).createSync(recursive: true);
        File(
          p.join(packageRoot.path, 'hook', 'build.dart'),
        ).writeAsStringSync('void main(List<String> args) {}\n');
        File(p.join(packageRoot.path, 'pubspec.yaml')).writeAsStringSync('''
name: hook_fallback_pkg
''');

        final project = NativeProject(
          name: 'hook_fallback_pkg',
          asset: NativeAssetSpec(
            assetName: 'src/hook_fallback_pkg.dart',
            libraryStem: 'hook_fallback_pkg',
            linkMode: DynamicLoadingBundled(),
          ),
          prebuilts: const PrebuiltManifest(
            schemaVersion: 1,
            release: GitHubReleaseSource(
              owner: 'example',
              repository: 'example',
              tag: 'v0.0.0',
            ),
            artifacts: {
              'linux-x64': PrebuiltArtifact(
                archiveName: 'hook_fallback_pkg-linux-x64.tar.gz',
                archiveSha256: '',
                payloadSha256: '',
                payload: DynamicLibraryPayload(libraryStem: 'manifest_stem'),
              ),
            },
          ),
          sources: const [],
          build: const NativeBuildDefinition(recipes: []),
        );

        final runner = _HookBuildRunner();
        final executor = NativeProjectExecutor(
          project: project,
          source: ResolvedSource(
            directory: packageRoot,
            origin: SourceOrigin.local,
          ),
          runner: runner,
        );

        final result = await executor.build(
          target: const NativeTarget(
            os: OS.linux,
            architecture: Architecture.x64,
          ),
          outputDir: outputDir,
        );

        expect(runner.executable, equals('dart'));
        expect(
          runner.arguments,
          containsAllInOrder(['run', 'hook/build.dart', '--config']),
        );
        expect(runner.workingDirectory, equals(packageRoot.path));

        expect(result.artifacts, hasLength(1));
        final artifact = result.artifacts.single;
        expect(
          artifact.id,
          equals('package:hook_fallback_pkg/src/hook_fallback_pkg.dart'),
        );
        expect(artifact.primary.path, equals('libmanifest_stem.so'));
        expect(artifact.primary.source.existsSync(), isTrue);
        expect(
          File(p.join(outputDir.path, artifact.primary.path)).existsSync(),
          isTrue,
        );
      } finally {
        if (outputDir.existsSync()) {
          outputDir.deleteSync(recursive: true);
        }
        packageRoot.deleteSync(recursive: true);
      }
    },
  );
}

final class _HookBuildRunner implements ProcessRunnerInterface {
  String? executable;
  List<String> arguments = const [];
  String? workingDirectory;

  @override
  Future<ProcessResult> runStreaming(
    String executable,
    List<String> arguments, {
    Directory? workingDirectory,
    Map<String, String>? environment,
    bool requireSuccess = true,
  }) async {
    this.executable = executable;
    this.arguments = List<String>.from(arguments);
    this.workingDirectory = workingDirectory?.path;

    final configPath = arguments.last;
    final input = BuildInput(
      jsonDecode(File(configPath).readAsStringSync()) as Map<String, Object?>,
    );

    final builtLib = File.fromUri(input.outputDirectory.resolve('libweird.so'))
      ..createSync(recursive: true)
      ..writeAsStringSync('fake shared object');

    final output = BuildOutputBuilder()
      ..assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: 'src/hook_fallback_pkg.dart',
          linkMode: DynamicLoadingBundled(),
          file: builtLib.uri,
        ),
      );

    File.fromUri(input.outputFile).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(output.build().json),
    );

    return const ProcessResult(exitCode: 0, stdout: '', stderr: '');
  }
}
