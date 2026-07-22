# Changelog

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
