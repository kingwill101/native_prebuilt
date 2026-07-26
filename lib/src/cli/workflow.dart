import 'dart:io';

import 'package:artisanal/args.dart';
import 'package:path/path.dart' as p;

import '../config/native_prebuilt_config.dart';
import 'cli_config.dart';

class WorkflowCommand extends Command<void> {
  WorkflowCommand() {
    addSubcommand(WorkflowInitCommand());
  }

  @override
  String get name => 'workflow';

  @override
  String get description => 'Manage reusable workflow templates.';

  @override
  Future<void> run() async {
    io.info(usage);
  }
}

class WorkflowInitCommand extends Command<void> {
  WorkflowInitCommand() {
    argParser.addOption(
      'config',
      abbr: 'c',
      help: 'Path to native_prebuilt.yaml.',
    );
    argParser.addOption('output', abbr: 'o', help: 'Output directory.');
    argParser.addFlag('force', help: 'Overwrite existing files.');
    argParser.addFlag('gitlab', help: 'Write GitLab CI YAML templates.');
    argParser.addMultiOption(
      'platform',
      abbr: 'p',
      help:
          'Optional platform filter. Repeat this flag or pass a comma-separated list. '
          'Supported values: linux, macos, windows, android, ios. '
          'Defaults to the platforms declared in the manifest.',
    );
  }

  @override
  String get name => 'init';

  @override
  String get description => 'Write reusable workflow templates.';

  @override
  Future<void> run() async {
    final configFile = resolveConfigFile(option('config') as String?) ??
        (throw UsageException(
          'Could not find native_prebuilt.yaml. Pass --config explicitly.',
          usage,
        ));
    final gitlab = (option('gitlab') as bool?) ?? false;
    final config = await loadNativePrebuiltConfig(configFile);
    final output =
        option('output') as String? ?? (gitlab ? '.' : '.github/workflows');
    final force = (option('force') as bool?) ?? false;
    final requestedPlatforms =
        (option('platform') as List<String>?) ?? const <String>[];
    final dir = Directory(output)..createSync(recursive: true);
    final templates = gitlab
        ? gitlabWorkflowTemplates(
            packageName: config.package,
            artifactLabels: config.artifacts.keys,
            platforms: requestedPlatforms,
          )
        : workflowTemplates(
            packageName: config.package,
            artifactLabels: config.artifacts.keys,
          );
    for (final entry in templates.entries) {
      final file = File(p.join(dir.path, entry.key));
      file.parent.createSync(recursive: true);
      if (file.existsSync() && !force) continue;
      file.writeAsStringSync(entry.value);
      io.info('Wrote ${file.path}');
    }
  }
}

Map<String, String> workflowTemplates({
  required String packageName,
  Iterable<String>? artifactLabels,
}) => {
  'prebuilt.yml': _githubPrebuiltWorkflow(packageName, artifactLabels),
  'publish.yml': nativePrebuiltPublishWorkflow,
  'native-prebuilt-build.yml': nativePrebuiltBuildWorkflow,
  'native-prebuilt-release.yml': nativePrebuiltReleaseWorkflow,
  'native-prebuilt-update-manifest.yml': nativePrebuiltUpdateManifestWorkflow,
};

const _workflowPlatformOrder = <String>[
  'linux',
  'macos',
  'windows',
  'android',
  'ios',
];

String _githubPrebuiltWorkflow(
  String packageName,
  Iterable<String>? artifactLabels,
) {
  final platforms = <String>{};
  if (artifactLabels != null) {
    for (final label in artifactLabels) {
      platforms.add(_workflowPlatformFromArtifactLabel(label));
    }
  } else {
    platforms.addAll(['linux', 'macos', 'windows']);
  }
  final orderedPlatforms = _workflowPlatformOrder
      .where(platforms.contains)
      .toList(growable: false);

  final b = StringBuffer()
    ..writeln('name: Prebuilt')
    ..writeln()
    ..writeln('on:')
    ..writeln('  push:')
    ..writeln('    branches:')
    ..writeln('      - main')
    ..writeln('    tags:')
    ..writeln("      - '${packageName}-v*'")
    ..writeln('  pull_request:')
    ..writeln('  workflow_dispatch:')
    ..writeln('    inputs:')
    ..writeln('      tag:')
    ..writeln('        description: Tag to stamp into the generated manifest')
    ..writeln('        required: false')
    ..writeln('        type: string')
    ..writeln()
    ..writeln('permissions:')
    ..writeln('  contents: read')
    ..writeln()
    ..writeln('env:')
    ..writeln('  PUB_CACHE: \${{ github.workspace }}/.pub-cache')
    ..writeln('  CONFIG: native_prebuilt.yaml')
    ..writeln('  MANIFEST_OUTPUT: lib/src/hook/${packageName}_prebuilts.g.dart')
    ..writeln()
    ..writeln('jobs:');

  for (final platform in orderedPlatforms) {
    b.writeln(_githubBuildJob(platform));
  }

  final needs = orderedPlatforms.map((p) => 'build-$p').join('\n      - ');
  final downloads = orderedPlatforms
      .map(
        (p) =>
            """      - uses: actions/download-artifact@v4
        with:
          name: ${p}-built-library
          path: downloaded/$p/""",
      )
      .join('\n');
  final copyLines = orderedPlatforms
      .map((p) => '          cp -R downloaded/$p/. built-library/')
      .join('\n');

  b
    ..writeln('  update-manifest:')
    ..writeln(
      '    if: github.event_name == \'workflow_dispatch\' || startsWith(github.ref, \'refs/tags/\')',
    )
    ..writeln('    needs:')
    ..writeln('      - $needs')
    ..writeln('    runs-on: ubuntu-latest')
    ..writeln('    steps:')
    ..writeln('      - uses: actions/checkout@v4')
    ..writeln('      - uses: dart-lang/setup-dart@v1')
    ..writeln(downloads)
    ..writeln('      - name: Merge built libraries')
    ..writeln('        run: |')
    ..writeln('          rm -rf built-library release-assets')
    ..writeln('          mkdir -p built-library release-assets')
    ..writeln(copyLines)
    ..writeln('      - run: dart pub get')
    ..writeln('      - name: Generate manifest and release assets')
    ..writeln('        run: |')
    ..writeln(
      '          TAG=\"\${{ github.event_name == \'workflow_dispatch\' && github.event.inputs.tag || github.ref_name }}\"',
    )
    ..writeln('          dart run native_prebuilt manifest update \\')
    ..writeln('            --config \"\$CONFIG\" \\')
    ..writeln('            --output \"\$MANIFEST_OUTPUT\" \\')
    ..writeln('            --built-library-dir built-library \\')
    ..writeln('            --release-assets-dir release-assets \\')
    ..writeln('            --tag \"\$TAG\"')
    ..writeln('      - uses: actions/upload-artifact@v4')
    ..writeln('        with:')
    ..writeln('          name: release-assets')
    ..writeln('          path: release-assets/')
    ..writeln('          if-no-files-found: error')
    ..writeln()
    ..writeln('  release:')
    ..writeln(
      '    if: github.event_name == \'workflow_dispatch\' || startsWith(github.ref, \'refs/tags/\')',
    )
    ..writeln('    needs:')
    ..writeln('      - update-manifest')
    ..writeln('    runs-on: ubuntu-latest')
    ..writeln('    permissions:')
    ..writeln('      contents: write')
    ..writeln('    steps:')
    ..writeln('      - uses: actions/checkout@v4')
    ..writeln('      - uses: actions/download-artifact@v4')
    ..writeln('        with:')
    ..writeln('          name: release-assets')
    ..writeln('          path: release-assets/')
    ..writeln('      - name: Publish GitHub release assets')
    ..writeln('        uses: softprops/action-gh-release@v2')
    ..writeln('        with:')
    ..writeln(
      '          tag_name: \${{ github.event_name == \'workflow_dispatch\' && github.event.inputs.tag || github.ref_name }}',
    )
    ..writeln('          fail_on_unmatched_files: true')
    ..writeln('          files: release-assets/*');

  return b.toString();
}

String _githubBuildJob(String platform) {
  final runner = switch (platform) {
    'linux' => 'ubuntu-latest',
    'macos' => 'macos-15',
    'windows' => 'windows-latest',
    _ => 'ubuntu-latest',
  };
  final steps = StringBuffer();
  steps.writeln('    steps:');
  steps.writeln('      - uses: actions/checkout@v4');
  steps.writeln('      - uses: dart-lang/setup-dart@v1');
  if (platform == 'linux') {
    steps.writeln('      - name: Install native toolchain');
    steps.writeln('        run: |');
    steps.writeln('          sudo apt-get update');
    steps.writeln(
      '          sudo apt-get install -y --no-install-recommends \\',
    );
    steps.writeln('            build-essential \\');
    steps.writeln('            clang \\');
    steps.writeln('            cmake \\');
    steps.writeln('            libclang-dev \\');
    steps.writeln('            ninja-build \\');
    steps.writeln('            pkg-config');
  }
  steps.writeln('      - run: dart pub get');
  steps.writeln('      - run: dart test');
  steps.writeln('      - name: Stage built library');
  steps.writeln('        run: |');
  if (platform == 'windows') {
    steps.writeln(
      '          New-Item -ItemType Directory -Force -Path built-library | Out-Null',
    );
    steps.writeln(
      '          Copy-Item -Recurse -Force ".dart_tool/lib/*" built-library',
    );
  } else {
    steps.writeln('          mkdir -p built-library');
    steps.writeln('          cp -R .dart_tool/lib/. built-library/');
  }
  steps.writeln('      - uses: actions/upload-artifact@v4');
  steps.writeln('        with:');
  steps.writeln('          name: ${platform}-built-library');
  steps.writeln('          path: built-library/');
  steps.writeln('          if-no-files-found: error');

  return '''  build-$platform:
    runs-on: $runner
${steps.toString()}''';
}

List<String> _workflowPlatforms(List<String> rawPlatforms) {
  final selected = <String>{};
  for (final raw in rawPlatforms) {
    for (final part in raw.split(',')) {
      final platform = part.trim().toLowerCase();
      if (platform.isEmpty) continue;
      if (!_workflowPlatformOrder.contains(platform)) {
        throw FormatException(
          'Unsupported platform "$platform". Supported values: '
          '${_workflowPlatformOrder.join(', ')}',
        );
      }
      selected.add(platform);
    }
  }
  if (selected.isEmpty)
    return List<String>.unmodifiable(_workflowPlatformOrder);
  return _workflowPlatformOrder
      .where(selected.contains)
      .toList(growable: false);
}

List<String> _workflowPlatformsFromArtifacts(
  Iterable<String> artifactLabels,
  List<String> rawPlatforms,
) {
  final configured = <String>{};
  for (final label in artifactLabels) {
    final platform = _workflowPlatformFromArtifactLabel(label);
    configured.add(platform);
  }
  final filtered = rawPlatforms.isEmpty
      ? configured
      : configured.intersection(_workflowPlatforms(rawPlatforms).toSet());
  return _workflowPlatformOrder
      .where(filtered.contains)
      .toList(growable: false);
}

String _workflowPlatformFromArtifactLabel(String label) {
  final platform = label.split('-').first.toLowerCase();
  if (!_workflowPlatformOrder.contains(platform)) {
    throw FormatException(
      'Unsupported artifact platform "$label". Supported values: '
      '${_workflowPlatformOrder.join(', ')}',
    );
  }
  return platform;
}

Map<String, String> gitlabWorkflowTemplates({
  required String packageName,
  Iterable<String>? platforms,
  Iterable<String>? artifactLabels,
}) {
  final selectedPlatforms = artifactLabels == null
      ? _workflowPlatforms(platforms?.toList() ?? const [])
      : _workflowPlatformsFromArtifacts(
          artifactLabels,
          platforms?.toList() ?? const [],
        );
  final templates = <String, String>{
    '.gitlab-ci.yml': _gitlabRootPipeline(packageName, selectedPlatforms),
    '.gitlab/ci/native-prebuilt-release.yml': gitlabNativePrebuiltRelease,
    '.gitlab/ci/native-prebuilt-update-manifest.yml': _gitlabUpdateManifest(
      selectedPlatforms,
    ),
  };

  for (final platform in selectedPlatforms) {
    templates['.gitlab/ci/native-prebuilt-build-$platform.yml'] =
        _gitlabBuildTemplate(platform);
  }

  return templates;
}

String _gitlabBuildTemplate(String platform) {
  final template = switch (platform) {
    'linux' => gitlabNativePrebuiltBuildLinux,
    'macos' => gitlabNativePrebuiltBuildMacos,
    'windows' => gitlabNativePrebuiltBuildWindows,
    'android' => gitlabNativePrebuiltBuildAndroid,
    'ios' => gitlabNativePrebuiltBuildIos,
    _ => throw FormatException('Unsupported platform "$platform".'),
  };
  return template.replaceFirst(RegExp(r'\n  rules:\n    - if: .*\n'), '\n');
}

String _gitlabRootPipeline(String packageName, Iterable<String> platforms) {
  final includes = platforms
      .map(
        (platform) =>
            "  - local: '.gitlab/ci/native-prebuilt-build-$platform.yml'",
      )
      .join('\n');
  return '''
default:
  image: dart:stable

stages:
  - build
  - update
  - release

variables:
  PUB_CACHE: "\$CI_PROJECT_DIR/.pub-cache"
  BUILD_COMMAND: "dart test"
  CONFIG: "native_prebuilt.yaml"
  MANIFEST_OUTPUT: "lib/src/hook/${packageName}_prebuilts.g.dart"
  BUILT_LIBRARY_DIR: "built-library"
  RELEASE_ASSETS_DIR: "release-assets"
  RELEASE_PACKAGE_NAME: "${packageName}"
  TAG: "\$CI_COMMIT_TAG"

cache:
  paths:
    - .pub-cache/

include:
$includes
  - local: '.gitlab/ci/native-prebuilt-release.yml'
  - local: '.gitlab/ci/native-prebuilt-update-manifest.yml'
''';
}

String _gitlabUpdateManifest(Iterable<String> platforms) {
  final needs = platforms
      .map(
        (platform) =>
            '''
    - job: native_prebuilt:build:$platform
      artifacts: true''',
      )
      .join('\n');
  return '''
native_prebuilt:update_manifest:
  stage: update
  needs:
$needs
  rules:
    - if: '\$CI_COMMIT_TAG'
  script:
    - dart pub get
    - dart run native_prebuilt manifest update --config "\$CONFIG" --output "\$MANIFEST_OUTPUT" --built-library-dir "\$BUILT_LIBRARY_DIR" --release-assets-dir "\$RELEASE_ASSETS_DIR" --tag "\$TAG"
  artifacts:
    when: always
    paths:
      - "\$MANIFEST_OUTPUT"
      - "\$RELEASE_ASSETS_DIR/"
''';
}

const nativePrebuiltBuildWorkflow = r'''
name: Native Prebuilt Build
on:
  workflow_call:
    inputs:
      runner:
        required: true
        type: string
      build-script:
        required: true
        type: string
      artifact-name:
        required: true
        type: string
jobs:
  build:
    runs-on: ${{ inputs.runner }}
    steps:
      - uses: actions/checkout@v4
      - uses: dart-lang/setup-dart@v1
      - run: dart pub get
      - run: ${{ inputs.build-script }}
      - uses: actions/upload-artifact@v4
        with:
          name: ${{ inputs.artifact-name }}
          path: build/
''';

const nativePrebuiltReleaseWorkflow = r'''
name: Native Prebuilt Release
on:
  workflow_call:
    inputs:
      tag:
        required: true
        type: string
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: echo "Release ${{ inputs.tag }}"
''';

const nativePrebuiltUpdateManifestWorkflow = r'''
name: Native Prebuilt Update Manifest
on:
  workflow_call:
    inputs:
      config:
        required: true
        type: string
      built-library-dir:
        required: false
        type: string
        default: built-library
      release-assets-dir:
        required: false
        type: string
        default: release-assets
jobs:
  update-manifest:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: dart run native_prebuilt manifest update --config ${{ inputs.config }} --output lib/src/hook/asset_hashes.dart --built-library-dir ${{ inputs.built-library-dir }} --release-assets-dir ${{ inputs.release-assets-dir }}
''';

const nativePrebuiltPublishWorkflow = r'''
name: Publish to pub.dev

on:
  push:
    tags:
      - 'v[0-9]+.[0-9]+.[0-9]+*'

jobs:
  publish:
    permissions:
      id-token: write
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dart-lang/setup-dart@v1
      - name: Install dependencies
        run: dart pub get
      - name: Publish
        run: dart pub publish --force
''';

const gitlabRootPipeline = r'''
default:
  image: dart:stable

stages:
  - build
  - update
  - release

variables:
  PUB_CACHE: "$CI_PROJECT_DIR/.pub-cache"
  BUILD_COMMAND: "dart test"
  CONFIG: "native_prebuilt.yaml"
  MANIFEST_OUTPUT: "lib/src/hook/asset_hashes.dart"
  BUILT_LIBRARY_DIR: "built-library"
  RELEASE_ASSETS_DIR: "release-assets"
  RELEASE_PACKAGE_NAME: "release-assets"
  TAG: "$CI_COMMIT_TAG"
  ENABLE_ALL_PLATFORMS: "true"

cache:
  paths:
    - .pub-cache/

include:
  - local: '.gitlab/ci/native-prebuilt-build-linux.yml'
  - local: '.gitlab/ci/native-prebuilt-build-macos.yml'
  - local: '.gitlab/ci/native-prebuilt-build-windows.yml'
  - local: '.gitlab/ci/native-prebuilt-build-android.yml'
  - local: '.gitlab/ci/native-prebuilt-build-ios.yml'
  - local: '.gitlab/ci/native-prebuilt-release.yml'
  - local: '.gitlab/ci/native-prebuilt-update-manifest.yml'
''';

const gitlabNativePrebuiltBuildLinux = r'''
native_prebuilt:build:linux:
  stage: build
  image: dart:stable
  rules:
    - if: '$CI_COMMIT_TAG'
  script:
    - apt-get update
    - apt-get install -y --no-install-recommends build-essential clang pkg-config cmake ninja-build libclang-dev
    - dart pub get
    - "$BUILD_COMMAND"
    - mkdir -p "$BUILT_LIBRARY_DIR"
    - cp -R .dart_tool/lib/. "$BUILT_LIBRARY_DIR"/
  artifacts:
    when: always
    paths:
      - "$BUILT_LIBRARY_DIR/"
''';

const gitlabNativePrebuiltBuildMacos = r'''
native_prebuilt:build:macos:
  stage: build
  tags:
    - macos
  rules:
    - if: '$CI_COMMIT_TAG && $ENABLE_ALL_PLATFORMS == "true"'
  script:
    - dart pub get
    - "$BUILD_COMMAND"
    - mkdir -p "$BUILT_LIBRARY_DIR"
    - cp -R .dart_tool/lib/. "$BUILT_LIBRARY_DIR"/
  artifacts:
    when: always
    paths:
      - "$BUILT_LIBRARY_DIR/"
''';

const gitlabNativePrebuiltBuildWindows = r'''
native_prebuilt:build:windows:
  stage: build
  tags:
    - windows
  rules:
    - if: '$CI_COMMIT_TAG && $ENABLE_ALL_PLATFORMS == "true"'
  script:
    - dart pub get
    - "$BUILD_COMMAND"
    - New-Item -ItemType Directory -Force -Path "$env:BUILT_LIBRARY_DIR" | Out-Null
    - Copy-Item -Recurse -Force ".dart_tool/lib/*" "$env:BUILT_LIBRARY_DIR"
  artifacts:
    when: always
    paths:
      - "$BUILT_LIBRARY_DIR/"
''';

const gitlabNativePrebuiltBuildAndroid = r'''
native_prebuilt:build:android:
  stage: build
  image: ghcr.io/cirruslabs/flutter:stable
  rules:
    - if: '$CI_COMMIT_TAG && $ENABLE_ALL_PLATFORMS == "true"'
  script:
    - dart pub get
    - "$BUILD_COMMAND"
    - mkdir -p "$BUILT_LIBRARY_DIR"
    - cp -R .dart_tool/lib/. "$BUILT_LIBRARY_DIR"/
  artifacts:
    when: always
    paths:
      - "$BUILT_LIBRARY_DIR/"
''';

const gitlabNativePrebuiltBuildIos = r'''
native_prebuilt:build:ios:
  stage: build
  tags:
    - macos
  rules:
    - if: '$CI_COMMIT_TAG && $ENABLE_ALL_PLATFORMS == "true"'
  script:
    - dart pub get
    - "$BUILD_COMMAND"
    - mkdir -p "$BUILT_LIBRARY_DIR"
    - cp -R .dart_tool/lib/. "$BUILT_LIBRARY_DIR"/
  artifacts:
    when: always
    paths:
      - "$BUILT_LIBRARY_DIR/"
''';

const gitlabNativePrebuiltRelease = r'''
native_prebuilt:release:
  stage: release
  image: alpine:3.20
  needs:
    - job: native_prebuilt:update_manifest
      artifacts: true
  rules:
    - if: '$CI_COMMIT_TAG'
  before_script:
    - apk add --no-cache curl
  script:
    - |
      RELEASE_API="${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/releases"
      PACKAGE_BASE="${CI_PROJECT_URL}/-/packages/generic/${RELEASE_PACKAGE_NAME}/${TAG}"
      curl --fail --request POST \
        --header "JOB-TOKEN: ${CI_JOB_TOKEN}" \
        --data-urlencode "name=Release ${TAG}" \
        --data-urlencode "tag_name=${TAG}" \
        "${RELEASE_API}" || true
      for asset in "${RELEASE_ASSETS_DIR}"/*; do
        filename="$(basename "$asset")"
        curl --fail --request PUT \
          --header "JOB-TOKEN: ${CI_JOB_TOKEN}" \
          --upload-file "$asset" \
          "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/generic/${RELEASE_PACKAGE_NAME}/${TAG}/${filename}"
        curl --fail --request POST \
          --header "JOB-TOKEN: ${CI_JOB_TOKEN}" \
          --data-urlencode "name=${filename}" \
          --data-urlencode "url=${PACKAGE_BASE}/${filename}" \
          --data-urlencode "direct_asset_path=/release-assets/${filename}" \
          --data-urlencode "link_type=package" \
          "${RELEASE_API}/${TAG}/assets/links"
      done
''';

const gitlabNativePrebuiltUpdateManifest = r'''
native_prebuilt:update_manifest:
  stage: update
  needs:
    - job: native_prebuilt:build:linux
      artifacts: true
    - job: native_prebuilt:build:macos
      artifacts: true
      optional: true
    - job: native_prebuilt:build:windows
      artifacts: true
      optional: true
    - job: native_prebuilt:build:android
      artifacts: true
      optional: true
    - job: native_prebuilt:build:ios
      artifacts: true
      optional: true
  rules:
    - if: '$CI_COMMIT_TAG'
  script:
    - dart pub get
    - dart run native_prebuilt manifest update --config "$CONFIG" --output "$MANIFEST_OUTPUT" --built-library-dir "$BUILT_LIBRARY_DIR" --release-assets-dir "$RELEASE_ASSETS_DIR" --tag "$TAG"
  artifacts:
    when: always
    paths:
      - "$MANIFEST_OUTPUT"
      - "$RELEASE_ASSETS_DIR/"
''';
