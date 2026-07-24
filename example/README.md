# native_prebuilt Examples

This directory contains examples demonstrating different approaches to using native_prebuilt.

## Examples

### 1. `managed_build/` - Declarative Managed Build (Recommended)
**Approach**: Uses `NativeProject` with `nativePrebuiltBuild` hook entry point.

- **Declarative**: Project defined as a `NativeProject` data structure
- **Managed**: Build orchestration handled by `NativeProjectBuilder`
- **Recipe-based**: Uses `StepBuildRecipe` with `CmakeConfigureStep` + `CmakeBuildStep`
- **Toolchain integration**: Works with `native_toolchain_c` and other toolchains

**Files**:
- `lib/src/hook/managed_build_project.dart` - Declarative project definition
- `hook/build.dart` - Simple entry point using `nativePrebuiltBuild`

### 2. `callback_source_builder/` - Legacy Callback + CBuilder
**Approach**: Uses `PrebuiltCodeAssetBuilder` with `native_toolchain_c`'s `CBuilder` as source fallback.

- **Hybrid**: Prebuilt resolution via native_prebuilt + source fallback via native_toolchain_c
- **Callback pattern**: Uses legacy `SourceBuilder` function signature
- **Good for**: Migration from older packages or when using CBuilder directly

**Files**:
- `hook/build.dart` - Uses `PrebuiltCodeAssetBuilder` with `CBuilder` as `sourceBuilder`
- `lib/src/hook/callback_source_builder_prebuilts.dart` - Prebuilt manifest

## Comparison

| Aspect | Managed Build | Callback + CBuilder |
|--------|---------------|---------------------|
| Project definition | Declarative `NativeProject` | Inline in hook |
| Build orchestration | Managed (`NativeProjectBuilder`) | Manual via `PrebuiltCodeAssetBuilder` |
| Build recipes | `StepBuildRecipe` + steps | `CBuilder` handles build |
| Toolchain | Configurable via recipes | Fixed to CBuilder's toolchain |
| Extensibility | Add custom steps/recipes | Limited to CBuilder options |
| Migration path | Recommended for new projects | For existing CBuilder users |

## Running the Examples

```bash
# For managed_build
cd example/managed_build
dart pub get
dart run tool/native_prebuilt.dart plan --target linux-x64
dart run tool/native_prebuilt.dart build --target linux-x64

# For callback_source_builder
cd example/callback_source_builder
dart pub get
# Build hook runs automatically during code generation
```

## Building for Other Platforms

Both examples can be extended to support more platforms by adding entries to:
- `NativeProject.build.recipes` (managed build)
- `native_prebuilt.yaml` artifacts (callback source builder)
