# native_prebuilt

Use this skill when you need to work with native libraries in Dart packages - whether generating manifests, building from source, or setting up prebuilt resolution.

## Three API Paths

### 1. Hooks Builder integration (simple packages)

For packages with single-stage builds using existing hooks builders like `CBuilder`:

```dart
import 'package:hooks/hooks.dart';
import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    await PrebuiltCodeAssetBuilder(
      assetName: 'src/my_package.dart',
      libraryStem: 'my_package',
      manifest: myPackagePrebuilts,
      linkModeResolver: (_) => DynamicLoadingBundled(),
      sourceFallback: SourceFallback(
        sources: [LocalSource(paths: ['.'])],
        builder: HookBuilderSourceBuilder.factory(
          (input) => CBuilder.library(
            name: 'my_package',
            packageName: input.packageName,
            assetName: 'src/my_package.dart',
            sources: const ['src/native/my_package.c'],
          ),
        ),
      ),
    ).run(input: input, output: output, logger: Logger.root);
  });
}
```

### 2. Managed build recipes (complex packages)

For multi-stage builds with caching and cross-compilation, you can write the `NativeProject` in Dart by hand:

```dart
final project = NativeProject(
  name: 'tdlib',
  asset: const NativeAssetSpec(
    assetName: 'src/tdlib.g.dart',
    libraryStem: 'tdjson',
    linkMode: DynamicLoadingBundled(),
  ),
  build: NativeBuildDefinition(
    recipes: {
      OS.linux: StepBuildRecipe(steps: [
        CmakeConfigureStep(buildDirectory: 'build'),
        CmakeBuildStep(buildDirectory: 'build', targets: ['tdjson']),
        ExportArtifactStep(artifactPath: 'build/td/libtdjson.so'),
      ]),
    },
  ),
);

// hook/build.dart
await runNativeProjectCli(args, project: project);
```

### 3. Declarative manifest (recommended for release builds)

You can define the complete project in `native_prebuilt.yaml` instead of writing `NativeProject` code manually. The CLI loads that manifest, validates it, and generates the build graph from it.

## CLI Commands

### Manifest Management
- `dart run native_prebuilt manifest update` - Generate/refresh manifest from `native_prebuilt.yaml`
- `dart run native_prebuilt manifest verify` - Verify manifest hashes match built artifacts
- `dart run native_prebuilt schema export` - Write `schema/native_prebuilt.schema.json` for editor validation

### Build Pipeline
- `dart run native_prebuilt plan --target <platform>` - Show build plan for a target
- `dart run native_prebuilt build --target <platform> --output <dir>` - Build native library
- `dart run native_prebuilt cache-key --target <platform>` - Show cache key for a build
- `dart run native_prebuilt explain-cache --target <platform>` - Explain cache state
- `dart run native_prebuilt verify --target <platform>` - Verify built artifact

### Workflow Generation
- `dart run native_prebuilt workflow init` - Generate GitHub workflow files
- `dart run native_prebuilt workflow init --gitlab` - Generate GitLab CI files
- `dart run native_prebuilt workflow init --gitlab --platform linux,windows` - Filter GitLab outputs by platform

## Build Steps

Common YAML keys:
- `type` (required)
- `id` (required)
- `needs` (optional)

| type | Purpose |
|------|---------|
| `cmake_configure` | Run CMake configure/generate |
| `cmake_build` | Run CMake build with targets |
| `command` | Run arbitrary commands |
| `download_archive` | Download and extract archives |
| `git_checkout` | Clone or update git repositories |
| `git_apply_patch` | Apply patch files |
| `copy` | Copy files or directories |
| `strip` | Strip debug symbols |
| `export_artifact` | Export the final artifact |

Use `schema/native_prebuilt.schema.json` for editor validation.

## Platform Toolchains

Auto-detected from environment:
- **Android NDK** — `ANDROID_NDK_HOME` or SDK
- **Apple SDK** — Xcode paths
- **MSVC** — Visual Studio installation
- **vcpkg** — `VCPKG_ROOT`

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
- `failing_build/` - Intentionally broken
