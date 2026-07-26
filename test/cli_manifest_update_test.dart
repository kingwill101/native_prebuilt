/// Tests for manifest update CLI - platform-specific built library layout
library;

import 'dart:io';

import 'package:native_prebuilt/src/config/native_prebuilt_config.dart';
import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:test/test.dart';

void main() {
  group('generateManifest with platform-specific built library layout', () {
    late Directory tempDir;
    late Directory builtLibraryDir;
    late Directory releaseAssetsDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('manifest_update_test_');
      builtLibraryDir = Directory('${tempDir.path}/built-library');
      releaseAssetsDir = Directory('${tempDir.path}/release-assets');
      builtLibraryDir.createSync(recursive: true);
      releaseAssetsDir.createSync(recursive: true);

      // Create platform-specific subdirectory structure (like the workflow produces)
      // e.g., built-library/android-arm64/libtdjson.so
      final androidDir = Directory('${builtLibraryDir.path}/android-arm64');
      androidDir.createSync(recursive: true);

      // Create a dummy library file in platform-specific location
      final libFile = File('${androidDir.path}/libtdjson.so');
      libFile.createSync(recursive: true);
      libFile.writeAsBytesSync([0x7f, 0x45, 0x4c, 0x46]); // ELF magic
    });

    tearDownAll(() async {
      await tempDir.delete(recursive: true);
    });

    test(
      'generateManifest finds library in platform-specific subdirectory',
      () async {
        // This test should PASS after the fix
        // Before the fix, it will FAIL because generateManifest only looks at
        // built-library/libtdjson.so (flat layout) not
        // built-library/android-arm64/libtdjson.so (platform-specific layout)

        final config = NativePrebuiltConfig(
          schema: 2,
          package: 'tdlib',
          assetName: 'tdlib_bindings_generated.dart',
          libraryStem: 'tdjson',
          release: ReleaseConfig(
            provider: 'github',
            repository: 'tdlib/tdlib',
            tag: 'tdlib-v1.8.65',
          ),
          artifacts: {
            'android-arm64': ArtifactConfig(
              archive: 'tdlib-android-arm64.tar.gz',
              payload: PayloadConfig(type: 'dynamic_library'),
            ),
          },
        );

        // This should work after the fix - it should find the library in
        // built-library/android-arm64/libtdjson.so
        final manifest = await generateManifest(
          config: config,
          tag: 'tdlib-v1.8.65',
          allowMissing: false,
          builtLibraryDir: builtLibraryDir,
          releaseAssetsDir: releaseAssetsDir,
        );

        expect(manifest.artifacts, contains('android-arm64'));
        expect(
          manifest.artifacts['android-arm64']!.archiveName,
          'tdlib-android-arm64.tar.gz',
        );
      },
    );

    test(
      'generateManifest falls back to flat layout for backwards compatibility',
      () async {
        // Test that the flat layout still works
        final flatDir = Directory('${tempDir.path}/flat-built-library');
        flatDir.createSync(recursive: true);

        final libFile = File('${flatDir.path}/libtdjson.so');
        libFile.createSync(recursive: true);
        libFile.writeAsBytesSync([0x7f, 0x45, 0x4c, 0x46]);

        final config = NativePrebuiltConfig(
          schema: 2,
          package: 'tdlib',
          assetName: 'tdlib_bindings_generated.dart',
          libraryStem: 'tdjson',
          release: ReleaseConfig(
            provider: 'github',
            repository: 'tdlib/tdlib',
            tag: 'tdlib-v1.8.65',
          ),
          artifacts: {
            'linux-x64': ArtifactConfig(
              archive: 'tdlib-linux-x64.tar.gz',
              payload: PayloadConfig(type: 'dynamic_library'),
            ),
          },
        );

        // This should work with both old and new code
        final manifest = await generateManifest(
          config: config,
          tag: 'tdlib-v1.8.65',
          allowMissing: false,
          builtLibraryDir: flatDir,
          releaseAssetsDir: releaseAssetsDir,
        );

        expect(manifest.artifacts, contains('linux-x64'));
      },
    );

    test(
      'generateManifest fails with clear error when library missing entirely',
      () async {
        final emptyDir = Directory('${tempDir.path}/empty');
        emptyDir.createSync(recursive: true);

        final config = NativePrebuiltConfig(
          schema: 2,
          package: 'tdlib',
          assetName: 'tdlib_bindings_generated.dart',
          libraryStem: 'tdjson',
          release: ReleaseConfig(
            provider: 'github',
            repository: 'tdlib/tdlib',
            tag: 'tdlib-v1.8.65',
          ),
          artifacts: {
            'android-arm64': ArtifactConfig(
              archive: 'tdlib-android-arm64.tar.gz',
              payload: PayloadConfig(type: 'dynamic_library'),
            ),
          },
        );

        try {
          await generateManifest(
            config: config,
            tag: 'tdlib-v1.8.65',
            allowMissing: false,
            builtLibraryDir: emptyDir,
            releaseAssetsDir: releaseAssetsDir,
          );
          fail('Expected StateError to be thrown');
        } on StateError catch (e) {
          expect(e.message, contains('android-arm64'));
        }
      },
    );
  });
}
