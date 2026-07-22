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

  test('workflow templates include expected files', () {
    final templates = workflowTemplates();
    expect(templates.keys, contains('native-prebuilt-build.yml'));
    expect(templates.keys, contains('native-prebuilt-release.yml'));
    expect(templates.keys, contains('native-prebuilt-update-manifest.yml'));
  });

  test('gitlab workflow templates include expected files', () {
    final templates = gitlabWorkflowTemplates();
    expect(templates.keys, contains('.gitlab-ci.yml'));
    expect(templates.keys, contains('.gitlab/ci/native-prebuilt-build.yml'));
    expect(templates.keys, contains('.gitlab/ci/native-prebuilt-release.yml'));
    expect(
      templates.keys,
      contains('.gitlab/ci/native-prebuilt-update-manifest.yml'),
    );
  });
}
