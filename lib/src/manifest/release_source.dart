/// Describes where prebuilt artifacts are published.
sealed class ReleaseSource {
  const ReleaseSource();
}

/// Artifacts are hosted as GitHub Release assets.
final class GitHubReleaseSource extends ReleaseSource {
  const GitHubReleaseSource({
    required this.owner,
    required this.repository,
    required this.tag,
    this.baseUri,
  });

  /// The GitHub organization or user.
  ///
  /// Example: `kingwill101`.
  final String owner;

  /// The GitHub repository name.
  ///
  /// Example: `dart_terminal`.
  final String repository;

  /// The release tag.
  ///
  /// Example: `portable_pty-v0.0.6`.
  final String tag;

  /// Optional base URI for downloads.
  ///
  /// Defaults to the GitHub Releases URL for [owner]/[repository]/[tag].
  /// Useful for tests or mirrors.
  final Uri? baseUri;

  /// The base URL for downloading artifacts from this release.
  Uri get baseUrl =>
      baseUri ??
      Uri.https(
        'github.com',
        '/$owner/$repository/releases/download/$tag/',
      );

  /// Constructs the full download URL for an artifact by name.
  Uri artifactUrl(String archiveName) => baseUrl.resolve(archiveName);

  @override
  String toString() =>
      'GitHubReleaseSource($owner/$repository@$tag)';
}
