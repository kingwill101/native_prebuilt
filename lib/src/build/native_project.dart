import 'package:code_assets/code_assets.dart';

import '../manifest/prebuilt_manifest.dart';
import '../platform/native_target.dart';
import '../source/source_specification.dart';
import 'native_build_recipe.dart';

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

  /// The asset name for the generated bindings file.
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
/// The [os] is required; [architecture] and [iOSSdk] are optional matchers.
/// When null, they match any value.
final class NativeTargetPattern {
  const NativeTargetPattern({required this.os, this.architecture, this.iOSSdk});

  /// The target OS (required).
  final OS os;

  /// If non-null, only matches targets with this architecture.
  final Architecture? architecture;

  /// If non-null, only matches targets with this iOS SDK.
  final IOSSdk? iOSSdk;

  /// Whether this pattern matches the given [target].
  bool matches(NativeTarget target) {
    if (target.os != os) return false;
    if (architecture != null && target.architecture != architecture)
      return false;
    if (iOSSdk != null && target.iOSSdk != iOSSdk) return false;
    return true;
  }
}

/// A recipe associated with a target pattern.
final class NativeTargetRecipe {
  const NativeTargetRecipe({required this.pattern, required this.recipe});

  /// The target pattern this recipe handles.
  final NativeTargetPattern pattern;

  /// The build recipe to execute.
  final NativeBuildRecipe recipe;
}

/// Definition of how to build a native project for different platforms.
final class NativeBuildDefinition {
  const NativeBuildDefinition({required this.recipes});

  /// Build recipes with target patterns.
  final List<NativeTargetRecipe> recipes;

  /// Find the first recipe that matches the given [target].
  NativeBuildRecipe? recipeFor(NativeTarget target) {
    for (final entry in recipes) {
      if (entry.pattern.matches(target)) {
        return entry.recipe;
      }
    }
    return null;
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
}
