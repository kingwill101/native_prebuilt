import 'dart:io';

import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:native_prebuilt/src/cli/native_prebuilt_cli.dart';
import 'package:native_prebuilt/src/cli/native_prebuilt_config.dart';
import 'package:test/test.dart';

void main() {
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

      final config = NativePrebuiltConfig.loadFile(configFile.path);
      expect(config.package, 'native_prebuilt_demo');
      expect(config.release, isA<GitHubReleaseSource>());
      final github = config.release as GitHubReleaseSource;
      expect(github.owner, 'kingwill101');
      expect(github.repository, 'dart_terminal');
      expect(github.tag, 'demo-v1.0.0');
      expect(config.artifacts.keys, contains('linux-x64'));
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

      final config = NativePrebuiltConfig.loadFile(configFile.path);
      expect(config.package, 'native_prebuilt_demo');
      expect(config.release, isA<GitLabReleaseSource>());
      final gitlab = config.release as GitLabReleaseSource;
      expect(gitlab.projectPath, 'group/subgroup/demo');
      expect(gitlab.tag, 'demo-v1.0.0');
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

  test('workflow templates include expected files', () {
    final templates = workflowTemplates(packageName: 'native_prebuilt_demo');
    expect(templates.keys, contains('prebuilt.yml'));
    expect(templates.keys, contains('publish.yml'));
    expect(templates.keys, contains('native-prebuilt-build.yml'));
    expect(templates.keys, contains('native-prebuilt-release.yml'));
    expect(templates.keys, contains('native-prebuilt-update-manifest.yml'));
    expect(templates['prebuilt.yml'], contains('name: Prebuilt'));
    expect(templates['prebuilt.yml'], contains('native_prebuilt_demo-v*'));
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
    expect(templates['prebuilt.yml'], contains('actions/download-artifact@v4'));
    expect(templates['prebuilt.yml'], contains('Merge built libraries'));
    expect(templates['prebuilt.yml'], contains('downloaded/windows/'));
    expect(templates['prebuilt.yml'], contains('release-assets'));
    expect(templates['prebuilt.yml'], contains('softprops/action-gh-release@v2'));
    expect(templates['prebuilt.yml'], contains('Publish GitHub release assets'));
  });

  test('gitlab workflow templates include expected files', () {
    final templates = gitlabWorkflowTemplates(packageName: 'native_prebuilt_demo');
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
    expect(templates['.gitlab-ci.yml'], contains('native-prebuilt-build-ios.yml'));
    expect(
      templates['.gitlab-ci.yml'],
      contains('MANIFEST_OUTPUT: "lib/src/hook/native_prebuilt_demo_prebuilts.g.dart"'),
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
    expect(
      templates['.gitlab-ci.yml'],
      contains('RELEASE_ASSETS_DIR'),
    );
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
}
