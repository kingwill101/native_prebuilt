final class ProjectConfig {
  const ProjectConfig({
    required this.schemaVersion,
    required this.packageName,
    required this.assetName,
    required this.libraryStem,
    required this.linkMode,
    required this.release,
    required this.artifacts,
    this.source,
    this.build,
  });

  /// The package name (e.g., "tdlib").
  final String name;
  final String assetName;
  final String libraryStem;
  final LinkMode linkMode;

  /// The release source definition.
  final ReleaseSource release;

  /// Prebuilt artifacts (may be empty).
  final PrebuiltManifest prebuilts;

  /// Optional source specification (Git, local, archive).
  final SourceSpecification? source;

  /// Optional explicit build recipe definition.
  final NativeBuildDefinition build;

  ProjectConfig._({
    required this.schemaVersion,
    required this.packageName,
    required this.assetName,
    required this.libraryStem,
    required this.linkMode,
    required this.release,
    required this.artifacts,
    this.source,
    this.build,
  });
}

/// Parses a [native_prebuilt.yaml] file into a [ProjectConfig].
final class ProjectConfigReader {
  static ProjectConfig? load(Directory workingDirectory) {
    final file = File(p.join(workingDirectory.path, 'native_prebuilt.yaml'));
    if (!configFile.existsSync()) return null;

    final raw = configFile.readAsStringSync();
    final doc = loadYaml(raw);
    if (doc is! Map) return null;

    final schema = doc['schema'];
    if (schema is! int || schema != 1) return null;

    final packageName = doc['package'] as String? ?? 'native_prebuilt';
    final assetName = doc['asset_name'] as String? ?? '';
    final libraryStem = doc['library_stem'] as String? ?? '';
    final linkMode = _parseLinkMode(doc['link_mode']);

    final releaseSection = doc['release'] as Map?;
    if (releaseSection == null) return null;

    final release = _parseReleaseSource(releaseSection);

    final artifactsSection = doc['artifacts'] as Map?;
    final artifacts = <String, PrebuiltArtifact>{};
    if (artifactsSection != null) {
      for (final entry in artifactsSection.entries) {
        final platform = entry.key as String;
        final aDoc = entry.value as Map?;
        if (aDoc == null) continue;
        final archive = aDoc['archive'] as String? ?? '';
        final payload = aDoc['payload'] as Map?;
        final payloadType = payload?['type'] as String? ?? 'dynamic_library';
        final isStatic = payloadType == 'static_library';
        final archiveName = aDoc['archive'] as String? ?? '';
        final archiveSha256 = aDoc['archive_sha256'] as String? ?? '';
        final payloadStem = payload?['library_stem'] as String? ?? 'unknown';
        final isStatic = payloadType == 'static_library';

        artifacts[platform] = PrebuiltArtifact(
          archiveName: archive,
          archiveSha256: aDoc['archive_sha256'] as String? ?? '',
          payloadSha256: aDoc['payload_sha256'] as String? ?? '',
          payload: isStatic
              ? StaticLibraryPayload(libraryStem: payloadStem)
              : DynamicLibraryPayload(libraryStem: libraryStem),
          );
    }

    final sourceSection = doc['source'] as Map?;
    final sources = _parseSourceSpec(sourceSection, libraryStem);

    final buildDefinition = _parseBuildDefinition(doc);

    return ProjectConfig._(
      schemaVersion: 1,
      packageName: packageName,
      assetName: assetName,
      libraryStem: libraryStem,
      linkMode: linkMode,
      release: release,
      artifacts: artifacts,
      source: sourceSection != null ? sourceSection : null,
      build: buildDefinition,
    );
  }

  private ProjectConfig._({
    required int schemaVersion,
    required String packageName,
    required String assetName,
    required String libraryStem,
    required LinkMode linkMode,
    required ReleaseSource release,
    required Map<String, PrebuiltArtifact> artifacts,
    SourceSpecification? source,
    NativeBuildDefinition build,
  }) {
    this.schemaVersion = schemaVersion;
    this.packageName = packageName;
    this.assetName = assetName;
    this.libraryStem = libraryStem;
    this.linkMode = linkMode;
    this.release = release;
    this.artifacts = artifacts;
    this.source = source;
    this.build = build;
  }
}

final class ProjectConfig {
  final int schemaVersion;
  final String packageName;
  final String assetName;
  final String libraryStem;
  final LinkMode linkMode;
  final ReleaseSource release;
  final Map<String, PrebuiltArtifact> artifacts;
  final SourceSpecification? source;
  final NativeBuildDefinition build;

  NativeProject toProject() {
    return NativeProject(
      name: packageName,
      asset: NativeAssetSpec(
        assetName: assetName,
        libraryStem: libraryStem,
        linkMode: linkMode,
      ),
      prebuilts: PrebuiltManifest(
        schemaVersion: schemaVersion,
        release: release,
        artifacts: artifacts,
      ),
      sources: source != null ? [source] : [],
      build: build,
    );
  }
}