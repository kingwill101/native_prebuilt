import 'package:code_assets/code_assets.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

/// JSON Schema definitions for native_prebuilt build configuration validation.
///
/// These schemas validate the structure of the YAML configuration before
/// deserialization. They ensure that required fields are present, types are
/// correct, and no unrecognized properties are included.
///
/// Semantic validation (e.g., checking that `needs:` references point to
/// existing steps) is handled separately in `validation.dart`.

/// Schema for a CMake configure step.
final cmakeConfigureStepSchema = Schema.object(
  required: ['id', 'type', 'source_directory', 'build_directory'],
  properties: {
    'id': S.string(minLength: 1),
    'type': S.string(enumValues: ['cmake_configure']),
    'source_directory': S.string(minLength: 1),
    'build_directory': S.string(minLength: 1),
    'generator': S.string(),
    'toolchain_file': S.string(),
    'definitions': S.object(additionalProperties: S.string()),
    'needs': S.list(items: S.string(minLength: 1), uniqueItems: true),
  },
  additionalProperties: false,
);

/// Schema for a CMake build step.
final cmakeBuildStepSchema = Schema.object(
  required: ['id', 'type', 'build_directory'],
  properties: {
    'id': S.string(minLength: 1),
    'type': S.string(enumValues: ['cmake_build']),
    'build_directory': S.string(minLength: 1),
    'targets': S.list(items: S.string(minLength: 1), uniqueItems: true),
    'parallel': S.boolean(),
    'environment': S.object(additionalProperties: S.string()),
    'needs': S.list(items: S.string(minLength: 1), uniqueItems: true),
  },
  additionalProperties: false,
);

/// Schema for an export artifact step.
final exportArtifactStepSchema = Schema.object(
  required: ['id', 'type', 'artifact', 'primary'],
  properties: {
    'id': S.string(minLength: 1),
    'type': S.string(enumValues: ['export_artifact']),
    'artifact': S.string(minLength: 1),
    'kind': S.string(enumValues: ['dynamic_library', 'static_library']),
    'primary': S.string(minLength: 1),
    'runtime_dependencies': S.list(items: S.string(minLength: 1)),
    'import_library': S.string(),
    'debug_symbols': S.string(),
    'needs': S.list(items: S.string(minLength: 1), uniqueItems: true),
  },
  additionalProperties: false,
);

/// Schema for a command step.
final commandStepSchema = Schema.object(
  required: ['id', 'type', 'commands'],
  properties: {
    'id': S.string(minLength: 1),
    'type': S.string(enumValues: ['command']),
    'commands': S.list(
      items: S.list(items: S.string(minLength: 1)),
      minItems: 1,
    ),
    'working_directory': S.string(),
    'environment': S.object(additionalProperties: S.string()),
    'needs': S.list(items: S.string(minLength: 1), uniqueItems: true),
  },
  additionalProperties: false,
);

/// Schema for a download archive step.
final downloadArchiveStepSchema = Schema.object(
  required: ['id', 'type', 'url'],
  properties: {
    'id': S.string(minLength: 1),
    'type': S.string(enumValues: ['download_archive']),
    'url': S.string(minLength: 1),
    'sha256': S.string(),
    'output_directory': S.string(),
    'needs': S.list(items: S.string(minLength: 1), uniqueItems: true),
  },
  additionalProperties: false,
);

/// Schema for a git checkout step.
final gitCheckoutStepSchema = Schema.object(
  required: ['id', 'type', 'repository', 'revision'],
  properties: {
    'id': S.string(minLength: 1),
    'type': S.string(enumValues: ['git_checkout']),
    'repository': S.string(minLength: 1),
    'revision': S.string(minLength: 1),
    'target_directory': S.string(),
    'submodules': S.boolean(),
    'needs': S.list(items: S.string(minLength: 1), uniqueItems: true),
  },
  additionalProperties: false,
);

/// Schema for a git apply patch step.
final gitApplyPatchStepSchema = Schema.object(
  required: ['id', 'type', 'patch_path'],
  properties: {
    'id': S.string(minLength: 1),
    'type': S.string(enumValues: ['git_apply_patch']),
    'patch_path': S.string(minLength: 1),
    'target_directory': S.string(),
    'needs': S.list(items: S.string(minLength: 1), uniqueItems: true),
  },
  additionalProperties: false,
);

/// Schema for a copy step.
final copyStepSchema = S.object(
  required: ['id', 'type', 'source_path', 'destination_path'],
  properties: {
    'id': S.string(minLength: 1),
    'type': S.string(enumValues: ['copy']),
    'source_path': S.string(minLength: 1),
    'destination_path': S.string(minLength: 1),
    'recursive': S.boolean(),
    'needs': S.list(items: S.string(minLength: 1), uniqueItems: true),
  },
  additionalProperties: false,
);

/// Schema for a strip step.
final stripStepSchema = S.object(
  required: ['id', 'type', 'input_path', 'output_path'],
  properties: {
    'id': S.string(minLength: 1),
    'type': S.string(enumValues: ['strip']),
    'input_path': S.string(minLength: 1),
    'output_path': S.string(minLength: 1),
    'strip_all': S.boolean(),
    'needs': S.list(items: S.string(minLength: 1), uniqueItems: true),
  },
  additionalProperties: false,
);

/// Combined schema for any build step using `oneOf`.
///
/// The step must match exactly one supported step shape.
final buildStepSchema = S.combined(
  oneOf: [
    cmakeConfigureStepSchema,
    cmakeBuildStepSchema,
    exportArtifactStepSchema,
    commandStepSchema,
    downloadArchiveStepSchema,
    gitCheckoutStepSchema,
    gitApplyPatchStepSchema,
    copyStepSchema,
    stripStepSchema,
  ],
);

/// Schema for a target pattern.
final targetPatternSchema = S.object(
  properties: {
    'os': S.string(enumValues: _osValues()),
    'architecture': S.string(enumValues: _architectureValues()),
    'sdk': S.string(enumValues: _iosSdkValues()),
  },
  additionalProperties: false,
);

/// Schema for a target recipe.
final targetRecipeSchema = S.object(
  required: ['target', 'steps'],
  properties: {
    'target': targetPatternSchema,
    'steps': S.list(items: buildStepSchema, minItems: 1),
  },
  additionalProperties: false,
);

/// Schema for the build section of the configuration.
final buildConfigSchema = S.object(
  properties: {
    'recipes': S.list(items: targetRecipeSchema),
    'dependencies': S.object(
      additionalProperties: S.object(
        properties: {
          'version': S.string(),
          'url': S.string(),
          'sha256': S.string(),
          'repository': S.string(),
          'revision': S.string(),
        },
      ),
    ),
    'options': S.object(additionalProperties: S.any()),
  },
  additionalProperties: false,
);

/// Schema for the source section of the configuration.
final sourceConfigSchema = S.object(
  required: ['type', 'repository'],
  properties: {
    'type': S.string(enumValues: ['git']),
    'repository': S.string(minLength: 1),
    'revision': S.string(),
    'subdirectory': S.string(),
    'submodules': S.boolean(),
  },
  additionalProperties: false,
);

/// Schema for the release section of the configuration.
final releaseConfigSchema = S.object(
  required: ['provider', 'repository', 'tag'],
  properties: {
    'provider': S.string(enumValues: ['github', 'gitlab']),
    'repository': S.string(minLength: 1),
    'tag': S.string(minLength: 1),
  },
  additionalProperties: false,
);

/// Schema for the payload section of an artifact.
final payloadConfigSchema = S.object(
  required: ['type'],
  properties: {
    'type': S.string(enumValues: ['dynamic_library', 'static_library']),
  },
  additionalProperties: false,
);

/// Schema for an artifact entry.
final artifactConfigSchema = S.object(
  required: ['archive', 'payload'],
  properties: {
    'archive': S.string(minLength: 1),
    'payload': payloadConfigSchema,
  },
  additionalProperties: false,
);

/// Schema for a target configuration.
final targetConfigSchema = S.object(
  properties: {
    'enabled': S.boolean(),
    'abi': S.string(),
    'api': S.integer(minimum: 1),
    'sdk': S.string(),
    'deployment_target': S.string(),
    'vcpkg_triplet': S.string(),
  },
  additionalProperties: false,
);

/// Schema for the entire native_prebuilt.yaml configuration.
final nativePrebuiltSchema = S.fromMap({
  r'$schema': 'https://json-schema.org/draft/2020-12/schema',
  ...S
      .object(
        required: [
          'schema',
          'package',
          'asset_name',
          'library_stem',
          'release',
          'artifacts',
        ],
        properties: {
          'schema': S.integer(minimum: 1),
          'package': S.string(minLength: 1),
          'asset_name': S.string(minLength: 1),
          'library_stem': S.string(minLength: 1),
          'link_mode': S.string(
            enumValues: ['dynamic_library', 'static_library'],
          ),
          'source': sourceConfigSchema,
          'build': buildConfigSchema,
          'variables': S.object(additionalProperties: S.any()),
          'release': releaseConfigSchema,
          'artifacts': S.object(additionalProperties: artifactConfigSchema),
          'targets': S.object(additionalProperties: targetConfigSchema),
        },
        additionalProperties: false,
      )
      .value,
});

/// Validates a normalized YAML map against [nativePrebuiltSchema].
Future<List<ValidationError>> validateNativePrebuiltSchema(
  Map<String, dynamic> data,
) {
  return nativePrebuiltSchema.validate(data);
}

List<String> _osValues() => [for (final os in OS.values) os.name];

List<String> _architectureValues() => [
  for (final architecture in Architecture.values) architecture.name,
];

List<String> _iosSdkValues() => [for (final sdk in IOSSdk.values) sdk.type];
