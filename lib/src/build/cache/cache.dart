import 'dart:convert';
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

  Map<String, dynamic> toJson() => {'id': id, 'hash': hash};

  factory NativeBuildFingerprint.fromJson(Map<String, dynamic> json) {
    return NativeBuildFingerprint(
      id: json['id'] as String,
      hash: json['hash'] as String,
    );
  }
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
    final dir = Directory(path.join(cacheRoot.path, fingerprint));
    if (!dir.existsSync()) {
      return null;
    }
    final filePath = path.join(dir.path, filename);
    return File(filePath).existsSync() ? File(filePath) : null;
  }
}

/// Tracks executed build steps and their fingerprints.
final class BuildStepCache {
  BuildStepCache({required this.buildCache}) {
    _load();
  }

  /// The build cache instance
  final BuildCache buildCache;

  /// Tracks executed steps by ID
  final Map<String, NativeBuildFingerprint> executedSteps = {};

  Directory get _fingerprintDirectory =>
      Directory(path.join(buildCache.cacheRoot.path, 'step-fingerprints'));

  File get _fingerprintFile =>
      File(path.join(_fingerprintDirectory.path, 'step_fingerprints.json'));

  void _load() {
    if (!_fingerprintFile.existsSync()) {
      return;
    }
    final decoded = jsonDecode(_fingerprintFile.readAsStringSync());
    if (decoded is! Map<String, dynamic>) {
      return;
    }
    for (final entry in decoded.entries) {
      final value = entry.value;
      if (value is Map<String, dynamic>) {
        executedSteps[entry.key] = NativeBuildFingerprint.fromJson(value);
      }
    }
  }

  void _persist() {
    _fingerprintDirectory.createSync(recursive: true);
    _fingerprintFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(
        executedSteps.map((key, value) => MapEntry(key, value.toJson())),
      ),
    );
  }

  /// Checks if a step has been executed with matching fingerprint
  bool hasExecuted(String stepId, String fingerprint) {
    final existing = executedSteps[stepId];
    return existing != null && existing.hash == fingerprint;
  }

  /// Records a step execution with its fingerprint
  void recordExecution(String stepId, NativeBuildFingerprint fingerprint) {
    executedSteps[stepId] = fingerprint;
    _persist();
  }
}
