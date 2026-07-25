import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'native_build_context.dart';
import 'native_build_result.dart';
import 'native_build_recipe.dart';
import 'native_project.dart';
import '../cache/build_cache.dart';
import '../source/resolved_source.dart';
import '../source/source_builder.dart';
import '../source/source_fallback.dart';

/// Shared build entry point for CLI, hooks, CI, and tests.
///
/// Orchestrates the complete native build pipeline:
/// 1. Resolves source if not provided
/// 2. Resolves the recipe via [NativeBuildDefinition.recipeFor]
/// 3. Executes the recipe
/// 4. Stages the artifact bundle with role-based subdirectories
/// 5. Writes `native_prebuilt.json` metadata
/// 6. Returns [NativeBuildResult]
final class NativeProjectExecutor {
  const NativeProjectExecutor({
    required this.project,
    this.source,
    this.sourceFallback,
    this.cache,
    this.logger,
  });

  /// The native project definition.
  final NativeProject project;

  /// The resolved source to build from.
  ///
  /// When provided, skips source resolution. When null, [sourceFallback]
  /// is used to resolve the source from the project's source specifications.
  final ResolvedSource? source;

  /// Source fallback configuration for resolving source when [source] is null.
  final SourceFallback? sourceFallback;

  /// Optional build cache for step-level caching.
  final BuildCache? cache;

  /// Optional logger for build output.
  final Logger? logger;

  /// Build for a specific [target].
  ///
  /// [outputDir] is where artifacts are staged (e.g., `built-library/linux-x64/`).
  /// [workDir] is the working directory for build commands.
  Future<NativeBuildResult> build({
    required NativeTarget target,
    required Directory outputDir,
    Directory? workDir,
    LinkMode? linkMode,
  }) async {
    logger?.info('Building ${project.name} for ${target.label}...');

    // 1. Resolve recipe
    final recipe = project.build.recipeFor(target);
    if (recipe == null) {
      throw StateError(
        'No build recipe for ${project.name} on ${target.label}.',
      );
    }

    // 2. Resolve source if not provided
    var resolvedSource = source;
    if (resolvedSource == null) {
      // When no explicit source or sourceFallback is given, fall back
      // to project.sources so that CLI callers (and any executor user)
      // can build from the project's declared sources automatically.
      final effectiveFallback = sourceFallback ??
          (project.sources.isNotEmpty
              ? SourceFallback(
                  sources: project.sources,
                  builder: const NoOpSourceBuilder(),
                  preparation: [],
                )
              : null);
      if (effectiveFallback == null) {
        throw StateError(
          'No source provided and no source fallback configured for '
          '${project.name} on ${target.label}.',
        );
      }

      logger?.info('Resolving source...');
      final sourceResult = await SourceFallbackResolver().resolve(
        fallback: effectiveFallback,
        packageRoot: Directory.current,
        sourceCacheRoot: Directory(
          p.join(
            Directory.current.path,
            '.dart_tool',
            'native_prebuilt',
            'sources',
          ),
        ),
        input: _dummyInput(target),
        output: _dummyOutput(),
        logger: logger,
      );

      if (sourceResult == null) {
        throw StateError(
          'Failed to resolve source for ${project.name} on ${target.label}.',
        );
      }

      resolvedSource = sourceResult.source;
      workDir ??= sourceResult.workDirectory;
    }

    // 3. Create build context
    final context = NativeBuildContext(
      target: target,
      hook: NativeHookConfiguration(
        packageName: project.name,
        assetName: project.asset.assetName,
        libraryStem: project.asset.libraryStem,
        linkMode: linkMode ?? project.asset.linkMode,
      ),
      directories: NativeBuildDirectories(
        source: resolvedSource.directory,
        output: outputDir,
        cache: workDir ?? resolvedSource.directory,
        work: workDir ?? resolvedSource.directory,
      ),
      toolchains: const ToolchainRegistry(),
      environment: {},
      logger: logger,
    );

    // 4. Execute the recipe
    logger?.info('Executing recipe: ${recipe.runtimeType}...');

    // Inject cache into StepBuildRecipe if available
    NativeBuildRecipe effectiveRecipe = recipe;
    if (cache != null && recipe is StepBuildRecipe) {
      effectiveRecipe = StepBuildRecipe(steps: recipe.steps, cache: cache);
    }

    final result = await effectiveRecipe.execute(context, resolvedSource);

    // 5. Stage artifact bundle
    await _stageArtifacts(context, result);

    // 6. Write metadata
    await _writeMetadata(context, result, target);

    logger?.info(
      'Build completed: ${result.artifacts.length} artifact(s) staged '
      'to ${outputDir.path}',
    );

    return result;
  }

  /// Create a minimal [BuildInput] for source resolution.
  BuildInput _dummyInput(NativeTarget target) {
    final builder = BuildInputBuilder()
      ..setupShared(
        packageRoot: Directory.current.uri,
        packageName: project.name,
        outputFile: Directory.systemTemp.uri.resolve('output.json'),
        outputDirectoryShared: Directory.systemTemp.uri.resolve(
          'output_shared/',
        ),
      )
      ..setupBuildInput()
      ..config.setupBuild(linkingEnabled: false)
      ..config.addBuildAssetTypes(['code_assets/code']);
    return builder.build();
  }

  /// Create a minimal [BuildOutputBuilder] for source resolution.
  BuildOutputBuilder _dummyOutput() {
    return BuildOutputBuilder();
  }

  /// Stage artifact entries to role-based subdirectories.
  Future<void> _stageArtifacts(
    NativeBuildContext context,
    NativeBuildResult result,
  ) async {
    for (final artifact in result.artifacts) {
      for (final entry in artifact.entries) {
        final destDir = _destinationDirectory(entry.role, context);
        final entryDir = p.dirname(entry.path);
        final destSubDir = entryDir == '.' || entryDir == ''
            ? destDir
            : Directory(p.join(destDir.path, entryDir));
        destSubDir.createSync(recursive: true);
        final destPath = p.join(destSubDir.path, p.basename(entry.path));

        if (entry.source is File) {
          await (entry.source as File).copy(destPath);
        } else if (entry.source is Directory) {
          await _copyDirectory(entry.source as Directory, Directory(destPath));
        }

        logger?.fine(
          'Staged: ${entry.role.name} -> ${p.relative(destPath, from: context.directories.output.path)}',
        );
      }
    }
  }

  /// Determine the destination directory for an entry based on its role.
  Directory _destinationDirectory(
    NativeArtifactRole role,
    NativeBuildContext context,
  ) {
    final outputBase = context.directories.output.path;
    return switch (role) {
      NativeArtifactRole.primary ||
      NativeArtifactRole.runtimeDependency => Directory(outputBase),
      NativeArtifactRole.importLibrary => Directory(p.join(outputBase, 'link')),
      NativeArtifactRole.debugSymbols => Directory(
        p.join(outputBase, 'symbols'),
      ),
      NativeArtifactRole.resource => Directory(p.join(outputBase, 'resources')),
      NativeArtifactRole.license => Directory(p.join(outputBase, 'licenses')),
    };
  }

  /// Write `native_prebuilt.json` metadata file.
  Future<void> _writeMetadata(
    NativeBuildContext context,
    NativeBuildResult result,
    NativeTarget target,
  ) async {
    final metadata = <String, dynamic>{
      'schemaVersion': 1,
      'project': project.name,
      'target': target.label,
      'artifacts': result.artifacts
          .map(
            (a) => {
              'id': a.id,
              'kind': a.kind.name,
              'primary': a.primary.path,
              'files': a.entries
                  .map(
                    (e) => {
                      'path': e.path,
                      'role': e.role.name,
                      'optional': e.optional,
                    },
                  )
                  .toList(),
            },
          )
          .toList(),
    };

    final metadataFile = File(
      p.join(context.directories.output.path, 'native_prebuilt.json'),
    );
    metadataFile.parent.createSync(recursive: true);
    await metadataFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(metadata),
    );

    logger?.fine('Wrote metadata to ${metadataFile.path}');
  }

  /// Recursively copy a directory.
  Future<void> _copyDirectory(Directory source, Directory destination) async {
    destination.createSync(recursive: true);
    await for (final entity in source.list(recursive: true)) {
      if (entity is File) {
        final relativePath = p.relative(entity.path, from: source.path);
        final targetFile = File(p.join(destination.path, relativePath));
        targetFile.parent.createSync(recursive: true);
        await entity.copy(targetFile.path);
      }
    }
  }
}
