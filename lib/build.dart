/// Build orchestration for native libraries.
///
/// This library provides the high-level API for building native libraries
/// from source, including:
/// - [NativeProject] - the central project definition
/// - [NativeProjectBuilder] - orchestrates the build pipeline
/// - [NativeBuildContext] - build configuration per target
/// - [NativeBuildRecipe] - build step recipes
/// - [NativeBuildResult] - build output artifacts
/// - [runNativePrebuiltCli] - unified CLI entry point
/// - [nativePrebuiltBuild] - convenience hook entry point
library native_prebuilt.build;

export 'src/cli/cli.dart';
export 'src/cli/shared.dart';
export 'src/build/native_build_context.dart';
export 'src/build/native_build_recipe.dart';
export 'src/build/native_build_result.dart';
export 'src/build/native_project.dart';
export 'src/builder/native_project_builder.dart';
export 'src/build/native_project_executor.dart';
export 'src/build/fingerprint.dart';
export 'src/build/process_runner.dart';
export 'src/build/steps/steps.dart';
export 'src/build/toolchains/toolchains.dart';
export 'src/cache/build_cache.dart';
