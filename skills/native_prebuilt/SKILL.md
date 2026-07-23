# native_prebuilt CLI

Use this skill when you need to generate manifests, workflow scaffolds, or release assets for a Dart package that ships prebuilt native libraries.

## Core commands

- `dart run native_prebuilt manifest update`
  - Generates the checked-in manifest file from `native_prebuilt.yaml`.
  - Supports `--built-library-dir` and `--release-assets-dir`.
  - This is the only supported way to refresh `archiveSha256` and `payloadSha256`.
- `dart run native_prebuilt manifest verify`
  - Recomputes the manifest and checks it against the checked-in file.
- `dart run native_prebuilt fetch`
  - Downloads one release asset for a platform into a local directory.
- `dart run native_prebuilt workflow init`
  - Generates GitHub workflow files (`prebuilt.yml`, `publish.yml`, reusable templates).
- `dart run native_prebuilt workflow init --gitlab`
  - Generates GitLab CI files based on the platforms declared in `native_prebuilt.yaml`.

## Workflow rules

- The manifest config (`native_prebuilt.yaml`) is the source of truth for package name, release source, and artifact labels.
- Generated GitHub workflows should use package-specific filenames and tag patterns.
- Release asset archives are written to `release-assets/` during manifest generation.
- Checked-in manifests should live under `lib/src/hook/<package>_prebuilts.g.dart`.

## Typical release flow

1. Build native libraries.
2. Run `manifest update` to generate the manifest and release archives.
3. Publish release assets from the generated workflow.
4. Tag the release and verify consumers can fetch from the published assets.
