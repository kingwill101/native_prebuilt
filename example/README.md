# native_prebuilt example

This is a full end-to-end example of:

- `hooks` build hooks
- `native_prebuilt` release metadata + prebuilt resolution
- fallback native compilation with `native_toolchain_c`
- release-manifest generation via the `native_prebuilt` CLI

## File layout

```text
example/
├── pubspec.yaml
├── native_prebuilt.yaml
├── hook/build.dart
├── lib/src/hook/demo_prebuilts.g.dart
└── src/native/demo.c
```

## How it works

1. `hook/build.dart` runs `PrebuiltCodeAssetBuilder`.
2. It first tries:
   - `hooks.user_defines`
   - local `.prebuilt/`
   - GitHub Release download
3. If no prebuilt is available, it falls back to `native_toolchain_c` and builds `src/native/demo.c`.
4. On release, you generate the manifest from `native_prebuilt.yaml` and publish the matching GitHub Release artifacts.

## Commands

Generate/update the manifest:

```bash
cd example
dart run native_prebuilt manifest update \
  --config native_prebuilt.yaml \
  --output lib/src/hook/demo_prebuilts.g.dart
```

Verify it:

```bash
dart run native_prebuilt manifest verify \
  --config native_prebuilt.yaml \
  --output lib/src/hook/demo_prebuilts.g.dart
```

Fetch a prebuilt locally:

```bash
dart run native_prebuilt fetch \
  --config native_prebuilt.yaml \
  --platform linux-x64
```

Generate workflow templates:

```bash
dart run native_prebuilt workflow init
```

## Notes

- The checked-in hashes are placeholders; this example still works because the fallback C build will run when prebuilt downloads are unavailable.
- Replace the placeholder release metadata and hashes with the values for your real release before publishing.
- The native source is intentionally tiny (`return 42;`) so the example stays readable.
