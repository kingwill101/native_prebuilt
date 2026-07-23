import 'dart:io';

import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'network_policy.dart';
import 'resolved_source.dart';
import 'source_builder.dart';
import 'source_preparation.dart';
import 'source_provider.dart';
import 'source_specification.dart';

/// Configuration for source-based fallback when no prebuilt is available.
///
/// This separates source acquisition, preparation, and compilation into
/// distinct stages:
///
/// 1. **Acquire** — resolve source from local, archive, or git
/// 2. **Prepare** — apply patches, run setup commands
/// 3. **Build** — compile the source into a native library
final class SourceFallback {
  const SourceFallback({
    required this.sources,
    required this.builder,
    this.preparation = const [],
    this.networkPolicy = NetworkPolicy.allowed,
  });

  /// Source specifications in priority order.
  ///
  /// The first source that resolves successfully is used.
  final List<SourceSpecification> sources;

  /// Compiles the resolved source into a native library.
  final SourceBuilder builder;

  /// Preparation steps applied after acquisition, before building.
  ///
  /// Typically used for applying patches or running setup scripts.
  final List<SourcePreparation> preparation;

  /// Network access policy for source resolution.
  final NetworkPolicy networkPolicy;
}

/// Resolves and builds from source as a fallback when prebuilts fail.
///
/// This is the source-side equivalent of [SharedCacheResolver].
/// It runs after the prebuilt resolution chain has been exhausted.
final class SourceFallbackResolver {
  const SourceFallbackResolver({
    this.providers = const [
      LocalSourceProvider(),
      ArchiveSourceProvider(),
      GitSourceProvider(),
    ],
  });

  /// Source providers in priority order.
  final List<SourceProvider> providers;

  /// Resolve, prepare, and build from source.
  ///
  /// Returns the directory containing the built library, or `null`
  /// if no source could be resolved.
  Future<SourceBuildResult?> resolve({
    required SourceFallback fallback,
    required Directory packageRoot,
    required Directory sourceCacheRoot,
    required BuildInput input,
    required BuildOutputBuilder output,
    required Logger? logger,
  }) async {
    // Try each source specification with each provider.
    ResolvedSource? resolved;
    for (final spec in fallback.sources) {
      final specContext = SourceResolutionContext(
        specification: spec,
        packageRoot: packageRoot,
        sourceCacheRoot: sourceCacheRoot,
      );

      for (final provider in providers) {
        try {
          resolved = await provider.resolve(specContext);
          if (resolved != null) break;
        } catch (e) {
          logger?.warning('Source provider ${provider.runtimeType} failed: $e');
          continue;
        }
      }
      if (resolved != null) break;
    }

    if (resolved == null) {
      logger?.warning('No source resolved from ${fallback.sources.length} specifications');
      return null;
    }

    logger?.info('Resolved source: ${resolved.origin.label} at ${resolved.directory.path}');

    // Apply preparation steps.
    // Work in a copy of the resolved source to keep the cache immutable.
    final workDir = await _prepareWorkingDirectory(resolved, input, logger);
    try {
      for (final step in fallback.preparation) {
        await step.apply(directory: workDir, logger: logger);
      }

      // Build.
      await fallback.builder.build(
        source: ResolvedSource(
          directory: workDir,
          origin: resolved.origin,
          revision: resolved.revision,
        ),
        input: input,
        output: output,
        logger: logger,
      );

      return SourceBuildResult(
        source: resolved,
        workDirectory: workDir,
      );
    } catch (e) {
      logger?.severe('Source build failed: $e');
      rethrow;
    }
  }

  /// Create a working directory from the resolved source.
  ///
  /// For local sources, uses the original directory directly.
  /// For cached/downloaded sources, creates a copy to keep the cache immutable.
  Future<Directory> _prepareWorkingDirectory(
    ResolvedSource resolved,
    BuildInput input,
    Logger? logger,
  ) async {
    if (resolved.origin == SourceOrigin.local) {
      // Local sources can be used in-place.
      return resolved.directory;
    }

    // Copy cached source to a working directory.
    final workDir = Directory.fromUri(
      input.outputDirectory.resolve('source_work/'),
    );
    if (workDir.existsSync()) workDir.deleteSync(recursive: true);

    logger?.info('Copying source to working directory: ${workDir.path}');
    await _copyDirectory(resolved.directory, workDir);

    return workDir;
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    destination.createSync(recursive: true);
    await for (final entity in source.list(recursive: true)) {
      if (entity is File) {
        final relativePath = p.relative(entity.path, from: source.path);
        final target = File(p.join(destination.path, relativePath));
        target.parent.createSync(recursive: true);
        await entity.copy(target.path);
      } else if (entity is Directory) {
        final relativePath = p.relative(entity.path, from: source.path);
        Directory(p.join(destination.path, relativePath))
            .createSync(recursive: true);
      }
    }
  }
}

/// Result of a successful source build.
final class SourceBuildResult {
  const SourceBuildResult({
    required this.source,
    required this.workDirectory,
  });

  /// The resolved source that was built.
  final ResolvedSource source;

  /// The working directory where the build took place.
  final Directory workDirectory;
}
