# Changelog

## 0.4.0

- Add ELF architecture validation in `NativeBinaryInspector`.
  - Reads the `e_machine` field from ELF headers with proper endianness handling.
  - Validates ARM, AArch64, x86, and x86-64 architectures.
  - Throws `BinaryArchitectureException` with diagnostic messages on mismatch.
- Add Mach-O architecture validation in `NativeBinaryInspector`.
  - Reads the `cputype` field from Mach-O headers.
  - Validates ARM, ARM64, x86, and x86_64 architectures.
- Update test utilities to generate proper ELF and Mach-O headers with architecture fields.
- Add comprehensive tests for architecture validation including mismatch detection.

## 0.3.2

- Honor the hook's requested static or dynamic link mode when resolving manifests.
- Fall back to source builds when a requested static payload has no matching prebuilt.

## 0.3.1

- Add `native_prebuilt init` to scaffold a manifest from package metadata.
- Expose target, library, directory, source, hook, and custom option values to Liquid recipes.
- Add manifest-level shared `variables.*` values with recursive Liquid expansion.
- Treat dynamic artifact payloads as the default in declarative manifests.
- Select the effective payload/link mode from target artifact declarations.

## 0.3.0

- Add native_prebuilt.lock.yaml support and automatic lock overlay detection.
- Allow manifest updates to emit lock YAML in addition to Dart manifests.
- Update TDLib to consume the checked-in lock file instead of a generated g.dart manifest.

## 0.2.1

- Resolve built libraries from nested platform output directories when generating manifests.
- Keep flat built-library layouts working for backward compatibility.

## 0.2.0

- Add hook/build.dart fallback for packages without declarative recipes.
- Standardize hook fallback output using the manifest artifact payload when available.
- Improve CLI errors when neither native_prebuilt.yaml nor hook/build.dart exist.

## 0.0.13

- Generate platform-filtered GitHub `prebuilt.yml` from manifest artifact labels.
- Stop publishing the generated manifest file as a GitHub release asset.

## 0.0.12

- Stop publishing the generated manifest file as a GitHub release asset.

## 0.0.11

- Generate package-specific workflow filenames, manifest outputs, and tag prefixes.
- Add generated `publish.yml` scaffolds for pub.dev release publishing.
- Refresh the README and CLI skill docs for the new workflow layout.

## 0.0.10

- Publish GitLab release assets from the generated GitLab pipeline.
- Upload release archives to the GitLab generic package registry and link them from the release.
- Generate manifest updates with a dedicated release-assets directory for both GitHub and GitLab workflows.

## 0.0.9

- Generate and upload release asset archives alongside the manifest.
- Publish the repo-level GitHub release assets from the generated workflow.
- Allow `manifest update` to write release archives into a dedicated directory.

## 0.0.8

- Make the generated `prebuilt.yml` download and merge all desktop built libraries before manifest generation.
- Keep the repo-level workflow aligned with the reusable templates.
- Continue using manifest-driven GitLab scaffolds and visible built-library staging.

## 0.0.7

- Make workflow scaffolds manifest-driven for GitLab.
- Stage built libraries into `built-library/` before manifest generation.
- Allow `workflow init` to filter selected platforms while defaulting to the manifest artifact set.
- Update reusable update-manifest workflow inputs to accept a built-library directory.

## 0.0.6

- Add scaffolded GitLab build templates for macOS, Windows, Android, and iOS.
- Keep GitLab multi-platform jobs opt-in while Linux remains the default validation path.
- Preserve manifest-before-release generation from built libraries.

## 0.0.5

- Generate GitLab manifest updates from built libraries before the release job runs.
- Package built native libraries locally during manifest generation.
- Keep GitLab release/update jobs tag-scoped so branch pipelines stay green.

## 0.0.4

- Fix GitLab CI templates to upload the native asset output directory instead of a missing `build/` folder.
- Keep GitLab release/update jobs tag-scoped so branch pipelines stay green.

## 0.0.3

- Fix GitLab CI templates to use a valid Dart Docker-based workflow.
- Use `dart test` for CI validation instead of calling `hook/build.dart` directly.

## 0.0.2

- Add GitLab release-source support.
- Generate GitLab CI templates from the CLI.
- Improve release-source abstraction and downloader handling.

## 0.0.1

- Initial alpha release.
- Build-hook integration for prebuilt native assets.
- Manifest generation, download/cache/install, validation, and CLI tooling.
- Example package and reusable workflow templates.
- GitHub and GitLab release-source support.
