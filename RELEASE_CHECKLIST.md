# Release checklist

## Before publishing

- [ ] Bump `pubspec.yaml` version (alpha starts at `0.0.1`)
- [ ] Run `dart analyze`
- [ ] Run `dart test`
- [ ] Run `dart run bin/native_prebuilt.dart --help`
- [ ] Run `dart pub publish --dry-run`
- [ ] Verify README install snippets and public URLs
- [ ] Verify example package builds locally (if applicable)

## Publish

- [ ] `git tag v0.0.1`
- [ ] `git push origin main --tags`
- [ ] `dart pub publish`

## After publish

- [ ] Update the e2e repo dependency to `native_prebuilt: ^0.0.1`
- [ ] `dart pub get` in the e2e repo
- [ ] Run the e2e hook build / smoke tests
- [ ] Create the first GitHub release in the private e2e repo
- [ ] Confirm prebuilt resolution works from pub.dev
