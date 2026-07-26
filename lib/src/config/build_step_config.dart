import 'package:json_annotation/json_annotation.dart';

import '../build/native_build_recipe.dart';
import '../build/native_artifact_model.dart';
import '../build/steps/steps.dart';

part 'build_step_config.g.dart';

/// Base type for all build step configurations.
///
/// Subclasses are dispatched by the [type] field using
/// [BuildStepConfig.fromJson].
sealed class BuildStepConfig {
  const BuildStepConfig({required this.id, this.needs = const []});

  /// Unique identifier for this step within the recipe.
  final String id;

  /// Step IDs that must complete before this step runs.
  final List<String> needs;

  /// The step type string used for registry dispatch.
  String get type;

  /// Creates the right [BuildStepConfig] subclass from [json].
  factory BuildStepConfig.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    // Strip the 'type' key before passing to the concrete class fromJson
    // since the concrete classes don't have a 'type' field.
    final stepJson = Map<String, dynamic>.from(json)..remove('type');
    return switch (type) {
      'cmake_configure' => CmakeConfigureStepConfig.fromJson(stepJson),
      'cmake_build' => CmakeBuildStepConfig.fromJson(stepJson),
      'export_artifact' => ExportArtifactStepConfig.fromJson(stepJson),
      'command' => CommandStepConfig.fromJson(stepJson),
      'download_archive' => DownloadArchiveStepConfig.fromJson(stepJson),
      'git_checkout' => GitCheckoutStepConfig.fromJson(stepJson),
      'git_apply_patch' => GitApplyPatchStepConfig.fromJson(stepJson),
      'copy' => CopyStepConfig.fromJson(stepJson),
      'strip' => StripStepConfig.fromJson(stepJson),
      _ => throw FormatException('Unknown build step type: $type'),
    };
  }

  /// Converts this config to its runtime [NativeBuildStep] equivalent.
  NativeBuildStep toBuildStep();

  Map<String, dynamic> toJson();
}

@JsonSerializable(
  checked: true,
  disallowUnrecognizedKeys: true,
  fieldRename: FieldRename.snake,
)
final class CmakeConfigureStepConfig extends BuildStepConfig {
  CmakeConfigureStepConfig({
    required super.id,
    required this.sourceDirectory,
    required this.buildDirectory,
    this.generator,
    this.toolchainFile,
    this.definitions = const {},
    super.needs,
  });

  @override
  String get type => 'cmake_configure';

  factory CmakeConfigureStepConfig.fromJson(Map<String, dynamic> json) =>
      _$CmakeConfigureStepConfigFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$CmakeConfigureStepConfigToJson(this);

  @override
  NativeBuildStep toBuildStep() => CmakeConfigureStep(
    id: id,
    sourceDirectory: sourceDirectory,
    buildDirectory: buildDirectory,
    defines: definitions,
    generator: generator,
    toolchainFile: toolchainFile,
  );

  final String sourceDirectory;
  final String buildDirectory;
  final String? generator;
  final String? toolchainFile;
  final Map<String, String> definitions;
}

@JsonSerializable(
  checked: true,
  disallowUnrecognizedKeys: true,
  fieldRename: FieldRename.snake,
)
final class CmakeBuildStepConfig extends BuildStepConfig {
  CmakeBuildStepConfig({
    required super.id,
    required this.buildDirectory,
    this.targets = const [],
    this.parallel = true,
    this.environment,
    super.needs,
  });

  @override
  String get type => 'cmake_build';

  factory CmakeBuildStepConfig.fromJson(Map<String, dynamic> json) =>
      _$CmakeBuildStepConfigFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$CmakeBuildStepConfigToJson(this);

  @override
  NativeBuildStep toBuildStep() => CmakeBuildStep(
    id: id,
    buildDirectory: buildDirectory,
    targets: targets,
    parallel: parallel,
    environment: environment,
  );

  final String buildDirectory;
  final List<String> targets;
  final bool parallel;
  final Map<String, String>? environment;
}

@JsonSerializable(
  checked: true,
  disallowUnrecognizedKeys: true,
  fieldRename: FieldRename.snake,
)
final class ExportArtifactStepConfig extends BuildStepConfig {
  ExportArtifactStepConfig({
    required super.id,
    required this.artifact,
    this.kind = 'dynamic_library',
    this.primary,
    super.needs,
  });

  @override
  String get type => 'export_artifact';

  factory ExportArtifactStepConfig.fromJson(Map<String, dynamic> json) =>
      _$ExportArtifactStepConfigFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$ExportArtifactStepConfigToJson(this);

  @override
  NativeBuildStep toBuildStep() => ExportArtifactStep(
    id: id,
    declaration: NativeArtifactDeclaration(
      id: artifact,
      kind: kind == 'static_library'
          ? NativeArtifactKind.staticLibrary
          : NativeArtifactKind.dynamicLibrary,
      primaryPath: primary ?? '',
    ),
  );

  final String artifact;
  final String kind;
  final String? primary;
}

@JsonSerializable(
  checked: true,
  disallowUnrecognizedKeys: true,
  fieldRename: FieldRename.snake,
)
final class CommandStepConfig extends BuildStepConfig {
  CommandStepConfig({
    required super.id,
    required this.commands,
    this.workingDirectory,
    this.environment,
    super.needs,
  });

  @override
  String get type => 'command';

  factory CommandStepConfig.fromJson(Map<String, dynamic> json) =>
      _$CommandStepConfigFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$CommandStepConfigToJson(this);

  @override
  NativeBuildStep toBuildStep() => CommandStep(
    id: id,
    commands: commands,
    workingDirectory: workingDirectory,
    environment: environment,
  );

  final List<List<String>> commands;
  final String? workingDirectory;
  final Map<String, String>? environment;
}

@JsonSerializable(
  checked: true,
  disallowUnrecognizedKeys: true,
  fieldRename: FieldRename.snake,
)
final class DownloadArchiveStepConfig extends BuildStepConfig {
  DownloadArchiveStepConfig({
    required super.id,
    required this.url,
    this.sha256,
    this.outputDirectory,
    super.needs,
  });

  @override
  String get type => 'download_archive';

  factory DownloadArchiveStepConfig.fromJson(Map<String, dynamic> json) =>
      _$DownloadArchiveStepConfigFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$DownloadArchiveStepConfigToJson(this);

  @override
  NativeBuildStep toBuildStep() => DownloadArchiveStep(
    id: id,
    url: url,
    sha256: sha256,
    outputDirectory: outputDirectory,
  );

  final String url;
  final String? sha256;
  final String? outputDirectory;
}

@JsonSerializable(
  checked: true,
  disallowUnrecognizedKeys: true,
  fieldRename: FieldRename.snake,
)
final class GitCheckoutStepConfig extends BuildStepConfig {
  GitCheckoutStepConfig({
    required super.id,
    required this.repository,
    required this.revision,
    this.targetDirectory,
    this.submodules = false,
    super.needs,
  });

  @override
  String get type => 'git_checkout';

  factory GitCheckoutStepConfig.fromJson(Map<String, dynamic> json) =>
      _$GitCheckoutStepConfigFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$GitCheckoutStepConfigToJson(this);

  @override
  NativeBuildStep toBuildStep() => GitCheckoutStep(
    id: id,
    repository: repository,
    revision: revision,
    targetDirectory: targetDirectory,
    submodules: submodules,
  );

  final String repository;
  final String revision;
  final String? targetDirectory;
  final bool submodules;
}

@JsonSerializable(
  checked: true,
  disallowUnrecognizedKeys: true,
  fieldRename: FieldRename.snake,
)
final class GitApplyPatchStepConfig extends BuildStepConfig {
  GitApplyPatchStepConfig({
    required super.id,
    required this.patchPath,
    this.targetDirectory,
    super.needs,
  });

  @override
  String get type => 'git_apply_patch';

  factory GitApplyPatchStepConfig.fromJson(Map<String, dynamic> json) =>
      _$GitApplyPatchStepConfigFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$GitApplyPatchStepConfigToJson(this);

  @override
  NativeBuildStep toBuildStep() => GitApplyPatchStep(
    id: id,
    patchPath: patchPath,
    targetDirectory: targetDirectory,
  );

  final String patchPath;
  final String? targetDirectory;
}

@JsonSerializable(
  checked: true,
  disallowUnrecognizedKeys: true,
  fieldRename: FieldRename.snake,
)
final class CopyStepConfig extends BuildStepConfig {
  CopyStepConfig({
    required super.id,
    required this.sourcePath,
    required this.destinationPath,
    this.recursive = true,
    super.needs,
  });

  @override
  String get type => 'copy';

  factory CopyStepConfig.fromJson(Map<String, dynamic> json) =>
      _$CopyStepConfigFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$CopyStepConfigToJson(this);

  @override
  NativeBuildStep toBuildStep() => CopyStep(
    id: id,
    sourcePath: sourcePath,
    destinationPath: destinationPath,
    recursive: recursive,
  );

  final String sourcePath;
  final String destinationPath;
  final bool recursive;
}

@JsonSerializable(
  checked: true,
  disallowUnrecognizedKeys: true,
  fieldRename: FieldRename.snake,
)
final class StripStepConfig extends BuildStepConfig {
  StripStepConfig({
    required super.id,
    required this.inputPath,
    required this.outputPath,
    this.stripAll = false,
    super.needs,
  });

  @override
  String get type => 'strip';

  factory StripStepConfig.fromJson(Map<String, dynamic> json) =>
      _$StripStepConfigFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$StripStepConfigToJson(this);

  @override
  NativeBuildStep toBuildStep() => StripStep(
    id: id,
    inputPath: inputPath,
    outputPath: outputPath,
    stripAll: stripAll,
  );

  final String inputPath;
  final String outputPath;
  final bool stripAll;
}
