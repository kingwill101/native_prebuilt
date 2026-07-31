import 'package:code_assets/code_assets.dart';

import '../manifest/prebuilt_manifest.dart';
import '../platform/native_target.dart';
import '../source/source_specification.dart';
import 'native_build_recipe.dart';

export 'native_build_recipe.dart' show NativeBuildRecipe, StepBuildRecipe;
export 'native_build_context.dart'
    show
        NativeBuildContext,
        NativeHookConfiguration,
        NativeBuildDirectories,
        ToolchainRegistry;

/// Specification for a native asset to be built or resolved.
final class NativeAssetSpec {
  const NativeAssetSpec({
    required this.assetName,
    required this.libraryStem,
    required this.linkMode,
  });

  /// The Dart library path that declares the native code asset.
  ///
  /// This becomes the code-asset ID under `package:<name>/`.
  final String assetName;

  /// The library stem (e.g., 'tdjson' for libtdjson.so).
  final String libraryStem;

  /// The link mode to use.
  final LinkMode linkMode;

  /// Creates a dynamic library specification.
  factory NativeAssetSpec.dynamicLibrary({
    required String assetName,
    required String libraryStem,
  }) {
    return NativeAssetSpec(
      assetName: assetName,
      libraryStem: libraryStem,
      linkMode: DynamicLoadingBundled(),
    );
  }

  /// Creates a static library specification.
  factory NativeAssetSpec.staticLibrary({
    required String assetName,
    required String libraryStem,
  }) {
    return NativeAssetSpec(
      assetName: assetName,
      libraryStem: libraryStem,
      linkMode: StaticLinking(),
    );
  }

  Map<String, dynamic> toJson() => {
    'asset_name': assetName,
    'library_stem': libraryStem,
    'link_mode': switch (linkMode) {
      DynamicLoadingBundled() => 'dynamic_library',
      StaticLinking() => 'static_library',
      _ => 'dynamic_library',
    },
  };

  factory NativeAssetSpec.fromJson(Map<String, dynamic> json) {
    return switch (json['link_mode'] as String? ?? 'dynamic_library') {
      'static_library' => NativeAssetSpec.staticLibrary(
        assetName: json['asset_name'] as String,
        libraryStem: json['library_stem'] as String,
      ),
      _ => NativeAssetSpec.dynamicLibrary(
        assetName: json['asset_name'] as String,
        libraryStem: json['library_stem'] as String,
      ),
    };
  }
}

/// Policy for preferring prebuilt artifacts vs building from source.
abstract interface class PrebuiltPolicy {
  const PrebuiltPolicy();

  /// Prefer prebuilt artifacts, fall back to source build.
  static const PrebuiltPolicy preferPrebuilt = _PreferPrebuilt();

  /// Always build from source, ignore prebuilts.
  static const PrebuiltPolicy forceSourceBuild = _ForceSourceBuild();
}

final class _PreferPrebuilt implements PrebuiltPolicy {
  const _PreferPrebuilt();
}

final class _ForceSourceBuild implements PrebuiltPolicy {
  const _ForceSourceBuild();
}

/// A pattern that matches native build targets.
///
/// Used to look up recipes for specific platform/architecture combinations.
/// All fields are optional; when null, they match any value.
final class NativeTargetPattern {
  const NativeTargetPattern({this.os, this.architecture, this.iOSSdk});

  /// The target OS (e.g., linux, android, ios).
  /// When null, matches any OS.
  final OS? os;

  /// If non-null, only matches targets with this architecture.
  final Architecture? architecture;

  /// If non-null, only matches targets with this iOS SDK.
  final IOSSdk? iOSSdk;

  /// Whether this pattern matches the given [target].
  bool matches(NativeTarget target) {
    if (os != null && target.os != os) return false;
    if (architecture != null && target.architecture != architecture)
      return false;
    if (iOSSdk != null && target.iOSSdk != iOSSdk) return false;
    return true;
  }

  Map<String, dynamic> toJson() => {
    if (os != null) 'os': os!.name,
    if (architecture != null) 'architecture': architecture!.name,
    if (iOSSdk != null)
      'sdk': iOSSdk == IOSSdk.iPhoneSimulator ? 'iphonesimulator' : 'iphoneos',
  };

  factory NativeTargetPattern.fromJson(Map<String, dynamic> json) {
    final sdk = switch (json['sdk'] as String?) {
      'iphonesimulator' => IOSSdk.iPhoneSimulator,
      'iphoneos' => IOSSdk.iPhoneOS,
      _ => null,
    };
    return NativeTargetPattern(
      os: json['os'] == null ? null : OS.fromString(json['os'] as String),
      architecture: json['architecture'] == null
          ? null
          : Architecture.fromString(json['architecture'] as String),
      iOSSdk: sdk,
    );
  }
}

/// A recipe associated with a target pattern.
final class NativeTargetRecipe {
  const NativeTargetRecipe({required this.pattern, required this.recipe});

  /// The target pattern this recipe handles.
  final NativeTargetPattern pattern;

  /// The build recipe to execute.
  final NativeBuildRecipe recipe;

  Map<String, dynamic> toJson() => {
    'pattern': pattern.toJson(),
    'recipe': recipe.toJson(),
  };

  factory NativeTargetRecipe.fromJson(Map<String, dynamic> json) {
    return NativeTargetRecipe(
      pattern: NativeTargetPattern.fromJson(
        json['pattern'] as Map<String, dynamic>,
      ),
      recipe: StepBuildRecipe.fromJson(json['recipe'] as Map<String, dynamic>),
    );
  }
}

/// Definition of how to build a native project for different platforms.
final class NativeBuildDefinition {
  const NativeBuildDefinition({
    required this.recipes,
    this.options = const <String, Object?>{},
    this.variables = const <String, Object?>{},
  });

  /// Build recipes with target patterns.
  final List<NativeTargetRecipe> recipes;

  /// User-defined values exposed to Liquid recipes as `options.*`.
  final Map<String, Object?> options;

  /// Shared values exposed to Liquid recipes as `variables.*`.
  final Map<String, Object?> variables;

  /// Find the first recipe that matches the given [target].
  NativeBuildRecipe? recipeFor(NativeTarget target) {
    for (final entry in recipes) {
      if (entry.pattern.matches(target)) {
        return entry.recipe;
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'recipes': recipes.map((recipe) => recipe.toJson()).toList(),
    if (options.isNotEmpty) 'options': options,
    if (variables.isNotEmpty) 'variables': variables,
  };

  factory NativeBuildDefinition.fromJson(Map<String, dynamic> json) {
    return NativeBuildDefinition(
      recipes: (json['recipes'] as List<dynamic>? ?? const [])
          .map(
            (recipe) =>
                NativeTargetRecipe.fromJson(recipe as Map<String, dynamic>),
          )
          .toList(),
      options: Map<String, Object?>.from(
        (json['options'] as Map?)?.cast<String, Object?>() ?? const {},
      ),
      variables: Map<String, Object?>.from(
        (json['variables'] as Map?)?.cast<String, Object?>() ?? const {},
      ),
    );
  }
}

/// A complete native project definition combining prebuilts, sources, and build logic.
///
/// This is the central model that replaces the fragmented configuration
/// currently spread across multiple parameters.
final class NativeProject {
  const NativeProject({
    required this.name,
    required this.asset,
    required this.prebuilts,
    required this.sources,
    required this.build,
    this.prebuiltPolicy = PrebuiltPolicy.preferPrebuilt,
  });

  /// The project name (e.g., 'tdlib').
  final String name;

  /// The native asset specification.
  final NativeAssetSpec asset;

  /// The prebuilt manifest for release artifacts.
  final PrebuiltManifest prebuilts;

  /// Source specifications in priority order.
  final List<SourceSpecification> sources;

  /// Build definitions per platform.
  final NativeBuildDefinition build;

  /// Policy for preferring prebuilts vs source builds.
  final PrebuiltPolicy prebuiltPolicy;

  /// Creates a NativeProject from a [SourceFallback]-based configuration.
  factory NativeProject.fromSourceFallback({
    required String name,
    required String assetName,
    required String libraryStem,
    required PrebuiltManifest manifest,
    required LinkMode linkMode,
    required List<SourceSpecification> sources,
  }) {
    return NativeProject(
      name: name,
      asset: NativeAssetSpec(
        assetName: assetName,
        libraryStem: libraryStem,
        linkMode: linkMode,
      ),
      prebuilts: manifest,
      sources: sources,
      build: const NativeBuildDefinition(recipes: []),
    );
  }

  /// Creates a copy of this project with optional overrides.
  NativeProject copyWith({
    String? name,
    NativeAssetSpec? asset,
    PrebuiltManifest? prebuilts,
    List<SourceSpecification>? sources,
    NativeBuildDefinition? build,
    PrebuiltPolicy? prebuiltPolicy,
  }) {
    return NativeProject(
      name: name ?? this.name,
      asset: asset ?? this.asset,
      prebuilts: prebuilts ?? this.prebuilts,
      sources: sources ?? this.sources,
      build: build ?? this.build,
      prebuiltPolicy: prebuiltPolicy ?? this.prebuiltPolicy,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'asset': asset.toJson(),
    'prebuilts': prebuilts.toJson(),
    'sources': sources.map((source) => source.toJson()).toList(),
    'build': build.toJson(),
    'prebuilt_policy': switch (prebuiltPolicy) {
      _PreferPrebuilt() => 'prefer_prebuilt',
      _ForceSourceBuild() => 'force_source_build',
      _ => 'prefer_prebuilt',
    },
  };

  factory NativeProject.fromJson(Map<String, dynamic> json) {
    return NativeProject(
      name: json['name'] as String,
      asset: NativeAssetSpec.fromJson(json['asset'] as Map<String, dynamic>),
      prebuilts: PrebuiltManifest.fromJson(
        json['prebuilts'] as Map<String, dynamic>,
      ),
      sources: (json['sources'] as List<dynamic>? ?? const [])
          .map(
            (source) =>
                SourceSpecification.fromJson(source as Map<String, dynamic>),
          )
          .toList(),
      build: NativeBuildDefinition.fromJson(
        json['build'] as Map<String, dynamic>,
      ),
      prebuiltPolicy: switch (json['prebuilt_policy'] as String?) {
        'force_source_build' => PrebuiltPolicy.forceSourceBuild,
        _ => PrebuiltPolicy.preferPrebuilt,
      },
    );
  }
}
