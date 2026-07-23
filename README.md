# native_prebuilt

Reusable infrastructure for Dart packages that ship prebuilt native libraries from GitHub or GitLab releases.

## What it provides

- `PrebuiltCodeAssetBuilder` for `hook/build.dart`
- `PrebuiltManifest` / `PrebuiltArtifact` immutable release metadata
- `ArtifactInstaller` for download → verify → extract → validate → cache
- `PrebuiltResolver` chain for override / local / cached / downloaded prebuilts
- `NativeBinaryInspector` and library-name helpers
- CLI tooling for manifest generation, fetch, verification, and workflow templates
- Reusable GitHub Actions and pub.dev workflow templates

## Install

```yaml
dependencies:
  native_prebuilt: ^0.0.11
```

## Hook usage

```dart
import 'package:hooks/hooks.dart';
import 'package:native_prebuilt/hooks.dart';
import 'package:my_package/src/hook/my_package_prebuilts.g.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    await PrebuiltCodeAssetBuilder(
      assetName: 'my_bindings.dart',
      libraryStem: 'mylib',
      manifest: myPrebuilts,
      linkModeResolver: (_) => DynamicLoadingBundled(),
      fallback: CallbackBuilder((input, output) async {
        // build from source
      }),
    ).run(input: input, output: output, logger: null);
  });
}
```

## Manifest format

`native_prebuilt` expects a YAML config file like:

```yaml
schema: 1
package: my_package
asset_name: my_bindings.dart
library_stem: mylib
release:
  provider: github
  repository: myorg/myrepo
  tag: mylib-v1.0.0
artifacts:
  linux-x64:
    archive: mylib-linux-x64.tar.gz
    payload:
      type: dynamic_library
```

Use:

```bash
dart run native_prebuilt manifest update \
  --config native_prebuilt.yaml \
  --output lib/src/hook/my_package_prebuilts.g.dart \
  --built-library-dir built-library \
  --release-assets-dir release-assets \
dart run native_prebuilt manifest verify \
  --config native_prebuilt.yaml \
  --output lib/src/hook/my_package_prebuilts.g.dart \
  --built-library-dir built-library \
  --release-assets-dir release-assets
```

## Fetch locally

```bash
dart run native_prebuilt fetch --config native_prebuilt.yaml --platform linux-x64
```

## GitHub Actions

```bash
dart run native_prebuilt workflow init
```

Generates into `.github/workflows/`:

| File | Purpose |
|------|---------|
| `prebuilt.yml` | Builds native libraries on every platform, generates manifest + release assets on tag pushes |
| `publish.yml` | Publishes to pub.dev on `v*` tags |
| `native-prebuilt-build.yml` | Reusable build workflow (called by `prebuilt.yml`) |
| `native-prebuilt-release.yml` | Reusable release workflow |
| `native-prebuilt-update-manifest.yml` | Reusable manifest generation workflow |

Tag triggers are package-specific (e.g. `my_package-v*`). On tag push:

1. `build-linux`, `build-windows`, `build-macos` jobs compile native code and upload artifacts
2. `update-manifest` downloads all artifacts, generates the manifest, and creates release archives
3. `release` publishes archives to GitHub Releases via `softprops/action-gh-release`

The set of build jobs is automatically filtered to match the platforms declared in `native_prebuilt.yaml`.

### Releasing

```bash
git tag my_package-v1.0.0
git push origin my_package-v1.0.0
```

This triggers `prebuilt.yml` which builds, generates the manifest, and publishes release assets.

## GitLab CI

```bash
dart run native_prebuilt workflow init --gitlab
```

Generates into `.gitlab-ci.yml` and `.gitlab/ci/`:

| File | Purpose |
|------|---------|
| `.gitlab-ci.yml` | Root pipeline — stages platform build jobs, manifest generation, and release |
| `.gitlab/ci/native-prebuilt-build-<platform>.yml` | Per-platform build job |
| `.gitlab/ci/native-prebuilt-release.yml` | Uploads release assets to GitLab Generic Package Registry |
| `.gitlab/ci/native-prebuilt-update-manifest.yml` | Generates manifest and release archives |

Platforms are determined by the `artifacts:` section in `native_prebuilt.yaml`. Only declared platforms get build jobs.

### GitLab release source

For packages hosted on GitLab, set the release source in `native_prebuilt.yaml`:

```yaml
release:
  provider: gitlab
  project: mygroup/myproject
  tag: my_package-v1.0.0
```

### Releasing on GitLab

```bash
git tag my_package-v1.0.0
git push origin my_package-v1.0.0
```

This triggers the GitLab pipeline which builds, generates the manifest, and uploads release assets to the GitLab Generic Package Registry.

## Local overrides

Resolution chain: `user_defines` → `.prebuilt/` directory → shared cache →
download from release. The first hit wins.

### Option 1: `hooks.user_defines` (per-project override)

In your consumer package's `pubspec.yaml`:

```yaml
hooks:
  user_defines:
    my_package:
      prebuilt_path: /absolute/path/to/libmy_package.so
```

The key is the package name. `prebuilt_path` is the default key read by
`UserDefinePrebuiltResolver`. If the file exists, it is used directly.

### Option 2: `.prebuilt/` directory (per-build override)

Drop a library into `.prebuilt/<platform>/` next to your `pubspec.yaml`:

```
my_package/
  .prebuilt/
    linux-x64/
      libmy_package.so
    windows-x64/
      my_package.dll
    macos-arm64/
      libmy_package.dylib
  pubspec.yaml
```

The subdirectory must match the platform label from your manifest (e.g.
`linux-x64`, `macos-arm64`). `LocalPrebuiltResolver` picks up any matching
library without extra config.

## Platforms

Platforms are declared in `native_prebuilt.yaml` under `artifacts:`. Each key is
a platform label in the form `<os>-<arch>` (e.g. `linux-x64`, `macos-arm64`,
`windows-x64`).

Minimal form — `archive` and `payload.type` default automatically:

```yaml
artifacts:
  linux-x64:
  linux-arm64:
  macos-arm64:
```

Defaults:
- `archive` → `<package>-<platform>.tar.gz` (e.g. `my_package-linux-x64.tar.gz`)
- `payload.type` → `dynamic_library`

Explicit form when you need custom names:

```yaml
artifacts:
  linux-x64:
    archive: custom-name-linux-x64.tar.gz
    payload:
      type: dynamic_library
  linux-arm64:
    archive: custom-name-linux-arm64.tar.gz
    payload:
      type: static_library
```

### Supported platform labels

| OS | Architectures |
|----|---------------|
| `linux` | `x64`, `arm64` |
| `macos` | `x64`, `arm64` |
| `windows` | `x64`, `arm64` |
| `android` | `x64`, `arm64`, `armv7` |
| `ios` | `arm64` |

### Adding a platform

Add an entry to `artifacts:` and regenerate:

```yaml
artifacts:
  linux-x64:
    archive: my_package-linux-x64.tar.gz
    payload:
      type: dynamic_library
  linux-arm64:                          # ← new
    archive: my_package-linux-arm64.tar.gz
    payload:
      type: dynamic_library
```

Then regenerate workflows and the manifest:

```bash
dart run native_prebuilt workflow init --config native_prebuilt.yaml
dart run native_prebuilt manifest update \
  --config native_prebuilt.yaml \
  --output lib/src/hook/my_package_prebuilts.g.dart \
  --built-library-dir .dart_tool/lib
```

The regenerated `prebuilt.yml` will automatically include a `build-linux-arm64`
job. GitLab CI will include a `native-prebuilt-build-linux.yml` job.

### Removing a platform

Delete the entry from `artifacts:` and regenerate. The build job for that
platform will be removed from the CI configs.

### Filtering platforms at generation time

Use `--platform` to scaffold only a subset of the declared platforms:

```bash
dart run native_prebuilt workflow init --platform linux --platform macos
```

This is useful when you only want to generate CI for the platforms you can
test locally. The manifest still contains all platforms — `--platform` only
affects which CI jobs are generated.

## Using with different hook builders

`PrebuiltCodeAssetBuilder` accepts any `Builder` as `fallback`. When no prebuilt
is found for the current platform, the fallback runs automatically.

### CBuilder (C/C++)

Uses [`native_toolchain_c`](https://pub.dev/packages/native_toolchain_c):

```dart
import 'package:hooks/hooks.dart';
import 'package:native_prebuilt/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:my_package/src/hook/my_package_prebuilts.g.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    await PrebuiltCodeAssetBuilder(
      assetName: 'src/my_package.dart',
      libraryStem: 'my_package',
      manifest: myPackagePrebuilts,
      linkModeResolver: (code) => DynamicLoadingBundled(),
      fallback: CBuilder.library(
        name: 'my_package',
        packageName: input.packageName,
        assetName: 'src/my_package.dart',
        sources: const ['src/native/my_package.c'],
      ),
    ).run(input: input, output: output, logger: null);
  });
}
```

### RustBuilder

Uses [`native_toolchain_rust`](https://pub.dev/packages/native_toolchain_rust).
Requires a `Cargo.toml` with `crate-type = ["staticlib", "cdylib"]` and a
`rust-toolchain.toml` pinned to a specific version.

```dart
import 'package:hooks/hooks.dart';
import 'package:native_prebuilt/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';
import 'package:my_package/src/hook/my_package_prebuilts.g.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    await PrebuiltCodeAssetBuilder(
      assetName: 'src/my_package.dart',
      libraryStem: 'my_package',
      manifest: myPackagePrebuilts,
      linkModeResolver: (code) => DynamicLoadingBundled(),
      fallback: RustBuilder(
        assetName: 'src/my_package.dart',
      ),
    ).run(input: input, output: output, logger: null);
  });
}
```

### CallbackBuilder (inline source build)

```dart
await PrebuiltCodeAssetBuilder(
  assetName: 'src/my_package.dart',
  libraryStem: 'my_package',
  manifest: myPackagePrebuilts,
  linkModeResolver: (code) => DynamicLoadingBundled(),
  fallback: CallbackBuilder((input, output) async {
    // Your custom build logic here.
  }),
).run(input: input, output: output, logger: null);
```

## Notes

- Use `release.provider: gitlab` and `release.project` for GitLab release assets.
- `workflow init --platform ...` is repeatable; omit it to scaffold the platforms declared in the manifest.
- Generated GitHub workflows derive filenames and tag prefixes from `package:` in `native_prebuilt.yaml`.
- Generated GitLab scaffolds stage built libraries in `built-library/` and use the manifest to decide which platform jobs to emit.
- The package exports `OS`, `Architecture`, and `IOSSdk` from `code_assets`.
- The cache and installer are designed for repeated hook runs and concurrent builds.
