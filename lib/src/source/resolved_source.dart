import 'dart:io';

/// A resolved source directory ready for preparation and building.
final class ResolvedSource {
  const ResolvedSource({
    required this.directory,
    required this.origin,
    this.revision,
  });

  /// Directory containing the source code.
  final Directory directory;

  /// How the source was acquired.
  final SourceOrigin origin;

  /// Commit SHA or archive hash, if applicable.
  final String? revision;
}

/// How source code was acquired.
enum SourceOrigin {
  local('local workspace'),
  git('git clone'),
  archive('source archive'),
  cache('cached source');

  const SourceOrigin(this.label);
  final String label;
}
