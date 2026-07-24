import 'dart:io';

import '../platform/native_target.dart';

/// Result of a native build operation.
///
/// Contains the built artifacts and optional metadata about the build.
final class NativeBuildResult {
  const NativeBuildResult({required this.artifacts, this.metadata = const {}});

  /// The native artifacts produced by the build.
  final List<BuiltNativeArtifact> artifacts;

  /// Optional metadata about the build (e.g., build duration, toolchain versions).
  final Map<String, Object?> metadata;
}

/// A built native artifact ready for packaging.
///
/// Represents a compiled native library or binary with all metadata needed
/// for packaging and deployment.
final class BuiltNativeArtifact {
  const BuiltNativeArtifact({
    required this.file,
    required this.type,
    required this.target,
    this.runtimeDependencies = const [],
    this.debugSymbols,
    this.importLibrary,
  });

  /// The built file (e.g., libtdjson.so, tdjson.dll, libtdjson.dylib).
  final File file;

  /// The type of artifact (dynamic library, static library, executable, etc.).
  final NativeArtifactType type;

  /// The target platform this artifact was built for.
  final NativeTarget target;

  /// Runtime dependencies (e.g., libc++, OpenSSL) that must be bundled.
  final List<File> runtimeDependencies;

  /// Optional debug symbols file (e.g., .dSYM, .pdb, or separate .debug file).
  final File? debugSymbols;

  /// Optional import library for Windows DLLs (.lib file).
  final File? importLibrary;
}

/// Type of native artifact produced by a build.
enum NativeArtifactType {
  /// Dynamic/shared library (.so, .dylib, .dll)
  dynamicLibrary,

  /// Static library (.a, .lib)
  staticLibrary,

  /// Executable binary
  executable,

  /// Object file (.o, .obj)
  objectFile,
}
