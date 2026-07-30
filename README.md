# native_prebuilt

Reusable infrastructure for Dart packages that build, cache, and ship native libraries through Dart hooks.

## Contents

- [Three API paths](#three-api-paths)
- [Comparison](#comparison)
- [Install](#install)
- [Source fallback pipeline](#source-fallback-pipeline)
- [Build steps](#build-steps)
- [CLI commands](#cli-commands)
- [Platform toolchains](#platform-toolchains)
- [Caching](#caching)
- [License](#license)

## Three API paths

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

### 3. Declarative manifest (recommended for most release builds)

You can define the complete project in `native_prebuilt.yaml` instead of writing `NativeProject` code manually. The CLI reads that manifest, validates it, and generates the build graph from it.

`assetName` is the Dart library path that declares the native code asset (the `@Native` bindings), not the shared-library filename.

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
  native_prebuilt: ^0.2.0
```

## Source fallback pipeline

When no prebuilt is available, you can let `native_prebuilt` resolve source and build from it.

Resolution order:
1. `hooks.user_defines` override
2. Local `.prebuilt/` directory
3. Shared cache / release download
4. Source build using recipe or callback

`native_prebuilt build` executes declarative YAML recipes, and falls back to
`hook/build.dart` when no recipe is declared. If the manifest has an artifact
entry for the target, that entry is used to standardize the staged payload name.

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

Every step has these common YAML keys:

- `type` (required)
- `id` (required)
- `needs` (optional list of step ids)

| type | Required keys | Optional keys |
|------|---------------|---------------|
| `cmake_configure` | `source_directory`, `build_directory` | `needs`, `generator`, `toolchain_file`, `definitions` |
| `cmake_build` | `build_directory` | `needs`, `targets`, `parallel`, `environment` |
| `command` | `commands` | `needs`, `working_directory`, `environment` |
| `download_archive` | `url` | `needs`, `sha256`, `output_directory` |
| `git_checkout` | `repository`, `revision` | `needs`, `target_directory`, `submodules` |
| `git_apply_patch` | `patch_path` | `needs`, `target_directory` |
| `copy` | `source_path`, `destination_path` | `needs`, `recursive` |
| `strip` | `input_path`, `output_path` | `needs`, `strip_all` |
| `export_artifact` | `artifact`, `primary` | `needs`, `kind` |

## JSON schema

Export the checked-in schema copy with:

```bash
dart run native_prebuilt schema export
```

This writes `schema/native_prebuilt.schema.json`. Point editors at that file,
for example in VS Code:

```json
{
  "yaml.schemas": {
    "./schema/native_prebuilt.schema.json": "native_prebuilt.yaml"
  }
}
```

## CLI commands

| Command | Description |
|---------|-------------|
| `plan --target <platform>` | Show build plan and recipe steps |
| `build --target <platform> --output <dir>` | Build native library from declarative recipes |
| `cache-key --target <platform>` | Show cache key |
| `explain-cache --target <platform>` | Explain cache state |
| `verify --target <platform>` | Verify built artifact |
| `manifest update` | Generate/refresh Dart manifest |
| `manifest verify` | Verify manifest hashes |
| `schema export` | Write the JSON schema copy used by editors |
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
