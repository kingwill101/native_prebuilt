import 'dart:io';

import 'package:path/path.dart' as p;

import '../fingerprint.dart';
import '../native_artifact_model.dart';
import '../native_build_context.dart';
import '../native_build_recipe.dart';
import '../recipe_value_expansion.dart';
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
    final stepId = map['id'] as String;
    final artifactId = map['artifact'] as String? ?? stepId;
    return ExportArtifactStep(
      id: stepId,
      declaration: NativeArtifactDeclaration(
        id: artifactId,
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
      'id': id,
      'artifact': declaration.id,
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
      hash: fingerprintHash(
        '$id:${expandRecipeValue(declaration.primaryPath, context.buildContext, context.source)}:${declaration.companions.map((c) => '${c.role.name}:${expandRecipeValue(c.path, context.buildContext, context.source)}:${c.optional}').join('|')}',
      ),
    );
  }

  @override
  Future<NativeStepResult> execute(
    NativeBuildContext context,
    ResolvedSource source,
  ) async {
    final logger = context.logger;
    logger?.info('[export_artifact] Exporting artifact: ${declaration.id}');

    final primaryPath = expandRecipeValue(declaration.primaryPath, context, source);
    final primaryEntry = await _resolveRequiredEntry(
      context: context,
      source: source,
      path: primaryPath,
      role: NativeArtifactRole.primary,
    );

    final companionEntries = <NativeArtifactEntry>[];
    for (final companion in declaration.companions) {
      final entry = await _resolveEntry(
        context: context,
        source: source,
        path: expandRecipeValue(companion.path, context, source),
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
    required ResolvedSource source,
    required String path,
    required NativeArtifactRole role,
  }) async {
    final entry = await _resolveEntry(
      context: context,
      source: source,
      path: path,
      role: role,
    );
    if (entry == null) {
      throw StateError('Required artifact not found: $path');
    }
    return entry;
  }

  /// Resolve a single artifact entry, copying it to the staging directory.
  Future<NativeArtifactEntry?> _resolveEntry({
    required NativeBuildContext context,
    required ResolvedSource source,
    required String path,
    required NativeArtifactRole role,
    bool optional = false,
  }) async {
    final logger = context.logger;

    final srcPath = _resolveFirstExistingSourcePath(path, context);
    if (srcPath == null) {
      if (optional) {
        logger?.warning('[export_artifact] Optional artifact not found: $path');
        return null;
      }
      throw StateError('Required artifact not found: $path');
    }

    final srcFile = File(srcPath);
    final destPath = _resolveDestinationPath(path, context, source);
    final destFile = File(destPath);
    destFile.parent.createSync(recursive: true);
    await srcFile.copy(destPath);

    logger?.fine('[export_artifact] Staged: $path');

    return NativeArtifactEntry(
      source: srcFile,
      path: _resolveDestinationRelativePath(path, context, source),
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

    final workRoot = context.directories.work.path;
    final desiredNames = <String>{p.basename(relativePath)};
    if (declaration.kind == NativeArtifactKind.dynamicLibrary) {
      desiredNames.addAll(_sharedLibraryNameVariants(p.basename(relativePath)));
    }

    if (Directory(workRoot).existsSync()) {
      for (final entity in Directory(workRoot).listSync(recursive: true)) {
        if (entity is File && desiredNames.contains(p.basename(entity.path))) {
          return entity.path;
        }
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
    } else if (relativePath.endsWith('.dll')) {
      yield relativePath.substring(0, relativePath.length - 4) + '.so';
      yield relativePath.substring(0, relativePath.length - 4) + '.dylib';
    }
  }

  Iterable<String> _sharedLibraryNameVariants(String fileName) sync* {
    yield fileName;
    if (fileName.endsWith('.so')) {
      yield fileName.substring(0, fileName.length - 3) + '.dylib';
      yield fileName.substring(0, fileName.length - 3) + '.dll';
    } else if (fileName.endsWith('.dylib')) {
      yield fileName.substring(0, fileName.length - 7) + '.so';
      yield fileName.substring(0, fileName.length - 7) + '.dll';
    } else if (fileName.endsWith('.dll')) {
      yield fileName.substring(0, fileName.length - 4) + '.so';
      yield fileName.substring(0, fileName.length - 4) + '.dylib';
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
    ResolvedSource source,
  ) {
    final resolvedRelative = _resolveDestinationRelativePath(
      relativePath,
      context,
      source,
    );
    final resolved = p.normalize(
      p.join(context.directories.output.path, resolvedRelative),
    );
    final outputRoot = p.normalize(context.directories.output.path);
    if (!p.isWithin(outputRoot, resolved) && resolved != outputRoot) {
      throw StateError('Artifact path escapes output directory: $relativePath');
    }
    return resolved;
  }

  String _resolveDestinationRelativePath(
    String relativePath,
    NativeBuildContext context,
    ResolvedSource source,
  ) {
    final expanded = expandRecipeValue(relativePath, context, source);
    if (!p.isAbsolute(expanded)) {
      return expanded;
    }

    final normalized = p.normalize(expanded);
    final workRoot = p.normalize(context.directories.work.path);
    if (p.isWithin(workRoot, normalized)) {
      return p.relative(normalized, from: workRoot);
    }
    return p.basename(normalized);
  }
}
