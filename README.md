# native_prebuilt

Reusable infrastructure for Dart packages that build, cache, and ship native libraries through Dart hooks.

## Contents

- [Two API paths](#two-api-paths)
- [Comparison](#comparison)
- [Install](#install)
- [Source fallback pipeline](#source-fallback-pipeline)
- [Build steps](#build-steps)
- [CLI commands](#cli-commands)
- [Platform toolchains](#platform-toolchains)
- [Caching](#caching)
- [License](#license)

## Two API paths

### 1. Hooks Builder integration (simple packages)

For packages with single-stage builds using existing hooks builders:

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
          (input, source) => CBuilder.library(
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

For multi-stage builds with caching and cross-compilation:

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

## Comparison

| Capability | Hooks Builder callback | Managed recipe |
|------------|----------------------:|---------------:|
| Prebuilt resolution | Yes | Yes |
| Source fallback | Yes | Yes |
| Standard hook caching | Yes | Yes |
| Existing hooks builders | Yes | Not required |
| Step-level native cache | No | Yes |
| Multi-stage graph | Manual | Yes |
| Standalone CI build | Limited | Yes |
| Central artifact validation | After registration | Yes |

## Install

```yaml
dependencies:
  native_prebuilt: ^0.0.13
```

## Source fallback pipeline

When no prebuilt is available, you can let `native_prebuilt` resolve source and build from it.

Resolution order:
1. `hooks.user_defines` override
2. Local `.prebuilt/` directory
3. Shared cache / release download
4. Source build using recipe or callback

## Build steps

Recipe values are Liquid templates rendered with:

- `source.path`
- `work`
- `output`
- `cache`
- `env.*`

Example:

```yaml
source_directory: "{{ source.path }}/example/android"
build_directory: "{{ work }}/build"
CMAKE_TOOLCHAIN_FILE: "{{ env.VCPKG_ROOT }}/scripts/buildsystems/vcpkg.cmake"
```

| Step | Purpose |
|------|---------|
| `CmakeConfigureStep` | Run `cmake -B` with defines |
| `CmakeBuildStep` | Run `cmake --build` with targets |
| `CommandStep` | Run arbitrary commands |
| `DownloadArchiveStep` | Download and extract archives |
| `GitCheckoutStep` | Clone/update git repositories |
| `GitApplyPatchStep` | Apply patch files |
| `StripStep` | Strip debug symbols |
| `FindArtifactStep` | Find built artifacts |
| `CopyStep` | Copy files/directories |
| `ExportArtifactStep` | Export final artifact to output |

## CLI commands

| Command | Description |
|---------|-------------|
| `plan --target <platform>` | Show build plan and recipe steps |
| `build --target <platform> --output <dir>` | Build native library |
| `cache-key --target <platform>` | Show cache key |
| `explain-cache --target <platform>` | Explain cache state |
| `verify --target <platform>` | Verify built artifact |
| `manifest update` | Generate/refresh Dart manifest |
| `manifest verify` | Verify manifest hashes |
| `fetch` | Download prebuilt artifacts |
| `doctor` | Check build environment |
| `workflow init` | Generate GitHub/GitLab CI workflows |

`workflow init` writes 5 GitHub workflow files, or 8 GitLab files by default. Use `--gitlab --platform ...` to filter GitLab outputs to selected platforms.

## Platform toolchains

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

## License

MIT
