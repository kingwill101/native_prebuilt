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

## Workflow templates

GitHub Actions:

```bash
dart run native_prebuilt workflow init
```

This writes a repo-level `prebuilt.yml` workflow, a `publish.yml` pub.dev workflow,
and the reusable workflow templates. The generated tag trigger is package-specific
(e.g. `my_package-v*`) and tag runs publish GitHub release assets.

GitLab CI generated from the same command uploads GitLab release assets too:

```bash
dart run native_prebuilt workflow init --gitlab --config native_prebuilt.yaml
```

GitLab CI (defaults to the platforms declared in `native_prebuilt.yaml`):

```bash
dart run native_prebuilt workflow init --gitlab --config native_prebuilt.yaml
```

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

## Adding / removing platforms

Platforms are declared in `native_prebuilt.yaml` under `artifacts:`. Add a
new entry to support a platform, remove one to stop shipping it:

```yaml
schema: 1
package: my_package
asset_name: src/my_package.dart
library_stem: my_package
release:
  provider: github
  repository: owner/repo
  tag: my_package-v1.0.0
artifacts:
  linux-x64:
    archive: my_package-linux-x64.tar.gz
    payload:
      type: dynamic_library
  linux-arm64:                              # ← add
    archive: my_package-linux-arm64.tar.gz
    payload:
      type: dynamic_library
  # macos-x64:                              # ← remove by deleting
  #   archive: my_package-macos-x64.tar.gz
  #   payload:
  #     type: dynamic_library
```

After editing, regenerate workflows and the manifest:

```bash
dart run native_prebuilt workflow init --config native_prebuilt.yaml
dart run native_prebuilt manifest update \
  --config native_prebuilt.yaml \
  --output lib/src/hook/my_package_prebuilts.g.dart \
  --built-library-dir .dart_tool/lib
```

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
