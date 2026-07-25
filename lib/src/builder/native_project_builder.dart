import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../binary/library_name.dart';
import '../build/native_build_context.dart';
import '../build/native_project.dart';
import '../build/native_project_executor.dart';
import '../manifest/prebuilt_artifact.dart';
import '../manifest/prebuilt_manifest.dart';
import '../manifest/release_source.dart';
import '../platform/target_resolver.dart';
import '../resolution/prebuilt_resolver.dart';
import '../resolution/resolution_result.dart';
import '../source/resolved_source.dart';
import '../source/source_builder.dart';
import '../source/source_fallback.dart';

/// High-level builder that orchestrates the complete native build pipeline.
///
/// This handles both prebuilt resolution and source builds through
/// a [NativeProject] definition.
///
/// For packages that use external hook builders (e.g. [CBuilder]),
/// use [NativeProjectBuilder.fromSourceFallback] to create an instance
/// from a [SourceFallback] with a [SourceBuilder] callback.
final class NativeProjectBuilder {
  const NativeProjectBuilder({
    required this.project,
    this.sourceFallback,
    this.resolvers,
    this.localDirectoryName = '.prebuilt',
  });

  /// Creates a [NativeProjectBuilder] from a [SourceFallback] with callback.
  ///
  /// This is used by [PrebuiltCodeAssetBuilder] to bridge the callback-based
  /// API into the unified build pipeline.
  factory NativeProjectBuilder.fromSourceFallback({
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
        build: const NativeBuildDefinition(recipes: []),
      ),
      sourceFallback: sourceFallback,
      resolvers: resolvers,
    );
  }

  /// The native project definition.
  final NativeProject project;

  /// Optional source fallback with a [SourceBuilder] callback.
  ///
  /// When provided and no recipe exists for the target, this is used instead.
  final SourceFallback? sourceFallback;

  /// Custom resolver chain override.
  final List<PrebuiltResolver>? resolvers;

  /// Directory name for local prebuilt overrides.
  final String localDirectoryName;

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
            LocalPrebuiltResolver(directoryName: localDirectoryName),
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
    final recipe = project.build.recipeFor(target);

    if (recipe != null) {
      // Use the new recipe-based build system via executor
      await _buildWithExecutor(
        target: target,
        linkMode: linkMode,
        payload: payload,
        input: input,
        output: output,
        logger: logger,
      );
      return;
    }

    // Fall back to source builder callback if available
    if (sourceFallback != null) {
      await _buildWithSourceFallback(
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

  /// Build using the executor.
  Future<void> _buildWithExecutor({
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
        builder: const NoOpSourceBuilder(),
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

    // Create output directory for this target
    final platformDir = '${target.os.name}-${target.architecture.name}';
    if (target.iOSSdk != null) {
      // e.g., ios-sim-arm64
    }
    final outputDir = Directory(
      p.join(input.outputDirectory.toFilePath(), platformDir),
    );

    // Use the executor
    final executor = NativeProjectExecutor(
      project: project,
      source: sourceResult.source,
      logger: logger,
    );

    final buildResult = await executor.build(
      target: target,
      outputDir: outputDir,
      workDir: sourceResult.workDirectory,
      linkMode: linkMode,
    );

    // Register built artifacts with the hook output
    // Hook only stages primary + runtime deps (not symbols/import libs)
    for (final artifact in buildResult.artifacts) {
      final libraryName = canonicalLibraryName(
        target: artifact.target,
        libraryStem: project.asset.libraryStem,
        payload: payload,
      );
      final bundledLibUri = input.outputDirectory.resolve(
        '$platformDir/$libraryName',
      );

      final srcFile = File.fromUri(artifact.primary.source.uri);
      if (srcFile.existsSync()) {
        await srcFile.copy(File.fromUri(bundledLibUri).path);
      }

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

  /// Build using a [SourceBuilder] callback.
  Future<void> _buildWithSourceFallback({
    required NativeTarget target,
    required LinkMode linkMode,
    required ArtifactPayload payload,
    required BuildInput input,
    required BuildOutputBuilder output,
    required Logger? logger,
  }) async {
    _logInfo(logger, 'Building via source builder callback.');

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


