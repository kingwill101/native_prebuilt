import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../build/native_build_recipe.dart';

/// Persistent build cache for step-level caching.
///
/// Stores metadata about completed steps in
/// `.dart_tool/native_prebuilt/build-cache/<project>/<target>/<fingerprint>/meta.json`.
///
/// On cache hit: the step is skipped.
/// On cache miss: the step is executed and its output recorded.
final class BuildCache {
  const BuildCache({
    required this.projectName,
    required this.targetLabel,
    this.cacheRoot,
    this.logger,
  });

  /// The project name (used as subdirectory under cache root).
  final String projectName;

  /// The target label (e.g., `linux-x64`, `android-arm64`).
  final String targetLabel;

  /// Optional override for the cache root directory.
  ///
  /// Defaults to `.dart_tool/native_prebuilt/build-cache/` in the current
  /// working directory.
  final Directory? cacheRoot;

  /// Optional logger.
  final Logger? logger;

  /// Get the base directory for this project+target cache.
  Directory get cacheDir {
    final root =
        cacheRoot ??
        Directory(
          p.join(
            Directory.current.path,
            '.dart_tool',
            'native_prebuilt',
            'build-cache',
          ),
        );
    return Directory(p.join(root.path, projectName, targetLabel));
  }

  /// Check if a step with the given [fingerprint] has been cached.
  ///
  /// Returns `true` if the cache entry exists and its outputs are still valid.
  Future<bool> isCached(NativeStepFingerprint fingerprint) async {
    final metaFile = _metaFile(fingerprint);
    if (!metaFile.existsSync()) {
      logger?.fine('Cache miss for ${fingerprint.id} (no metadata)');
      return false;
    }

    try {
      final json =
          jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
      final cachedHash = json['hash'] as String?;
      if (cachedHash != fingerprint.hash) {
        logger?.fine(
          'Cache miss for ${fingerprint.id}: '
          'hash mismatch (cached=$cachedHash, current=${fingerprint.hash})',
        );
        return false;
      }

      // Verify all recorded output files still exist
      final outputs = (json['outputs'] as List<dynamic>?) ?? [];
      for (final output in outputs) {
        final path = output as String;
        if (!File(path).existsSync()) {
          logger?.fine(
            'Cache miss for ${fingerprint.id}: output missing at $path',
          );
          return false;
        }
      }

      logger?.fine('Cache hit for ${fingerprint.id}');
      return true;
    } catch (e) {
      logger?.warning('Cache read error for ${fingerprint.id}: $e');
      return false;
    }
  }

  /// Record a completed step in the cache.
  ///
  /// [fingerprint] is the step's fingerprint.
  /// [outputPaths] are the absolute paths to files produced by this step.
  /// [artifactDeclarations] are JSON-serializable artifact declarations
  /// produced by this step, used to reconstruct artifacts on cache hit.
  Future<void> record({
    required NativeStepFingerprint fingerprint,
    List<String> outputPaths = const [],
    List<Map<String, Object?>> artifactDeclarations = const [],
  }) async {
    final metaFile = _metaFile(fingerprint);
    metaFile.parent.createSync(recursive: true);

    final metadata = <String, dynamic>{
      'stepId': fingerprint.id,
      'hash': fingerprint.hash,
      'outputs': outputPaths,
      'artifactDeclarations': artifactDeclarations,
      'recordedAt': DateTime.now().toIso8601String(),
    };

    await metaFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(metadata),
    );

    logger?.fine(
      'Cached ${fingerprint.id} with ${outputPaths.length} output(s)',
    );
  }

  /// Retrieve cached artifact declarations for a step.
  ///
  /// Returns the JSON-serializable artifact declarations stored when
  /// the step was last executed. Returns an empty list if not cached.
  Future<List<Map<String, Object?>>> getCachedArtifacts(
    NativeStepFingerprint fingerprint,
  ) async {
    final metaFile = _metaFile(fingerprint);
    if (!metaFile.existsSync()) return [];

    try {
      final json =
          jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
      final declarations = json['artifactDeclarations'];
      if (declarations is List) {
        return declarations.cast<Map<String, Object?>>();
      }
    } catch (_) {}
    return [];
  }

  /// Invalidate the cache for a specific step.
  Future<void> invalidate(NativeStepFingerprint fingerprint) async {
    final metaFile = _metaFile(fingerprint);
    if (metaFile.existsSync()) {
      await metaFile.delete();
      logger?.fine('Invalidated cache for ${fingerprint.id}');
    }
  }

  /// Clear all cached data for this project+target.
  Future<void> clear() async {
    final dir = cacheDir;
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
      logger?.info('Cleared cache for $projectName/$targetLabel');
    }
  }

  /// Get the path to the metadata file for a fingerprint.
  File _metaFile(NativeStepFingerprint fingerprint) {
    return File(
      p.join(cacheDir.path, fingerprint.id, '${fingerprint.hash}.json'),
    );
  }
}
