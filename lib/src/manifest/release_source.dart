/// Describes where prebuilt artifacts are published.
sealed class ReleaseSource {
  const ReleaseSource();

  /// The release tag.
  String get tag;

  /// Constructs the full download URL for an artifact by name.
  Uri artifactUrl(String archiveName);

  /// Optional request headers needed to download artifacts from this source.
  Map<String, String> get requestHeaders => const {};

  /// Returns a copy of this release source with a different tag.
  ReleaseSource withTag(String tag);
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

  @override
  Uri artifactUrl(String archiveName) => baseUrl.resolve(archiveName);

  @override
  ReleaseSource withTag(String tag) => GitHubReleaseSource(
    owner: owner,
    repository: repository,
    tag: tag,
    baseUri: baseUri,
  );

  @override
  String toString() => 'GitHubReleaseSource($owner/$repository@$tag)';
}

/// Artifacts are hosted as GitLab release assets.
final class GitLabReleaseSource extends ReleaseSource {
  const GitLabReleaseSource({
    required this.projectPath,
    required this.tag,
    this.baseUri,
  });

  /// The GitLab project path or numeric project id.
  ///
  /// Example: `group/subgroup/project`.
  final String projectPath;

  /// The release tag.
  final String tag;

  /// Optional base URI for downloads.
  ///
  /// Defaults to the GitLab Releases API download URL for [projectPath] and
  /// [tag]. Useful for tests or self-managed mirrors.
  final Uri? baseUri;

  Uri get baseUrl =>
      baseUri ??
      Uri.parse(
        'https://gitlab.com/api/v4/projects/${Uri.encodeComponent(projectPath)}/releases/${Uri.encodeComponent(tag)}/downloads/',
      );

  @override
  Uri artifactUrl(String archiveName) => baseUrl.resolve(archiveName);

  @override
  ReleaseSource withTag(String tag) => GitLabReleaseSource(
    projectPath: projectPath,
    tag: tag,
    baseUri: baseUri,
  );

  @override
  String toString() => 'GitLabReleaseSource($projectPath@$tag)';
}
