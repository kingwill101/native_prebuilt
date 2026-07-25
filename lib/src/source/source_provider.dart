import 'dart:io';

import 'package:logging/logging.dart';

import '../build/process_runner.dart';
import 'resolved_source.dart';
import 'source_specification.dart';

/// Context passed to source providers during resolution.
final class SourceResolutionContext {
  const SourceResolutionContext({
    required this.specification,
    required this.packageRoot,
    required this.sourceCacheRoot,
  });

  /// The source specification to resolve.
  final SourceSpecification specification;

  /// Root directory of the Dart package.
  final Directory packageRoot;

  /// Root directory for caching downloaded/cloned sources.
  final Directory sourceCacheRoot;

  /// Compute a cache subdirectory for a given repository and revision.
  Directory sourceCacheDirectory({required String key}) {
    // Sanitize the key for use as a directory name.
    final sanitized = key.replaceAll(RegExp(r'[/\\:]'), '_');
    return Directory('${sourceCacheRoot.path}/$sanitized');
  }
}

/// Resolves a [SourceSpecification] into a [ResolvedSource] directory.
///
/// Providers are tried in order by [SourceFallbackResolver].
/// The first to return a non-null result wins.
abstract interface class SourceProvider {
  /// Try to resolve the source specification.
  ///
  /// Returns a [ResolvedSource] if this provider can handle the
  /// specification, or `null` to skip to the next provider.
  Future<ResolvedSource?> resolve(SourceResolutionContext context);
}

/// Resolves [LocalSource] specifications.
///
/// Checks each path in the specification against the package root
/// and returns the first existing directory.
final class LocalSourceProvider implements SourceProvider {
  const LocalSourceProvider();

  @override
  Future<ResolvedSource?> resolve(SourceResolutionContext context) async {
    final spec = context.specification;
    if (spec is! LocalSource) return null;

    final directory = spec.resolve(context.packageRoot);
    if (directory == null) return null;

    return ResolvedSource(directory: directory, origin: SourceOrigin.local);
  }
}

/// Resolves [ArchiveSource] specifications.
///
/// Downloads the archive, verifies its SHA-256 hash, extracts it,
/// and caches the result.
final class ArchiveSourceProvider implements SourceProvider {
  const ArchiveSourceProvider({this.logger});

  final Logger? logger;

  @override
  Future<ResolvedSource?> resolve(SourceResolutionContext context) async {
    final spec = context.specification;
    if (spec is! ArchiveSource) return null;

    final cacheDir = context.sourceCacheDirectory(key: spec.sha256);
    if (cacheDir.existsSync()) {
      logger?.info('Using cached archive source: ${spec.label}');
      return ResolvedSource(
        directory: _applySubdirectory(cacheDir, spec.subdirectory),
        origin: SourceOrigin.cache,
        revision: spec.sha256,
      );
    }

    logger?.info('Downloading source archive: ${spec.label}');
    await _downloadAndExtract(spec, cacheDir);

    return ResolvedSource(
      directory: _applySubdirectory(cacheDir, spec.subdirectory),
      origin: SourceOrigin.archive,
      revision: spec.sha256,
    );
  }

  Future<void> _downloadAndExtract(
    ArchiveSource spec,
    Directory cacheDir,
  ) async {
    // TODO: Use HttpDownloader with SHA-256 verification.
    // For now, delegate to curl + tar.
    cacheDir.createSync(recursive: true);

    final tempDir = await Directory.systemTemp.createTemp(
      'native_prebuilt_src_',
    );
    try {
      final archivePath = '${tempDir.path}/archive';

       // Download.
       final curlResult = await ProcessRunner().runStreaming(
         'curl',
         [
           '-fsSL',
           '-o',
           archivePath,
           spec.uri.toString(),
         ],
       );
       if (curlResult.exitCode != 0) {
         throw Exception('Failed to download ${spec.uri}');
       }

       // Verify SHA-256.
       final hashResult = await ProcessRunner().runStreaming(
         'shasum',
         ['-a', '256', archivePath],
       );
       final hashOutput = (hashResult.stdout).trim();
      // Handle different sha256sum output formats:
      // - Linux/macOS: 'hash  filename'
      // - Windows (Git Bash): may have backslash prefix or different format
      final hash = hashOutput.split(RegExp(r'\s+')).first.replaceAll(r'\', '');
      if (hash != spec.sha256) {
        throw Exception(
          'SHA-256 mismatch for ${spec.uri}: expected ${spec.sha256}, got $hash',
        );
      }

       // Extract.
       final tarResult = await ProcessRunner().runStreaming(
         'tar',
         [
           '-xzf',
           archivePath,
           '-C',
           cacheDir.path,
           '--strip-components=1',
         ],
       );
       if (tarResult.exitCode != 0) {
         throw Exception('Failed to extract archive');
       }
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  }

  Directory _applySubdirectory(Directory base, String? subdirectory) {
    if (subdirectory == null) return base;
    return Directory('${base.path}/$subdirectory');
  }
}

/// Resolves [GitSource] specifications.
///
/// Clones the repository at the specified revision with `--depth=1`
/// and caches the result.
final class GitSourceProvider implements SourceProvider {
  const GitSourceProvider({this.gitExecutable = 'git', this.logger});

  final String gitExecutable;
  final Logger? logger;

  @override
  Future<ResolvedSource?> resolve(SourceResolutionContext context) async {
    final spec = context.specification;
    if (spec is! GitSource) return null;

    final cacheDir = context.sourceCacheDirectory(key: spec.cacheKey);
    if (cacheDir.existsSync()) {
      logger?.info('Using cached git source: ${spec.label}');
      return ResolvedSource(
        directory: _applySubdirectory(cacheDir, spec.subdirectory),
        origin: SourceOrigin.cache,
        revision: spec.revision,
      );
    }

    logger?.info('Cloning git source: ${spec.label}');
    await _clone(spec, cacheDir);

    return ResolvedSource(
      directory: _applySubdirectory(cacheDir, spec.subdirectory),
      origin: SourceOrigin.git,
      revision: spec.revision,
    );
  }

  Future<void> _clone(GitSource spec, Directory cacheDir) async {
    final env = {'GIT_TERMINAL_PROMPT': '0', 'GIT_LFS_SKIP_SMUDGE': '1'};

    cacheDir.createSync(recursive: true);

    await _runGit(['init', cacheDir.path], environment: env);
    await _runGit([
      '-C',
      cacheDir.path,
      'remote',
      'add',
      'origin',
      spec.repository.toString(),
    ], environment: env);
    await _runGit([
      '-C',
      cacheDir.path,
      'fetch',
      '--depth=1',
      'origin',
      spec.revision,
    ], environment: env);
    await _runGit([
      '-C',
      cacheDir.path,
      'checkout',
      '--detach',
      'FETCH_HEAD',
    ], environment: env);

    if (spec.submodules) {
      await _runGit([
        '-C',
        cacheDir.path,
        'submodule',
        'update',
        '--init',
        '--recursive',
        '--depth=1',
      ], environment: env);
    }
  }

  Future<void> _runGit(
    List<String> arguments, {
    Map<String, String>? environment,
  }) async {
    final result = await ProcessRunner().runStreaming(
      gitExecutable,
      arguments,
      environment: environment,
    );
    if (result.exitCode != 0) {
      throw Exception('git ${arguments.first} failed');
    }
  }

  Directory _applySubdirectory(Directory base, String? subdirectory) {
    if (subdirectory == null) return base;
    return Directory('${base.path}/$subdirectory');
  }
}
