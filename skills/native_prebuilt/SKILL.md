# native_prebuilt

Use this skill when you need to work with native libraries in Dart packages - whether generating manifests, building from source, or setting up prebuilt resolution.

## Two API Paths

### 1. Legacy API (PrebuiltCodeAssetBuilder)
For packages that download prebuilt binaries from GitHub/GitLab releases:

```dart
await PrebuiltCodeAssetBuilder(
  assetName: 'src/bindings.dart',
  libraryStem: 'my_native',
  manifest: myPrebuilts,
  linkModeResolver: (_) => DynamicLoadingBundled(),
  sourceFallback: SourceFallback(
    sources: [LocalSource(paths: ['.'])],
    builder: CallbackSourceBuilder(
      callback: ({required source, required input, required output, required logger}) async {
        // Build from source
      },
    ),
  ),
).run(input: input, output: output, logger: logger);
```

### 2. New API (NativeProject + NativeProjectBuilder)
For packages with multi-stage native builds:

```dart
final project = NativeProject(
  name: 'my_lib',
  asset: NativeAssetSpec(
    assetName: 'src/bindings.dart',
    libraryStem: 'my_native',
    linkMode: DynamicLoadingBundled(),
  ),
  build: NativeBuildDefinition(
    recipes: {
      OS.linux: StepBuildRecipe(steps: [
        CmakeConfigureStep(buildDirectory: 'build'),
        CmakeBuildStep(buildDirectory: 'build', targets: ['my_native']),
        ExportArtifactStep(artifactPath: 'build/libmy_native.so'),
      ]),
      OS.macOS: StepBuildRecipe(steps: [...]),
      OS.windows: StepBuildRecipe(steps: [...]),
    },
  ),
);

// In hook/build.dart
await runNativeProjectCli(args, project: project);
```

## CLI Commands

### Manifest Management
- `dart run native_prebuilt manifest update` - Generate/refresh manifest from `native_prebuilt.yaml`
- `dart run native_prebuilt manifest verify` - Verify manifest hashes match built artifacts

### Build Pipeline
- `dart run native_prebuilt plan --target <platform>` - Show build plan for a target
- `dart run native_prebuilt build --target <platform> --output <dir>` - Build native library
- `dart run native_prebuilt cache-key --target <platform>` - Show cache key for a build
- `dart run native_prebuilt explain-cache --target <platform>` - Explain cache state
- `dart run native_prebuilt verify --target <platform>` - Verify built artifact

### Workflow Generation
- `dart run native_prebuilt workflow init` - Generate GitHub workflow files
- `dart run native_prebuilt workflow init --gitlab` - Generate GitLab CI files

## Build Steps Available

| Step | Purpose |
|------|---------|
| `CmakeConfigureStep` | Run cmake -B with defines |
| `CmakeBuildStep` | Run cmake --build with targets |
| `CommandStep` | Run arbitrary commands |
| `DownloadArchiveStep` | Download and extract archives |
| `GitCheckoutStep` | Clone/update git repositories |
| `GitApplyPatchStep` | Apply patch files |
| `StripStep` | Strip debug symbols |
| `FindArtifactStep` | Find built artifacts |
| `CopyStep` | Copy files/directories |
| `ExportArtifactStep` | Export final artifact to output |

## Platform Toolchains

The package auto-detects:
- **Android NDK** - From `ANDROID_NDK_HOME` or SDK
- **Apple SDK** - iOS/macOS from Xcode
- **MSVC** - Windows Visual Studio
- **vcpkg** - From `VCPKG_ROOT`

## Caching

Build steps are cached using content-based fingerprints:
- Same inputs → cache hit (skip build)
- Changed source/toolchain → cache miss (rebuild)
- Cache stored in `.dart_tool/native_prebuilt/build-cache/`

## Test Fixtures

Located in `test/fixtures/native_projects/`:
- `simple_shared/` - Basic shared library
- `static_library/` - Static library
- `generated_source/` - Multi-stage with code generation
- `dependency_graph/` - Library with dependencies
- `patchable_source/` - Patchable source
- `failing_build/` - Intentionally broken (for error testing)

## Workflow Rules

- The manifest config (`native_prebuilt.yaml`) is the source of truth for release-based packages
- Generated workflows should use package-specific filenames and tag patterns
- Release asset archives are written to `release-assets/` during manifest generation
- Checked-in manifests should live under `lib/src/hook/<package>_prebuilts.g.dart`
