# native_prebuilt

Reusable infrastructure for Dart packages that build, cache, and ship native libraries through Dart hooks.

## What it provides

- **NativeProject** — Declarative project definition with build recipes
- **StepBuildRecipe** — Multi-stage build pipelines with fingerprinting
- **Build cache** — Step-level caching with content-based fingerprints
- **Platform toolchains** — Auto-detection for Android NDK, Apple SDK, MSVC, vcpkg
- **NativeProjectBuilder** — High-level build orchestration
- **CLI tools** — Build, plan, cache inspection, and workflow generation
- **Test fixtures** — CMake projects for testing native builds

## Install

```yaml
dependencies:
  native_prebuilt: ^0.0.13
```

## Quick start

### Define your project

```dart
import 'package:code_assets/code_assets.dart';
import 'package:native_prebuilt/native_prebuilt.dart';

final myProject = NativeProject(
  name: 'my_package',
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
      OS.macOS: StepBuildRecipe(steps: [
        CmakeConfigureStep(buildDirectory: 'build'),
        CmakeBuildStep(buildDirectory: 'build', targets: ['my_native']),
        ExportArtifactStep(artifactPath: 'build/libmy_native.dylib'),
      ]),
      OS.windows: StepBuildRecipe(steps: [
        CmakeConfigureStep(buildDirectory: 'build'),
        CmakeBuildStep(buildDirectory: 'build', targets: ['my_native']),
        ExportArtifactStep(artifactPath: 'build/my_native.dll'),
      ]),
    },
  ),
);
```

### Use in your hook

```dart
// hook/build.dart
import 'package:hooks/hooks.dart';
import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:my_package/src/my_project.dart';

Future<void> main(List<String> args) {
  return runNativeProjectCli(args, project: myProject);
}
```

### Use in CI

```bash
dart run native_prebuilt plan --target linux-x64
dart run native_prebuilt build --target linux-x64 --output built-library
dart run native_prebuilt cache-key --target linux-x64
dart run native_prebuilt explain-cache --target linux-x64
```

## Build steps

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

## Multi-stage builds

For complex builds like TDLib (OpenSSL + code generation + cross-compilation):

```dart
final tdlibProject = NativeProject(
  name: 'tdlib',
  asset: const NativeAssetSpec(
    assetName: 'src/tdlib.g.dart',
    libraryStem: 'tdjson',
    linkMode: DynamicLoadingBundled(),
  ),
  build: NativeBuildDefinition(
    recipes: {
      OS.linux: StepBuildRecipe(steps: [
        CmakeConfigureStep(
          buildDirectory: 'build',
          defines: {'CMAKE_C_COMPILER_LAUNCHER': 'sccache'},
        ),
        CmakeBuildStep(buildDirectory: 'build', targets: ['tdjson']),
        ExportArtifactStep(artifactPath: 'build/td/libtdjson.so'),
      ]),
      OS.android: StepBuildRecipe(steps: [
        // Step 1: Build OpenSSL
        CommandStep(
          id: 'build-openssl',
          commands: [['make', 'OpenSSL-android']],
        ),
        // Step 2: Configure TDLib
        CmakeConfigureStep(
          buildDirectory: 'build',
          defines: {
            'ANDROID_ABI': 'arm64-v8a',
            'ANDROID_STL': 'c++_static',
          },
        ),
        // Step 3: Build TDLib
        CmakeBuildStep(buildDirectory: 'build', targets: ['tdjson']),
        // Step 4: Strip symbols
        StripStep(
          inputPath: 'build/td/libtdjson.so',
          outputPath: 'libtdjson.so',
        ),
        // Step 5: Export
        ExportArtifactStep(artifactPath: 'libtdjson.so'),
      ]),
    },
  ),
);
```

## Caching

Build steps are automatically cached using content-based fingerprints:

- Same inputs → cache hit (skip build)
- Changed source, toolchain, or defines → cache miss (rebuild)
- Cache stored in `.dart_tool/native_prebuilt/build-cache/`

```bash
dart run native_prebuilt explain-cache --target linux-x64
# Shows why each step was cached or rebuilt
```

## Platform toolchains

Auto-detected from environment:

| Platform | Detection |
|----------|-----------|
| Android NDK | `ANDROID_NDK_HOME` or SDK path |
| Apple SDK | Xcode paths |
| MSVC | Visual Studio installation |
| vcpkg | `VCPKG_ROOT` |

## Prebuilt resolution

For packages that also ship prebuilt binaries:

```dart
final project = NativeProject(
  name: 'my_package',
  asset: NativeAssetSpec(...),
  prebuilts: PrebuiltManifest(
    schemaVersion: 1,
    release: GitHubReleaseSource(
      owner: 'myorg',
      repository: 'myrepo',
      tag: 'v1.0.0',
    ),
    artifacts: {},
  ),
  sources: [
    GitSource(
      repository: Uri.parse('https://github.com/myorg/myrepo.git'),
      revision: 'abc123...',
    ),
  ],
  build: NativeBuildDefinition(recipes: {...}),
);
```

Resolution order:
1. User-defined override via `hooks.user_defines`
2. Local `.prebuilt/` directory
3. Shared cache (download from release)
4. Source build using recipe

## CLI commands

| Command | Description |
|---------|-------------|
| `plan --target <platform>` | Show build plan |
| `build --target <platform> --output <dir>` | Build native library |
| `cache-key --target <platform>` | Show cache key |
| `explain-cache --target <platform>` | Explain cache state |
| `verify --target <platform>` | Verify built artifact |
| `manifest update` | Generate/refresh manifest |
| `manifest verify` | Verify manifest hashes |
| `workflow init` | Generate CI workflows |

## Test fixtures

Located in `test/fixtures/native_projects/`:

| Fixture | Description |
|---------|-------------|
| `simple_shared/` | Basic shared library |
| `static_library/` | Static library |
| `generated_source/` | Multi-stage with code generation |
| `dependency_graph/` | Library with dependencies |
| `patchable_source/` | Patchable source |
| `failing_build/` | Intentionally broken |

## CI setup

### GitHub Actions

```yaml
# .github/workflows/ci.yml
jobs:
  build:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: dart-lang/setup-dart@v1
      - run: dart pub get
      - run: dart test
```

### GitLab CI

```yaml
# .gitlab-ci.yml
stages:
  - test

test:
  stage: test
  script:
    - dart pub get
    - dart test
  rules:
    - if: $CI_MERGE_REQUEST_IID
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
```

## License

MIT
