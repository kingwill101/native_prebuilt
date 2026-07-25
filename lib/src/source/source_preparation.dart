import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../build/process_runner.dart';

/// A preparation step applied to source code before building.
///
/// Preparation runs after source acquisition but before compilation.
/// The most common use case is applying patches.
sealed class SourcePreparation {
  const SourcePreparation();

  /// Apply this preparation step to the source [directory].
  Future<void> apply({required Directory directory, required Logger? logger});
}

/// Applies one or more patch files to the source directory.
///
/// Patches are applied in order using the `patch` command.
final class ApplyPatches extends SourcePreparation {
  const ApplyPatches({required this.paths, this.reverse = false});

  /// Relative paths to patch files, resolved against the package root.
  final List<String> paths;

  /// If true, apply patches in reverse (useful for un-applying).
  final bool reverse;

  @override
  Future<void> apply({
    required Directory directory,
    required Logger? logger,
  }) async {
    for (final patchPath in paths) {
      final patchFile = File(patchPath);
      if (!patchFile.existsSync()) {
        throw SourcePreparationException('Patch file not found: $patchPath');
      }

      logger?.info('Applying patch: ${p.basename(patchPath)}');

      final args = [
        if (reverse) '--reverse',
        '--directory=${directory.path}',
        '--input=${patchFile.path}',
        '--strip=1',
      ];

       final result = await ProcessRunner().runStreaming(
         'patch',
         args,
       );
       if (result.exitCode != 0) {
         throw SourcePreparationException(
           'Failed to apply patch ${p.basename(patchPath)}',
         );
       }
    }
  }
}

/// Runs a custom shell command in the source directory.
final class RunCommand extends SourcePreparation {
  const RunCommand({
    required this.executable,
    this.arguments = const [],
    this.environment,
  });

  final String executable;
  final List<String> arguments;
  final Map<String, String>? environment;

  @override
  Future<void> apply({
    required Directory directory,
    required Logger? logger,
  }) async {
    logger?.info('Running: $executable ${arguments.join(' ')}');

     final result = await ProcessRunner().runStreaming(
       executable,
       arguments,
       workingDirectory: directory,
       environment: environment,
     );

     if (result.exitCode != 0) {
       throw SourcePreparationException(
         'Command failed: $executable ${arguments.join(' ')}',
       );
     }
  }
}

/// Exception thrown when a source preparation step fails.
class SourcePreparationException implements Exception {
  const SourcePreparationException(this.message);
  final String message;

  @override
  String toString() => 'SourcePreparationException: $message';
}
