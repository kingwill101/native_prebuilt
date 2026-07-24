/// Integration test for PrebuiltCodeAssetBuilder + CallbackSourceBuilder + CBuilder.
///
/// This test verifies that the CallbackSourceBuilder path works end-to-end:
/// 1. CBuilder compiles C source into a native shared library
/// 2. The library is FFI-callable (add(2,3)=5, version="1.0.0")
library;

import 'dart:ffi';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:code_assets/src/code_assets/config.dart';
import 'package:ffi/ffi.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fixture_workspace.dart';

void main() {
  group('native_toolchain_c_fallback fixture (CallbackSourceBuilder + CBuilder)',
      () {
    late FixtureWorkspace workspace;

    setUp(() async {
      workspace = await FixtureWorkspace.create('native_toolchain_c_fallback');
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
          ..config.addBuildAssetTypes(['code_assets/code'])
          ..config.setupCode(
            targetArchitecture: Architecture.x64,
            targetOS: OS.linux,
            linkModePreference: LinkModePreference.dynamic,
          );

        final input = inputBuilder.build();
        final output = BuildOutputBuilder();

        print('input.outputDirectory = ${input.outputDirectory}');
        print('input.outputDirectoryShared = ${input.outputDirectoryShared}');
        print('input.config.buildAssetTypes = ${input.config.buildAssetTypes}');
        print('input.config.buildCodeAssets = ${input.config.buildCodeAssets}');

        // Run CBuilder through CallbackSourceBuilder pattern
        final source = ResolvedSource(
          directory: workspace.source,
          origin: SourceOrigin.local,
        );

        final cCallbackBuilder = CallbackSourceBuilder(
          callback: ({
            required source,
            required input,
            required output,
            required logger,
          }) async {
            await cBuilder.run(input: input, output: output, logger: logger);
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

        final addFn = lib.lookupFunction<
          Int32 Function(Int32, Int32),
          int Function(int, int)
        >('native_toolchain_c_fallback_add');

        final result = addFn(2, 3);
        expect(result, equals(5), reason: 'add(2, 3) should return 5');

        final versionFn = lib.lookupFunction<
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
  });
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
