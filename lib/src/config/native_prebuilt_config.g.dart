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
  'release': instance.release.toJson(),
  'artifacts': instance.artifacts.map((k, e) => MapEntry(k, e.toJson())),
  'targets': instance.targets?.map((k, e) => MapEntry(k, e.toJson())),
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
