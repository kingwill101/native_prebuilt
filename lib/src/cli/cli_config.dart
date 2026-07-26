import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:native_prebuilt/build.dart';
import 'package:native_prebuilt/src/config/native_prebuilt_config.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../manifest/prebuilt_artifact.dart';
import '../manifest/prebuilt_manifest.dart';
import '../manifest/release_source.dart';
import '../source/source_specification.dart';



/// Resolves the nearest `native_prebuilt.yaml` starting at [workingDirectory]
/// and walking up parent directories.
///
/// Returns `null` if no manifest can be found.
File? resolveConfigFile([String? configPath, Directory? workingDirectory]) {
  if (configPath != null) {
    return File(configPath).absolute;
  }

  var dir = (workingDirectory ?? Directory.current).absolute;
  while (true) {
    final candidate = File(p.join(dir.path, 'native_prebuilt.yaml'));
    if (candidate.existsSync()) {
      return candidate;
    }

    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

/// Attempts to auto-discover a [NativeProject] from the nearest
/// `native_prebuilt.yaml`.
///
/// Returns `null` if the file is absent, has an unsupported
/// schema version, or cannot be parsed.
NativeProject? detect([Directory? workingDirectory]) {
  final configFile = resolveConfigFile(null, workingDirectory);
  if (configFile == null) return null;

  final raw = configFile.readAsStringSync();
  final doc = loadYaml(raw);
  if (doc is! Map) return null;

  final schema = doc['schema'];
  if (schema is! int || schema < 1) return null;


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
  final build = _parseBuildDefinition(doc, libraryStem);

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
/// Supports schema v2 YAML format where the build section has
/// `recipes` with `target` patterns and `steps` lists.
/// Falls back to a generic CMake build definition when no recipes
/// are present.
NativeBuildDefinition _parseBuildDefinition(
  Map<dynamic, dynamic> doc,
  String libraryStem,
) {
  final buildSection = doc['build'] as Map?;
  if (buildSection == null) {
    return _genericCmakeBuildDefinition(libraryStem);
  }

  // Try to parse using the typed config model.
  try {
    final normalized = normalizeYaml(buildSection);
    if (normalized is! Map<String, dynamic>) {
      return _genericCmakeBuildDefinition(libraryStem);
    }
    final buildConfig = BuildConfig.fromJson(normalized);
    if (buildConfig.recipes.isNotEmpty) {
      return buildConfig.toBuildDefinition();
    }
  } on FormatException {
    // Fall through to generic CMake if parsing fails
  } on CheckedFromJsonException {
    // Fall through to generic CMake if parsing fails
  }

  return _genericCmakeBuildDefinition(libraryStem);
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
