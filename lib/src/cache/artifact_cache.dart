import 'dart:io';

import 'package:logging/logging.dart';

import '../manifest/prebuilt_artifact.dart';
import '../manifest/prebuilt_manifest.dart';
import '../platform/native_target.dart';
import 'artifact_installer.dart';

/// Backwards-compatible facade around [ArtifactInstaller].
///
/// This keeps the earlier API working while exposing a more explicit
/// installer abstraction for advanced use.
final class ArtifactCache {
  ArtifactCache({
    required this.cacheDir,
    this.installer,
  });

  /// The root cache directory.
  final Directory cacheDir;

  /// The installer used to populate the cache.
  final ArtifactInstaller? installer;

  Future<File?> resolve({
    required PrebuiltManifest manifest,
    required NativeTarget target,
    required String libraryStem,
    required ArtifactPayload payload,
    Logger? logger,
  }) {
    logger?.info('Checking shared prebuilt cache for ${target.label}.');
    return (installer ?? DefaultArtifactInstaller()).install(
      manifest: manifest,
      target: target,
      libraryStem: libraryStem,
      payload: payload,
      cacheDirectory: cacheDir,
      logger: logger,
    );
  }
}
