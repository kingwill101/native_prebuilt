// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'build_step_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CmakeConfigureStepConfig _$CmakeConfigureStepConfigFromJson(
  Map<String, dynamic> json,
) => $checkedCreate(
  'CmakeConfigureStepConfig',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      allowedKeys: const [
        'id',
        'needs',
        'execution',
        'source_directory',
        'build_directory',
        'generator',
        'toolchain_file',
        'definitions',
        'expect_targets',
      ],
    );
    final val = CmakeConfigureStepConfig(
      id: $checkedConvert('id', (v) => v as String),
      sourceDirectory: $checkedConvert('source_directory', (v) => v as String),
      buildDirectory: $checkedConvert('build_directory', (v) => v as String),
      generator: $checkedConvert('generator', (v) => v as String?),
      toolchainFile: $checkedConvert('toolchain_file', (v) => v as String?),
      definitions: $checkedConvert(
        'definitions',
        (v) =>
            (v as Map<String, dynamic>?)?.map(
              (k, e) => MapEntry(k, e as String),
            ) ??
            const {},
      ),
      expectTargets: $checkedConvert(
        'expect_targets',
        (v) =>
            (v as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      ),
      needs: $checkedConvert(
        'needs',
        (v) =>
            (v as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      ),
      execution: $checkedConvert('execution', (v) => v as String? ?? 'target'),
    );
    return val;
  },
  fieldKeyMap: const {
    'sourceDirectory': 'source_directory',
    'buildDirectory': 'build_directory',
    'toolchainFile': 'toolchain_file',
    'expectTargets': 'expect_targets',
  },
);

Map<String, dynamic> _$CmakeConfigureStepConfigToJson(
  CmakeConfigureStepConfig instance,
) => <String, dynamic>{
  'id': instance.id,
  'needs': instance.needs,
  'execution': instance.execution,
  'source_directory': instance.sourceDirectory,
  'build_directory': instance.buildDirectory,
  'generator': instance.generator,
  'toolchain_file': instance.toolchainFile,
  'definitions': instance.definitions,
  'expect_targets': instance.expectTargets,
};

CmakeBuildStepConfig _$CmakeBuildStepConfigFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('CmakeBuildStepConfig', json, ($checkedConvert) {
  $checkKeys(
    json,
    allowedKeys: const [
      'id',
      'needs',
      'execution',
      'build_directory',
      'targets',
      'parallel',
      'environment',
    ],
  );
  final val = CmakeBuildStepConfig(
    id: $checkedConvert('id', (v) => v as String),
    buildDirectory: $checkedConvert('build_directory', (v) => v as String),
    targets: $checkedConvert(
      'targets',
      (v) =>
          (v as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
    ),
    parallel: $checkedConvert('parallel', (v) => v as bool? ?? true),
    environment: $checkedConvert(
      'environment',
      (v) =>
          (v as Map<String, dynamic>?)?.map((k, e) => MapEntry(k, e as String)),
    ),
    needs: $checkedConvert(
      'needs',
      (v) =>
          (v as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
    ),
    execution: $checkedConvert('execution', (v) => v as String? ?? 'target'),
  );
  return val;
}, fieldKeyMap: const {'buildDirectory': 'build_directory'});

Map<String, dynamic> _$CmakeBuildStepConfigToJson(
  CmakeBuildStepConfig instance,
) => <String, dynamic>{
  'id': instance.id,
  'needs': instance.needs,
  'execution': instance.execution,
  'build_directory': instance.buildDirectory,
  'targets': instance.targets,
  'parallel': instance.parallel,
  'environment': instance.environment,
};

ExportArtifactStepConfig _$ExportArtifactStepConfigFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('ExportArtifactStepConfig', json, ($checkedConvert) {
  $checkKeys(
    json,
    allowedKeys: const [
      'id',
      'needs',
      'execution',
      'artifact',
      'kind',
      'primary',
    ],
  );
  final val = ExportArtifactStepConfig(
    id: $checkedConvert('id', (v) => v as String),
    artifact: $checkedConvert('artifact', (v) => v as String),
    kind: $checkedConvert('kind', (v) => v as String? ?? 'dynamic_library'),
    primary: $checkedConvert('primary', (v) => v as String?),
    needs: $checkedConvert(
      'needs',
      (v) =>
          (v as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
    ),
    execution: $checkedConvert('execution', (v) => v as String? ?? 'target'),
  );
  return val;
});

Map<String, dynamic> _$ExportArtifactStepConfigToJson(
  ExportArtifactStepConfig instance,
) => <String, dynamic>{
  'id': instance.id,
  'needs': instance.needs,
  'execution': instance.execution,
  'artifact': instance.artifact,
  'kind': instance.kind,
  'primary': instance.primary,
};

CommandStepConfig _$CommandStepConfigFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('CommandStepConfig', json, ($checkedConvert) {
  $checkKeys(
    json,
    allowedKeys: const [
      'id',
      'needs',
      'execution',
      'commands',
      'working_directory',
      'environment',
    ],
  );
  final val = CommandStepConfig(
    id: $checkedConvert('id', (v) => v as String),
    commands: $checkedConvert(
      'commands',
      (v) => (v as List<dynamic>)
          .map((e) => (e as List<dynamic>).map((e) => e as String).toList())
          .toList(),
    ),
    workingDirectory: $checkedConvert('working_directory', (v) => v as String?),
    environment: $checkedConvert(
      'environment',
      (v) =>
          (v as Map<String, dynamic>?)?.map((k, e) => MapEntry(k, e as String)),
    ),
    needs: $checkedConvert(
      'needs',
      (v) =>
          (v as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
    ),
    execution: $checkedConvert('execution', (v) => v as String? ?? 'target'),
  );
  return val;
}, fieldKeyMap: const {'workingDirectory': 'working_directory'});

Map<String, dynamic> _$CommandStepConfigToJson(CommandStepConfig instance) =>
    <String, dynamic>{
      'id': instance.id,
      'needs': instance.needs,
      'execution': instance.execution,
      'commands': instance.commands,
      'working_directory': instance.workingDirectory,
      'environment': instance.environment,
    };

DownloadArchiveStepConfig _$DownloadArchiveStepConfigFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('DownloadArchiveStepConfig', json, ($checkedConvert) {
  $checkKeys(
    json,
    allowedKeys: const [
      'id',
      'needs',
      'execution',
      'url',
      'sha256',
      'output_directory',
    ],
  );
  final val = DownloadArchiveStepConfig(
    id: $checkedConvert('id', (v) => v as String),
    url: $checkedConvert('url', (v) => v as String),
    sha256: $checkedConvert('sha256', (v) => v as String?),
    outputDirectory: $checkedConvert('output_directory', (v) => v as String?),
    needs: $checkedConvert(
      'needs',
      (v) =>
          (v as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
    ),
    execution: $checkedConvert('execution', (v) => v as String? ?? 'target'),
  );
  return val;
}, fieldKeyMap: const {'outputDirectory': 'output_directory'});

Map<String, dynamic> _$DownloadArchiveStepConfigToJson(
  DownloadArchiveStepConfig instance,
) => <String, dynamic>{
  'id': instance.id,
  'needs': instance.needs,
  'execution': instance.execution,
  'url': instance.url,
  'sha256': instance.sha256,
  'output_directory': instance.outputDirectory,
};

GitCheckoutStepConfig _$GitCheckoutStepConfigFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('GitCheckoutStepConfig', json, ($checkedConvert) {
  $checkKeys(
    json,
    allowedKeys: const [
      'id',
      'needs',
      'execution',
      'repository',
      'revision',
      'target_directory',
      'submodules',
    ],
  );
  final val = GitCheckoutStepConfig(
    id: $checkedConvert('id', (v) => v as String),
    repository: $checkedConvert('repository', (v) => v as String),
    revision: $checkedConvert('revision', (v) => v as String),
    targetDirectory: $checkedConvert('target_directory', (v) => v as String?),
    submodules: $checkedConvert('submodules', (v) => v as bool? ?? false),
    needs: $checkedConvert(
      'needs',
      (v) =>
          (v as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
    ),
    execution: $checkedConvert('execution', (v) => v as String? ?? 'target'),
  );
  return val;
}, fieldKeyMap: const {'targetDirectory': 'target_directory'});

Map<String, dynamic> _$GitCheckoutStepConfigToJson(
  GitCheckoutStepConfig instance,
) => <String, dynamic>{
  'id': instance.id,
  'needs': instance.needs,
  'execution': instance.execution,
  'repository': instance.repository,
  'revision': instance.revision,
  'target_directory': instance.targetDirectory,
  'submodules': instance.submodules,
};

GitApplyPatchStepConfig _$GitApplyPatchStepConfigFromJson(
  Map<String, dynamic> json,
) => $checkedCreate(
  'GitApplyPatchStepConfig',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      allowedKeys: const [
        'id',
        'needs',
        'execution',
        'patch_path',
        'target_directory',
      ],
    );
    final val = GitApplyPatchStepConfig(
      id: $checkedConvert('id', (v) => v as String),
      patchPath: $checkedConvert('patch_path', (v) => v as String),
      targetDirectory: $checkedConvert('target_directory', (v) => v as String?),
      needs: $checkedConvert(
        'needs',
        (v) =>
            (v as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      ),
      execution: $checkedConvert('execution', (v) => v as String? ?? 'target'),
    );
    return val;
  },
  fieldKeyMap: const {
    'patchPath': 'patch_path',
    'targetDirectory': 'target_directory',
  },
);

Map<String, dynamic> _$GitApplyPatchStepConfigToJson(
  GitApplyPatchStepConfig instance,
) => <String, dynamic>{
  'id': instance.id,
  'needs': instance.needs,
  'execution': instance.execution,
  'patch_path': instance.patchPath,
  'target_directory': instance.targetDirectory,
};

CopyStepConfig _$CopyStepConfigFromJson(
  Map<String, dynamic> json,
) => $checkedCreate(
  'CopyStepConfig',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      allowedKeys: const [
        'id',
        'needs',
        'execution',
        'source_path',
        'destination_path',
        'recursive',
      ],
    );
    final val = CopyStepConfig(
      id: $checkedConvert('id', (v) => v as String),
      sourcePath: $checkedConvert('source_path', (v) => v as String),
      destinationPath: $checkedConvert('destination_path', (v) => v as String),
      recursive: $checkedConvert('recursive', (v) => v as bool? ?? true),
      needs: $checkedConvert(
        'needs',
        (v) =>
            (v as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      ),
      execution: $checkedConvert('execution', (v) => v as String? ?? 'target'),
    );
    return val;
  },
  fieldKeyMap: const {
    'sourcePath': 'source_path',
    'destinationPath': 'destination_path',
  },
);

Map<String, dynamic> _$CopyStepConfigToJson(CopyStepConfig instance) =>
    <String, dynamic>{
      'id': instance.id,
      'needs': instance.needs,
      'execution': instance.execution,
      'source_path': instance.sourcePath,
      'destination_path': instance.destinationPath,
      'recursive': instance.recursive,
    };

StripStepConfig _$StripStepConfigFromJson(
  Map<String, dynamic> json,
) => $checkedCreate(
  'StripStepConfig',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      allowedKeys: const [
        'id',
        'needs',
        'execution',
        'input_path',
        'output_path',
        'strip_all',
      ],
    );
    final val = StripStepConfig(
      id: $checkedConvert('id', (v) => v as String),
      inputPath: $checkedConvert('input_path', (v) => v as String),
      outputPath: $checkedConvert('output_path', (v) => v as String),
      stripAll: $checkedConvert('strip_all', (v) => v as bool? ?? false),
      needs: $checkedConvert(
        'needs',
        (v) =>
            (v as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      ),
      execution: $checkedConvert('execution', (v) => v as String? ?? 'target'),
    );
    return val;
  },
  fieldKeyMap: const {
    'inputPath': 'input_path',
    'outputPath': 'output_path',
    'stripAll': 'strip_all',
  },
);

Map<String, dynamic> _$StripStepConfigToJson(StripStepConfig instance) =>
    <String, dynamic>{
      'id': instance.id,
      'needs': instance.needs,
      'execution': instance.execution,
      'input_path': instance.inputPath,
      'output_path': instance.outputPath,
      'strip_all': instance.stripAll,
    };
