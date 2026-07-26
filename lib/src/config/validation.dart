import 'build_step_config.dart';
import 'native_prebuilt_config.dart';

/// Validates a fully parsed native_prebuilt configuration.
void validateNativePrebuiltConfig(NativePrebuiltConfig config) {
  final build = config.build;
  if (build == null) return;

  for (final recipe in build.recipes) {
    validateRecipe(recipe);
  }
}

/// Validates the build graph for a single target recipe.
void validateRecipe(TargetRecipeConfig recipe) {
  final stepById = <String, BuildStepConfig>{};
  for (final step in recipe.steps) {
    final previous = stepById[step.id];
    if (previous != null) {
      throw FormatException('Duplicate step id "${step.id}" in build recipe.');
    }
    stepById[step.id] = step;
  }

  if (!recipe.steps.any((step) => step is ExportArtifactStepConfig)) {
    throw FormatException('Build recipe must export at least one artifact.');
  }

  for (final step in recipe.steps) {
    for (final dependencyId in step.needs) {
      if (dependencyId == step.id) {
        throw FormatException('Step "${step.id}" cannot depend on itself.');
      }
      if (!stepById.containsKey(dependencyId)) {
        throw FormatException(
          'Step "${step.id}" depends on unknown step "$dependencyId".',
        );
      }
    }
  }

  _detectCycles(recipe.steps);
}

void _detectCycles(List<BuildStepConfig> steps) {
  final stepById = {for (final step in steps) step.id: step};
  final visiting = <String>{};
  final visited = <String>{};

  bool visit(String stepId) {
    if (visited.contains(stepId)) return false;
    if (!visiting.add(stepId)) return true;

    final step = stepById[stepId];
    if (step != null) {
      for (final dependencyId in step.needs) {
        if (visit(dependencyId)) return true;
      }
    }

    visiting.remove(stepId);
    visited.add(stepId);
    return false;
  }

  for (final step in steps) {
    if (visit(step.id)) {
      throw FormatException('Build recipe contains a dependency cycle.');
    }
  }
}
