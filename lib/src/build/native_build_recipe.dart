import 'dart:async';

import '../source/resolved_source.dart';
import 'native_build_context.dart';
import 'native_build_result.dart';

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
    for (final step in steps) {
      await step.execute(context, source);
    }

    // Find the export artifact step and return its result.
    // In a full implementation, this would collect results from all steps.
    return NativeBuildResult(artifacts: []);
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
