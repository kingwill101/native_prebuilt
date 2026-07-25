import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../binary/library_name.dart';
import '../manifest/prebuilt_artifact.dart';
import '../manifest/prebuilt_manifest.dart';
import '../manifest/release_source.dart';
import '../platform/target_resolver.dart';
import '../resolution/prebuilt_resolver.dart';
import '../resolution/resolution_result.dart';
import '../source/resolved_source.dart';
import '../source/source_builder.dart';
import '../source/source_fallback.dart';
import '../build/native_build_context.dart';
import '../build/native_project.dart';

/// High-level builder that orchestrates the complete native build pipeline.
///
/// This replaces the fragmented [PrebuiltCodeAssetBuilder] with a unified
/// API that handles both prebuilt resolution and source builds through
/// a single [NativeProject] definition.
///
/// For backward compatibility, this builder can also work with a legacy
/// [SourceFallback] that uses a [SourceBuilder] callback. Use
/// [NativeProjectBuilder.fromLegacy] to create an instance from the old API.
final class NativeProjectBuilder {
  const NativeProjectBuilder({
    required this.project,
    this.sourceFallback,
    this.resolvers,
  });

  /// Creates a [NativeProjectBuilder] from legacy parameters.
  ///
  /// This is used by [PrebuiltCodeAssetBuilder] to delegate to the new
  /// build pipeline while maintaining backward compatibility.
  factory NativeProjectBuilder.fromLegacy({
    required String assetName,
    required String libraryStem,
    required PrebuiltManifest manifest,
    required LinkMode linkMode,
    required SourceFallback? sourceFallback,
    List<PrebuiltResolver>? resolvers,
    String localDirectoryName = '.prebuilt',
  }) {
    // Derive a project name from the release source
    final projectName = switch (manifest.release) {
      GitHubReleaseSource(:final owner, :final repository) =>
        '$owner/$repository',
      GitLabReleaseSource(:final projectPath) => projectPath,
    };

    return NativeProjectBuilder(
      project: NativeProject(
        name: projectName,
        asset: NativeAssetSpec(
          assetName: assetName,
          libraryStem: libraryStem,
          linkMode: linkMode,
        ),
        prebuilts: manifest,
        sources: sourceFallback?.sources ?? [],
        build: const NativeBuildDefinition(recipes: {}),
      ),
      sourceFallback: sourceFallback,
      resolvers: resolvers,
    );
  }

  /// The native project definition.
  final NativeProject project;

  /// Optional legacy source fallback with a [SourceBuilder] callback.
  ///
  /// When provided and no recipe exists for the target, this is used instead.
  final SourceFallback? sourceFallback;

  /// Custom resolver chain override.
  final List<PrebuiltResolver>? resolvers;

  /// Run the native build pipeline.
  ///
  /// This is the main entry point that replaces [PrebuiltCodeAssetBuilder.run].
  Future<void> run({
    required BuildInput input,
    required BuildOutputBuilder output,
    required Logger? logger,
  }) async {
    final code = input.config.code;
    if (!input.config.buildCodeAssets) {
      _logInfo(
        logger,
        'Skipping native_prebuilt: buildCodeAssets is disabled.',
      );
      return;
    }

    final target = targetFromCodeConfig(code);
    final linkMode = project.asset.linkMode;
    final payload = _payloadForLinkMode(linkMode);

    _logInfo(
      logger,
      'Resolving ${project.asset.libraryStem} for ${target.label} '
      '(${payload is DynamicLibraryPayload ? 'dynamic' : 'static'}).',
    );

    // Try prebuilt resolution first
    if (project.prebuiltPolicy == PrebuiltPolicy.preferPrebuilt) {
      final context = PrebuiltResolutionContext(
        input: input,
        manifest: project.prebuilts,
        target: target,
        libraryStem: project.asset.libraryStem,
        payload: payload,
        localSearchRoot: Directory.fromUri(input.outputDirectory),
        logger: logger,
      );

      final chain =
          resolvers ??
          [
            UserDefinePrebuiltResolver(),
            LocalPrebuiltResolver(directoryName: '.prebuilt'),
            SharedCacheResolver(),
          ];

      ResolvedPrebuilt? result;
      for (final resolver in chain) {
        _logInfo(logger, 'Trying ${resolver.runtimeType}...');
        result = await resolver.resolve(context);
        if (result != null) break;
      }

      if (result is ResolvedPrebuiltFound) {
        final libraryName = canonicalLibraryName(
          target: target,
          libraryStem: project.asset.libraryStem,
          payload: payload,
        );
        final bundledLibUri = input.outputDirectory.resolve(libraryName);

        await File(result.file.path).copy(File.fromUri(bundledLibUri).path);

        output.assets.code.add(
          CodeAsset(
            package: input.packageName,
            name: project.asset.assetName,
            linkMode: linkMode,
            file: bundledLibUri,
          ),
        );

        _logInfo(
          logger,
          'Using prebuilt ${project.asset.libraryStem} for ${target.label} '
          '(from ${result.source.label})',
        );
        return;
      }
    }

    // Fall back to source build
    _logInfo(
      logger,
      'No prebuilt available for ${target.label}; attempting source build.',
    );

    // Check if we have a recipe for this target
    final recipe = project.build.recipes[target.os];

    if (recipe != null) {
      // Use the new recipe-based build system
      await _buildWithRecipe(
        recipe: recipe,
        target: target,
        linkMode: linkMode,
        payload: payload,
        input: input,
        output: output,
        logger: logger,
      );
      return;
    }

    // Fall back to legacy SourceBuilder if available
    if (sourceFallback != null) {
      await _buildWithLegacySourceBuilder(
        target: target,
        linkMode: linkMode,
        payload: payload,
        input: input,
        output: output,
        logger: logger,
      );
      return;
    }

    final message =
        'No build recipe or source fallback for ${project.asset.libraryStem} '
        'on ${target.label}.';
    _logWarning(logger, message);
    throw StateError(message);
  }

  /// Build using the new recipe-based system.
  Future<void> _buildWithRecipe({
    required dynamic recipe,
    required NativeTarget target,
    required LinkMode linkMode,
    required ArtifactPayload payload,
    required BuildInput input,
    required BuildOutputBuilder output,
    required Logger? logger,
  }) async {
    // Resolve source
    final sourceResult = await SourceFallbackResolver().resolve(
      fallback: SourceFallback(
        sources: project.sources,
        builder: const _NoOpSourceBuilder(),
        preparation: [],
      ),
      packageRoot: Directory.fromUri(input.packageRoot),
      sourceCacheRoot: Directory(
        p.join(
          input.outputDirectoryShared.toFilePath(),
          'native_prebuilt',
          'sources',
        ),
      ),
      input: input,
      output: output,
      logger: logger,
    );

    if (sourceResult == null) {
      final message =
          'No source resolved for ${project.asset.libraryStem} on ${target.label}.';
      _logWarning(logger, message);
      throw StateError(message);
    }

    // Build using the recipe
    final buildContext = NativeBuildContext(
      target: NativeTarget(
        os: target.os,
        architecture: target.architecture,
        iOSSdk: target.iOSSdk,
      ),
      hook: NativeHookConfiguration(
        packageName: input.packageName,
        assetName: project.asset.assetName,
        libraryStem: project.asset.libraryStem,
        linkMode: linkMode,
      ),
      directories: NativeBuildDirectories(
        source: sourceResult.workDirectory,
        output: Directory.fromUri(input.outputDirectory),
        cache: Directory(
          p.join(
            input.outputDirectoryShared.toFilePath(),
            'native_prebuilt',
            'build-cache',
          ),
        ),
        work: sourceResult.workDirectory,
      ),
      toolchains: const ToolchainRegistry(),
      environment: {},
      logger: logger,
    );

    final buildResult = await recipe.execute(buildContext, sourceResult.source);

    // Register the built artifacts
    for (final artifact in buildResult.artifacts) {
      final libraryName = canonicalLibraryName(
        target: artifact.target,
        libraryStem: project.asset.libraryStem,
        payload: payload,
      );
      final bundledLibUri = input.outputDirectory.resolve(libraryName);

      await File(artifact.file.path).copy(File.fromUri(bundledLibUri).path);

      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: project.asset.assetName,
          linkMode: linkMode,
          file: bundledLibUri,
        ),
      );
    }

    _logInfo(logger, 'Source build completed for ${target.label}.');
  }

  /// Build using a legacy [SourceBuilder] callback.
  Future<void> _buildWithLegacySourceBuilder({
    required NativeTarget target,
    required LinkMode linkMode,
    required ArtifactPayload payload,
    required BuildInput input,
    required BuildOutputBuilder output,
    required Logger? logger,
  }) async {
    _logInfo(logger, 'Using legacy source builder.');

    try {
      final sourceResult = await SourceFallbackResolver().resolve(
        fallback: sourceFallback!,
        packageRoot: Directory.fromUri(input.packageRoot),
        sourceCacheRoot: Directory(
          p.join(
            input.outputDirectoryShared.toFilePath(),
            'native_prebuilt',
            'sources',
          ),
        ),
        input: input,
        output: output,
        logger: logger,
      );

      if (sourceResult != null) {
        _logInfo(
          logger,
          'Source build completed for ${target.label} '
          '(from ${sourceResult.source.origin.label}).',
        );
        return;
      }
    } catch (e) {
      _logWarning(logger, 'Source fallback failed: $e');
      rethrow;
    }

    final message =
        'No source fallback configured for ${project.asset.libraryStem} '
        'on ${target.label}.';
    _logWarning(logger, message);
    throw StateError(message);
  }

  ArtifactPayload _payloadForLinkMode(LinkMode linkMode) {
    if (linkMode is StaticLinking) {
      return StaticLibraryPayload(libraryStem: project.asset.libraryStem);
    }
    return DynamicLibraryPayload(libraryStem: project.asset.libraryStem);
  }

  void _logInfo(Logger? logger, String message) {
    if (logger != null) {
      logger.info(message);
    } else {
      stdout.writeln(message);
    }
  }

  void _logWarning(Logger? logger, String message) {
    if (logger != null) {
      logger.warning(message);
    } else {
      stdout.writeln('Warning: $message');
    }
  }
}

/// No-op source builder used as placeholder in legacy adapter.
final class _NoOpSourceBuilder implements SourceBuilder {
  const _NoOpSourceBuilder();

  @override
  Future<void> build({
    required ResolvedSource source,
    required BuildInput input,
    required BuildOutputBuilder output,
    required Logger? logger,
  }) async {
    // No-op: actual source builds are handled by NativeBuildRecipe.
  }
}
