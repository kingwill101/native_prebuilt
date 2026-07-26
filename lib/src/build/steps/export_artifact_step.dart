import 'dart:io';

import 'package:path/path.dart' as p;

import '../fingerprint.dart';
import '../native_artifact_model.dart';
import '../native_build_context.dart';
import '../native_build_recipe.dart';
import '../../source/resolved_source.dart';

/// Artifact export step for native builds.
///
/// Resolves declared artifact paths against the build output directory,
/// copies them to the staging area, and returns a [NativeStepResult]
/// containing a fully described [BuiltNativeArtifact].
final class ExportArtifactStep implements NativeBuildStep {
  const ExportArtifactStep({required this.id, required this.declaration});

  /// Step identifier.
  @override
  final String id;

  /// Declarative description of the artifact to export.
  final NativeArtifactDeclaration declaration;

  /// Creates an [ExportArtifactStep] from a YAML-derived map.
  factory ExportArtifactStep.fromMap(Map<String, dynamic> map) {
    final kindString = map['kind'] as String? ?? 'dynamic_library';
    final kind = NativeArtifactKind.values.firstWhere(
      (k) => k.name == kindString,
      orElse: () => NativeArtifactKind.dynamicLibrary,
    );
    final companions = <NativeArtifactCompanion>[];
    if (map['companions'] is List) {
      for (final c in map['companions'] as List) {
        if (c is Map<String, dynamic>) {
          final roleString = c['role'] as String? ?? 'primary';
          final role = NativeArtifactRole.values.firstWhere(
            (r) => r.name == roleString,
            orElse: () => NativeArtifactRole.primary,
          );
          companions.add(
            NativeArtifactCompanion(
              path: c['path'] as String,
              role: role,
              optional: c['optional'] as bool? ?? false,
            ),
          );
        }
      }
    }
    return ExportArtifactStep(
      id: map['id'] as String,
      declaration: NativeArtifactDeclaration(
        id: map['id'] as String,
        kind: kind,
        primaryPath: map['primary_path'] as String,
        companions: companions,
      ),
    );
  }

  /// Serializes this step to a map suitable for YAML output.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'type': 'export_artifact',
      'id': declaration.id,
      'kind': declaration.kind.name,
      'primary_path': declaration.primaryPath,
      if (declaration.companions.isNotEmpty)
        'companions': declaration.companions
            .map(
              (c) => <String, dynamic>{
                'path': c.path,
                'role': c.role.name,
                'optional': c.optional,
              },
            )
            .toList(),
    };
  }

  @override
  Map<String, dynamic> toJson() => toMap();

  @override
  Future<NativeStepFingerprint> fingerprint(NativeStepContext context) async {
    return NativeStepFingerprint(
      id: id,
      hash: fingerprintHash(declaration.toJson().toString()),
    );
  }

  @override
  Future<NativeStepResult> execute(
    NativeBuildContext context,
    ResolvedSource source,
  ) async {
    final logger = context.logger;
    logger?.info('[export_artifact] Exporting artifact: ${declaration.id}');

    // Resolve primary artifact (required)
    final primaryEntry = await _resolveRequiredEntry(
      context: context,
      path: declaration.primaryPath,
      role: NativeArtifactRole.primary,
    );

    // Resolve companion artifacts
    final companionEntries = <NativeArtifactEntry>[];
    for (final companion in declaration.companions) {
      final entry = await _resolveEntry(
        context: context,
        path: companion.path,
        role: companion.role,
        optional: companion.optional,
      );
      if (entry != null) {
        companionEntries.add(entry);
      }
    }

    final artifact = BuiltNativeArtifact(
      id: declaration.id,
      target: context.target,
      kind: declaration.kind,
      primary: primaryEntry,
      companions: companionEntries,
    );

    logger?.info(
      '[export_artifact] Exported ${declaration.id} '
      '(${companionEntries.length + 1} entries)',
    );

    return NativeStepResult(artifacts: [artifact]);
  }

  /// Resolve a single artifact entry, copying it to the staging directory.
  Future<NativeArtifactEntry> _resolveRequiredEntry({
    required NativeBuildContext context,
    required String path,
    required NativeArtifactRole role,
  }) async {
    final entry = await _resolveEntry(context: context, path: path, role: role);
    if (entry == null) {
      throw StateError('Required artifact not found: $path');
    }
    return entry;
  }

  /// Resolve a single artifact entry, copying it to the staging directory.
  Future<NativeArtifactEntry?> _resolveEntry({
    required NativeBuildContext context,
    required String path,
    required NativeArtifactRole role,
    bool optional = false,
  }) async {
    final logger = context.logger;

    _validateRelativePath(path, context);

    final srcPath = _resolveFirstExistingSourcePath(path, context);
    if (srcPath == null) {
      if (optional) {
        logger?.warning('[export_artifact] Optional artifact not found: $path');
        return null;
      }
      throw StateError(
        'Required artifact not found: ${_resolveSourcePath(path, context)}',
      );
    }

    final srcFile = File(srcPath);

    // Stage the file to the output directory
    final destPath = _resolveDestinationPath(path, context);
    final destFile = File(destPath);
    destFile.parent.createSync(recursive: true);
    await srcFile.copy(destPath);

    logger?.fine('[export_artifact] Staged: $path');

    return NativeArtifactEntry(
      source: srcFile,
      path: path,
      role: role,
      optional: optional,
    );
  }

  /// Resolve a relative path against the build working directory.
  String _resolveSourcePath(String relativePath, NativeBuildContext context) {
    if (p.isAbsolute(relativePath)) {
      return relativePath;
    }
    return p.join(context.directories.work.path, relativePath);
  }

  String? _resolveFirstExistingSourcePath(
    String relativePath,
    NativeBuildContext context,
  ) {
    for (final candidate in _sourcePathCandidates(relativePath, context)) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    return null;
  }

  List<String> _sourcePathCandidates(
    String relativePath,
    NativeBuildContext context,
  ) {
    final candidates = <String>{_resolveSourcePath(relativePath, context)};

    if (declaration.kind == NativeArtifactKind.dynamicLibrary) {
      final variants = <String>{
        ..._sharedLibraryVariants(relativePath),
        ..._sharedLibraryDirectoryVariants(relativePath),
      };
      for (final variant in variants) {
        candidates.add(_resolveSourcePath(variant, context));
      }
    }

    return candidates.toList();
  }

  Iterable<String> _sharedLibraryVariants(String relativePath) sync* {
    if (relativePath.endsWith('.so')) {
      yield relativePath.substring(0, relativePath.length - 3) + '.dylib';
    } else if (relativePath.endsWith('.dylib')) {
      yield relativePath.substring(0, relativePath.length - 7) + '.so';
    }
  }

  Iterable<String> _sharedLibraryDirectoryVariants(String relativePath) sync* {
    if (relativePath.contains('install/lib/')) {
      final swapped = relativePath.replaceFirst('install/lib/', 'build/');
      yield swapped;
      yield* _sharedLibraryVariants(swapped);
      return;
    }

    if (relativePath.startsWith('build/')) {
      final swapped = relativePath.replaceFirst('build/', 'install/lib/');
      yield swapped;
      yield* _sharedLibraryVariants(swapped);
    }
  }

  String _resolveDestinationPath(
    String relativePath,
    NativeBuildContext context,
  ) {
    final resolved = p.normalize(
      p.join(context.directories.output.path, relativePath),
    );
    final outputRoot = p.normalize(context.directories.output.path);
    if (!p.isWithin(outputRoot, resolved) && resolved != outputRoot) {
      throw StateError('Artifact path escapes output directory: $relativePath');
    }
    return resolved;
  }

  void _validateRelativePath(String path, NativeBuildContext context) {
    if (p.isAbsolute(path)) {
      throw StateError(
        'Artifact path must be relative to output directory: $path',
      );
    }
    final resolved = p.normalize(p.join(context.directories.output.path, path));
    final outputRoot = p.normalize(context.directories.output.path);
    if (!p.isWithin(outputRoot, resolved) && resolved != outputRoot) {
      throw StateError('Artifact path escapes output directory: $path');
    }
  }
}
