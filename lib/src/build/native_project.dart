import 'package:code_assets/code_assets.dart';

import '../manifest/prebuilt_manifest.dart';
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

/// Definition of how to build a native project for different platforms.
final class NativeBuildDefinition {
  const NativeBuildDefinition({required this.recipes});

  /// Build recipes keyed by target OS.
  final Map<OS, NativeBuildRecipe> recipes;
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

  /// Creates a NativeProject from legacy parameters for backward compatibility.
  factory NativeProject.fromLegacy({
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
      build: const NativeBuildDefinition(recipes: {}),
    );
  }
}
