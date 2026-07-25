import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:logging/logging.dart';

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
final class StepBuildRecipe implements NativeBuildRecipe {
  const StepBuildRecipe({required this.steps});

  /// The ordered list of build steps to execute.
  final List<NativeBuildStep> steps;

  @override
  Future<NativeBuildResult> execute(
    NativeBuildContext context,
    ResolvedSource source,
  ) async {
    final logger = context.logger ?? Logger('StepBuildRecipe');
    logger.fine('Starting build recipe for ${context.target.label}');
    logger.fine('Recipe has ${steps.length} steps: ${steps.map((s) => s.id).join(', ')}');

    final artifacts = <BuiltNativeArtifact>[];

    for (final step in steps) {
      logger.info('Executing step: ${step.id}');
      final stopwatch = Stopwatch()..start();
      await step.execute(context, source);
      stopwatch.stop();
      logger.info('Step ${step.id} completed in ${stopwatch.elapsedMilliseconds}ms');

      // Collect artifacts from ExportArtifactStep
      if (step is ExportArtifactStep) {
        final outputName = step.outputName ?? step.artifactPath.split('/').last;
        final artifactFile = File(p.join(
          context.directories.output.path,
          outputName,
        ));
        if (artifactFile.existsSync()) {
          artifacts.add(BuiltNativeArtifact(
            file: artifactFile,
            type: NativeArtifactType.dynamicLibrary,
            target: context.target,
          ));
        }
      }
    }

    return NativeBuildResult(artifacts: artifacts);
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
  Future<void> execute(NativeBuildContext context, ResolvedSource source);
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
