import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:yaml/yaml.dart';

import '../build/native_project.dart';
import '../manifest/prebuilt_artifact.dart';
import '../manifest/release_source.dart';
import 'build_step_config.dart';
import 'schema/build_schema.dart';
import 'validation.dart';
import '../source/source_specification.dart';

part 'native_prebuilt_config.g.dart';

@JsonSerializable(
  checked: true,
  disallowUnrecognizedKeys: true,
  explicitToJson: true,
  fieldRename: FieldRename.snake,
)
final class NativePrebuiltConfig {
  NativePrebuiltConfig({
    required this.schema,
    required this.package,
    required this.assetName,
    required this.libraryStem,
    this.linkMode,
    this.source,
    this.build,
    required this.release,
    required this.artifacts,
    this.targets,
  });

  factory NativePrebuiltConfig.fromJson(Map<String, dynamic> json) =>
      _$NativePrebuiltConfigFromJson(json);

  Map<String, dynamic> toJson() => _$NativePrebuiltConfigToJson(this);

  final int schema;
  final String package;
  final String assetName;
  final String libraryStem;
  final String? linkMode;
  final SourceConfig? source;
  final BuildConfig? build;
  final ReleaseConfig release;
  final Map<String, ArtifactConfig> artifacts;
  final Map<String, TargetConfig>? targets;
}

@JsonSerializable(
  checked: true,
  disallowUnrecognizedKeys: true,
  fieldRename: FieldRename.snake,
)
final class ReleaseConfig {
  ReleaseConfig({
    required this.provider,
    required this.repository,
    required this.tag,
  });

  factory ReleaseConfig.fromJson(Map<String, dynamic> json) =>
      _$ReleaseConfigFromJson(json);

  Map<String, dynamic> toJson() => _$ReleaseConfigToJson(this);

  ReleaseSource toReleaseSource() {
    return switch (provider.toLowerCase()) {
      'github' => GitHubReleaseSource(
        owner: _splitRepository(repository).first,
        repository: _splitRepository(repository).last,
        tag: tag,
      ),
      'gitlab' => GitLabReleaseSource(projectPath: repository, tag: tag),
      _ => throw FormatException('Unsupported release.provider "$provider"'),
    };
  }

  final String provider;
  final String repository;
  final String tag;

  @override
  String toString() =>
      'ReleaseConfig(provider: $provider, repository: $repository, tag: $tag)';
}

@JsonSerializable(
  checked: true,
  disallowUnrecognizedKeys: true,
  fieldRename: FieldRename.snake,
)
final class SourceConfig {
  SourceConfig({
    required this.type,
    required this.repository,
    this.revision,
    this.subdirectory,
    this.submodules = false,
  });

  factory SourceConfig.fromJson(Map<String, dynamic> json) =>
      _$SourceConfigFromJson(json);

  Map<String, dynamic> toJson() => _$SourceConfigToJson(this);

  SourceSpecification? toSourceSpecification() {
    return switch (type) {
      'git' => GitSource(
        repository: Uri.parse(repository),
        revision: revision ?? '',
        subdirectory: subdirectory,
        submodules: submodules,
      ),
      _ => null,
    };
  }

  final String type;
  final String repository;
  final String? revision;
  final String? subdirectory;
  final bool submodules;
}

@JsonSerializable(
  checked: true,
  disallowUnrecognizedKeys: true,
  explicitToJson: true,
  fieldRename: FieldRename.snake,
)
final class BuildConfig {
  BuildConfig({
    this.recipes = const [],
    this.dependencies = const {},
    this.options = const {},
  });

  factory BuildConfig.fromJson(Map<String, dynamic> json) =>
      _$BuildConfigFromJson(json);

  Map<String, dynamic> toJson() => _$BuildConfigToJson(this);

  /// Target-specific build recipes.
  final List<TargetRecipeConfig> recipes;

  /// Optional dependency declarations.
  final Map<String, DependencyConfig> dependencies;

  /// Optional build options.
  final Map<String, Object?> options;

  /// Converts this config into a [NativeBuildDefinition] that can resolve
  /// recipes for specific targets.
  NativeBuildDefinition toBuildDefinition() {
    return NativeBuildDefinition(
      recipes: [
        for (final recipe in recipes)
          NativeTargetRecipe(
            pattern: recipe.target.toNativeTargetPattern(),
            recipe: StepBuildRecipe(
              steps: [for (final step in recipe.steps) step.toBuildStep()],
              needsById: {
                for (final step in recipe.steps) step.id: step.needs,
              },
            ),
          ),
      ],
    );
  }
}

/// Pattern for matching build targets.
@JsonSerializable(
  checked: true,
  disallowUnrecognizedKeys: true,
  fieldRename: FieldRename.snake,
)
final class TargetPatternConfig {
  const TargetPatternConfig({this.os, this.architecture, this.sdk});

  factory TargetPatternConfig.fromJson(Map<String, dynamic> json) =>
      _$TargetPatternConfigFromJson(json);

  Map<String, dynamic> toJson() => _$TargetPatternConfigToJson(this);

  /// Target OS (e.g., "linux", "android", "ios", "macos", "windows").
  /// When null, matches any OS.
  final String? os;

  /// Target architecture (e.g., "x64", "arm64").
  /// When null, matches any architecture.
  final String? architecture;

  /// iOS SDK (e.g., "iphoneos", "iphonesimulator").
  /// When null, matches any iOS SDK.
  final String? sdk;

  /// Converts to a [NativeTargetPattern] for runtime matching.
  NativeTargetPattern toNativeTargetPattern() {
    return NativeTargetPattern(
      os: _parseOS(os),
      architecture: _parseArchitecture(architecture),
      iOSSdk: _parseIOSSdk(sdk),
    );
  }
}

List<String> _splitRepository(String repository) {
  final parts = repository.split('/');
  if (parts.length != 2) {
    throw FormatException(
      'release.repository must be "owner/repo" (got "$repository")',
    );
  }
  return parts;
}

/// A build recipe associated with a target pattern.
@JsonSerializable(
  checked: true,
  disallowUnrecognizedKeys: true,
  explicitToJson: true,
  fieldRename: FieldRename.snake,
)
final class TargetRecipeConfig {
  const TargetRecipeConfig({required this.target, required this.steps});

  factory TargetRecipeConfig.fromJson(Map<String, dynamic> json) =>
      _$TargetRecipeConfigFromJson(json);

  Map<String, dynamic> toJson() => _$TargetRecipeConfigToJson(this);

  /// The target pattern this recipe handles.
  final TargetPatternConfig target;

  /// Build steps for this recipe.
  final List<BuildStepConfig> steps;
}

OS? _parseOS(String? os) {
  if (os == null) return null;
  return OS.fromString(os);
}

Architecture? _parseArchitecture(String? arch) {
  if (arch == null) return null;
  return Architecture.fromString(arch);
}

IOSSdk? _parseIOSSdk(String? sdk) {
  if (sdk == null) return null;
  return switch (sdk) {
    'iphoneos' => IOSSdk.iPhoneOS,
    'iphonesimulator' => IOSSdk.iPhoneSimulator,
    _ => null,
  };
}

@JsonSerializable(
  checked: true,
  disallowUnrecognizedKeys: true,
  fieldRename: FieldRename.snake,
)
final class DependencyConfig {
  DependencyConfig({
    this.version,
    this.url,
    this.sha256,
    this.repository,
    this.revision,
  });

  factory DependencyConfig.fromJson(Map<String, dynamic> json) =>
      _$DependencyConfigFromJson(json);

  Map<String, dynamic> toJson() => _$DependencyConfigToJson(this);

  final String? version;
  final String? url;
  final String? sha256;
  final String? repository;
  final String? revision;
}

@JsonSerializable(
  checked: true,
  disallowUnrecognizedKeys: true,
  fieldRename: FieldRename.snake,
)
final class TargetConfig {
  TargetConfig({
    this.enabled = true,
    this.abi,
    this.api,
    this.sdk,
    this.deploymentTarget,
    this.vcpkgTriplet,
  });

  factory TargetConfig.fromJson(Map<String, dynamic> json) =>
      _$TargetConfigFromJson(json);

  Map<String, dynamic> toJson() => _$TargetConfigToJson(this);

  final bool enabled;
  final String? abi;
  final int? api;
  final String? sdk;
  final String? deploymentTarget;
  final String? vcpkgTriplet;
}

@JsonSerializable(
  checked: true,
  disallowUnrecognizedKeys: true,
  explicitToJson: true,
  fieldRename: FieldRename.snake,
)
final class ArtifactConfig {
  ArtifactConfig({required this.archive, required this.payload});

  factory ArtifactConfig.fromJson(Map<String, dynamic> json) =>
      _$ArtifactConfigFromJson(json);

  Map<String, dynamic> toJson() => _$ArtifactConfigToJson(this);

  final String archive;
  final PayloadConfig payload;
}

@JsonSerializable(
  checked: true,
  disallowUnrecognizedKeys: true,
  fieldRename: FieldRename.snake,
)
final class PayloadConfig {
  PayloadConfig({required this.type});

  factory PayloadConfig.fromJson(Map<String, dynamic> json) =>
      _$PayloadConfigFromJson(json);

  Map<String, dynamic> toJson() => _$PayloadConfigToJson(this);

  final String type;

  ArtifactPayload toArtifactPayload(String libraryStem) {
    return switch (type) {
      'dynamic_library' => DynamicLibraryPayload(libraryStem: libraryStem),
      'static_library' => StaticLibraryPayload(libraryStem: libraryStem),
      _ => throw FormatException('Unsupported payload type "$type"'),
    };
  }
}

// -- YAML loading -----------------------------------------------------------------

/// Loads a `native_prebuilt.yaml` file and returns a typed [NativePrebuiltConfig].
///
/// The YAML is parsed with [loadYaml], normalized to plain Dart types,
/// validated against the JSON schema, and then deserialized using the
/// generated `fromJson` code so that `checked: true` and
/// `disallowUnrecognizedKeys: true` are enforced.
Future<NativePrebuiltConfig> loadNativePrebuiltConfig(File file) async {
  final contents = await file.readAsString();
  Object? yaml;
  try {
    yaml = loadYaml(contents, sourceUrl: file.uri);
  } on YamlException catch (error) {
    throw FormatException('Invalid YAML in ${file.path}: $error');
  }
  final normalized = normalizeYaml(yaml);
  if (normalized case final Map<String, dynamic> map) {
    final canonical = _canonicalizeNativePrebuiltYaml(map);
    // Validate against JSON Schema before deserialization
    final validationErrors = await validateNativePrebuiltSchema(canonical);
    if (validationErrors.isNotEmpty) {
      throw FormatException(
        [
          'Invalid ${file.path}:',
          for (final error in validationErrors) '  - ${error.toErrorString()}',
        ].join('\n'),
      );
    }

    try {
      final config = NativePrebuiltConfig.fromJson(canonical);
      validateNativePrebuiltConfig(config);
      return config;
    } on CheckedFromJsonException catch (error) {
      throw FormatException(
        'Invalid native_prebuilt configuration in '
        '${file.path}: $error',
      );
    }
  }
  throw FormatException('The root of ${file.path} must be a YAML mapping.');
}

/// Recursively converts [YamlMap] and [YamlList] to plain Dart [Map] and [List].
Object? normalizeYaml(Object? value) {
  return switch (value) {
    YamlMap yamlMap => <String, dynamic>{
      for (final entry in yamlMap.entries)
        _requireStringKey(entry.key): normalizeYaml(entry.value),
    },
    Map map => <String, dynamic>{
      for (final entry in map.entries)
        _requireStringKey(entry.key): normalizeYaml(entry.value),
    },
    YamlList yamlList => [for (final item in yamlList) normalizeYaml(item)],
    List list => [for (final item in list) normalizeYaml(item)],
    String() || num() || bool() || null => value,
    _ => throw FormatException('Unsupported YAML value: ${value.runtimeType}'),
  };
}

String _requireStringKey(Object? key) {
  if (key case final String stringKey) {
    return stringKey;
  }
  throw FormatException(
    'YAML mapping keys must be strings; '
    'received ${key.runtimeType}.',
  );
}

Map<String, dynamic> _canonicalizeNativePrebuiltYaml(
  Map<String, dynamic> input,
) {
  final map = Map<String, dynamic>.from(input);

  final release = map['release'];
  if (release is Map<String, dynamic>) {
    final canonicalRelease = Map<String, dynamic>.from(release);
    canonicalRelease.putIfAbsent('provider', () => 'github');

    final owner = canonicalRelease.remove('owner');
    final project = canonicalRelease.remove('project');
    final repository = canonicalRelease['repository'] as String?;
    final provider = (canonicalRelease['provider'] as String?)?.toLowerCase();
    if (provider == 'github') {
      if (owner is String && owner.isNotEmpty) {
        canonicalRelease['repository'] =
            repository == null || repository.isEmpty
            ? owner
            : repository.contains('/')
            ? repository
            : '$owner/$repository';
      }
    } else if (provider == 'gitlab') {
      if (project is String && project.isNotEmpty) {
        canonicalRelease['repository'] =
            repository == null || repository.isEmpty ? project : repository;
      }
    }

    map['release'] = canonicalRelease;
  }

  final artifacts = map['artifacts'];
  if (artifacts is Map<String, dynamic>) {
    map['artifacts'] = <String, dynamic>{
      for (final entry in artifacts.entries)
        entry.key: _canonicalizeArtifactConfig(
          entry.key,
          entry.value,
          map['library_stem'] as String? ?? '',
        ),
    };
  }

  return map;
}

Map<String, dynamic> _canonicalizeArtifactConfig(
  String platform,
  Object? value,
  String libraryStem,
) {
  final fallbackArchive = '$libraryStem-$platform.tar.gz';
  if (value is! Map<String, dynamic>) {
    return {
      'archive': fallbackArchive,
      'payload': {'type': 'dynamic_library'},
    };
  }

  final artifact = Map<String, dynamic>.from(value);
  artifact.putIfAbsent('archive', () => fallbackArchive);

  final payload = artifact['payload'];
  if (payload is! Map<String, dynamic>) {
    artifact['payload'] = {'type': 'dynamic_library'};
  } else {
    final canonicalPayload = Map<String, dynamic>.from(payload);
    canonicalPayload.putIfAbsent('type', () => 'dynamic_library');
    artifact['payload'] = canonicalPayload;
  }

  return artifact;
}
