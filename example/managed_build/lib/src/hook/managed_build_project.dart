/// Declarative project definition for managed build
///
/// This demonstrates the declarative approach where you define a NativeProject
/// and the build system handles everything automatically.
library;

import 'package:code_assets/code_assets.dart';
import 'package:native_prebuilt/native_prebuilt.dart';

final managedBuildProject = NativeProject(
  name: 'managed_build_example',
  asset: NativeAssetSpec(
    assetName: 'managed_build_example_bindings_generated.dart',
    libraryStem: 'managed_build_example',
    linkMode: DynamicLoadingBundled(),
  ),
  prebuilts: PrebuiltManifest(
    schemaVersion: 1,
    release: GitHubReleaseSource(
      owner: 'example',
      repository: 'managed_build_example',
      tag: 'managed_build_example-v0.1.0',
    ),
    artifacts: {},
  ),
  sources: [
    GitSource(
      repository: Uri.parse('https://github.com/example/managed_build_example.git'),
      revision: 'main',
    ),
  ],
  build: NativeBuildDefinition(
    recipes: {
      OS.linux: StepBuildRecipe(
        steps: [
          CmakeConfigureStep(
            sourceDirectory: '.',
            buildDirectory: 'build',
          ),
          CmakeBuildStep(
            buildDirectory: 'build',
            targets: ['managed_build_example'],
          ),
        ],
      ),
      OS.macOS: StepBuildRecipe(
        steps: [
          CmakeConfigureStep(
            sourceDirectory: '.',
            buildDirectory: 'build',
          ),
          CmakeBuildStep(
            buildDirectory: 'build',
            targets: ['managed_build_example'],
          ),
        ],
      ),
      OS.windows: StepBuildRecipe(
        steps: [
          CmakeConfigureStep(
            sourceDirectory: '.',
            buildDirectory: 'build',
          ),
          CmakeBuildStep(
            buildDirectory: 'build',
            targets: ['managed_build_example'],
          ),
        ],
      ),
    },
  ),
);
