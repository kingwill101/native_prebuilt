# native_prebuilt

Reusable infrastructure for Dart packages that ship prebuilt native libraries from GitHub or GitLab releases.

## What it provides

- `PrebuiltCodeAssetBuilder` for `hook/build.dart`
- `PrebuiltManifest` / `PrebuiltArtifact` immutable release metadata
- `ArtifactInstaller` for download → verify → extract → validate → cache
- `PrebuiltResolver` chain for override / local / cached / downloaded prebuilts
- `NativeBinaryInspector` and library-name helpers
- CLI tooling for manifest generation, fetch, verification, and workflow templates
- Reusable GitHub Actions workflow templates

## Install

```yaml
dependencies:
  native_prebuilt: ^0.0.6
```

## Hook usage

```dart
import 'package:hooks/hooks.dart';
import 'package:native_prebuilt/hooks.dart';
import 'package:my_package/src/hook/prebuilts.g.dart';

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
dart run native_prebuilt manifest update --config native_prebuilt.yaml --output lib/src/hook/prebuilts.g.dart
dart run native_prebuilt manifest verify --config native_prebuilt.yaml --output lib/src/hook/prebuilts.g.dart
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

GitLab CI (Linux by default, with opt-in macOS/Windows/Android/iOS scaffolds):

```bash
dart run native_prebuilt workflow init --gitlab
```

## Notes

- `hooks.user_defines` is preferred for local override paths.
- Use `release.provider: gitlab` and `release.project` for GitLab release assets.
- The package exports `OS`, `Architecture`, and `IOSSdk` from `code_assets`.
- The cache and installer are designed for repeated hook runs and concurrent builds.
