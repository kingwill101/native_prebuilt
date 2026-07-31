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

  // Build recipes: use YAML-defined declarative recipes only.
  final build = _parseBuildDefinition(doc, variables: _parseVariables(doc));

  final project = NativeProject(
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

  final lockFile = resolveLockFile(null, configFile.parent);
  if (lockFile != null && lockFile.existsSync()) {
    return _applyNativePrebuiltLock(project, lockFile);
  }

  return project;
}

File? resolveLockFile([String? lockPath, Directory? workingDirectory]) {
  if (lockPath != null) {
    return File(lockPath).absolute;
  }

  var dir = (workingDirectory ?? Directory.current).absolute;
  while (true) {
    final candidate = File(p.join(dir.path, 'native_prebuilt.lock.yaml'));
    if (candidate.existsSync()) {
      return candidate;
    }

    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

NativeProject _applyNativePrebuiltLock(NativeProject project, File lockFile) {
  final doc = loadYaml(lockFile.readAsStringSync());
  if (doc is! Map) {
    return project;
  }

  final schema = doc['schema'];
  if (schema is! int || schema < 1) {
    return project;
  }

  final releaseSection = doc['release'] as Map?;
  final lockTag = releaseSection?['tag'] as String?;
  final artifactsSection = doc['artifacts'] as Map?;
  if (lockTag == null && artifactsSection == null) {
    return project;
  }

  final artifacts = <String, PrebuiltArtifact>{
    for (final entry in project.prebuilts.artifacts.entries)
      entry.key: entry.value,
  };

  if (artifactsSection != null) {
    for (final entry in artifactsSection.entries) {
      final platform = entry.key as String;
      final lockArtifact = entry.value as Map?;
      final baseArtifact = artifacts[platform];
      if (lockArtifact == null || baseArtifact == null) continue;

      final archiveSha256 = lockArtifact['archive_sha256'] as String?;
      final payloadSha256 = lockArtifact['payload_sha256'] as String?;
      if (!_isSha256(archiveSha256) || !_isSha256(payloadSha256)) {
        continue;
      }

      artifacts[platform] = PrebuiltArtifact(
        archiveName: baseArtifact.archiveName,
        archiveSha256: archiveSha256!,
        payloadSha256: payloadSha256!,
        payload: baseArtifact.payload,
      );
    }
  }

  return project.copyWith(
    prebuilts: PrebuiltManifest(
      schemaVersion: project.prebuilts.schemaVersion,
      release: lockTag == null
          ? project.prebuilts.release
          : project.prebuilts.release.withTag(lockTag),
      artifacts: artifacts,
    ),
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
  return GitHubReleaseSource(owner: repository, repository: '', tag: tag);
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
    repository: Uri.parse(
      yaml['url'] as String? ?? yaml['repository'] as String? ?? '',
    ),
    revision: yaml['ref'] as String? ?? yaml['revision'] as String? ?? '',
    subdirectory: yaml['subdirectory'] as String?,
    submodules: yaml['submodules'] as bool? ?? false,
  );
}

// -- YAML recipe parsing -------------------------------------------------

/// Parses the optional `build` section of `native_prebuilt.yaml` into
/// a [NativeBuildDefinition].
///
/// If no build recipes are declared, returns an empty definition so the CLI
/// can report that no declarative build recipe exists instead of guessing a
/// build system. Packages with custom builders should use their hook entrypoint
/// rather than `native_prebuilt build`.
/// Discovers a build project for the CLI.
///
/// Prefers a declarative `native_prebuilt.yaml`. If none exists, falls back
/// to a `hook/build.dart` project using the package name from `pubspec.yaml`.
/// Throws a descriptive error when neither exists.
NativeProject discoverBuildProject([Directory? workingDirectory]) {
  final dir = (workingDirectory ?? Directory.current).absolute;
  final configFile = resolveConfigFile(null, dir);
  if (configFile != null) {
    final project = detect(dir);
    if (project == null) {
      throw StateError(
        'Found native_prebuilt.yaml at ${configFile.path}, but it could not be parsed. '
        'Fix the manifest or remove it to use hook/build.dart fallback.',
      );
    }
    return project;
  }

  final hookBuildFile = resolveHookBuildFile(dir);
  if (hookBuildFile != null) {
    final packageName = readPackageName(dir) ?? p.basename(dir.path);
    return NativeProject(
      name: packageName,
      asset: NativeAssetSpec(
        assetName: 'src/$packageName.dart',
        libraryStem: packageName,
        linkMode: DynamicLoadingBundled(),
      ),
      prebuilts: const PrebuiltManifest(
        schemaVersion: 1,
        release: GitHubReleaseSource(owner: '', repository: '', tag: ''),
        artifacts: {},
      ),
      sources: const [],
      build: const NativeBuildDefinition(recipes: []),
      prebuiltPolicy: PrebuiltPolicy.forceSourceBuild,
    );
  }

  throw StateError(
    'No native_prebuilt.yaml or hook/build.dart found in ${dir.path}. '
    'Add a manifest for declarative builds or a hook/build.dart for hook-based builds.',
  );
}

File? resolveHookBuildFile([Directory? workingDirectory]) {
  var dir = (workingDirectory ?? Directory.current).absolute;
  while (true) {
    final candidate = File(p.join(dir.path, 'hook', 'build.dart'));
    if (candidate.existsSync()) {
      return candidate;
    }

    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

String? readPackageName([Directory? workingDirectory]) {
  var dir = (workingDirectory ?? Directory.current).absolute;
  while (true) {
    final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      final yaml = loadYaml(pubspec.readAsStringSync());
      if (yaml is YamlMap) {
        final name = yaml['name'];
        if (name is String && name.isNotEmpty) return name;
      }
    }

    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

Map<String, Object?> _parseVariables(Map<dynamic, dynamic> doc) {
  final section = doc['variables'];
  if (section == null) return const {};
  try {
    final normalized = normalizeYaml(section);
    if (normalized is Map<String, dynamic>) {
      return Map<String, Object?>.from(normalized);
    }
  } on FormatException {
    // Let manifest validation report malformed values through the typed loader.
  }
  return const {};
}

NativeBuildDefinition _parseBuildDefinition(
  Map<dynamic, dynamic> doc, {
  Map<String, Object?> variables = const {},
}) {
  final buildSection = doc['build'] as Map?;
  if (buildSection == null) {
    return const NativeBuildDefinition(recipes: []);
  }

  try {
    final normalized = normalizeYaml(buildSection);
    if (normalized is! Map<String, dynamic>) {
      return const NativeBuildDefinition(recipes: []);
    }
    final buildConfig = BuildConfig.fromJson(normalized);
    final definition = buildConfig.toBuildDefinition();
    return NativeBuildDefinition(
      recipes: definition.recipes,
      options: definition.options,
      variables: variables,
    );
  } on FormatException {
    return const NativeBuildDefinition(recipes: []);
  } on CheckedFromJsonException {
    return const NativeBuildDefinition(recipes: []);
  }
}

bool _isSha256(String? value) {
  return value != null && RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(value);
}
