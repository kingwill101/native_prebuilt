import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../fingerprint.dart';
import '../native_build_context.dart';
import '../native_build_recipe.dart';
import '../recipe_value_expansion.dart';
import '../../source/resolved_source.dart';

/// Copy files or directories.
final class CopyStep implements NativeBuildStep {
  const CopyStep({
    required this.id,
    this.execution = 'target',
    required this.sourcePath,
    required this.destinationPath,
    this.recursive = true,
  });

  @override
  final String id;

  @override
  final String execution;


  /// Source file or directory path.
  final String sourcePath;

  /// Destination path.
  final String destinationPath;

  /// Whether to copy directories recursively.
  final bool recursive;

  /// Creates a [CopyStep] from a YAML-derived map.
  factory CopyStep.fromMap(Map<String, dynamic> map) {
    return CopyStep(
      id: map['id'] as String,
      sourcePath: map['source_path'] as String,
      destinationPath: map['destination_path'] as String,
      recursive: map['recursive'] as bool? ?? true,
    );
  }

  /// Serializes this step to a map suitable for YAML output.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'type': 'copy',
      'id': id,
      'source_path': sourcePath,
      'destination_path': destinationPath,
      if (recursive != true) 'recursive': recursive,
    };
  }

  @override
  Map<String, dynamic> toJson() => toMap();

  @override
  Future<NativeStepFingerprint> fingerprint(NativeStepContext context) async {
    return NativeStepFingerprint(
      id: id,
      hash: fingerprintHash(
        '$id:${expandRecipeValue(sourcePath, context.buildContext, context.source)}_'
        '${expandRecipeValue(destinationPath, context.buildContext, context.source)}',
      ),
    );
  }

  @override
  Future<NativeStepResult> execute(
    NativeBuildContext context,
    ResolvedSource source,
  ) async {
    final logger = context.logger;
    logger?.info('[copy] Copying files');
    final srcPath = expandRecipeValue(sourcePath, context, source);
    final destPath = expandRecipeValue(destinationPath, context, source);
    final src = p.isAbsolute(srcPath)
        ? srcPath
        : p.join(source.directory.path, srcPath);
    final dest = p.isAbsolute(destPath)
        ? destPath
        : p.join(context.directories.work.path, destPath);

    logger?.info('[copy] Source: $src');
    logger?.info('[copy] Destination: $dest');
    final srcEntity = FileSystemEntity.typeSync(src);
    if (srcEntity == FileSystemEntityType.directory) {
      await _copyDirectory(
        Directory(src),
        Directory(dest),
        recursive: recursive,
      );
    } else if (srcEntity == FileSystemEntityType.file) {
      Directory(p.dirname(dest)).createSync(recursive: true);
      File(src).copySync(dest);
    } else {
      throw StateError('Copy source does not exist: $src');
    }
    logger?.info('[copy] Copy completed');

    return const NativeStepResult();
  }

  Future<void> _copyDirectory(
    Directory source,
    Directory destination, {
    required bool recursive,
  }) async {
    destination.createSync(recursive: true);
    await for (final entity in source.list(recursive: recursive)) {
      if (entity is File) {
        final relativePath = p.relative(entity.path, from: source.path);
        final targetFile = File(p.join(destination.path, relativePath));
        targetFile.parent.createSync(recursive: true);
        await entity.copy(targetFile.path);
      } else if (entity is Directory && !recursive) {
        Directory(
          p.join(destination.path, p.basename(entity.path)),
        ).createSync(recursive: true);
      }
    }
  }
}
