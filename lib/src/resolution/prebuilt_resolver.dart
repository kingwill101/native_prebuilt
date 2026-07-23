import 'dart:io';

import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../archive/archive_reader.dart';
import '../binary/binary_inspector.dart';
import '../binary/library_name.dart';
import '../cache/artifact_cache.dart';
import '../cache/artifact_installer.dart';
import '../download/http_downloader.dart';
import '../manifest/prebuilt_artifact.dart';
import '../manifest/prebuilt_manifest.dart';
import '../platform/native_target.dart';
import 'resolution_result.dart';

/// Context passed to resolvers during the resolution chain.
final class PrebuiltResolutionContext {
  const PrebuiltResolutionContext({
    required this.input,
    required this.manifest,
    required this.target,
    required this.libraryStem,
    required this.payload,
    required this.localSearchRoot,
    this.logger,
  });

  final BuildInput input;
  final PrebuiltManifest manifest;
  final NativeTarget target;
  final String libraryStem;
  final ArtifactPayload payload;
  final Directory localSearchRoot;

  /// Logger used to emit resolution progress messages.
  final Logger? logger;
}

/// Abstract interface for resolving prebuilt artifacts.
///
/// Implementations are tried in order by [PrebuiltCodeAssetBuilder].
/// The first to return a non-null result wins.
abstract interface class PrebuiltResolver {
  Future<ResolvedPrebuilt?> resolve(PrebuiltResolutionContext context);
}

/// Resolves prebuilts from `hooks.user_defines` configuration.
///
/// In `pubspec.yaml`:
/// ```yaml
/// hooks:
///   user_defines:
///     my_package:
///       prebuilt_path: /absolute/path/to/library.so
/// ```
final class UserDefinePrebuiltResolver implements PrebuiltResolver {
  const UserDefinePrebuiltResolver({
    this.key = 'prebuilt_path',
  });

  final String key;

  @override
  Future<ResolvedPrebuilt?> resolve(PrebuiltResolutionContext context) async {
    final pathUri = context.input.userDefines.path(key);
    if (pathUri == null) return null;

    final file = File(pathUri.toFilePath());
    if (!file.existsSync()) {
      return ResolvedPrebuiltNotFound(
        reason: 'user_defines $key points to non-existent file: $pathUri',
        attempts: [
          ResolutionAttempt(
            source: PrebuiltSource.userDefine,
            success: false,
            path: pathUri.toFilePath(),
            error: 'File not found',
          ),
        ],
      );
    }

    final hash = await ArchiveReader.sha256Hash(file);
    return ResolvedPrebuiltFound(
      file: ResolvedFile(path: file.path, hash: hash),
      source: PrebuiltSource.userDefine,
    );
  }
}

/// Resolves prebuilts from the local `.prebuilt/` directory.
///
/// Searches up from the build output directory and from the package root.
final class LocalPrebuiltResolver implements PrebuiltResolver {
  const LocalPrebuiltResolver({
    this.directoryName = '.prebuilt',
  });

  final String directoryName;

  @override
  Future<ResolvedPrebuilt?> resolve(PrebuiltResolutionContext context) async {
    final canonicalName = canonicalLibraryName(
      target: context.target,
      libraryStem: context.libraryStem,
      payload: context.payload,
    );

    final searchRoots = _computeSearchRoots(context);

    for (final root in searchRoots) {
      final candidate = File(p.join(
        root.path,
        directoryName,
        context.target.label,
        canonicalName,
      ));
      if (candidate.existsSync()) {
        try {
          final hash = await ArchiveReader.sha256Hash(candidate);
          return ResolvedPrebuiltFound(
            file: ResolvedFile(path: candidate.path, hash: hash),
            source: PrebuiltSource.localCache,
          );
        } catch (_) {
          // Invalid file, skip.
        }
      }
    }

    return null;
  }

  List<Directory> _computeSearchRoots(PrebuiltResolutionContext context) {
    final roots = <Directory>[];

    // Walk up from output directory.
    var dir = Directory.fromUri(context.input.outputDirectory).absolute;
    while (true) {
      if (_isProjectRoot(dir)) {
        roots.add(dir);
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }

    // Also check from package root.
    final pkgDir = Directory.fromUri(context.input.packageRoot).absolute;
    if (!roots.any((r) => r.path == pkgDir.path)) {
      roots.add(pkgDir);
    }

    return roots;
  }

  bool _isProjectRoot(Directory dir) {
    final hasPubspec = File('${dir.path}/pubspec.yaml').existsSync();
    final hasDartTool = Directory('${dir.path}/.dart_tool').existsSync();
    return hasPubspec && hasDartTool;
  }
}

/// Resolves prebuilts from the shared hook cache (outputDirectoryShared)
/// by downloading from the release source.
final class SharedCacheResolver implements PrebuiltResolver {
  const SharedCacheResolver({
    this.downloader = const HttpDownloader(),
    this.inspector = const NativeBinaryInspector(),
  });

  final HttpDownloader downloader;
  final NativeBinaryInspector inspector;

  @override
  Future<ResolvedPrebuilt?> resolve(PrebuiltResolutionContext context) async {
    final cache = ArtifactCache(
      cacheDir: Directory.fromUri(
        context.input.outputDirectoryShared,
      ),
      installer: DefaultArtifactInstaller(
        downloader: downloader,
        inspector: inspector,
      ),
    );

    final file = await cache.resolve(
      manifest: context.manifest,
      target: context.target,
      libraryStem: context.libraryStem,
      payload: context.payload,
      logger: context.logger,
    );

    if (file == null) return null;

    final hash = await ArchiveReader.sha256Hash(file);
    return ResolvedPrebuiltFound(
      file: ResolvedFile(path: file.path, hash: hash),
      source: PrebuiltSource.download,
    );
  }
}
