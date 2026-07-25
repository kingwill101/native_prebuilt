import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../fingerprint.dart';
import '../native_build_context.dart';
import '../native_build_recipe.dart';
import '../../source/resolved_source.dart';

/// Copy files or directories.
final class CopyStep implements NativeBuildStep {
  const CopyStep({
    required this.id,
    required this.sourcePath,
    required this.destinationPath,
    this.recursive = true,
  });

  @override
  final String id;

  /// Source file or directory path.
  final String sourcePath;

  /// Destination path.
  final String destinationPath;

  /// Whether to copy directories recursively.
  final bool recursive;

  @override
  Future<NativeStepFingerprint> fingerprint(NativeStepContext context) async {
    return NativeStepFingerprint(
      id: id,
      hash: fingerprintHash('${sourcePath}_$destinationPath'),
    );
  }

  @override
  Future<NativeStepResult> execute(
    NativeBuildContext context,
    ResolvedSource source,
  ) async {
    final logger = context.logger;
    logger?.info('[copy] Copying files');
    final src = p.isAbsolute(sourcePath)
        ? sourcePath
        : p.join(source.directory.path, sourcePath);
    final dest = p.isAbsolute(destinationPath)
        ? destinationPath
        : p.join(context.directories.work.path, destinationPath);

    logger?.info('[copy] Source: $src');
    logger?.info('[copy] Destination: $dest');
    final srcEntity = FileSystemEntity.typeSync(src);
    if (srcEntity == FileSystemEntityType.directory) {
      await _copyDirectory(Directory(src), Directory(dest));
    } else if (srcEntity == FileSystemEntityType.file) {
      Directory(p.dirname(dest)).createSync(recursive: true);
      File(src).copySync(dest);
    } else {
      throw StateError('Copy source does not exist: $src');
    }
    logger?.info('[copy] Copy completed');

    return const NativeStepResult();
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    destination.createSync(recursive: true);
    await for (final entity in source.list(recursive: true)) {
      if (entity is File) {
        final relativePath = p.relative(entity.path, from: source.path);
        final targetFile = File(p.join(destination.path, relativePath));
        targetFile.parent.createSync(recursive: true);
        await entity.copy(targetFile.path);
      }
    }
  }
}
