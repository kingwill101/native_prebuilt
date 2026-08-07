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

  /// Serialize this recipe to JSON.
  Map<String, dynamic> toJson();
}

/// Composable build recipe that executes a sequence of steps.
///
/// When a [BuildCache] is provided, each step is checked against the cache
/// before execution. On cache hit, the step is skipped. On cache miss,
/// the step is executed and its output recorded.
final class StepBuildRecipe implements NativeBuildRecipe {
  const StepBuildRecipe({
    required this.steps,
    this.needsById = const {},
    this.cache,
  });

  /// The ordered list of build steps to execute.
  final List<NativeBuildStep> steps;

  /// Step dependencies keyed by step id.
  final Map<String, List<String>> needsById;

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

    final orderedSteps = _orderedSteps();
    final artifacts = <BuiltNativeArtifact>[];

    for (final step in orderedSteps) {
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

  @override
  Map<String, dynamic> toJson() => {
    'type': 'step_build_recipe',
    'steps': steps.map((step) => step.toJson()).toList(),
    if (needsById.isNotEmpty) 'needs_by_id': needsById,
  };

  factory StepBuildRecipe.fromJson(Map<String, dynamic> json) {
    return StepBuildRecipe(
      steps: (json['steps'] as List<dynamic>? ?? const [])
          .map((step) => NativeBuildStep.fromJson(step as Map<String, dynamic>))
          .toList(),
      needsById: json['needs_by_id'] is Map
          ? Map<String, List<String>>.fromEntries(
              (json['needs_by_id'] as Map).entries.map(
                (entry) => MapEntry(
                  entry.key.toString(),
                  (entry.value as List<dynamic>? ?? const [])
                      .map((value) => value.toString())
                      .toList(),
                ),
              ),
            )
          : const {},
    );
  }

  List<NativeBuildStep> _orderedSteps() {
    if (needsById.isEmpty) return steps;

    final ordered = <NativeBuildStep>[];
    final orderedIds = <String>{};

    while (ordered.length < steps.length) {
      var progress = false;
      for (final step in steps) {
        if (orderedIds.contains(step.id)) continue;
        final deps = needsById[step.id] ?? const [];
        if (deps.every(orderedIds.contains)) {
          ordered.add(step);
          orderedIds.add(step.id);
          progress = true;
        }
      }
      if (!progress) {
        final unresolved = steps
            .map((step) => step.id)
            .where((id) => !orderedIds.contains(id))
            .toList();
        throw StateError('Unable to resolve build step order: $unresolved');
      }
    }

    return ordered;
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

  /// Execution context: `host` or `target`.
  String get execution;

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

  /// Serialize this step to JSON.
  Map<String, dynamic> toJson();

  /// Deserialize a step from JSON.
  factory NativeBuildStep.fromJson(Map<String, dynamic> json) {
    return switch (json['type'] as String?) {
      'cmake_configure' => CmakeConfigureStep.fromMap(json),
      'cmake_build' => CmakeBuildStep.fromMap(json),
      'export_artifact' => ExportArtifactStep.fromMap(json),
      'command' => CommandStep.fromMap(json),
      'download_archive' => DownloadArchiveStep.fromMap(json),
      'git_checkout' => GitCheckoutStep.fromMap(json),
      'git_apply_patch' => GitApplyPatchStep.fromMap(json),
      'copy' => CopyStep.fromMap(json),
      'strip' => StripStep.fromMap(json),
      final type => throw FormatException('Unknown build step type: $type'),
    };
  }
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

  Map<String, dynamic> toJson() => {
    'artifacts': artifacts.map((artifact) => artifact.toJson()).toList(),
  };

  factory NativeStepResult.fromJson(Map<String, dynamic> json) {
    return NativeStepResult(
      artifacts: (json['artifacts'] as List<dynamic>? ?? const [])
          .map(
            (artifact) =>
                BuiltNativeArtifact.fromJson(artifact as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

/// Fingerprint for a build step, used for caching.
final class NativeStepFingerprint {
  const NativeStepFingerprint({required this.id, required this.hash});

  /// The step identifier.
  final String id;

  /// A hash representing the step's inputs and configuration.
  final String hash;

  Map<String, dynamic> toJson() => {'id': id, 'hash': hash};

  factory NativeStepFingerprint.fromJson(Map<String, dynamic> json) {
    return NativeStepFingerprint(
      id: json['id'] as String,
      hash: json['hash'] as String,
    );
  }
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
