import 'dart:io';
import 'dart:convert';

import 'package:code_assets/code_assets.dart';
import 'package:code_assets/src/code_assets/config.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_prebuilt/hooks.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('SourceSpecification', () {
    test('LocalSource resolves existing path', () {
      final tempDir = Directory.systemTemp.createTempSync('source_test');
      try {
        final subDir = Directory(p.join(tempDir.path, 'vendor', 'lib'));
        subDir.createSync(recursive: true);

        final source = LocalSource(paths: ['vendor/lib', 'other']);
        final resolved = source.resolve(tempDir);

        expect(resolved, isNotNull);
        expect(resolved!.path, subDir.path);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('LocalSource returns null for non-existent paths', () {
      final tempDir = Directory.systemTemp.createTempSync('source_test');
      try {
        final source = LocalSource(paths: ['nonexistent', 'also_missing']);
        final resolved = source.resolve(tempDir);
        expect(resolved, isNull);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('LocalSource tries paths in priority order', () {
      final tempDir = Directory.systemTemp.createTempSync('source_test');
      try {
        final second = Directory(p.join(tempDir.path, 'second'));
        second.createSync(recursive: true);

        final source = LocalSource(paths: ['first', 'second']);
        final resolved = source.resolve(tempDir);

        expect(resolved, isNotNull);
        expect(resolved!.path, second.path);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('ArchiveSource has correct label', () {
      final source = ArchiveSource(
        uri: Uri.parse('https://github.com/org/repo/archive/v1.0.tar.gz'),
        sha256: 'abc123',
      );
      expect(source.label, contains('v1.0.tar.gz'));
    });

    test('GitSource has correct label and cacheKey', () {
      final source = GitSource(
        repository: Uri.parse('https://github.com/org/repo.git'),
        revision: 'abc123def456',
      );
      expect(source.label, contains('repo'));
      expect(source.cacheKey, contains('abc123def456'));
    });
  });

  group('SourceProvider', () {
    test('LocalSourceProvider resolves local source', () async {
      final tempDir = Directory.systemTemp.createTempSync('source_test');
      final cacheDir = Directory.systemTemp.createTempSync('source_cache');
      try {
        final srcDir = Directory(p.join(tempDir.path, 'native'));
        srcDir.createSync(recursive: true);

        final provider = LocalSourceProvider();
        final result = await provider.resolve(SourceResolutionContext(
          specification: LocalSource(paths: ['native']),
          packageRoot: tempDir,
          sourceCacheRoot: cacheDir,
        ));

        expect(result, isNotNull);
        expect(result!.origin, SourceOrigin.local);
        expect(result.directory.path, srcDir.path);
      } finally {
        tempDir.deleteSync(recursive: true);
        cacheDir.deleteSync(recursive: true);
      }
    });

    test('LocalSourceProvider returns null for wrong type', () async {
      final tempDir = Directory.systemTemp.createTempSync('source_test');
      final cacheDir = Directory.systemTemp.createTempSync('source_cache');
      try {
        final provider = LocalSourceProvider();
        final result = await provider.resolve(SourceResolutionContext(
          specification: ArchiveSource(
            uri: Uri.parse('https://example.com/src.tar.gz'),
            sha256: 'abc123',
          ),
          packageRoot: tempDir,
          sourceCacheRoot: cacheDir,
        ));

        expect(result, isNull);
      } finally {
        tempDir.deleteSync(recursive: true);
        cacheDir.deleteSync(recursive: true);
      }
    });

    test('ArchiveSourceProvider downloads and extracts archive', () async {
      final tempDir = Directory.systemTemp.createTempSync('source_test');
      final cacheDir = Directory.systemTemp.createTempSync('source_cache');
      try {
        final archiveBytes = makeTarGz({
          'repo-123/add.c': utf8.encode('int add(int a, int b) { return a + b; }'),
        });
        final archiveFile = File(p.join(tempDir.path, 'source.tar.gz'))
          ..writeAsBytesSync(archiveBytes);

        final provider = ArchiveSourceProvider();
        final result = await provider.resolve(SourceResolutionContext(
          specification: ArchiveSource(
            uri: Uri.file(archiveFile.path),
            sha256: sha256Hash(archiveBytes),
          ),
          packageRoot: tempDir,
          sourceCacheRoot: cacheDir,
        ));

        expect(result, isNotNull);
        expect(File(p.join(result!.directory.path, 'add.c')).existsSync(), isTrue);
      } finally {
        tempDir.deleteSync(recursive: true);
        cacheDir.deleteSync(recursive: true);
      }
    });

    test('GitSourceProvider clones a local git repo', () async {
      final tempDir = Directory.systemTemp.createTempSync('source_test');
      final cacheDir = Directory.systemTemp.createTempSync('source_cache');
      try {
        final repoDir = Directory(p.join(tempDir.path, 'repo'))..createSync();
        await Process.run('git', ['init', repoDir.path]);
        File(p.join(repoDir.path, 'add.c')).writeAsStringSync('int add(int a, int b) { return a + b; }');
        await Process.run('git', ['-C', repoDir.path, 'add', 'add.c']);
        await Process.run('git', [
          '-C', repoDir.path,
          '-c', 'user.email=test@example.com',
          '-c', 'user.name=Test User',
          'commit', '-m', 'init',
        ]);
        final commit = (await Process.run('git', ['-C', repoDir.path, 'rev-parse', 'HEAD'])).stdout.toString().trim();

        final provider = GitSourceProvider();
        final result = await provider.resolve(SourceResolutionContext(
          specification: GitSource(
            repository: Uri.file(repoDir.path),
            revision: commit,
          ),
          packageRoot: tempDir,
          sourceCacheRoot: cacheDir,
        ));

        expect(result, isNotNull);
        expect(File(p.join(result!.directory.path, 'add.c')).existsSync(), isTrue);
      } finally {
        tempDir.deleteSync(recursive: true);
        cacheDir.deleteSync(recursive: true);
      }
    });
  });

  group('SourceFallbackResolver', () {
    test('resolves local source and invokes builder', () async {
      final tempDir = Directory.systemTemp.createTempSync('source_test');
      final cacheDir = Directory.systemTemp.createTempSync('source_cache');
      try {
        final srcDir = Directory(p.join(tempDir.path, 'src'));
        srcDir.createSync(recursive: true);
        File(p.join(srcDir.path, 'main.c')).writeAsStringSync('int main() {}');

        final root = await tempPackageRoot('source_fallback_test');
        try {
          final inputBuilder = BuildInputBuilder()
            ..setupShared(
              packageRoot: root.uri,
              packageName: 'source_fallback_test',
              outputFile: root.uri.resolve('output.json'),
              outputDirectoryShared: root.uri.resolve('shared/'),
            )
            ..setupBuildInput()
            ..config.setupBuild(linkingEnabled: false)
            ..config.addBuildAssetTypes(['code_assets/code'])
            ..config.setupCode(
              targetArchitecture: Architecture.x64,
              targetOS: OS.linux,
              linkModePreference: LinkModePreference.dynamic,
            );

          final input = inputBuilder.build();
          final output = BuildOutputBuilder();
          String? builtSourceDir;

          final resolver = SourceFallbackResolver();

          final result = await resolver.resolve(
            fallback: SourceFallback(
              sources: [LocalSource(paths: ['src'])],
              builder: CallbackSourceBuilder(
                callback: ({
                  required source,
                  required input,
                  required output,
                  required logger,
                }) async {
                  builtSourceDir = source.directory.path;
                },
              ),
            ),
            packageRoot: tempDir,
            sourceCacheRoot: cacheDir,
            input: input,
            output: output,
            logger: Logger('test'),
          );

          expect(result, isNotNull);
          expect(builtSourceDir, srcDir.path);
        } finally {
          root.deleteSync(recursive: true);
        }
      } finally {
        tempDir.deleteSync(recursive: true);
        cacheDir.deleteSync(recursive: true);
      }
    });

    test('returns null when no source resolves', () async {
      final tempDir = Directory.systemTemp.createTempSync('source_test');
      final cacheDir = Directory.systemTemp.createTempSync('source_cache');
      try {
        final root = await tempPackageRoot('source_fallback_null');
        try {
          final inputBuilder = BuildInputBuilder()
            ..setupShared(
              packageRoot: root.uri,
              packageName: 'source_fallback_null',
              outputFile: root.uri.resolve('output.json'),
              outputDirectoryShared: root.uri.resolve('shared/'),
            )
            ..setupBuildInput()
            ..config.setupBuild(linkingEnabled: false)
            ..config.addBuildAssetTypes(['code_assets/code'])
            ..config.setupCode(
              targetArchitecture: Architecture.x64,
              targetOS: OS.linux,
              linkModePreference: LinkModePreference.dynamic,
            );

          final input = inputBuilder.build();
          final output = BuildOutputBuilder();

          final resolver = SourceFallbackResolver();

          final result = await resolver.resolve(
            fallback: SourceFallback(
              sources: [LocalSource(paths: ['nonexistent'])],
              builder: CallbackSourceBuilder(
                callback: ({
                  required source,
                  required input,
                  required output,
                  required logger,
                }) async {},
              ),
            ),
            packageRoot: tempDir,
            sourceCacheRoot: cacheDir,
            input: input,
            output: output,
            logger: Logger('test'),
          );

          expect(result, isNull);
        } finally {
          root.deleteSync(recursive: true);
        }
      } finally {
        tempDir.deleteSync(recursive: true);
        cacheDir.deleteSync(recursive: true);
      }
    });
  });

  group('ApplyPatches', () {
    test('throws on missing patch file', () async {
      final tempDir = Directory.systemTemp.createTempSync('source_test');
      try {
        final patches = ApplyPatches(paths: ['nonexistent.patch']);
        expect(
          () => patches.apply(directory: tempDir, logger: null),
          throwsA(isA<SourcePreparationException>()),
        );
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('NetworkPolicy', () {
    test('has all expected values', () {
      expect(NetworkPolicy.values.length, 4);
      expect(NetworkPolicy.allowed.name, 'allowed');
      expect(NetworkPolicy.offline.name, 'offline');
    });
  });

  group('PrebuiltCodeAssetBuilder with sourceFallback', () {
    test('invokes source fallback when no prebuilt found', () async {
      final root = await tempPackageRoot('source_fallback_builder');
      try {
        final inputBuilder = BuildInputBuilder()
          ..setupShared(
            packageRoot: root.uri,
            packageName: 'source_fallback_builder',
            outputFile: root.uri.resolve('output.json'),
            outputDirectoryShared: root.uri.resolve('shared/'),
          )
          ..setupBuildInput()
          ..config.setupBuild(linkingEnabled: false)
          ..config.addBuildAssetTypes(['code_assets/code'])
          ..config.setupCode(
            targetArchitecture: Architecture.x64,
            targetOS: OS.linux,
            linkModePreference: LinkModePreference.dynamic,
          );

        final input = inputBuilder.build();
        final output = BuildOutputBuilder();
        var sourceBuilderCalled = false;

        // Create a local source directory.
        final srcDir = Directory(p.join(root.path, 'src'));
        srcDir.createSync(recursive: true);

        await PrebuiltCodeAssetBuilder(
          assetName: 'demo_bindings.dart',
          libraryStem: 'demo',
          manifest: const PrebuiltManifest(
            schemaVersion: 1,
            release: GitHubReleaseSource(
              owner: 'nonexistent',
              repository: 'repo',
              tag: 'v0.0.1',
            ),
            artifacts: {},
          ),
          linkModeResolver: (_) => DynamicLoadingBundled(),
          sourceFallback: SourceFallback(
            sources: [LocalSource(paths: ['src'])],
            builder: CallbackSourceBuilder(
              callback: ({
                required source,
                required input,
                required output,
                required logger,
              }) async {
                sourceBuilderCalled = true;
              },
            ),
          ),
        ).run(input: input, output: output, logger: Logger('test'));

        expect(sourceBuilderCalled, isTrue);
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('skips source fallback when prebuilt found', () async {
      final root = await tempPackageRoot('source_fallback_skip');
      try {
        // Create a fake prebuilt.
        final prebuilt = File('${root.path}/libdemo.so')
          ..writeAsBytesSync(makeElfBytes());

        final inputBuilder = BuildInputBuilder()
          ..setupShared(
            packageRoot: root.uri,
            packageName: 'source_fallback_skip',
            outputFile: root.uri.resolve('output.json'),
            outputDirectoryShared: root.uri.resolve('shared/'),
          )
          ..setupBuildInput()
          ..config.setupBuild(linkingEnabled: false)
          ..config.addBuildAssetTypes(['code_assets/code'])
          ..config.setupCode(
            targetArchitecture: Architecture.x64,
            targetOS: OS.linux,
            linkModePreference: LinkModePreference.dynamic,
          );

        final input = inputBuilder.build();
        final output = BuildOutputBuilder();
        var sourceBuilderCalled = false;

        await PrebuiltCodeAssetBuilder(
          assetName: 'demo_bindings.dart',
          libraryStem: 'demo',
          manifest: const PrebuiltManifest(
            schemaVersion: 1,
            release: GitHubReleaseSource(
              owner: 'nonexistent',
              repository: 'repo',
              tag: 'v0.0.1',
            ),
            artifacts: {},
          ),
          linkModeResolver: (_) => DynamicLoadingBundled(),
          sourceFallback: SourceFallback(
            sources: [LocalSource(paths: ['src'])],
            builder: CallbackSourceBuilder(
              callback: ({
                required source,
                required input,
                required output,
                required logger,
              }) async {
                sourceBuilderCalled = true;
              },
            ),
          ),
          resolvers: [_FakeResolver(prebuilt)],
        ).run(input: input, output: output, logger: Logger('test'));

        expect(sourceBuilderCalled, isFalse);
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('builds a real native_socket source tree', () async {
      final realSourceRoot = Directory('/home/kingwill101/code/dart_packages/native_socket');
      if (!realSourceRoot.existsSync()) {
        return;
      }

      final root = await tempPackageRoot('native_socket_real_world');
      try {
        final srcDir = Directory(p.join(root.path, 'src'))..createSync(recursive: true);
        File(p.join(srcDir.path, 'native_socket.c')).writeAsStringSync(
          File(p.join(realSourceRoot.path, 'src/native_socket.c')).readAsStringSync(),
        );
        File(p.join(srcDir.path, 'native_socket.h')).writeAsStringSync(
          File(p.join(realSourceRoot.path, 'src/native_socket.h')).readAsStringSync(),
        );

        final inputBuilder = BuildInputBuilder()
          ..setupShared(
            packageRoot: root.uri,
            packageName: 'native_socket_real_world',
            outputFile: root.uri.resolve('output.json'),
            outputDirectoryShared: root.uri.resolve('shared/'),
          )
          ..setupBuildInput()
          ..config.setupBuild(linkingEnabled: false)
          ..config.addBuildAssetTypes(['code_assets/code'])
          ..config.setupCode(
            targetArchitecture: Architecture.x64,
            targetOS: OS.linux,
            linkModePreference: LinkModePreference.dynamic,
          );

        final input = inputBuilder.build();
        final output = BuildOutputBuilder();

        await PrebuiltCodeAssetBuilder(
          assetName: 'src/native_socket_real_world.dart',
          libraryStem: 'native_socket',
          manifest: const PrebuiltManifest(
            schemaVersion: 1,
            release: GitHubReleaseSource(
              owner: 'nonexistent',
              repository: 'repo',
              tag: 'v0.0.1',
            ),
            artifacts: {},
          ),
          linkModeResolver: (_) => DynamicLoadingBundled(),
          sourceFallback: SourceFallback(
            sources: [LocalSource(paths: ['.'])],
            builder: CallbackSourceBuilder(
              callback: ({
                required source,
                required input,
                required output,
                required logger,
              }) async {
                final builtLib = File.fromUri(
                  input.outputDirectory.resolve('libnative_socket.so'),
                );
                final result = await Process.run(
                  'cc',
                  [
                    '-shared',
                    '-fPIC',
                    '-o',
                    builtLib.path,
                    'src/native_socket.c',
                  ],
                  workingDirectory: source.directory.path,
                );
                expect(result.exitCode, 0, reason: result.stderr.toString());
                output.assets.code.add(
                  CodeAsset(
                    package: input.packageName,
                    name: 'src/native_socket_real_world.dart',
                    linkMode: DynamicLoadingBundled(),
                    file: builtLib.uri,
                  ),
                );
              },
            ),
          ),
        ).run(input: input, output: output, logger: Logger('test'));

        final built = output.build();
        expect(built.assets.code, hasLength(1));
        final builtFile = File.fromUri(built.assets.code.single.file!);
        expect(builtFile.existsSync(), isTrue);
        expect(builtFile.readAsBytesSync().sublist(0, 4), [0x7F, 0x45, 0x4C, 0x46]);
      } finally {
        root.deleteSync(recursive: true);
      }
    });
  });
}

final class _FakeResolver implements PrebuiltResolver {
  _FakeResolver(this.file);
  final File file;

  @override
  Future<ResolvedPrebuilt?> resolve(PrebuiltResolutionContext context) async {
    return ResolvedPrebuiltFound(
      file: ResolvedFile(
        path: file.path,
        hash: sha256Hash(file.readAsBytesSync()),
      ),
      source: PrebuiltSource.localCache,
    );
  }
}
