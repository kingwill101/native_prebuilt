# Changelog

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
