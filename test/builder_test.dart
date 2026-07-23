import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:code_assets/src/code_assets/config.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_prebuilt/hooks.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  test('resolves a prebuilt and registers a code asset', () async {
    final root = await tempPackageRoot('native_prebuilt_builder');
    try {
      final prebuilt = File('${root.path}/libdemo.so')..writeAsBytesSync(makeElfBytes());

      final inputBuilder = BuildInputBuilder()
        ..setupShared(
          packageRoot: root.uri,
          packageName: 'native_prebuilt_builder',
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
        assetName: 'demo_bindings.dart',
        libraryStem: 'demo',
        manifest: const PrebuiltManifest(
          schemaVersion: 1,
          release: GitHubReleaseSource(
            owner: 'kingwill101',
            repository: 'dart_terminal',
            tag: 'v1',
          ),
          artifacts: {},
        ),
        linkModeResolver: (_) => DynamicLoadingBundled(),
        resolvers: [
          _FakeResolver(prebuilt),
        ],
      ).run(input: input, output: output, logger: Logger('test'));

      final built = output.build();
      expect(built.assets.code, hasLength(1));
      expect(File.fromUri(built.assets.code.single.file!).existsSync(), isTrue);
      expect(File.fromUri(built.assets.code.single.file!).readAsBytesSync().sublist(0, 4), [0x7F, 0x45, 0x4C, 0x46]);
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('invokes source fallback when no prebuilt is found', () async {
    final root = await tempPackageRoot('native_prebuilt_builder_fallback');
    try {
      final inputBuilder = BuildInputBuilder()
        ..setupShared(
          packageRoot: root.uri,
          packageName: 'native_prebuilt_builder_fallback',
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
      var called = false;

      await PrebuiltCodeAssetBuilder(
        assetName: 'demo_bindings.dart',
        libraryStem: 'demo',
        manifest: const PrebuiltManifest(
          schemaVersion: 1,
          release: GitHubReleaseSource(
            owner: 'kingwill101',
            repository: 'dart_terminal',
            tag: 'v1',
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
              called = true;
            },
          ),
        ),
      ).run(input: input, output: output, logger: Logger('test'));

      expect(called, isTrue);
    } finally {
      root.deleteSync(recursive: true);
    }
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
