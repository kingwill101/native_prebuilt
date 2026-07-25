import 'native_artifact_model.dart';

export 'native_artifact_model.dart';

/// Result of a native build operation.
///
/// Contains the built artifacts and optional metadata about the build.
final class NativeBuildResult {
  const NativeBuildResult({required this.artifacts, this.metadata = const {}});

  /// The native artifacts produced by the build.
  final List<BuiltNativeArtifact> artifacts;

  /// Optional metadata about the build (e.g., build duration, toolchain versions).
  final Map<String, Object?> metadata;
}
