import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:native_prebuilt/build.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../manifest/prebuilt_artifact.dart';
import '../manifest/prebuilt_manifest.dart';
import '../manifest/release_source.dart';
import '../source/source_specification.dart';

/// Maps build step type strings to their `fromMap` factories.
///
/// When a `native_prebuilt.yaml` contains a `build` section with
/// platform-specific step lists, each step is looked up by its
/// `type` key and constructed via this registry.
final Map<String, NativeBuildStep Function(Map<String, dynamic>)> recipeRegistry = {
  'cmake_configure': (map) => CmakeConfigureStep.fromMap(map),
  'cmake_build': (map) => CmakeBuildStep.fromMap(map),
  'export_artifact': (map) => ExportArtifactStep.fromMap(map),
  'command': (map) => CommandStep.fromMap(map),
  'download_archive': (map) => DownloadArchiveStep.fromMap(map),
  'git_checkout': (map) => GitCheckoutStep.fromMap(map),
  'git_apply_patch': (map) => GitApplyPatchStep.fromMap(map),
  'copy': (map) => CopyStep.fromMap(map),
  'strip': (map) => StripStep.fromMap(map),
};

/// Attempts to auto-discover a [NativeProject] from
/// `native_prebuilt.yaml` in [workingDirectory].
///
/// Returns `null` if the file is absent, has an unsupported
/// schema version, or cannot be parsed.
NativeProject? detect(Directory workingDirectory) {
  final configFile = File(p.join(workingDirectory.path, 'native_prebuilt.yaml'));
  if (!configFile.existsSync()) return null;

  final raw = configFile.readAsStringSync();
  final doc = loadYaml(raw);
  if (doc is! Map) return null;

  final schema = doc['schema'];
  if (schema is! int || schema != 1) return null;

  final packageName = doc['package'] as String? ?? 'native_prebuilt';
  final assetName = doc['asset_name'] as String? ?? '';
  final libraryStem = doc['library_stem'] as String? ?? '';
  final linkMode = _parseLinkMode(doc['link_mode']);

  final releaseSection = doc['release'] as Map?;
  if (releaseSection == null) return null;

  final release = _parseReleaseSource(releaseSection);

  // Prebuilt artifacts: archiveSha256/payloadSha256 may be empty
  // placeholders until valid hashes are available.
  final artifactsSection = doc['artifacts'] as Map?;
  final artifacts = <String, PrebuiltArtifact>{};
  if (artifactsSection != null) {
    for (final entry in artifactsSection.entries) {
      final platform = entry.key as String;
      final aDoc = entry.value as Map?;
      if (aDoc == null) continue;
      final archive = aDoc['archive'] as String? ?? '';
      final payload = aDoc['payload'] as Map?;
      final payloadType = payload?['type'] as String? ?? 'dynamic_library';
      final isStatic = payloadType == 'static_library';
      artifacts[platform] = PrebuiltArtifact(
        archiveName: archive,
        archiveSha256: aDoc['archive_sha256'] as String? ?? '',
        payloadSha256: aDoc['payload_sha256'] as String? ?? '',
        payload: isStatic
            ? StaticLibraryPayload(libraryStem: libraryStem)
            : DynamicLibraryPayload(libraryStem: libraryStem),
      );
    }
  }

  // Parse source specification from YAML (supports nested 'source.git' format).
  final sources = <SourceSpecification>[];
  final sourceSection = doc['source'] as Map?;
  if (sourceSection != null) {
    final sourceSpec = _parseSourceSpec(sourceSection);
    if (sourceSpec != null) {
      sources.add(sourceSpec);
    }
  } else if (release is GitHubReleaseSource && release.repository.isNotEmpty) {
    sources.add(
      GitSource(
        repository: Uri.parse(
          'https://github.com/${release.owner}/${release.repository}',
        ),
        revision: release.tag,
      ),
    );
  }

  // Build recipes: prefer YAML-defined recipes, fall back to generic CMake.
  final build = _parseBuildRecipes(doc, libraryStem);

  return NativeProject(
    name: packageName,
    asset: NativeAssetSpec(
      assetName: assetName,
      libraryStem: libraryStem,
      linkMode: linkMode,
    ),
    prebuilts: PrebuiltManifest(
      schemaVersion: 1,
      release: release,
      artifacts: artifacts,
    ),
    sources: sources,
    build: build,
  );
}

LinkMode _parseLinkMode(dynamic value) {
  if (value is String) {
    return switch (value.toLowerCase()) {
      'static_library' => StaticLinking(),
      _ => DynamicLoadingBundled(),
    };
  }
  return DynamicLoadingBundled();
}

ReleaseSource _parseReleaseSource(Map yaml) {
  final repository = yaml['repository'] as String? ?? '';
  final tag = yaml['tag'] as String? ?? '';
  if (repository.contains('/')) {
    final parts = repository.split('/');
    return GitHubReleaseSource(
      owner: parts.first,
      repository: parts.sublist(1).join('/'),
      tag: tag,
    );
  }
  return GitHubReleaseSource(
    owner: repository,
    repository: '',
    tag: tag,
  );
}

SourceSpecification? _parseSourceSpec(Map yaml) {
  // Handle nested format: source.git.url / source.git.ref
  if (yaml.containsKey('git')) {
    return _parseGitSource(yaml['git'] as Map);
  }

  // Handle flat format: type: git, url: ..., ref: ...
  final sourceType = yaml['type'] as String?;
  if (sourceType == 'git') {
    return _parseGitSource(yaml);
  }

  // Handle other types
  if (sourceType == 'local') {
    return LocalSource(
      paths: (yaml['paths'] as List?)?.map((e) => e as String).toList() ?? [],
    );
  }

  if (sourceType == 'archive') {
    return ArchiveSource(
      uri: Uri.parse(yaml['uri'] as String? ?? ''),
      sha256: yaml['sha256'] as String? ?? '',
      subdirectory: yaml['subdirectory'] as String?,
    );
  }

  return null;
}

SourceSpecification _parseGitSource(Map yaml) {
  return GitSource(
    repository: Uri.parse(yaml['url'] as String? ?? yaml['repository'] as String? ?? ''),
    revision: yaml['ref'] as String? ?? yaml['revision'] as String? ?? '',
    subdirectory: yaml['subdirectory'] as String?,
    submodules: yaml['submodules'] as bool? ?? false,
  );
}

// -- YAML recipe parsing -------------------------------------------------

/// Parses the optional `build` section of `native_prebuilt.yaml` into
/// a [NativeBuildDefinition].
///
/// The YAML structure is:
///
/// ```yaml
/// build:
///   linux-x64:
///     steps:
///       - type: cmake_configure
///         source_directory: .
///         build_directory: build
///         ...
///       - type: cmake_build
///         build_directory: build
///       - type: export_artifact
///         id: tdjson
///         kind: dynamic_library
///         primary_path: build/libtdjson.so
/// ```
///
/// When the `build` section is absent or a platform has no matching
/// recipe entries, [defaultSteps] is returned as a fallback.
NativeBuildDefinition _parseBuildRecipes(
  Map<dynamic, dynamic> doc,
  String libraryStem,
) {
  final buildSection = doc['build'] as Map?;
  if (buildSection == null) {
    return _genericCmakeBuildDefinition(libraryStem);
  }
  final recipes = <NativeTargetRecipe>[];
  for (final entry in buildSection.entries) {
    final platformName = entry.key as String?;
    final platformConfig = entry.value as Map?;
    if (platformName == null || platformConfig == null) continue;
    final steps = _parseStepList(platformConfig['steps'] as List?);
    if (steps.isEmpty) continue;
    final os = _parseOS(platformName);
    if (os == null) continue;
    recipes.add(
      NativeTargetRecipe(
        pattern: NativeTargetPattern(os: os),
        recipe: StepBuildRecipe(steps: steps),
      ),
    );
  }
  if (recipes.isEmpty) {
    return _genericCmakeBuildDefinition(libraryStem);
  }
  return NativeBuildDefinition(recipes: recipes);
}

/// Parses a list of YAML step maps into [NativeBuildStep] instances
/// using [recipeRegistry].
List<NativeBuildStep> _parseStepList(List<dynamic>? stepDocs) {
  if (stepDocs == null) return [];
  return stepDocs.map((stepDoc) {
    // YAML parsing returns YamlMap, not Map<String, dynamic>.
    // Convert to a plain Dart map first.
    final Map<String, dynamic> stepMap;
    if (stepDoc is Map) {
      stepMap = {
        for (final entry in stepDoc.entries) entry.key.toString(): entry.value,
      };
    } else {
      throw StateError('Each build step must be a map; got: ${stepDoc.runtimeType}');
    }
    final type = stepMap['type'] as String?;
    if (type == null) {
      throw StateError('Each build step must have a "type" key');
    }
    final factory = recipeRegistry[type];
    if (factory == null) {
      throw StateError(
        'Unknown build step type "$type". '
        'Known types: ${recipeRegistry.keys.join(", ")}',
      );
    }
    return factory(stepMap);
  }).toList();
}

/// Maps a platform identifier string (e.g. "linux-x64") to an [OS].
OS? _parseOS(String platform) {
  return switch (platform) {
    'linux-x64' => OS.linux,
    'linux-arm64' => OS.linux,
    'macos-arm64' => OS.macOS,
    'macos-x64' => OS.macOS,
    'windows-x64' => OS.windows,
    'windows-arm64' => OS.windows,
    'android-arm64' => OS.android,
    'android-arm' => OS.android,
    'ios-arm64' => OS.iOS,
    _ => null,
  };
}

// -- Legacy generic recipe (fallback) ------------------------------------

/// Builds generic CMake recipes for all supported platforms
/// using [libraryStem] for the output artifact name.
NativeBuildDefinition _genericCmakeBuildDefinition(String libraryStem) {
  final linux = 'build/lib$libraryStem.so';
  final macos = 'build/lib$libraryStem.dylib';
  final windows = 'build/$libraryStem.dll';

  return NativeBuildDefinition(
    recipes: [
      NativeTargetRecipe(
        pattern: const NativeTargetPattern(os: OS.linux),
        recipe: _cmakeRecipe(linux),
      ),
      NativeTargetRecipe(
        pattern: const NativeTargetPattern(os: OS.macOS),
        recipe: _cmakeRecipe(macos),
      ),
      NativeTargetRecipe(
        pattern: const NativeTargetPattern(os: OS.windows),
        recipe: StepBuildRecipe(steps: [
          CmakeConfigureStep(
            sourceDirectory: '.',
            buildDirectory: 'build',
            generator: 'Ninja',
            defines: {'CMAKE_BUILD_TYPE': 'Release'},
          ),
          CmakeBuildStep(buildDirectory: 'build'),
          ExportArtifactStep(
            id: 'export_library',
            declaration: NativeArtifactDeclaration(
              id: 'library',
              kind: NativeArtifactKind.dynamicLibrary,
              primaryPath: windows,
            ),
          ),
        ]),
      ),
      NativeTargetRecipe(
        pattern: const NativeTargetPattern(os: OS.android),
        recipe: _cmakeRecipe(linux),
      ),
      NativeTargetRecipe(
        pattern: const NativeTargetPattern(os: OS.iOS),
        recipe: StepBuildRecipe(steps: [
          CmakeConfigureStep(
            sourceDirectory: '.',
            buildDirectory: 'build',
            toolchainFile: 'CMake/iOS.cmake',
            defines: {
              'CMAKE_BUILD_TYPE': 'Release',
              'IOS_PLATFORM': 'OS',
              'IOS_DEPLOYMENT_TARGET': '17',
            },
          ),
          CmakeBuildStep(buildDirectory: 'build'),
          ExportArtifactStep(
            id: 'export_library',
            declaration: NativeArtifactDeclaration(
              id: 'library',
              kind: NativeArtifactKind.dynamicLibrary,
              primaryPath: macos,
            ),
          ),
        ]),
      ),
    ],
  );
}

StepBuildRecipe _cmakeRecipe(String primaryPath) {
  return StepBuildRecipe(steps: [
    CmakeConfigureStep(
      sourceDirectory: '.',
      buildDirectory: 'build',
      defines: {'CMAKE_BUILD_TYPE': 'Release'},
    ),
    CmakeBuildStep(buildDirectory: 'build'),
    ExportArtifactStep(
      id: 'export_library',
      declaration: NativeArtifactDeclaration(
        id: 'library',
        kind: NativeArtifactKind.dynamicLibrary,
        primaryPath: primaryPath,
      ),
    ),
  ]);
}
