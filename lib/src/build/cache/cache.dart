import 'dart:io';

import 'package:path/path.dart' as path;

/// Represents a unique fingerprint for a build step.
///
/// Used to determine if a step needs to be re-executed based on inputs.
final class NativeBuildFingerprint {
  const NativeBuildFingerprint({required this.id, required this.hash});

  /// Unique identifier for this step (e.g., 'cmake_configure')
  final String id;

  /// Hash representing the step's inputs and configuration
  final String hash;
}

/// Manages the build cache directory structure.
///
/// Stores artifacts and step fingerprints to enable caching.
final class BuildCache {
  BuildCache({required this.cacheRoot});

  /// Root directory for the build cache
  final Directory cacheRoot;

  /// Stores artifacts by fingerprint
  final Map<String, Directory> artifactCache = {};

  /// Stores step fingerprints
  final Map<String, NativeBuildFingerprint> stepFingerprints = {};

  /// Creates or returns a cache directory for a given fingerprint
  Directory getArtifactDirectory(String fingerprint) {
    final dir = Directory(path.join(cacheRoot.path, fingerprint));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Stores an artifact in the cache
  void cacheArtifact(String fingerprint, File artifact) {
    final dir = getArtifactDirectory(fingerprint);
    final fileName = path.basename(artifact.path);
    final dest = File(path.join(dir.path, fileName));
    artifact.copySync(dest.path);
  }

  /// Retrieves a cached artifact if available
  File? getCachedArtifact(String fingerprint, String filename) {
    final dir = getArtifactDirectory(fingerprint);
    final filePath = path.join(dir.path, filename);
    return File(filePath).existsSync() ? File(filePath) : null;
  }
}

/// Tracks executed build steps and their fingerprints.
final class BuildStepCache {
  BuildStepCache({required this.buildCache});

  /// The build cache instance
  final BuildCache buildCache;

  /// Tracks executed steps by ID
  final Map<String, NativeBuildFingerprint> executedSteps = {};

  /// Checks if a step has been executed with matching fingerprint
  bool hasExecuted(String stepId, String fingerprint) {
    final existing = executedSteps[stepId];
    return existing != null && existing.hash == fingerprint;
  }

  /// Records a step execution with its fingerprint
  void recordExecution(String stepId, NativeBuildFingerprint fingerprint) {
    executedSteps[stepId] = fingerprint;
  }
}
