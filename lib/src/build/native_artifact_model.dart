import 'dart:io';

import '../platform/native_target.dart';

/// Role of an artifact entry within a native artifact bundle.
enum NativeArtifactRole {
  /// Main file registered with code_assets (the primary library/executable).
  primary,

  /// Library that must accompany the primary library at runtime.
  runtimeDependency,

  /// Windows import library used during linking.
  importLibrary,

  /// Debug symbols (PDB, dSYM, separate .debug file, etc.).
  debugSymbols,

  /// Configuration or data required at runtime.
  resource,

  /// License or attribution file.
  license,
}

/// Kind of native artifact produced by a build.
enum NativeArtifactKind {
  /// Dynamic/shared library (.so, .dylib, .dll).
  dynamicLibrary,

  /// Static library (.a, .lib).
  staticLibrary,

  /// Executable binary.
  executable,

  /// Object file (.o, .obj).
  objectFile,

  /// Can be introduced when directory-based Apple bundles are supported.
  framework,

  /// General directory-style native bundle.
  bundle,
}

/// An entry within a native artifact bundle.
///
/// Each entry represents a file or directory that is part of the deployable
/// artifact bundle, with a specific role and destination path.
final class NativeArtifactEntry {
  const NativeArtifactEntry({
    required this.source,
    required this.path,
    required this.role,
    this.optional = false,
  });

  /// Original output from the build.
  ///
  /// This can be a File or Directory, allowing things such as `.dSYM`
  /// directories to be represented.
  final FileSystemEntity source;

  /// Relative path inside the staged artifact bundle.
  final String path;

  /// Role of this entry within the artifact bundle.
  final NativeArtifactRole role;

  /// Whether this entry is optional (e.g., debug symbols that may not exist).
  final bool optional;

  /// Creates a primary entry from a file.
  factory NativeArtifactEntry.primary({
    required File source,
    required String path,
  }) {
    return NativeArtifactEntry(
      source: source,
      path: path,
      role: NativeArtifactRole.primary,
    );
  }

  /// Creates a runtime dependency entry from a file.
  factory NativeArtifactEntry.runtimeDependency({
    required File source,
    required String path,
  }) {
    return NativeArtifactEntry(
      source: source,
      path: path,
      role: NativeArtifactRole.runtimeDependency,
    );
  }

  /// Creates an import library entry from a file.
  factory NativeArtifactEntry.importLibrary({
    required File source,
    required String path,
  }) {
    return NativeArtifactEntry(
      source: source,
      path: path,
      role: NativeArtifactRole.importLibrary,
    );
  }

  /// Creates a debug symbols entry from a file or directory.
  factory NativeArtifactEntry.debugSymbols({
    required FileSystemEntity source,
    required String path,
    bool optional = true,
  }) {
    return NativeArtifactEntry(
      source: source,
      path: path,
      role: NativeArtifactRole.debugSymbols,
      optional: optional,
    );
  }

  /// Creates a resource entry from a file or directory.
  factory NativeArtifactEntry.resource({
    required FileSystemEntity source,
    required String path,
  }) {
    return NativeArtifactEntry(
      source: source,
      path: path,
      role: NativeArtifactRole.resource,
    );
  }

  /// Creates a license entry from a file.
  factory NativeArtifactEntry.license({
    required File source,
    required String path,
  }) {
    return NativeArtifactEntry(
      source: source,
      path: path,
      role: NativeArtifactRole.license,
    );
  }
}

/// A built native artifact ready for packaging.
///
/// Represents a deployable native artifact bundle with a primary output
/// and optional companion files (runtime dependencies, debug symbols, etc.).
final class BuiltNativeArtifact {
  const BuiltNativeArtifact({
    required this.id,
    required this.target,
    required this.kind,
    required this.primary,
    this.companions = const [],
    this.metadata = const {},
  });

  /// Logical identity within the project.
  ///
  /// Examples:
  /// - tdjson
  /// - sqlite3
  /// - my_package
  final String id;

  /// Platform and architecture this artifact targets.
  final NativeTarget target;

  /// What the primary native output represents.
  final NativeArtifactKind kind;

  /// The library or executable registered as the principal artifact.
  final NativeArtifactEntry primary;

  /// Files/directories that belong to the same deployable bundle.
  final List<NativeArtifactEntry> companions;

  /// Source revision, toolchain versions, build fingerprint, etc.
  final Map<String, Object?> metadata;

  /// All entries in this artifact bundle (primary + companions).
  Iterable<NativeArtifactEntry> get entries sync* {
    yield primary;
    yield* companions;
  }

  /// Creates a dynamic library artifact with optional companions.
  factory BuiltNativeArtifact.dynamicLibrary({
    required String id,
    required NativeTarget target,
    required NativeArtifactEntry primary,
    List<NativeArtifactEntry> companions = const [],
    Map<String, Object?> metadata = const {},
  }) {
    return BuiltNativeArtifact(
      id: id,
      target: target,
      kind: NativeArtifactKind.dynamicLibrary,
      primary: primary,
      companions: companions,
      metadata: metadata,
    );
  }

  /// Creates a static library artifact with optional companions.
  factory BuiltNativeArtifact.staticLibrary({
    required String id,
    required NativeTarget target,
    required NativeArtifactEntry primary,
    List<NativeArtifactEntry> companions = const [],
    Map<String, Object?> metadata = const {},
  }) {
    return BuiltNativeArtifact(
      id: id,
      target: target,
      kind: NativeArtifactKind.staticLibrary,
      primary: primary,
      companions: companions,
      metadata: metadata,
    );
  }

  /// Creates an executable artifact with optional companions.
  factory BuiltNativeArtifact.executable({
    required String id,
    required NativeTarget target,
    required NativeArtifactEntry primary,
    List<NativeArtifactEntry> companions = const [],
    Map<String, Object?> metadata = const {},
  }) {
    return BuiltNativeArtifact(
      id: id,
      target: target,
      kind: NativeArtifactKind.executable,
      primary: primary,
      companions: companions,
      metadata: metadata,
    );
  }
}

/// Declarative description of an artifact to export.
///
/// Used by [ExportArtifactStep] to know what artifact to produce.
/// Paths are resolved relative to the build output directory.
final class NativeArtifactDeclaration {
  const NativeArtifactDeclaration({
    required this.id,
    required this.kind,
    required this.primaryPath,
    this.companions = const [],
  });

  /// Logical identity for the artifact (e.g., 'tdjson').
  final String id;

  /// What kind of native output this is.
  final NativeArtifactKind kind;

  /// Relative path to the primary artifact in the build output.
  final String primaryPath;

  /// Companion entries (runtime deps, import libs, debug symbols, etc.).
  final List<NativeArtifactCompanion> companions;
}

/// A companion entry in an artifact declaration.
final class NativeArtifactCompanion {
  const NativeArtifactCompanion({
    required this.path,
    required this.role,
    this.optional = false,
  });

  /// Relative path to the companion file in the build output.
  final String path;

  /// Role of this companion within the artifact bundle.
  final NativeArtifactRole role;

  /// Whether this companion is optional (e.g., debug symbols).
  final bool optional;
}
