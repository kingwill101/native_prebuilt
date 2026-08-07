# Release checklist

## Before publishing

- [ ] Bump `pubspec.yaml` version (alpha starts at `0.0.1`)
- [ ] Run `dart analyze`
- [ ] Run `dart test` (expect `All tests passed!`)
- [ ] Run `dart run native_prebuilt manifest verify-release --config example/.../native_prebuilt.yaml` if example has release-assets
- [ ] Run `dart run native_prebuilt doctor --config native_prebuilt.yaml --strict` (exit 0)
- [ ] Run `dart run bin/native_prebuilt.dart --help`
- [ ] Run `dart pub publish --dry-run`
- [ ] Verify README install snippets (`native_prebuilt: ^0.4.0`) and public URLs
- [ ] Verify example package builds locally (if applicable)
- [ ] Regenerate `schema/native_prebuilt.schema.json` via `dart run build_runner build` if `build_step_config.dart` changed

## Publish

- [ ] `git tag v0.4.0`
- [ ] `git push origin main --tags`
- [ ] `dart pub publish`

## After publish

- [ ] Update the e2e repo dependency to `native_prebuilt: ^0.4.0`
- [ ] `dart pub get` in the e2e repo
- [ ] Run the e2e hook build / smoke tests
- [ ] Create the first GitHub release in the private e2e repo
- [ ] Confirm prebuilt resolution works from pub.dev
