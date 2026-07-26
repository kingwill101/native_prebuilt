import 'dart:io';

import 'package:code_assets/code_assets.dart';

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

  Map<String, dynamic> toJson() => {
        'source_path': source.path,
        'source_kind': source is Directory ? 'directory' : 'file',
        'path': path,
        'role': role.name,
        'optional': optional,
      };

  factory NativeArtifactEntry.fromJson(Map<String, dynamic> json) {
    final sourcePath = json['source_path'] as String;
    final sourceKind = json['source_kind'] as String? ?? 'file';
    final source = sourceKind == 'directory'
        ? Directory(sourcePath)
        : File(sourcePath);
    return NativeArtifactEntry(
      source: source,
      path: json['path'] as String,
      role: NativeArtifactRole.values.firstWhere(
        (r) => r.name == json['role'],
        orElse: () => NativeArtifactRole.primary,
      ),
      optional: json['optional'] as bool? ?? false,
    );
  }

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

  Map<String, dynamic> toJson() => {
        'id': id,
        'target': {
          'os': target.os.name,
          'architecture': target.architecture.name,
          if (target.iOSSdk != null)
            'iOSSdk': target.iOSSdk == IOSSdk.iPhoneSimulator
                ? 'iPhoneSimulator'
                : 'iPhoneOS',
        },
        'kind': kind.name,
        'primary': primary.toJson(),
        'companions': companions.map((c) => c.toJson()).toList(),
        'metadata': metadata,
      };

  factory BuiltNativeArtifact.fromJson(Map<String, dynamic> json) {
    final target = json['target'] as Map<String, dynamic>;
    final ios = switch (target['iOSSdk'] as String?) {
      'iPhoneSimulator' => IOSSdk.iPhoneSimulator,
      'iPhoneOS' => IOSSdk.iPhoneOS,
      _ => null,
    };
    return BuiltNativeArtifact(
      id: json['id'] as String,
      target: NativeTarget(
        os: OS.values.firstWhere((o) => o.name == target['os']),
        architecture: Architecture.values.firstWhere(
          (a) => a.name == target['architecture'],
        ),
        iOSSdk: ios,
      ),
      kind: NativeArtifactKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => NativeArtifactKind.dynamicLibrary,
      ),
      primary: NativeArtifactEntry.fromJson(
        json['primary'] as Map<String, dynamic>,
      ),
      companions: (json['companions'] as List<dynamic>? ?? const [])
          .map((c) => NativeArtifactEntry.fromJson(c as Map<String, dynamic>))
          .toList(),
      metadata: (json['metadata'] as Map<String, dynamic>? ?? const {}),
    );
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'primary_path': primaryPath,
        if (companions.isNotEmpty)
          'companions': companions.map((c) => c.toJson()).toList(),
      };

  factory NativeArtifactDeclaration.fromJson(Map<String, dynamic> json) {
    return NativeArtifactDeclaration(
      id: json['id'] as String,
      kind: NativeArtifactKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => NativeArtifactKind.dynamicLibrary,
      ),
      primaryPath: json['primary_path'] as String,
      companions: (json['companions'] as List<dynamic>? ?? const [])
          .map((c) => NativeArtifactCompanion.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }
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

  Map<String, dynamic> toJson() => {
        'path': path,
        'role': role.name,
        'optional': optional,
      };

  factory NativeArtifactCompanion.fromJson(Map<String, dynamic> json) {
    return NativeArtifactCompanion(
      path: json['path'] as String,
      role: NativeArtifactRole.values.firstWhere(
        (r) => r.name == json['role'],
        orElse: () => NativeArtifactRole.primary,
      ),
      optional: json['optional'] as bool? ?? false,
    );
  }
}
