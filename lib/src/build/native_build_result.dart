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

  Map<String, dynamic> toJson() => {
    'artifacts': artifacts.map((artifact) => artifact.toJson()).toList(),
    'metadata': metadata,
  };

  factory NativeBuildResult.fromJson(Map<String, dynamic> json) {
    return NativeBuildResult(
      artifacts: (json['artifacts'] as List<dynamic>? ?? const [])
          .map(
            (artifact) =>
                BuiltNativeArtifact.fromJson(artifact as Map<String, dynamic>),
          )
          .toList(),
      metadata: json['metadata'] as Map<String, Object?>? ?? const {},
    );
  }
}
