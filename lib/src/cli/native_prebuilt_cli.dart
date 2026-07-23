import 'dart:io';

import 'package:artisanal/args.dart';
import 'package:code_assets/code_assets.dart';
import 'package:path/path.dart' as p;

import '../archive/archive_entry.dart';
import '../archive/archive_reader.dart';
import '../binary/library_name.dart';
import '../download/http_downloader.dart';
import '../manifest/prebuilt_artifact.dart';
import '../manifest/prebuilt_manifest.dart';
import '../manifest/release_source.dart';
import '../platform/native_target.dart';
import 'native_prebuilt_config.dart';

/// Runs the `native_prebuilt` CLI.
Future<void> runNativePrebuiltCli(List<String> args) async {
  final runner =
      CommandRunner<void>(
          'native_prebuilt',
          'Utilities for prebuilt native artifacts in Dart packages.',
        )
        ..addCommand(ManifestCommand())
        ..addCommand(FetchCommand())
        ..addCommand(DoctorCommand())
        ..addCommand(WorkflowCommand());

  await runner.run(args);
}

class ManifestCommand extends Command<void> {
  ManifestCommand() {
    argParser.addOption('config', abbr: 'c', help: 'Path to YAML config file.');
    argParser.addOption('output', abbr: 'o', help: 'Output Dart file.');
    argParser.addOption('tag', help: 'Override the release tag.');
    argParser.addFlag('allow-missing', help: 'Allow missing artifacts.');
    addSubcommand(_ManifestUpdateCommand());
    addSubcommand(_ManifestVerifyCommand());
  }

  @override
  String get name => 'manifest';

  @override
  String get description => 'Generate or verify the Dart manifest.';

  @override
  Future<void> run() async {
    io.info(usage);
  }
}

class _ManifestUpdateCommand extends Command<void> {
  @override
  String get name => 'update';

  @override
  String get description => 'Generate the Dart manifest from the release.';

  _ManifestUpdateCommand() {
    argParser.addOption('config', abbr: 'c', help: 'Path to YAML config file.');
    argParser.addOption('output', abbr: 'o', help: 'Output Dart file.');
    argParser.addOption('tag', help: 'Override the release tag.');
    argParser.addOption(
      'built-library-dir',
      help: 'Path to built native libraries to package before release.',
    );
    argParser.addFlag('allow-missing', help: 'Allow missing artifacts.');
  }

  @override
  Future<void> run() async {
    final configPath = option('config') as String?;
    final outputPath = option('output') as String?;
    if (configPath == null || outputPath == null) {
      throw UsageException('update requires --config and --output', usage);
    }

    final config = NativePrebuiltConfig.loadFile(configPath);
    final tag = (option('tag') as String?) ?? config.release.tag;
    final allowMissing = (option('allow-missing') as bool?) ?? false;
    final builtLibraryDirPath = option('built-library-dir') as String?;
    final builtLibraryDir = builtLibraryDirPath == null
        ? null
        : Directory(builtLibraryDirPath);

    final manifest = await _generateManifest(
      config: config,
      tag: tag,
      allowMissing: allowMissing,
      builtLibraryDir: builtLibraryDir,
    );

    final content = _renderManifest(config, manifest, tag);
    File(outputPath).writeAsStringSync(content);
    io.info('Wrote $outputPath');
  }
}

class _ManifestVerifyCommand extends Command<void> {
  @override
  String get name => 'verify';

  @override
  String get description => 'Verify the generated Dart manifest.';

  _ManifestVerifyCommand() {
    argParser.addOption('config', abbr: 'c', help: 'Path to YAML config file.');
    argParser.addOption('output', abbr: 'o', help: 'Output Dart file.');
    argParser.addOption('tag', help: 'Override the release tag.');
    argParser.addOption(
      'built-library-dir',
      help: 'Path to built native libraries to package before release.',
    );
    argParser.addFlag('allow-missing', help: 'Allow missing artifacts.');
  }

  @override
  Future<void> run() async {
    final configPath = option('config') as String?;
    final outputPath = option('output') as String?;
    if (configPath == null || outputPath == null) {
      throw UsageException('verify requires --config and --output', usage);
    }

    final config = NativePrebuiltConfig.loadFile(configPath);
    final tag = (option('tag') as String?) ?? config.release.tag;
    final allowMissing = (option('allow-missing') as bool?) ?? false;
    final builtLibraryDirPath = option('built-library-dir') as String?;
    final builtLibraryDir = builtLibraryDirPath == null
        ? null
        : Directory(builtLibraryDirPath);

    final manifest = await _generateManifest(
      config: config,
      tag: tag,
      allowMissing: allowMissing,
      builtLibraryDir: builtLibraryDir,
    );

    final expected = _renderManifest(config, manifest, tag);
    final actual = File(outputPath).readAsStringSync();
    if (actual != expected) {
      stderr.writeln('Manifest mismatch: $outputPath');
      exitCode = 1;
      return;
    }
    io.info('OK: $outputPath');
  }
}

class FetchCommand extends Command<void> {
  FetchCommand() {
    argParser.addOption('config', abbr: 'c', help: 'Path to YAML config file.');
    argParser.addOption(
      'platform',
      abbr: 'p',
      help: 'Platform label to fetch.',
    );
    argParser.addOption('out', abbr: 'o', help: 'Output directory.');
  }

  @override
  String get name => 'fetch';

  @override
  String get description => 'Fetch one prebuilt artifact to a local cache.';

  @override
  Future<void> run() async {
    final configPath = option('config') as String?;
    final platform = option('platform') as String?;
    final outPath = option('out') as String? ?? '.prebuilt';
    if (configPath == null || platform == null) {
      throw UsageException('fetch requires --config and --platform', usage);
    }

    final config = NativePrebuiltConfig.loadFile(configPath);
    final artifact = config.artifacts[platform];
    if (artifact == null) {
      throw UsageException('Unknown platform: $platform', usage);
    }

    final target = _targetFromPlatformLabel(platform);
    final canonicalName = canonicalLibraryName(
      target: target,
      libraryStem: config.libraryStem,
      payload: artifact.payload,
    );

    final downloader = HttpDownloader();
    final release = config.release;
    final tmpDir = await Directory.systemTemp.createTemp(
      'native_prebuilt_fetch_',
    );
    try {
      final archivePath = File(p.join(tmpDir.path, artifact.archiveName));
      await downloader.downloadReleaseArtifact(
        source: release,
        archiveName: artifact.archiveName,
        targetPath: archivePath,
      );

      final extracted = ArchiveReader().extractMatchingEntry(
        archiveFile: archivePath,
        outputDir: Directory(p.join(outPath, platform)),
        selection: ArchiveSelectionContext(
          canonicalName: canonicalName,
          acceptVersionedNames: artifact.payload is DynamicLibraryPayload,
        ),
      );
      if (extracted == null) {
        throw StateError(
          'No matching payload found in ${artifact.archiveName}',
        );
      }
      io.info(extracted.path);
    } finally {
      tmpDir.deleteSync(recursive: true);
    }
  }
}

class DoctorCommand extends Command<void> {
  DoctorCommand() {
    argParser.addOption('config', abbr: 'c', help: 'Path to YAML config file.');
  }

  @override
  String get name => 'doctor';

  @override
  String get description => 'Validate configuration and io.info a summary.';

  @override
  Future<void> run() async {
    final configPath = option('config') as String?;
    if (configPath == null) {
      throw UsageException('doctor requires --config', usage);
    }
    final config = NativePrebuiltConfig.loadFile(configPath);
    io.info('package: ${config.package}');
    io.info('release: ${config.release}');
    io.info('artifacts: ${config.artifacts.length}');
  }
}

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
    argParser.addOption('config', abbr: 'c', help: 'Path to native_prebuilt.yaml.');
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
    final configPath = option('config') as String? ?? 'native_prebuilt.yaml';
    final gitlab = (option('gitlab') as bool?) ?? false;
    final config = gitlab ? NativePrebuiltConfig.loadFile(configPath) : null;
    final output = option('output') as String? ??
        (gitlab ? '.' : '.github/workflows');
    final force = (option('force') as bool?) ?? false;
    final requestedPlatforms = (option('platform') as List<String>?) ??
        const <String>[];
    final dir = Directory(output)..createSync(recursive: true);
    final templates = gitlab
        ? gitlabWorkflowTemplates(
            artifactLabels: config!.artifacts.keys,
            platforms: requestedPlatforms,
          )
        : workflowTemplates();
    for (final entry in templates.entries) {
      final file = File(p.join(dir.path, entry.key));
      file.parent.createSync(recursive: true);
      if (file.existsSync() && !force) continue;
      file.writeAsStringSync(entry.value);
      io.info('Wrote ${file.path}');
    }
  }
}

Future<PrebuiltManifest> _generateManifest({
  required NativePrebuiltConfig config,
  required String tag,
  required bool allowMissing,
  Directory? builtLibraryDir,
}) async {
  final downloader = HttpDownloader();
  final archiveReader = ArchiveReader();
  final tempDir = await Directory.systemTemp.createTemp(
    'native_prebuilt_manifest_',
  );
  try {
    final payloadHashes = <String, String>{};
    final artifacts = <String, PrebuiltArtifact>{};

    for (final entry in config.artifacts.entries) {
      final platform = entry.key;
      final artifactConfig = entry.value;
      final target = _targetFromPlatformLabel(platform);
      final canonicalName = canonicalLibraryName(
        target: target,
        libraryStem: config.libraryStem,
        payload: artifactConfig.payload,
      );

      final archiveFile = File(
        p.join(tempDir.path, artifactConfig.archiveName),
      );
      if (builtLibraryDir != null) {
        final builtFile = File(
          p.join(builtLibraryDir.path, canonicalName),
        );
        if (!builtFile.existsSync()) {
          if (allowMissing) continue;
          throw StateError(
            'Missing built library for $platform: ${builtFile.path}',
          );
        }
        await _packageBuiltLibrary(
          builtLibraryDir: builtLibraryDir,
          canonicalName: canonicalName,
          archiveFile: archiveFile,
        );
      } else {
        try {
          await downloader.downloadReleaseArtifact(
            source: config.release.withTag(tag),
            archiveName: artifactConfig.archiveName,
            targetPath: archiveFile,
          );
        } catch (e) {
          if (allowMissing) continue;
          rethrow;
        }
      }

      final archiveHash = await ArchiveReader.sha256Hash(archiveFile);

      final extractedDir = Directory(p.join(tempDir.path, 'extract_$platform'))
        ..createSync(recursive: true);
      final extracted = archiveReader.extractMatchingEntry(
        archiveFile: archiveFile,
        outputDir: extractedDir,
        selection: ArchiveSelectionContext(
          canonicalName: canonicalName,
          acceptVersionedNames: artifactConfig.payload is DynamicLibraryPayload,
        ),
      );
      if (extracted == null) {
        if (allowMissing) continue;
        throw StateError('No payload found for $platform');
      }
      payloadHashes[platform] = await ArchiveReader.sha256Hash(extracted);

      artifacts[platform] = PrebuiltArtifact(
        archiveName: artifactConfig.archiveName,
        archiveSha256: archiveHash,
        payloadSha256: payloadHashes[platform]!,
        payload: artifactConfig.payload,
      );
    }

    return PrebuiltManifest(
      schemaVersion: config.schema,
      release: config.release.withTag(tag),
      artifacts: artifacts,
    );
  } finally {
    tempDir.deleteSync(recursive: true);
  }
}

Future<void> _packageBuiltLibrary({
  required Directory builtLibraryDir,
  required String canonicalName,
  required File archiveFile,
}) async {
  final result = await Process.run('tar', [
    'czf',
    archiveFile.path,
    '-C',
    builtLibraryDir.path,
    canonicalName,
  ]);
  if (result.exitCode != 0) {
    throw StateError('tar create failed: ${result.stderr}');
  }
}

String _renderManifest(
  NativePrebuiltConfig config,
  PrebuiltManifest manifest,
  String tag,
) {
  final b = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND.')
    ..writeln('// ignore_for_file: constant_identifier_names')
    ..writeln()
    ..writeln("import 'package:native_prebuilt/native_prebuilt.dart';")
    ..writeln()
    ..writeln('const ${config.package}Prebuilts = PrebuiltManifest(')
    ..writeln('  schemaVersion: ${manifest.schemaVersion},')
    ..writeln('  release: ${_renderReleaseSource(config.release.withTag(tag))},')
    ..writeln('  artifacts: {');

  for (final entry in manifest.artifacts.entries) {
    final platform = entry.key;
    final artifact = entry.value;
    b.writeln("    '$platform': PrebuiltArtifact(");
    b.writeln("      archiveName: '${artifact.archiveName}',");
    b.writeln("      archiveSha256: '${artifact.archiveSha256}',");
    b.writeln("      payloadSha256: '${artifact.payloadSha256}',");
    b.writeln('      payload: ${_renderPayload(artifact.payload)},');
    b.writeln('    ),');
  }

  b
    ..writeln('  },')
    ..writeln(');')
    ..writeln();
  return b.toString();
}

String _renderPayload(ArtifactPayload payload) => switch (payload) {
  DynamicLibraryPayload(:final libraryStem, :final acceptVersionedNames) =>
    'DynamicLibraryPayload(libraryStem: \'$libraryStem\', acceptVersionedNames: $acceptVersionedNames)',
  StaticLibraryPayload(:final libraryStem) =>
    'StaticLibraryPayload(libraryStem: \'$libraryStem\')',
};

String _renderReleaseSource(ReleaseSource source) => switch (source) {
  GitHubReleaseSource(:final owner, :final repository, :final tag) =>
    'GitHubReleaseSource(owner: \'$owner\', repository: \'$repository\', tag: \'$tag\')',
  GitLabReleaseSource(:final projectPath, :final tag) =>
    'GitLabReleaseSource(projectPath: \'$projectPath\', tag: \'$tag\')',
};

NativeTarget _targetFromPlatformLabel(String label) {
  final parts = label.split('-');
  if (label.startsWith('ios-sim-') && parts.length == 3) {
    return NativeTarget(
      os: OS.iOS,
      architecture: Architecture.fromString(parts[2]),
      iOSSdk: IOSSdk.iPhoneSimulator,
    );
  }
  if (parts.length != 2) {
    throw FormatException('Unsupported platform label: $label');
  }
  return NativeTarget(
    os: OS.fromString(parts[0]),
    architecture: Architecture.fromString(parts[1]),
  );
}

Map<String, String> workflowTemplates() => {
  'prebuilt.yml': nativePrebuiltPrebuiltWorkflow,
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
  if (selected.isEmpty) return List<String>.unmodifiable(_workflowPlatformOrder);
  return _workflowPlatformOrder.where(selected.contains).toList(growable: false);
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
  return _workflowPlatformOrder.where(filtered.contains).toList(growable: false);
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
    '.gitlab-ci.yml': _gitlabRootPipeline(selectedPlatforms),
    '.gitlab/ci/native-prebuilt-release.yml': gitlabNativePrebuiltRelease,
    '.gitlab/ci/native-prebuilt-update-manifest.yml':
        _gitlabUpdateManifest(selectedPlatforms),
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

String _gitlabRootPipeline(Iterable<String> platforms) {
  final includes = platforms
      .map((platform) => "  - local: '.gitlab/ci/native-prebuilt-build-$platform.yml'")
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
  MANIFEST_OUTPUT: "lib/src/hook/demo_prebuilts.g.dart"
  BUILT_LIBRARY_DIR: "built-library"
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
        (platform) => '''
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
    - dart run native_prebuilt manifest update --config "\$CONFIG" --output "\$MANIFEST_OUTPUT" --built-library-dir "\$BUILT_LIBRARY_DIR" --tag "\$TAG"
  artifacts:
    when: always
    paths:
      - "\$MANIFEST_OUTPUT"
''';
}

const nativePrebuiltPrebuiltWorkflow = r'''
name: Prebuilt

on:
  push:
    branches:
      - main
    tags:
      - 'native_prebuilt_e2e-v*'
  pull_request:
  workflow_dispatch:
    inputs:
      tag:
        description: Tag to stamp into the generated manifest
        required: false
        type: string

permissions:
  contents: read

env:
  PUB_CACHE: ${{ github.workspace }}/.pub-cache
  CONFIG: native_prebuilt.yaml
  MANIFEST_OUTPUT: lib/src/hook/demo_prebuilts.g.dart

jobs:
  build-linux:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dart-lang/setup-dart@v1
      - name: Install native toolchain
        run: |
          sudo apt-get update
          sudo apt-get install -y --no-install-recommends \
            build-essential \
            clang \
            cmake \
            libclang-dev \
            ninja-build \
            pkg-config
      - run: dart pub get
      - run: dart test
      - name: Stage built library
        run: |
          mkdir -p built-library
          cp -R .dart_tool/lib/. built-library/
      - uses: actions/upload-artifact@v4
        with:
          name: linux-built-library
          path: built-library/
          if-no-files-found: error

  build-windows:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dart-lang/setup-dart@v1
      - run: dart pub get
      - run: dart test
      - name: Stage built library
        run: |
          New-Item -ItemType Directory -Force -Path built-library | Out-Null
          Copy-Item -Recurse -Force ".dart_tool/lib/*" built-library
      - uses: actions/upload-artifact@v4
        with:
          name: windows-built-library
          path: built-library/
          if-no-files-found: error

  build-macos:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - uses: dart-lang/setup-dart@v1
      - run: dart pub get
      - run: dart test
      - name: Stage built library
        run: |
          mkdir -p built-library
          cp -R .dart_tool/lib/. built-library/
      - uses: actions/upload-artifact@v4
        with:
          name: macos-built-library
          path: built-library/
          if-no-files-found: error

  update-manifest:
    if: github.event_name == 'workflow_dispatch' || startsWith(github.ref, 'refs/tags/')
    needs:
      - build-linux
      - build-windows
      - build-macos
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dart-lang/setup-dart@v1
      - uses: actions/download-artifact@v4
        with:
          name: linux-built-library
          path: downloaded/linux/
      - uses: actions/download-artifact@v4
        with:
          name: windows-built-library
          path: downloaded/windows/
      - uses: actions/download-artifact@v4
        with:
          name: macos-built-library
          path: downloaded/macos/
      - name: Merge built libraries
        run: |
          rm -rf built-library
          mkdir -p built-library
          cp -R downloaded/linux/. built-library/
          cp -R downloaded/windows/. built-library/
          cp -R downloaded/macos/. built-library/
      - run: dart pub get
      - name: Generate manifest
        run: |
          TAG="${{ github.event_name == 'workflow_dispatch' && github.event.inputs.tag || github.ref_name }}"
          dart run native_prebuilt manifest update \
            --config "$CONFIG" \
            --output "$MANIFEST_OUTPUT" \
            --built-library-dir built-library \
            --tag "$TAG"
      - uses: actions/upload-artifact@v4
        with:
          name: generated-manifest
          path: ${{ env.MANIFEST_OUTPUT }}
''';

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
jobs:
  update-manifest:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: dart run native_prebuilt manifest update --config ${{ inputs.config }} --output lib/src/hook/asset_hashes.dart --built-library-dir ${{ inputs.built-library-dir }}
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
  script:
    - echo "Release $TAG"
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
    - dart run native_prebuilt manifest update --config "$CONFIG" --output "$MANIFEST_OUTPUT" --built-library-dir "$BUILT_LIBRARY_DIR" --tag "$TAG"
  artifacts:
    when: always
    paths:
      - "$MANIFEST_OUTPUT"
''';
