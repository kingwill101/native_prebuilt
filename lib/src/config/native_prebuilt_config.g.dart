// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'native_prebuilt_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

NativePrebuiltConfig _$NativePrebuiltConfigFromJson(
  Map<String, dynamic> json,
) => $checkedCreate(
  'NativePrebuiltConfig',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      allowedKeys: const [
        'schema',
        'package',
        'asset_name',
        'library_stem',
        'link_mode',
        'source',
        'build',
        'variables',
        'release',
        'artifacts',
        'targets',
      ],
    );
    final val = NativePrebuiltConfig(
      schema: $checkedConvert('schema', (v) => (v as num).toInt()),
      package: $checkedConvert('package', (v) => v as String),
      assetName: $checkedConvert('asset_name', (v) => v as String),
      libraryStem: $checkedConvert('library_stem', (v) => v as String),
      linkMode: $checkedConvert('link_mode', (v) => v as String?),
      source: $checkedConvert(
        'source',
        (v) =>
            v == null ? null : SourceConfig.fromJson(v as Map<String, dynamic>),
      ),
      build: $checkedConvert(
        'build',
        (v) =>
            v == null ? null : BuildConfig.fromJson(v as Map<String, dynamic>),
      ),
      variables: $checkedConvert(
        'variables',
        (v) => v as Map<String, dynamic>? ?? const {},
      ),
      release: $checkedConvert(
        'release',
        (v) => ReleaseConfig.fromJson(v as Map<String, dynamic>),
      ),
      artifacts: $checkedConvert(
        'artifacts',
        (v) => (v as Map<String, dynamic>).map(
          (k, e) =>
              MapEntry(k, ArtifactConfig.fromJson(e as Map<String, dynamic>)),
        ),
      ),
      targets: $checkedConvert(
        'targets',
        (v) => (v as Map<String, dynamic>?)?.map(
          (k, e) =>
              MapEntry(k, TargetConfig.fromJson(e as Map<String, dynamic>)),
        ),
      ),
    );
    return val;
  },
  fieldKeyMap: const {
    'assetName': 'asset_name',
    'libraryStem': 'library_stem',
    'linkMode': 'link_mode',
  },
);

Map<String, dynamic> _$NativePrebuiltConfigToJson(
  NativePrebuiltConfig instance,
) => <String, dynamic>{
  'schema': instance.schema,
  'package': instance.package,
  'asset_name': instance.assetName,
  'library_stem': instance.libraryStem,
  'link_mode': instance.linkMode,
  'source': instance.source?.toJson(),
  'build': instance.build?.toJson(),
  'variables': instance.variables,
  'release': instance.release.toJson(),
  'artifacts': instance.artifacts.map((k, e) => MapEntry(k, e.toJson())),
  'targets': instance.targets?.map((k, e) => MapEntry(k, e.toJson())),
};

const _$NativePrebuiltConfigJsonSchema = {
  r'$schema': 'https://json-schema.org/draft/2020-12/schema',
  'type': 'object',
  'properties': {
    'schema': {'type': 'integer'},
    'package': {'type': 'string'},
    'asset_name': {'type': 'string'},
    'library_stem': {'type': 'string'},
    'link_mode': {'type': 'string'},
    'source': {r'$ref': r'#/$defs/SourceConfig'},
    'build': {r'$ref': r'#/$defs/BuildConfig'},
    'variables': {
      'type': 'object',
      'additionalProperties': {'type': 'object'},
      'description':
          'Shared values exposed to Liquid recipes as `variables.*`.',
      'default': {},
    },
    'release': {r'$ref': r'#/$defs/ReleaseConfig'},
    'artifacts': {
      'type': 'object',
      'additionalProperties': {r'$ref': r'#/$defs/ArtifactConfig'},
    },
    'targets': {
      'type': 'object',
      'additionalProperties': {r'$ref': r'#/$defs/TargetConfig'},
    },
  },
  'required': [
    'schema',
    'package',
    'asset_name',
    'library_stem',
    'release',
    'artifacts',
  ],
  r'$defs': {
    'SourceConfig': {
      'type': 'object',
      'properties': {
        'type': {'type': 'string'},
        'repository': {'type': 'string'},
        'revision': {'type': 'string'},
        'subdirectory': {'type': 'string'},
        'submodules': {'type': 'boolean', 'default': false},
      },
      'required': ['type', 'repository'],
    },
    'TargetPatternConfig': {
      'type': 'object',
      'properties': {
        'os': {
          'type': 'string',
          'description':
              'Target OS (e.g., "linux", "android", "ios", "macos", "windows").\nWhen null, matches any OS.',
        },
        'architecture': {
          'type': 'string',
          'description':
              'Target architecture (e.g., "x64", "arm64").\nWhen null, matches any architecture.',
        },
        'sdk': {
          'type': 'string',
          'description':
              'iOS SDK (e.g., "iphoneos", "iphonesimulator").\nWhen null, matches any iOS SDK.',
        },
      },
    },
    'BuildStepConfig': {
      'type': 'object',
      'properties': {
        'id': {
          'type': 'string',
          'description': 'Unique identifier for this step within the recipe.',
        },
        'needs': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'Step IDs that must complete before this step runs.',
          'default': [],
        },
      },
      'required': ['id'],
    },
    'TargetRecipeConfig': {
      'type': 'object',
      'properties': {
        'target': {
          r'$ref': r'#/$defs/TargetPatternConfig',
          'description': 'The target pattern this recipe handles.',
        },
        'steps': {
          'type': 'array',
          'items': {r'$ref': r'#/$defs/BuildStepConfig'},
          'description': 'Build steps for this recipe.',
        },
      },
      'required': ['target', 'steps'],
    },
    'DependencyConfig': {
      'type': 'object',
      'properties': {
        'version': {'type': 'string'},
        'url': {'type': 'string'},
        'sha256': {'type': 'string'},
        'repository': {'type': 'string'},
        'revision': {'type': 'string'},
      },
    },
    'BuildConfig': {
      'type': 'object',
      'properties': {
        'recipes': {
          'type': 'array',
          'items': {r'$ref': r'#/$defs/TargetRecipeConfig'},
          'description': 'Target-specific build recipes.',
          'default': [],
        },
        'dependencies': {
          'type': 'object',
          'additionalProperties': {r'$ref': r'#/$defs/DependencyConfig'},
          'description': 'Optional dependency declarations.',
          'default': {},
        },
        'options': {
          'type': 'object',
          'additionalProperties': {'type': 'object'},
          'description': 'Optional build options.',
          'default': {},
        },
      },
    },
    'ReleaseConfig': {
      'type': 'object',
      'properties': {
        'provider': {'type': 'string'},
        'repository': {'type': 'string'},
        'tag': {'type': 'string'},
      },
      'required': ['provider', 'repository', 'tag'],
    },
    'PayloadConfig': {
      'type': 'object',
      'properties': {
        'type': {'type': 'string'},
      },
      'required': ['type'],
    },
    'ArtifactConfig': {
      'type': 'object',
      'properties': {
        'archive': {'type': 'string'},
        'payload': {r'$ref': r'#/$defs/PayloadConfig'},
      },
      'required': ['archive', 'payload'],
    },
    'TargetConfig': {
      'type': 'object',
      'properties': {
        'enabled': {'type': 'boolean', 'default': true},
        'abi': {'type': 'string'},
        'api': {'type': 'integer'},
        'sdk': {'type': 'string'},
        'deployment_target': {'type': 'string'},
        'vcpkg_triplet': {'type': 'string'},
      },
    },
  },
};

ReleaseConfig _$ReleaseConfigFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ReleaseConfig', json, ($checkedConvert) {
      $checkKeys(json, allowedKeys: const ['provider', 'repository', 'tag']);
      final val = ReleaseConfig(
        provider: $checkedConvert('provider', (v) => v as String),
        repository: $checkedConvert('repository', (v) => v as String),
        tag: $checkedConvert('tag', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$ReleaseConfigToJson(ReleaseConfig instance) =>
    <String, dynamic>{
      'provider': instance.provider,
      'repository': instance.repository,
      'tag': instance.tag,
    };

const _$ReleaseConfigJsonSchema = {
  r'$schema': 'https://json-schema.org/draft/2020-12/schema',
  'type': 'object',
  'properties': {
    'provider': {'type': 'string'},
    'repository': {'type': 'string'},
    'tag': {'type': 'string'},
  },
  'required': ['provider', 'repository', 'tag'],
};

SourceConfig _$SourceConfigFromJson(Map<String, dynamic> json) =>
    $checkedCreate('SourceConfig', json, ($checkedConvert) {
      $checkKeys(
        json,
        allowedKeys: const [
          'type',
          'repository',
          'revision',
          'subdirectory',
          'submodules',
        ],
      );
      final val = SourceConfig(
        type: $checkedConvert('type', (v) => v as String),
        repository: $checkedConvert('repository', (v) => v as String),
        revision: $checkedConvert('revision', (v) => v as String?),
        subdirectory: $checkedConvert('subdirectory', (v) => v as String?),
        submodules: $checkedConvert('submodules', (v) => v as bool? ?? false),
      );
      return val;
    });

Map<String, dynamic> _$SourceConfigToJson(SourceConfig instance) =>
    <String, dynamic>{
      'type': instance.type,
      'repository': instance.repository,
      'revision': instance.revision,
      'subdirectory': instance.subdirectory,
      'submodules': instance.submodules,
    };

const _$SourceConfigJsonSchema = {
  r'$schema': 'https://json-schema.org/draft/2020-12/schema',
  'type': 'object',
  'properties': {
    'type': {'type': 'string'},
    'repository': {'type': 'string'},
    'revision': {'type': 'string'},
    'subdirectory': {'type': 'string'},
    'submodules': {'type': 'boolean', 'default': false},
  },
  'required': ['type', 'repository'],
};

BuildConfig _$BuildConfigFromJson(Map<String, dynamic> json) => $checkedCreate(
  'BuildConfig',
  json,
  ($checkedConvert) {
    $checkKeys(json, allowedKeys: const ['recipes', 'dependencies', 'options']);
    final val = BuildConfig(
      recipes: $checkedConvert(
        'recipes',
        (v) =>
            (v as List<dynamic>?)
                ?.map(
                  (e) => TargetRecipeConfig.fromJson(e as Map<String, dynamic>),
                )
                .toList() ??
            const [],
      ),
      dependencies: $checkedConvert(
        'dependencies',
        (v) =>
            (v as Map<String, dynamic>?)?.map(
              (k, e) => MapEntry(
                k,
                DependencyConfig.fromJson(e as Map<String, dynamic>),
              ),
            ) ??
            const {},
      ),
      options: $checkedConvert(
        'options',
        (v) => v as Map<String, dynamic>? ?? const {},
      ),
    );
    return val;
  },
);

Map<String, dynamic> _$BuildConfigToJson(
  BuildConfig instance,
) => <String, dynamic>{
  'recipes': instance.recipes.map((e) => e.toJson()).toList(),
  'dependencies': instance.dependencies.map((k, e) => MapEntry(k, e.toJson())),
  'options': instance.options,
};

const _$BuildConfigJsonSchema = {
  r'$schema': 'https://json-schema.org/draft/2020-12/schema',
  'type': 'object',
  'properties': {
    'recipes': {
      'type': 'array',
      'items': {r'$ref': r'#/$defs/TargetRecipeConfig'},
      'description': 'Target-specific build recipes.',
      'default': [],
    },
    'dependencies': {
      'type': 'object',
      'additionalProperties': {r'$ref': r'#/$defs/DependencyConfig'},
      'description': 'Optional dependency declarations.',
      'default': {},
    },
    'options': {
      'type': 'object',
      'additionalProperties': {'type': 'object'},
      'description': 'Optional build options.',
      'default': {},
    },
  },
  r'$defs': {
    'TargetPatternConfig': {
      'type': 'object',
      'properties': {
        'os': {
          'type': 'string',
          'description':
              'Target OS (e.g., "linux", "android", "ios", "macos", "windows").\nWhen null, matches any OS.',
        },
        'architecture': {
          'type': 'string',
          'description':
              'Target architecture (e.g., "x64", "arm64").\nWhen null, matches any architecture.',
        },
        'sdk': {
          'type': 'string',
          'description':
              'iOS SDK (e.g., "iphoneos", "iphonesimulator").\nWhen null, matches any iOS SDK.',
        },
      },
    },
    'BuildStepConfig': {
      'type': 'object',
      'properties': {
        'id': {
          'type': 'string',
          'description': 'Unique identifier for this step within the recipe.',
        },
        'needs': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'Step IDs that must complete before this step runs.',
          'default': [],
        },
      },
      'required': ['id'],
    },
    'TargetRecipeConfig': {
      'type': 'object',
      'properties': {
        'target': {
          r'$ref': r'#/$defs/TargetPatternConfig',
          'description': 'The target pattern this recipe handles.',
        },
        'steps': {
          'type': 'array',
          'items': {r'$ref': r'#/$defs/BuildStepConfig'},
          'description': 'Build steps for this recipe.',
        },
      },
      'required': ['target', 'steps'],
    },
    'DependencyConfig': {
      'type': 'object',
      'properties': {
        'version': {'type': 'string'},
        'url': {'type': 'string'},
        'sha256': {'type': 'string'},
        'repository': {'type': 'string'},
        'revision': {'type': 'string'},
      },
    },
  },
};

TargetPatternConfig _$TargetPatternConfigFromJson(Map<String, dynamic> json) =>
    $checkedCreate('TargetPatternConfig', json, ($checkedConvert) {
      $checkKeys(json, allowedKeys: const ['os', 'architecture', 'sdk']);
      final val = TargetPatternConfig(
        os: $checkedConvert('os', (v) => v as String?),
        architecture: $checkedConvert('architecture', (v) => v as String?),
        sdk: $checkedConvert('sdk', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$TargetPatternConfigToJson(
  TargetPatternConfig instance,
) => <String, dynamic>{
  'os': instance.os,
  'architecture': instance.architecture,
  'sdk': instance.sdk,
};

const _$TargetPatternConfigJsonSchema = {
  r'$schema': 'https://json-schema.org/draft/2020-12/schema',
  'type': 'object',
  'properties': {
    'os': {
      'type': 'string',
      'description':
          'Target OS (e.g., "linux", "android", "ios", "macos", "windows").\nWhen null, matches any OS.',
    },
    'architecture': {
      'type': 'string',
      'description':
          'Target architecture (e.g., "x64", "arm64").\nWhen null, matches any architecture.',
    },
    'sdk': {
      'type': 'string',
      'description':
          'iOS SDK (e.g., "iphoneos", "iphonesimulator").\nWhen null, matches any iOS SDK.',
    },
  },
};

TargetRecipeConfig _$TargetRecipeConfigFromJson(Map<String, dynamic> json) =>
    $checkedCreate('TargetRecipeConfig', json, ($checkedConvert) {
      $checkKeys(json, allowedKeys: const ['target', 'steps']);
      final val = TargetRecipeConfig(
        target: $checkedConvert(
          'target',
          (v) => TargetPatternConfig.fromJson(v as Map<String, dynamic>),
        ),
        steps: $checkedConvert(
          'steps',
          (v) => (v as List<dynamic>)
              .map((e) => BuildStepConfig.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      );
      return val;
    });

Map<String, dynamic> _$TargetRecipeConfigToJson(TargetRecipeConfig instance) =>
    <String, dynamic>{
      'target': instance.target.toJson(),
      'steps': instance.steps.map((e) => e.toJson()).toList(),
    };

const _$TargetRecipeConfigJsonSchema = {
  r'$schema': 'https://json-schema.org/draft/2020-12/schema',
  'type': 'object',
  'properties': {
    'target': {
      r'$ref': r'#/$defs/TargetPatternConfig',
      'description': 'The target pattern this recipe handles.',
    },
    'steps': {
      'type': 'array',
      'items': {r'$ref': r'#/$defs/BuildStepConfig'},
      'description': 'Build steps for this recipe.',
    },
  },
  'required': ['target', 'steps'],
  r'$defs': {
    'TargetPatternConfig': {
      'type': 'object',
      'properties': {
        'os': {
          'type': 'string',
          'description':
              'Target OS (e.g., "linux", "android", "ios", "macos", "windows").\nWhen null, matches any OS.',
        },
        'architecture': {
          'type': 'string',
          'description':
              'Target architecture (e.g., "x64", "arm64").\nWhen null, matches any architecture.',
        },
        'sdk': {
          'type': 'string',
          'description':
              'iOS SDK (e.g., "iphoneos", "iphonesimulator").\nWhen null, matches any iOS SDK.',
        },
      },
    },
    'BuildStepConfig': {
      'type': 'object',
      'properties': {
        'id': {
          'type': 'string',
          'description': 'Unique identifier for this step within the recipe.',
        },
        'needs': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'Step IDs that must complete before this step runs.',
          'default': [],
        },
      },
      'required': ['id'],
    },
  },
};

DependencyConfig _$DependencyConfigFromJson(Map<String, dynamic> json) =>
    $checkedCreate('DependencyConfig', json, ($checkedConvert) {
      $checkKeys(
        json,
        allowedKeys: const [
          'version',
          'url',
          'sha256',
          'repository',
          'revision',
        ],
      );
      final val = DependencyConfig(
        version: $checkedConvert('version', (v) => v as String?),
        url: $checkedConvert('url', (v) => v as String?),
        sha256: $checkedConvert('sha256', (v) => v as String?),
        repository: $checkedConvert('repository', (v) => v as String?),
        revision: $checkedConvert('revision', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$DependencyConfigToJson(DependencyConfig instance) =>
    <String, dynamic>{
      'version': instance.version,
      'url': instance.url,
      'sha256': instance.sha256,
      'repository': instance.repository,
      'revision': instance.revision,
    };

const _$DependencyConfigJsonSchema = {
  r'$schema': 'https://json-schema.org/draft/2020-12/schema',
  'type': 'object',
  'properties': {
    'version': {'type': 'string'},
    'url': {'type': 'string'},
    'sha256': {'type': 'string'},
    'repository': {'type': 'string'},
    'revision': {'type': 'string'},
  },
};

TargetConfig _$TargetConfigFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'TargetConfig',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          allowedKeys: const [
            'enabled',
            'abi',
            'api',
            'sdk',
            'deployment_target',
            'vcpkg_triplet',
          ],
        );
        final val = TargetConfig(
          enabled: $checkedConvert('enabled', (v) => v as bool? ?? true),
          abi: $checkedConvert('abi', (v) => v as String?),
          api: $checkedConvert('api', (v) => (v as num?)?.toInt()),
          sdk: $checkedConvert('sdk', (v) => v as String?),
          deploymentTarget: $checkedConvert(
            'deployment_target',
            (v) => v as String?,
          ),
          vcpkgTriplet: $checkedConvert('vcpkg_triplet', (v) => v as String?),
        );
        return val;
      },
      fieldKeyMap: const {
        'deploymentTarget': 'deployment_target',
        'vcpkgTriplet': 'vcpkg_triplet',
      },
    );

Map<String, dynamic> _$TargetConfigToJson(TargetConfig instance) =>
    <String, dynamic>{
      'enabled': instance.enabled,
      'abi': instance.abi,
      'api': instance.api,
      'sdk': instance.sdk,
      'deployment_target': instance.deploymentTarget,
      'vcpkg_triplet': instance.vcpkgTriplet,
    };

const _$TargetConfigJsonSchema = {
  r'$schema': 'https://json-schema.org/draft/2020-12/schema',
  'type': 'object',
  'properties': {
    'enabled': {'type': 'boolean', 'default': true},
    'abi': {'type': 'string'},
    'api': {'type': 'integer'},
    'sdk': {'type': 'string'},
    'deployment_target': {'type': 'string'},
    'vcpkg_triplet': {'type': 'string'},
  },
};

ArtifactConfig _$ArtifactConfigFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ArtifactConfig', json, ($checkedConvert) {
      $checkKeys(json, allowedKeys: const ['archive', 'payload']);
      final val = ArtifactConfig(
        archive: $checkedConvert('archive', (v) => v as String),
        payload: $checkedConvert(
          'payload',
          (v) => PayloadConfig.fromJson(v as Map<String, dynamic>),
        ),
      );
      return val;
    });

Map<String, dynamic> _$ArtifactConfigToJson(ArtifactConfig instance) =>
    <String, dynamic>{
      'archive': instance.archive,
      'payload': instance.payload.toJson(),
    };

const _$ArtifactConfigJsonSchema = {
  r'$schema': 'https://json-schema.org/draft/2020-12/schema',
  'type': 'object',
  'properties': {
    'archive': {'type': 'string'},
    'payload': {r'$ref': r'#/$defs/PayloadConfig'},
  },
  'required': ['archive', 'payload'],
  r'$defs': {
    'PayloadConfig': {
      'type': 'object',
      'properties': {
        'type': {'type': 'string'},
      },
      'required': ['type'],
    },
  },
};

PayloadConfig _$PayloadConfigFromJson(Map<String, dynamic> json) =>
    $checkedCreate('PayloadConfig', json, ($checkedConvert) {
      $checkKeys(json, allowedKeys: const ['type']);
      final val = PayloadConfig(
        type: $checkedConvert('type', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$PayloadConfigToJson(PayloadConfig instance) =>
    <String, dynamic>{'type': instance.type};

const _$PayloadConfigJsonSchema = {
  r'$schema': 'https://json-schema.org/draft/2020-12/schema',
  'type': 'object',
  'properties': {
    'type': {'type': 'string'},
  },
  'required': ['type'],
};
