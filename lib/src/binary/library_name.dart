import 'package:code_assets/code_assets.dart';

import '../manifest/prebuilt_artifact.dart';
import '../platform/native_target.dart';

/// Returns the canonical dynamic library filename for a target and stem.
///
/// Example: `canonicalDynamicLibraryName(NativeTarget(...), 'mylib')`
/// returns `libmylib.so` on Linux, `libmylib.dylib` on macOS,
/// and `mylib.dll` on Windows.
String canonicalDynamicLibraryName(NativeTarget target, String libraryStem) {
  return target.os.libraryFileName(libraryStem, DynamicLoadingBundled());
}

/// Returns the canonical static library filename for a target and stem.
///
/// On Apple platforms, follows the `lib<stem>.a` convention.
String canonicalStaticLibraryName(NativeTarget target, String libraryStem) {
  return target.os.libraryFileName(libraryStem, StaticLinking());
}

/// Returns the canonical library filename for a payload type.
String canonicalLibraryName({
  required NativeTarget target,
  required String libraryStem,
  required ArtifactPayload payload,
}) {
  return switch (payload) {
    DynamicLibraryPayload() => canonicalDynamicLibraryName(target, libraryStem),
    StaticLibraryPayload() => canonicalStaticLibraryName(target, libraryStem),
  };
}

/// Whether the given filename matches a canonical library name, including
/// versioned variants like `libfoo.so.1.2`.
bool matchesLibraryName(
  String basename, {
  required String canonicalName,
  required bool acceptVersionedNames,
}) {
  if (basename == canonicalName) return true;

  if (!acceptVersionedNames) return false;

  // Match versioned .so: libfoo.so.1, libfoo.so.1.2.3
  if (canonicalName.endsWith('.so')) {
    return basename.startsWith('$canonicalName.');
  }

  // Match versioned .dylib: libfoo.1.2.3.dylib
  if (canonicalName.endsWith('.dylib')) {
    final stem = canonicalName.substring(
      0,
      canonicalName.length - '.dylib'.length,
    );
    return basename.startsWith('$stem.') && basename.endsWith('.dylib');
  }

  return false;
}

/// Ranks library name matches for deterministic selection.
///
/// Exact matches rank first, followed by versioned variants.
int libraryMatchRank(String basename, String canonicalName) {
  if (basename == canonicalName) return 0;

  if (canonicalName.endsWith('.so') && basename.startsWith('$canonicalName.')) {
    return 1;
  }

  if (canonicalName.endsWith('.dylib') && basename.endsWith('.dylib')) {
    final stem = canonicalName.substring(
      0,
      canonicalName.length - '.dylib'.length,
    );
    if (basename.startsWith('$stem.')) return 1;
  }

  return 2;
}

/// Whether the [name] appears to be a static library archive.
bool isStaticArchiveName(String name) => name.endsWith('.a');

/// Whether the [name] appears to be a WebAssembly module.
bool isWasmName(String name) => name.endsWith('.wasm');
