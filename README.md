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
    assetName: 'src/client/platform/io/tdjson_native.dart',
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

If `native_prebuilt.lock.yaml` is present next to the config file, `detect()` overlays it automatically. Use `project.copyWith(prebuilts: ...)` only for manual overrides in custom code.

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
  native_prebuilt: ^0.4.0
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

- `source.path`, `source.origin`, and `source.revision`
- `work`, `output`, `cache`, and the equivalent `directories.*` paths
- `env.*`
- `target.label`, `target.os`, `target.architecture`, `target.sdk`
- `target.rust_target`, `target.zig_target`, and target OS booleans
- `library.name`, `library.dynamic_name`, `library.static_name`,
  `library.versioned_name`, and `library.extension`
- `hook.*`, `project.*`, and custom `build.options.*` values

The manifest-level `variables` map defines shared Liquid values. Variables can
refer to the standard recipe values and to one another:

```yaml
variables:
  cargo_manifest: "{{ source.path }}/rust/Cargo.toml"
  cargo_target: "{{ target.rust_target }}"

build:
  recipes:
    - target: {os: linux, architecture: x64}
      steps:
        - id: build
          type: command
          commands:
            - [cargo, build, --manifest-path, "{{ variables.cargo_manifest }}", --target, "{{ variables.cargo_target }}"]
```

YAML anchors can still share complete step lists. Dynamic artifact payloads are
the default; specify `payload: {type: static_library}` only for static targets.

Example:

```yaml
variables:
  openssl_version: OpenSSL_1_1_1w
  android_api: "24"

source_directory: "{{ source.path }}/example/android"
build_directory: "{{ work }}/build"
# Toolchain auto-injected for Android/iOS when omitted:
# ANDROID_ABI, ANDROID_STL, ANDROID_PLATFORM, CMAKE_TOOLCHAIN_FILE(NDK)
```

Every step has these common YAML keys:

- `type` (required)
- `id` (required)
- `needs` (optional list of step ids)
- `execution` (optional `host`|`target`, default `target`) — use `host` for code-gen steps like `prepare_cross_compiling`

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
| `init` | Generate an initial `native_prebuilt.yaml` scaffold from `pubspec.yaml` |
| `plan --target <platform>` | Show build plan and recipe steps |
| `build --target <platform> --output <dir>` | Build native library from declarative recipes |
| `cache-key --target <platform>` | Show cache key |
| `explain-cache --target <platform>` | Explain cache state |
| `verify --target <platform>` | Verify built artifact (legacy); also `verify --ref <tag> [--config] [--manifest] [--release-assets-dir] [--ephemeral] [--target]` for isolated download + triple check |
| `manifest update [--strict]` | Generate/refresh Dart manifest or lock YAML. `--strict` rejects flat `built-library/<name>` layout |
| `manifest verify` | Verify manifest hashes |
| `manifest verify-release` | Verify `release-assets/` and `built-library/` hashes + binary triple vs lock/g.dart |
| `schema export` | Write the JSON schema copy used by editors |
| `fetch` | Download prebuilt artifacts |
| `doctor [--manifest] [--built-library-dir] [--release-assets-dir] [--target] [--strict]` | Summary + drift/hash/triple checks. Exit 2 on drift with `manifest update --tag` hint |
| `workflow init` | Generate GitHub/GitLab CI workflows (Node24: `checkout@v5`, `upload@v6`, `download@v7`, `gh-release@v3`) |

`init` creates a manifest without overwriting an existing file unless `--force`
is passed. Use `--package`, `--library-stem`, `--asset-name`, `--platform`, and
source/release options to make the scaffold non-interactive. Add the declarative
`build.recipes` for the native source build, then use `dart run native_prebuilt`
for build, manifest, and workflow commands.

`workflow init` writes 5 GitHub workflow files (now with `merge` + `doctor` + `verify-consumer` → `update-manifest` → `release` and `concurrency: native-prebuilt-release`), or 8 GitLab files by default. Use `--gitlab --platform ...` to filter GitLab outputs to selected platforms. The GitHub `prebuilt.yml` now uses `--strict` by default, uploads `merged-built-library`, and verifies archives before release.

`manifest update` prefers `built-library/<platform>/<canonicalName>` with recursive `platform/**/*` fallback; flat `built-library/<name>` emits `Warning: using flat layout…` and fails under `--strict`.

## Platform toolchains

Auto-detected from environment via `NativeToolchainResolver`:
- **Android NDK** — `ANDROID_NDK_HOME`/`ANDROID_NDK`/`ANDROID_HOME/ndk/*` → auto `android.toolchain.cmake`, `ANDROID_ABI`/`STL`/`PLATFORM`, `llvm-strip` from `toolchains/llvm/prebuilt/<host>/bin/`
- **Apple SDK** — `xcrun strip` for `ios`/`macos`
- **MSVC** — Visual Studio installation (strip fallback chain)
- **vcpkg** — `VCPKG_ROOT`

Omit `toolchain_file`/`ANDROID_ABI` in YAML to rely on auto-injection; override only when custom.

## Presets and dependencies

For simple libraries, use the preset instead of listing every step:

```yaml
build:
  system: cmake
  source_directory: "{{ source.path }}"
  target: foo        # becomes cmake_configure + cmake_build(foo) + export_artifact
```

`system: cargo|meson|autotools|zig|custom` are planned under the same hook. Complex projects should continue with `build.recipes[].steps` and `execution: host|target` for multi-stage builds (e.g., `prepare_cross_compiling` as `host`). Dependencies build independently and are cached:

```yaml
dependencies:
  openssl:
    source: {type: git, repository: https://github.com/openssl/openssl, revision: OpenSSL_1_1_1w}
    build: {preset: openssl}
    targets: inherit
# then: OPENSSL_ROOT_DIR: "{{ dependencies.openssl.prefix }}"
```

Use `expect: {targets: [tdjson]}` on `cmake_configure` to fail fast when CMake does not generate the required target (surfaces `Could NOT find OpenSSL` instead of later `unknown target tdjson`).

`init` now scans `CMakeLists.txt`/`Cargo.toml`/`meson.build`/`*.c`/`@Native` to suggest `platforms` and `build.system`.

## Caching

Build steps are cached using content-based fingerprints (including `execution`/`expectTargets`):
- Same inputs → cache hit (skip build)
- Changed source/toolchain → cache miss (rebuild)
- Cache stored in `.dart_tool/native_prebuilt/build-cache/`
- Host steps (`execution: host`) cached separately from target steps

## License

MIT
