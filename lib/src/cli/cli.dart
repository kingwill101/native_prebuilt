import 'dart:io';

import 'package:artisanal/args.dart';
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';

import '../build/native_build_recipe.dart';
import '../build/native_project.dart';
import '../build/steps/steps.dart';
import '../builder/native_project_builder.dart';
import '../manifest/prebuilt_manifest.dart';
import '../manifest/release_source.dart';
import '../resolution/prebuilt_resolver.dart';
import '../source/source_specification.dart';
import 'build.dart';
import 'cache_key.dart';
import 'cli_config.dart';
import 'doctor.dart';
import 'explain_cache.dart';
import 'fetch.dart';
import 'manifest.dart';
import 'plan.dart';
import 'shared.dart' show shouldBuildFromSource;
import 'verify.dart';
import 'workflow.dart';

/// Runs the `native_prebuilt` CLI.
///
/// If [project] is provided, it is used for the build-related commands
/// (plan, build, cache-key, explain-cache, verify). Otherwise
/// [_defaultProject] is used.
///
/// Runs the native project CLI for package-local builds.
/// This provides build commands for packages that define a [NativeProject]:
///
/// ```bash
/// dart run native_prebuilt_cli plan --target android-arm64
/// dart run native_prebuilt_cli build --target android-arm64 --output built-library
/// dart run native_prebuilt_cli cache-key --target android-arm64
/// dart run native_prebuilt_cli explain-cache --target android-arm64
/// dart run native_prebuilt_cli verify --target android-arm64
/// ```
Future<void> runNativePrebuiltCli(
  List<String> args, {
  NativeProject? project,
}) async {
  // If no project is explicitly passed, try to auto-discover it
  // from native_prebuilt.yaml in the current working directory.
  // Fall back to the hardcoded example project if not found.
  final buildProject = project ??
      detect(Directory.current) ??
      _defaultProject;
  final runner =
      CommandRunner<void>(
          'native_prebuilt',
          'Utilities for prebuilt native artifacts in Dart packages.',
        )
        ..addCommand(ManifestCommand())
        ..addCommand(FetchCommand())
        ..addCommand(DoctorCommand())
        ..addCommand(WorkflowCommand())
        ..addCommand(PlanCommand(project: buildProject))
        ..addCommand(BuildCommand(project: buildProject))
        ..addCommand(CacheKeyCommand(project: buildProject))
        ..addCommand(ExplainCacheCommand(project: buildProject))
        ..addCommand(VerifyCommand(project: buildProject));

  await runner.run(args);
}

/// High-level convenience function for hook entrypoints.
///
/// This replaces the pattern of manually setting up logging, checking
/// `buildCodeAssets`, and reading user-defined flags. It handles all
/// of that internally so that a hook can be just a single call:
///
/// ```dart
/// import 'package:native_prebuilt/hooks.dart';
/// import 'package:tdlib/src/hook/tdlib_project.dart';
///
/// Future<void> main(List<String> args) {
///   return nativePrebuiltBuild(args, project: tdlibProject);
/// }
/// ```
///
/// The hook automatically:
/// - Sets up [Logger.root] with [Level.INFO] output to stderr
/// - Checks [BuildConfig.buildCodeAssets] and returns early if disabled
/// - Reads the `build_from_source` user-defined flag from
///   [HookInput.userDefines] to skip prebuilt resolution when needed
Future<void> nativePrebuiltBuild(
  List<String> args, {
  required NativeProject project,
}) async {
  await build(args, (input, output) async {
    Logger.root
      ..level = Level.INFO
      ..onRecord.listen(
        (record) => stderr.writeln(
          '[${project.name}] ${record.level.name}: ${record.message}',
        ),
      );

    if (!input.config.buildCodeAssets) {
      Logger.root.info(
        'Skipping native_prebuilt: buildCodeAssets is disabled.',
      );
      return;
    }

    final buildFromSource = shouldBuildFromSource(input);

    final builder = NativeProjectBuilder(
      project: project,
      resolvers: buildFromSource ? <PrebuiltResolver>[] : null,
    );

    await builder.run(input: input, output: output, logger: Logger.root);
  });
}

/// Default NativeProject used by CLI build commands when no project is provided.
final NativeProject _defaultProject = NativeProject(
  name: 'native_prebuilt',
  asset: NativeAssetSpec(
    assetName: 'src/native_prebuilt.dart',
    libraryStem: 'native_prebuilt',
    linkMode: DynamicLoadingBundled(),
  ),
  prebuilts: PrebuiltManifest(
    schemaVersion: 1,
    release: GitHubReleaseSource(
      owner: 'example',
      repository: 'native_prebuilt',
      tag: 'v0.0.1',
    ),
    artifacts: {},
  ),
  sources: [
    GitSource(
      repository: Uri.parse('https://github.com/example/native_prebuilt.git'),
      revision: 'abc123',
    ),
  ],
  build: NativeBuildDefinition(
    recipes: [
      NativeTargetRecipe(
        pattern: const NativeTargetPattern(os: OS.linux),
        recipe: StepBuildRecipe(
          steps: [
            CmakeConfigureStep(sourceDirectory: '.', buildDirectory: 'build'),
            CmakeBuildStep(
              buildDirectory: 'build',
              targets: ['native_prebuilt'],
            ),
          ],
        ),
      ),
    ],
  ),
);
