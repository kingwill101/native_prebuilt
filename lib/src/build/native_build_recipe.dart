import 'dart:async';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../cache/build_cache.dart';
import '../source/resolved_source.dart';
import 'native_build_context.dart';
import 'native_build_result.dart';
import 'steps/steps.dart';

/// Abstract interface for a native build recipe.
///
/// A recipe encapsulates the complete build process for a native library,
/// from source acquisition to artifact export.
abstract interface class NativeBuildRecipe {
  /// Execute the build recipe.
  ///
  /// Returns the [NativeBuildResult] containing the built artifacts.
  Future<NativeBuildResult> execute(
    NativeBuildContext context,
    ResolvedSource source,
  );
}

/// Composable build recipe that executes a sequence of steps.
///
/// When a [BuildCache] is provided, each step is checked against the cache
/// before execution. On cache hit, the step is skipped. On cache miss,
/// the step is executed and its output recorded.
final class StepBuildRecipe implements NativeBuildRecipe {
  const StepBuildRecipe({required this.steps, this.cache});

  /// The ordered list of build steps to execute.
  final List<NativeBuildStep> steps;

  /// Optional build cache for step-level caching.
  final BuildCache? cache;

  @override
  Future<NativeBuildResult> execute(
    NativeBuildContext context,
    ResolvedSource source,
  ) async {
    final logger = context.logger ?? Logger('StepBuildRecipe');
    logger.fine('Starting build recipe for ${context.target.label}');
    logger.fine(
      'Recipe has ${steps.length} steps: ${steps.map((s) => s.id).join(', ')}',
    );

    final artifacts = <BuiltNativeArtifact>[];

    for (final step in steps) {
      logger.info('Executing step: ${step.id}');
      final stopwatch = Stopwatch()..start();

      // Check cache if available
      if (cache != null) {
        final stepContext = NativeStepContext(
          buildContext: context,
          source: source,
          stepId: step.id,
        );
        final fingerprint = await step.fingerprint(stepContext);
        final cached = await cache!.isCached(fingerprint);

        if (cached) {
          logger.info('Step ${step.id} skipped (cache hit)');
          // Reconstruct artifacts from cached declarations
          final cachedDecls = await cache!.getCachedArtifacts(fingerprint);
          for (final decl in cachedDecls) {
            final artifact = _reconstructArtifact(decl, context);
            if (artifact != null) artifacts.add(artifact);
          }
          stopwatch.stop();
          continue;
        }

        // Execute the step
        final result = await step.execute(context, source);
        stopwatch.stop();
        logger.info(
          'Step ${step.id} completed in ${stopwatch.elapsedMilliseconds}ms',
        );

        // Record in cache with artifact declarations
        final artifactDecls = result.artifacts
            .map((a) => _serializeArtifact(a))
            .toList();
        await cache!.record(
          fingerprint: fingerprint,
          artifactDeclarations: artifactDecls,
        );

        // Collect artifacts from step results
        artifacts.addAll(result.artifacts);
      } else {
        // No cache: just execute
        final result = await step.execute(context, source);
        stopwatch.stop();
        logger.info(
          'Step ${step.id} completed in ${stopwatch.elapsedMilliseconds}ms',
        );

        // Collect artifacts from step results
        artifacts.addAll(result.artifacts);
      }
    }

    return NativeBuildResult(artifacts: artifacts);
  }

  /// Serialize a [BuiltNativeArtifact] to a JSON-serializable map.
  Map<String, Object?> _serializeArtifact(BuiltNativeArtifact artifact) {
    return {
      'id': artifact.id,
      'target_os': artifact.target.os.name,
      'target_arch': artifact.target.architecture.name,
      'kind': artifact.kind.name,
      'primary_path': artifact.primary.path,
      'primary_role': artifact.primary.role.name,
      'companions': artifact.companions
          .map(
            (c) => {
              'path': c.path,
              'role': c.role.name,
              'optional': c.optional,
            },
          )
          .toList(),
    };
  }

  /// Reconstruct a [BuiltNativeArtifact] from a cached JSON declaration.
  BuiltNativeArtifact? _reconstructArtifact(
    Map<String, Object?> decl,
    NativeBuildContext context,
  ) {
    try {
      final targetOs = OS.values.firstWhere(
        (o) => o.name == decl['target_os'],
        orElse: () => OS.current,
      );
      final targetArch = Architecture.values.firstWhere(
        (a) => a.name == decl['target_arch'],
        orElse: () => Architecture.current,
      );
      final kind = NativeArtifactKind.values.firstWhere(
        (k) => k.name == decl['kind'],
        orElse: () => NativeArtifactKind.dynamicLibrary,
      );

      // Resolve primary source path against work directory
      final primaryPath = decl['primary_path'] as String;
      final sourceFile = File(
        p.isAbsolute(primaryPath)
            ? primaryPath
            : p.join(context.directories.work.path, primaryPath),
      );

      if (!sourceFile.existsSync()) {
        context.logger?.warning(
          'Cached artifact source missing: ${sourceFile.path}',
        );
        return null;
      }

      final primaryEntry = NativeArtifactEntry(
        source: sourceFile,
        path: primaryPath,
        role: NativeArtifactRole.primary,
      );

      final companionEntries = <NativeArtifactEntry>[];
      final companions = decl['companions'] as List<dynamic>? ?? [];
      for (final c in companions) {
        final cMap = c as Map<String, dynamic>;
        final cPath = cMap['path'] as String;
        final cRole = NativeArtifactRole.values.firstWhere(
          (r) => r.name == cMap['role'],
          orElse: () => NativeArtifactRole.primary,
        );
        final cOptional = cMap['optional'] as bool? ?? false;
        final cFile = File(
          p.isAbsolute(cPath)
              ? cPath
              : p.join(context.directories.work.path, cPath),
        );
        if (cFile.existsSync() || !cOptional) {
          companionEntries.add(
            NativeArtifactEntry(
              source: cFile,
              path: cPath,
              role: cRole,
              optional: cOptional,
            ),
          );
        }
      }

      return BuiltNativeArtifact(
        id: decl['id'] as String,
        target: NativeTarget(os: targetOs, architecture: targetArch),
        kind: kind,
        primary: primaryEntry,
        companions: companionEntries,
      );
    } catch (e) {
      context.logger?.warning('Failed to reconstruct cached artifact: $e');
      return null;
    }
  }
}

/// A single step in a native build recipe.
abstract interface class NativeBuildStep {
  /// A unique identifier for this step.
  String get id;

  /// Compute a fingerprint for this step based on its inputs.
  ///
  /// Used for build caching to determine if a step needs to be re-executed.
  Future<NativeStepFingerprint> fingerprint(NativeStepContext context);

  /// Execute this build step.
  ///
  /// The [context] provides access to the build configuration and logger.
  /// Returns a [NativeStepResult] containing any artifacts produced by this step.
  Future<NativeStepResult> execute(
    NativeBuildContext context,
    ResolvedSource source,
  );
}

/// Result of executing a single build step.
///
/// Contains any artifacts produced by the step. Most steps return an empty
/// result. Only steps that produce exportable artifacts (like
/// [ExportArtifactStep]) return non-empty results.
final class NativeStepResult {
  const NativeStepResult({this.artifacts = const []});

  /// Artifacts produced by this step.
  final List<BuiltNativeArtifact> artifacts;
}

/// Fingerprint for a build step, used for caching.
final class NativeStepFingerprint {
  const NativeStepFingerprint({required this.id, required this.hash});

  /// The step identifier.
  final String id;

  /// A hash representing the step's inputs and configuration.
  final String hash;
}

/// Context passed to individual build steps.
final class NativeStepContext {
  const NativeStepContext({
    required this.buildContext,
    required this.source,
    required this.stepId,
  });

  /// The parent build context.
  final NativeBuildContext buildContext;

  /// The resolved source being built.
  final ResolvedSource source;

  /// The identifier of the current step.
  final String stepId;
}
