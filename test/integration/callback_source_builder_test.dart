/// Integration test for PrebuiltCodeAssetBuilder + CallbackSourceBuilder + CBuilder.
///
/// This test verifies two paths:
/// 1. CallbackSourceBuilder with CBuilder directly
/// 2. PrebuiltCodeAssetBuilder → NativeProjectBuilder.fromSourceFallback → source fallback
/// Both paths should produce an FFI-callable shared library.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:ffi/ffi.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fixture_workspace.dart';

void main() {
  group(
    'native_toolchain_c_fallback fixture (CallbackSourceBuilder + CBuilder)',
    () {
      late FixtureWorkspace workspace;

      setUp(() async {
        workspace = await FixtureWorkspace.create(
          'native_toolchain_c_fallback',
        );
      });

      tearDown(() async {
        await workspace.dispose();
      });

      test(
        'CallbackSourceBuilder with CBuilder builds C library and FFI works',
        () async {
          final cBuilder = CBuilder.library(
            name: 'native_toolchain_c_fallback',
            packageName: workspace.source.path,
            assetName: 'src/native_library.dart',
            sources: const ['src/native/fixture.c'],
          );

          final inputBuilder = BuildInputBuilder()
            ..setupShared(
              packageRoot: workspace.source.uri,
              packageName: 'native_toolchain_c_fallback',
              outputFile: workspace.source.uri.resolve('output.json'),
              outputDirectoryShared: workspace.source.uri.resolve('build/'),
            )
            ..setupBuildInput()
            ..config.setupBuild(linkingEnabled: false)
            ..addExtension(
              CodeAssetExtension(
                targetArchitecture: Architecture.current,
                targetOS: OS.current,
                linkModePreference: LinkModePreference.dynamic,
                macOS: OS.current == OS.macOS
                    ? MacOSCodeConfig(targetVersion: 13)
                    : null,
              ),
            );

          final input = inputBuilder.build();
          final output = BuildOutputBuilder();

          print('input.outputDirectory = ${input.outputDirectory}');
          print('input.outputDirectoryShared = ${input.outputDirectoryShared}');
          print(
            'input.config.buildAssetTypes = ${input.config.buildAssetTypes}',
          );
          print(
            'input.config.buildCodeAssets = ${input.config.buildCodeAssets}',
          );

          // Run CBuilder through CallbackSourceBuilder pattern
          final source = ResolvedSource(
            directory: workspace.source,
            origin: SourceOrigin.local,
          );

          final cCallbackBuilder = CallbackSourceBuilder(
            callback:
                ({
                  required source,
                  required input,
                  required output,
                  required logger,
                }) async {
                  await cBuilder.run(
                    input: input,
                    output: output,
                    logger: logger,
                  );
                },
          );

          await cCallbackBuilder.build(
            source: source,
            input: input,
            output: output,
            logger: Logger('test'),
          );

          // Find the built library - search entire workspace recursively
          final libName = _sharedLibraryName('native_toolchain_c_fallback');
          final libPath = _findBuiltLibrary(workspace.source, libName);

          if (libPath == null) {
            print('Workspace contents:');
            for (final entity in workspace.source.listSync(recursive: true)) {
              print('  ${entity.path}');
            }
            fail('Built library not found: $libName');
          }

          expect(File(libPath).existsSync(), isTrue);
          print('✅ Built library via CallbackSourceBuilder + CBuilder');
          print('   Size: ${File(libPath).lengthSync()} bytes');

          // Verify FFI: add(2, 3) should return 5
          final lib = DynamicLibrary.open(libPath);

          final addFn = lib
              .lookupFunction<
                Int32 Function(Int32, Int32),
                int Function(int, int)
              >('native_toolchain_c_fallback_add');

          final result = addFn(2, 3);
          expect(result, equals(5), reason: 'add(2, 3) should return 5');

          final versionFn = lib
              .lookupFunction<
                Pointer<Utf8> Function(),
                Pointer<Utf8> Function()
              >('native_toolchain_c_fallback_version');

          final version = versionFn().toDartString();
          expect(version, equals('1.0.0'), reason: 'version should be "1.0.0"');

          print('✅ FFI calls work correctly');
          print('   add(2, 3) = $result');
          print('   version = $version');

          lib.close();
        },
        timeout: Timeout(Duration(minutes: 2)),
      );
    },
  );
  group(
    'PrebuiltCodeAssetBuilder via NativeProjectBuilder.fromSourceFallback',
    () {
      late FixtureWorkspace workspace;

      setUp(() async {
        workspace = await FixtureWorkspace.create(
          'native_toolchain_c_fallback',
        );
      });

      tearDown(() async {
        await workspace.dispose();
      });

      test(
        'PrebuiltCodeAssetBuilder with source fallback builds and FFI works',
        () async {
          final cBuilder = CBuilder.library(
            name: 'native_toolchain_c_fallback',
            packageName: workspace.source.path,
            assetName: 'src/native_library.dart',
            sources: const ['src/native/fixture.c'],
          );

          final inputBuilder = BuildInputBuilder()
            ..setupShared(
              packageRoot: workspace.source.uri,
              packageName: 'native_toolchain_c_fallback',
              outputFile: workspace.source.uri.resolve('output.json'),
              outputDirectoryShared: workspace.source.uri.resolve('build/'),
            )
            ..setupBuildInput()
            ..config.setupBuild(linkingEnabled: false)
            ..addExtension(
              CodeAssetExtension(
                targetArchitecture: Architecture.current,
                targetOS: OS.current,
                linkModePreference: LinkModePreference.dynamic,
                macOS: OS.current == OS.macOS
                    ? MacOSCodeConfig(targetVersion: 13)
                    : null,
              ),
            );

          final input = inputBuilder.build();
          final output = BuildOutputBuilder();

          // Create a PrebuiltCodeAssetBuilder with a source fallback.
          // This exercises the full source fallback path:
          // PrebuiltCodeAssetBuilder → NativeProjectBuilder.fromSourceFallback
          //   → _buildWithSourceFallback → SourceFallbackResolver
          //   → CallbackSourceBuilder.build → CBuilder
          final builder = PrebuiltCodeAssetBuilder(
            assetName: 'src/native_library.dart',
            libraryStem: 'native_toolchain_c_fallback',
            manifest: const PrebuiltManifest(
              schemaVersion: 1,
              release: GitHubReleaseSource(
                owner: 'example',
                repository: 'native_toolchain_c_fallback',
                tag: 'v0.0.0',
              ),
              artifacts: {},
            ),
            linkModeResolver: (_) => DynamicLoadingBundled(),
            sourceFallback: SourceFallback(
              sources: [
                LocalSource(paths: ['.']),
              ],
              builder: CallbackSourceBuilder(
                callback:
                    ({
                      required source,
                      required input,
                      required output,
                      required logger,
                    }) async {
                      await cBuilder.run(
                        input: input,
                        output: output,
                        logger: logger,
                      );
                    },
              ),
            ),
          );

          await builder.run(
            input: input,
            output: output,
            logger: Logger('test.prebuilt'),
          );

          // Find the built library
          final libName = _sharedLibraryName('native_toolchain_c_fallback');
          final libPath = _findBuiltLibrary(workspace.source, libName);

          if (libPath == null) {
            print('Workspace contents:');
            for (final entity in workspace.source.listSync(recursive: true)) {
              print('  ${entity.path}');
            }
            fail('Built library not found: $libName');
          }

          expect(File(libPath).existsSync(), isTrue);
          print('✅ Built library via PrebuiltCodeAssetBuilder');
          print('   Size: ${File(libPath).lengthSync()} bytes');

          // Verify FFI: add(2, 3) should return 5
          final lib = DynamicLibrary.open(libPath);

          final addFn = lib
              .lookupFunction<
                Int32 Function(Int32, Int32),
                int Function(int, int)
              >('native_toolchain_c_fallback_add');

          final result = addFn(2, 3);
          expect(result, equals(5), reason: 'add(2, 3) should return 5');

          final versionFn = lib
              .lookupFunction<
                Pointer<Utf8> Function(),
                Pointer<Utf8> Function()
              >('native_toolchain_c_fallback_version');

          final version = versionFn().toDartString();
          expect(version, equals('1.0.0'), reason: 'version should be "1.0.0"');

          print('✅ FFI calls work correctly via PrebuiltCodeAssetBuilder');
          print('   add(2, 3) = $result');
          print('   version = $version');

          lib.close();
        },
        timeout: Timeout(Duration(minutes: 2)),
      );
    },
  );
}

String _sharedLibraryName(String stem) {
  if (Platform.isWindows) return '$stem.dll';
  if (Platform.isMacOS) return 'lib$stem.dylib';
  return 'lib$stem.so';
}

String? _findBuiltLibrary(Directory searchDir, String libName) {
  try {
    for (final entity in searchDir.listSync(recursive: true)) {
      if (entity is File && p.basename(entity.path) == libName) {
        return entity.path;
      }
    }
  } catch (_) {}
  return null;
}
