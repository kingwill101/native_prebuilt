import 'dart:io';

import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:native_prebuilt/src/config/native_prebuilt_config.dart';
import 'package:native_prebuilt/src/cli/doctor.dart';
import 'package:native_prebuilt/src/cli/init.dart';
import 'package:native_prebuilt/src/cli/workflow.dart';
import 'package:test/test.dart';

void main() {
  test('init renders a manifest from package metadata', () {
    final manifest = renderInitialManifest(
      package: 'portable_pty',
      assetName: 'portable_pty_bindings_generated.dart',
      libraryStem: 'portable_pty_rs',
      linkMode: 'dynamic_library',
      releaseRepository: 'owner/repo',
      releaseTag: 'portable_pty-v0.1.0',
      sourceRepository: 'https://github.com/owner/repo',
      sourceRevision: 'deadbeef',
      sourceSubdirectory: 'pkgs/portable_pty',
      platforms: ['linux-x64', 'windows-x64'],
    );

    expect(manifest, contains('schema: 1'));
    expect(manifest, contains('package: portable_pty'));
    expect(manifest, contains('library_stem: portable_pty_rs'));
    expect(manifest, contains('subdirectory: pkgs/portable_pty'));
    expect(manifest, contains('portable_pty_rs-linux-x64.tar.gz'));
    expect(manifest, contains('portable_pty_rs-windows-x64.tar.gz'));
  });

  test('init discovers package metadata and refuses overwrite', () async {
    final dir = await Directory.systemTemp.createTemp('native_prebuilt_init_');
    final previous = Directory.current;
    try {
      Directory.current = dir;
      File('${dir.path}/pubspec.yaml').writeAsStringSync('''
name: demo_package
version: 2.3.4
repository: https://github.com/example/demo_package
''');

      await runNativePrebuiltCli([
        'init',
        '--output',
        'native_prebuilt.yaml',
        '--platform',
        'linux-x64,macos-arm64',
      ]);

      final output = File('${dir.path}/native_prebuilt.yaml');
      expect(output.existsSync(), isTrue);
      final content = output.readAsStringSync();
      expect(content, contains('package: demo_package'));
      expect(content, contains('repository: example/demo_package'));
      expect(content, contains('tag: demo_package-v2.3.4'));
      expect(content, contains('linux-x64'));
      expect(content, contains('macos-arm64'));

      final before = output.readAsStringSync();
      await runNativePrebuiltCli(['init']);
      expect(output.readAsStringSync(), before);
    } finally {
      Directory.current = previous;
      dir.deleteSync(recursive: true);
    }
  });

  test('loads CLI config', () async {
    final dir = await Directory.systemTemp.createTemp('native_prebuilt_cli_');
    try {
      final configFile = File('${dir.path}/native_prebuilt.yaml');
      configFile.writeAsStringSync('''
schema: 1
package: native_prebuilt_demo
asset_name: demo_bindings.dart
library_stem: demo_lib
release:
  repository: kingwill101/dart_terminal
  tag: demo-v1.0.0
artifacts:
  linux-x64:
    archive: demo-linux-x64.tar.gz
    payload:
      type: dynamic_library

''');

      final config = await loadNativePrebuiltConfig(configFile);
      expect(config.package, 'native_prebuilt_demo');
      expect(config.release.provider, 'github');
      expect(config.release.repository, 'kingwill101/dart_terminal');
      expect(config.release.tag, 'demo-v1.0.0');
      expect(config.artifacts.keys, contains('linux-x64'));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('loads minimal artifact config with defaults', () async {
    final dir = await Directory.systemTemp.createTemp('native_prebuilt_cli_');
    try {
      final configFile = File('${dir.path}/native_prebuilt.yaml');
      configFile.writeAsStringSync('''
schema: 1
package: my_package
asset_name: src/my_package.dart
library_stem: my_package
release:
  repository: owner/repo
  tag: my_package-v1.0.0
artifacts:
  linux-x64:
  linux-arm64:
''');

      final config = await loadNativePrebuiltConfig(configFile);
      expect(config.artifacts.length, 2);
      expect(
        config.artifacts['linux-x64']!.archive,
        'my_package-linux-x64.tar.gz',
      );
      expect(
        config.artifacts['linux-arm64']!.archive,
        'my_package-linux-arm64.tar.gz',
      );
      expect(config.artifacts['linux-x64']!.payload.type, 'dynamic_library');
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('loads GitLab CLI config', () async {
    final dir = await Directory.systemTemp.createTemp('native_prebuilt_cli_');
    try {
      final configFile = File('${dir.path}/native_prebuilt.yaml');
      configFile.writeAsStringSync('''
schema: 1
package: native_prebuilt_demo
asset_name: demo_bindings.dart
library_stem: demo_lib
release:
  provider: gitlab
  project: group/subgroup/demo
  tag: demo-v1.0.0
artifacts:
  linux-x64:
    archive: demo-linux-x64.tar.gz
    payload:
      type: dynamic_library

''');

      final config = await loadNativePrebuiltConfig(configFile);
      expect(config.package, 'native_prebuilt_demo');
      expect(config.release.provider, 'gitlab');
      expect(config.release.repository, 'group/subgroup/demo');
      expect(config.release.tag, 'demo-v1.0.0');
      expect(config.artifacts.keys, contains('linux-x64'));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('workflow init uses manifest artifact labels', () async {
    final dir = await Directory.systemTemp.createTemp('native_prebuilt_cli_');
    try {
      final configFile = File('${dir.path}/native_prebuilt.yaml');
      configFile.writeAsStringSync('''
schema: 1
package: native_prebuilt_demo
asset_name: demo_bindings.dart
library_stem: demo_lib
release:
  provider: gitlab
  project: group/subgroup/demo
  tag: demo-v1.0.0
artifacts:
  linux-x64:
    archive: demo-linux-x64.tar.gz
    payload:
      type: dynamic_library

''');

      final outputDir = Directory('${dir.path}/out');
      await runNativePrebuiltCli([
        'workflow',
        'init',
        '--gitlab',
        '--config',
        configFile.path,
        '--output',
        outputDir.path,
      ]);

      expect(File('${outputDir.path}/.gitlab-ci.yml').existsSync(), isTrue);
      expect(
        File(
          '${outputDir.path}/.gitlab/ci/native-prebuilt-build-linux.yml',
        ).existsSync(),
        isTrue,
      );
      expect(
        File(
          '${outputDir.path}/.gitlab/ci/native-prebuilt-build-macos.yml',
        ).existsSync(),
        isFalse,
      );
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('errors when no manifest or hook/build exists', () async {
    final dir = await Directory.systemTemp.createTemp('native_prebuilt_cli_');
    final previous = Directory.current;
    try {
      Directory.current = dir;
      File('${dir.path}/pubspec.yaml').writeAsStringSync('name: demo_pkg\n');

      expect(
        () => runNativePrebuiltCli(['build', '--target', 'linux-x64']),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('No native_prebuilt.yaml or hook/build.dart found'),
          ),
        ),
      );
    } finally {
      Directory.current = previous;
      dir.deleteSync(recursive: true);
    }
  });

  test('workflow templates include expected files', () {
    final templates = workflowTemplates(packageName: 'native_prebuilt_demo');
    expect(templates.keys, contains('prebuilt.yml'));
    expect(templates.keys, contains('publish.yml'));
    expect(templates.keys, contains('native-prebuilt-build.yml'));
    expect(templates.keys, contains('native-prebuilt-release.yml'));
    expect(templates.keys, contains('native-prebuilt-update-manifest.yml'));
    expect(templates['prebuilt.yml'], contains('name: Prebuilt'));
    expect(templates['prebuilt.yml'], contains('Release tag to publish'));
    expect(
      templates['prebuilt.yml'],
      contains('lib/src/hook/native_prebuilt_demo_prebuilts.g.dart'),
    );
    expect(templates['publish.yml'], contains('name: Publish to pub.dev'));
    expect(templates['publish.yml'], contains('dart pub publish --force'));
    expect(templates['prebuilt.yml'], contains('needs:'));
    expect(templates['prebuilt.yml'], contains('build-linux'));
    expect(templates['prebuilt.yml'], contains('build-windows'));
    expect(templates['prebuilt.yml'], contains('build-macos'));
    expect(templates['prebuilt.yml'], contains('actions/download-artifact@v7'));
    expect(templates['prebuilt.yml'], contains('Merge built libraries'));
    expect(templates['prebuilt.yml'], contains('downloaded/windows/'));
    expect(templates['prebuilt.yml'], contains('release-assets'));
    expect(
      templates['prebuilt.yml'],
      contains('softprops/action-gh-release@v3'),
    );
    expect(
      templates['prebuilt.yml'],
      contains('Publish GitHub release assets'),
    );
  });

  test('gitlab workflow templates include expected files', () {
    final templates = gitlabWorkflowTemplates(
      packageName: 'native_prebuilt_demo',
    );
    expect(templates.keys, contains('.gitlab-ci.yml'));
    expect(
      templates.keys,
      contains('.gitlab/ci/native-prebuilt-build-linux.yml'),
    );
    expect(
      templates.keys,
      contains('.gitlab/ci/native-prebuilt-build-macos.yml'),
    );
    expect(
      templates.keys,
      contains('.gitlab/ci/native-prebuilt-build-windows.yml'),
    );
    expect(
      templates.keys,
      contains('.gitlab/ci/native-prebuilt-build-android.yml'),
    );
    expect(
      templates.keys,
      contains('.gitlab/ci/native-prebuilt-build-ios.yml'),
    );
    expect(templates.keys, contains('.gitlab/ci/native-prebuilt-release.yml'));
    expect(
      templates.keys,
      contains('.gitlab/ci/native-prebuilt-update-manifest.yml'),
    );
    expect(
      templates['.gitlab-ci.yml'],
      contains('native-prebuilt-build-ios.yml'),
    );
    expect(
      templates['.gitlab-ci.yml'],
      contains(
        'MANIFEST_OUTPUT: "lib/src/hook/native_prebuilt_demo_prebuilts.g.dart"',
      ),
    );
    expect(
      templates['.gitlab-ci.yml'],
      contains('RELEASE_PACKAGE_NAME: "native_prebuilt_demo"'),
    );
    expect(
      templates['.gitlab/ci/native-prebuilt-build-linux.yml'],
      contains('apt-get install -y --no-install-recommends build-essential'),
    );
    expect(
      templates['.gitlab/ci/native-prebuilt-build-linux.yml'],
      contains('mkdir -p "\$BUILT_LIBRARY_DIR"'),
    );
    expect(
      templates['.gitlab/ci/native-prebuilt-build-linux.yml'],
      contains('cp -R .dart_tool/lib/. "\$BUILT_LIBRARY_DIR"/'),
    );
    expect(
      templates['.gitlab/ci/native-prebuilt-build-android.yml'],
      contains('ghcr.io/cirruslabs/flutter:stable'),
    );
    expect(templates['.gitlab-ci.yml'], contains('RELEASE_ASSETS_DIR'));
    expect(
      templates['.gitlab/ci/native-prebuilt-update-manifest.yml'],
      contains('--built-library-dir "\$BUILT_LIBRARY_DIR"'),
    );
    expect(
      templates['.gitlab/ci/native-prebuilt-update-manifest.yml'],
      contains('--release-assets-dir "\$RELEASE_ASSETS_DIR"'),
    );
    expect(
      templates['.gitlab/ci/native-prebuilt-update-manifest.yml'],
      contains('\$RELEASE_ASSETS_DIR/'),
    );
    expect(
      templates['.gitlab/ci/native-prebuilt-release.yml'],
      contains('apk add --no-cache curl'),
    );
    expect(
      templates['.gitlab/ci/native-prebuilt-release.yml'],
      contains('packages/generic'),
    );
    expect(
      templates['.gitlab/ci/native-prebuilt-release.yml'],
      contains('direct_asset_path=/release-assets/'),
    );
    expect(
      templates['.gitlab/ci/native-prebuilt-release.yml'],
      contains('for asset in "\${RELEASE_ASSETS_DIR}"/*'),
    );
  });

  test('gitlab workflow templates default to the manifest platforms', () {
    final templates = gitlabWorkflowTemplates(
      packageName: 'native_prebuilt_demo',
      artifactLabels: ['linux-x64'],
    );

    expect(
      templates.keys,
      contains('.gitlab/ci/native-prebuilt-build-linux.yml'),
    );
    expect(
      templates.keys,
      isNot(contains('.gitlab/ci/native-prebuilt-build-macos.yml')),
    );
    expect(
      templates.keys,
      isNot(contains('.gitlab/ci/native-prebuilt-build-windows.yml')),
    );
    expect(
      templates.keys,
      isNot(contains('.gitlab/ci/native-prebuilt-build-android.yml')),
    );
    expect(
      templates.keys,
      isNot(contains('.gitlab/ci/native-prebuilt-build-ios.yml')),
    );
    expect(
      templates['.gitlab-ci.yml'],
      contains('native-prebuilt-build-linux.yml'),
    );
    expect(
      templates['.gitlab/ci/native-prebuilt-update-manifest.yml'],
      contains('job: native_prebuilt:build:linux'),
    );
    expect(
      templates['.gitlab/ci/native-prebuilt-update-manifest.yml'],
      isNot(contains('job: native_prebuilt:build:windows')),
    );
  });

  test('gitlab workflow templates can be filtered to selected platforms', () {
    final templates = gitlabWorkflowTemplates(
      packageName: 'native_prebuilt_demo',
      platforms: ['linux', 'windows'],
    );

    expect(
      templates.keys,
      contains('.gitlab/ci/native-prebuilt-build-linux.yml'),
    );
    expect(
      templates.keys,
      contains('.gitlab/ci/native-prebuilt-build-windows.yml'),
    );
    expect(
      templates.keys,
      isNot(contains('.gitlab/ci/native-prebuilt-build-macos.yml')),
    );
    expect(
      templates.keys,
      isNot(contains('.gitlab/ci/native-prebuilt-build-android.yml')),
    );
    expect(
      templates.keys,
      isNot(contains('.gitlab/ci/native-prebuilt-build-ios.yml')),
    );
    expect(
      templates['.gitlab-ci.yml'],
      contains('native-prebuilt-build-linux.yml'),
    );
    expect(
      templates['.gitlab-ci.yml'],
      contains('native-prebuilt-build-windows.yml'),
    );
    expect(
      templates['.gitlab/ci/native-prebuilt-update-manifest.yml'],
      contains('job: native_prebuilt:build:linux'),
    );
    expect(
      templates['.gitlab/ci/native-prebuilt-update-manifest.yml'],
      contains('job: native_prebuilt:build:windows'),
    );
    expect(
      templates['.gitlab/ci/native-prebuilt-update-manifest.yml'],
      isNot(contains('job: native_prebuilt:build:macos')),
    );
  });

  group('manifest command', () {
    test(
      'update defaults to sibling built-library when build config exists',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'native_prebuilt_cli_',
        );
        try {
          final configFile = File('${dir.path}/native_prebuilt.yaml');
          configFile.writeAsStringSync('''
schema: 1
package: demo
asset_name: src/demo.dart
library_stem: demo
release:
  provider: github
  repository: owner/demo
  tag: demo-v1.0.0
build:
  recipes:
    - target:
        os: linux
      steps:
        - id: configure
          type: cmake_configure
          source_directory: .
          build_directory: build
        - id: build
          type: cmake_build
          build_directory: build
        - id: export
          type: export_artifact
          artifact: demo
          kind: dynamic_library
          primary: build/libdemo.so
artifacts:
  linux-x64:
    archive: demo-linux-x64.tar.gz
    payload:
      type: dynamic_library
''');

          final builtLibraryDir = Directory(
            '${dir.path}/built-library/linux-x64',
          )..createSync(recursive: true);
          File('${builtLibraryDir.path}/libdemo.so')
            ..createSync(recursive: true)
            ..writeAsBytesSync([0x7f, 0x45, 0x4c, 0x46]);

          final outputFile = File(
            '${dir.path}/lib/src/hook/demo_prebuilts.g.dart',
          );
          final previousDir = Directory.current;
          try {
            Directory.current = dir;
            await runNativePrebuiltCli([
              'manifest',
              'update',
              '--tag',
              'demo-v1.0.0',
            ]);

            expect(outputFile.existsSync(), isTrue);
            expect(
              outputFile.readAsStringSync(),
              contains('demo-linux-x64.tar.gz'),
            );

            await runNativePrebuiltCli(['manifest', 'verify']);
          } finally {
            Directory.current = previousDir;
          }
        } finally {
          dir.deleteSync(recursive: true);
        }
      },
    );

    test('update can write a native_prebuilt.lock.yaml file', () async {
      final dir = await Directory.systemTemp.createTemp('native_prebuilt_cli_');
      try {
        File('${dir.path}/native_prebuilt.yaml').writeAsStringSync('''
schema: 1
package: demo
asset_name: src/demo.dart
library_stem: demo
release:
  provider: github
  repository: owner/demo
  tag: demo-v1.0.0
build:
  recipes:
    - target:
        os: linux
      steps:
        - id: configure
          type: cmake_configure
          source_directory: .
          build_directory: build
        - id: build
          type: cmake_build
          build_directory: build
        - id: export
          type: export_artifact
          artifact: demo
          kind: dynamic_library
          primary: build/libdemo.so
artifacts:
  linux-x64:
    archive: demo-linux-x64.tar.gz
    payload:
      type: dynamic_library
''');

        final builtLibraryDir = Directory('${dir.path}/built-library/linux-x64')
          ..createSync(recursive: true);
        File('${builtLibraryDir.path}/libdemo.so')
          ..createSync(recursive: true)
          ..writeAsBytesSync([0x7f, 0x45, 0x4c, 0x46]);

        final outputFile = File('${dir.path}/native_prebuilt.lock.yaml');
        final previousDir = Directory.current;
        try {
          Directory.current = dir;
          await runNativePrebuiltCli([
            'manifest',
            'update',
            '--output',
            outputFile.path,
            '--tag',
            'demo-v1.0.0',
          ]);

          expect(outputFile.existsSync(), isTrue);
          final lock = outputFile.readAsStringSync();
          expect(lock, contains("tag: 'demo-v1.0.0'"));
          expect(lock, contains("'linux-x64':"));
          expect(lock, contains('archive_sha256:'));

          await runNativePrebuiltCli([
            'manifest',
            'verify',
            '--output',
            outputFile.path,
          ]);
        } finally {
          Directory.current = previousDir;
        }
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });

  group('plan command', () {
    test('plan with --target shows build plan', () async {
      await runNativePrebuiltCli(['plan', '--target', 'linux-x64']);
    });

    test('plan without --target shows help', () async {
      // Without --target, the command prints usage and exits cleanly (exit code 0)
      await runNativePrebuiltCli(['plan']);
    });
  });

  group('cache-key command', () {
    test('cache-key with --target shows cache key', () async {
      await runNativePrebuiltCli(['cache-key', '--target', 'linux-x64']);
    });
  });

  group('explain-cache command', () {
    test('explain-cache with --target shows cache explanation', () async {
      await runNativePrebuiltCli(['explain-cache', '--target', 'linux-x64']);
    });
  });

  group('fetch command', () {
    test('fetch without --config prints usage', () async {
      await runNativePrebuiltCli(['fetch', '--platform', 'linux-x64']);
    });

    test('fetch without --platform prints usage', () async {
      await runNativePrebuiltCli(['fetch', '--config', 'native_prebuilt.yaml']);
    });
  });

  group('doctor command', () {
    test('doctor without --config prints usage', () async {
      await runNativePrebuiltCli(['doctor']);
    });

    test('doctor with valid config shows summary', () async {
      final dir = await Directory.systemTemp.createTemp('native_prebuilt_cli_');
      try {
        final configFile = File('${dir.path}/native_prebuilt.yaml');
        configFile.writeAsStringSync('''
schema: 1
package: test
asset_name: test_bindings.dart
library_stem: test_lib
release:
  provider: github
  owner: test
  repository: test/repo
  tag: v1.0.0
artifacts:
  linux-x64:
    archive: test-linux-x64.tar.gz
    payload:
      type: dynamic_library
''');

        final config = await loadNativePrebuiltConfig(configFile);
        final summary = renderDoctorSummary(config);
        expect(summary, contains('package: test'));
        expect(
          summary,
          contains('release: GitHubReleaseSource(test/repo@v1.0.0)'),
        );
        expect(summary, contains('artifacts: 1'));
        expect(summary, contains('linux-x64'));
        expect(summary, contains('test-linux-x64.tar.gz'));

        await runNativePrebuiltCli(['doctor', '--config', configFile.path]);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}
