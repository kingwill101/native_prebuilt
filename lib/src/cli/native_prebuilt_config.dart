import 'dart:io';

import 'package:yaml/yaml.dart';

import '../manifest/prebuilt_artifact.dart';
import '../manifest/prebuilt_manifest.dart';
import '../manifest/release_source.dart';

/// Parsed CLI configuration for `native_prebuilt`.
final class NativePrebuiltConfig {
  const NativePrebuiltConfig({
    required this.schema,
    required this.package,
    required this.assetName,
    required this.libraryStem,
    required this.release,
    required this.artifacts,
  });

  final int schema;
  final String package;
  final String assetName;
  final String libraryStem;
  final ReleaseSource release;
  final Map<String, NativePrebuiltArtifactConfig> artifacts;

  static NativePrebuiltConfig loadFile(String path) {
    final file = File(path);
    final yaml = loadYaml(file.readAsStringSync());
    if (yaml is! YamlMap) {
      throw FormatException('Config must be a YAML mapping: $path');
    }

    int schema = 1;
    final schemaValue = yaml['schema'];
    if (schemaValue is int) schema = schemaValue;

    final package = _asString(yaml['package'], 'package');
    final assetName = _asString(yaml['asset_name'], 'asset_name');
    final libraryStem = _asString(yaml['library_stem'], 'library_stem');

    final release = _parseReleaseSource(_asMap(yaml['release'], 'release'));

    final artifactsMap = _asMap(yaml['artifacts'], 'artifacts');
    final artifacts = <String, NativePrebuiltArtifactConfig>{};
    for (final entry in artifactsMap.entries) {
      final platform = entry.key.toString();
      final artifactMap = _asMapOrNull(entry.value) ?? {};
      final archive =
          _asStringOrNull(artifactMap['archive']) ??
          '$package-$platform.tar.gz';
      final payloadMap = _asMapOrNull(artifactMap['payload']) ?? {};
      final type = _asStringOrNull(payloadMap['type']) ?? 'dynamic_library';
      final acceptVersionedNames =
          payloadMap['accept_versioned_names'] != false;
      final payload = switch (type) {
        'dynamic_library' => DynamicLibraryPayload(
          libraryStem: libraryStem,
          acceptVersionedNames: acceptVersionedNames,
        ),
        'static_library' => StaticLibraryPayload(libraryStem: libraryStem),
        _ => throw FormatException(
          'Unsupported payload type "$type" for artifacts.$platform',
        ),
      };
      artifacts[platform] = NativePrebuiltArtifactConfig(
        archiveName: archive,
        payload: payload,
      );
    }

    return NativePrebuiltConfig(
      schema: schema,
      package: package,
      assetName: assetName,
      libraryStem: libraryStem,
      release: release,
      artifacts: artifacts,
    );
  }

  static ReleaseSource _parseReleaseSource(Map<String, dynamic> releaseMap) {
    final provider =
        _asStringOrNull(releaseMap['provider'])?.toLowerCase() ?? 'github';
    final tag = _asString(releaseMap['tag'], 'release.tag');

    return switch (provider) {
      'github' => GitHubReleaseSource(
        owner: _asOwner(
          _asString(releaseMap['repository'], 'release.repository'),
        ),
        repository: _asRepo(
          _asString(releaseMap['repository'], 'release.repository'),
        ),
        tag: tag,
      ),
      'gitlab' => GitLabReleaseSource(
        projectPath: _asString(
          releaseMap['project'] ??
              releaseMap['project_path'] ??
              releaseMap['repository'],
          'release.project',
        ),
        tag: tag,
      ),
      _ => throw FormatException('Unsupported release.provider "$provider"'),
    };
  }

  static Map<String, dynamic> _asMap(Object? value, String name) {
    if (value is YamlMap) {
      return Map<String, dynamic>.from(value);
    }
    throw FormatException('$name must be a YAML mapping');
  }

  static Map<String, dynamic>? _asMapOrNull(Object? value) =>
      value is YamlMap ? Map<String, dynamic>.from(value) : null;

  static String _asString(Object? value, String name) {
    if (value is String && value.isNotEmpty) return value;
    throw FormatException('$name must be a non-empty string');
  }

  static String? _asStringOrNull(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static String _asOwner(String repository) {
    final parts = repository.split('/');
    if (parts.length != 2) {
      throw FormatException(
        'release.repository must be "owner/repo" (got "$repository")',
      );
    }
    return parts.first;
  }

  static String _asRepo(String repository) {
    final parts = repository.split('/');
    if (parts.length != 2) {
      throw FormatException(
        'release.repository must be "owner/repo" (got "$repository")',
      );
    }
    return parts.last;
  }

  PrebuiltManifest toManifest({
    required Map<String, String> archiveHashes,
    required Map<String, String> payloadHashes,
  }) {
    return PrebuiltManifest(
      schemaVersion: schema,
      release: release,
      artifacts: {
        for (final entry in artifacts.entries)
          entry.key: PrebuiltArtifact(
            archiveName: entry.value.archiveName,
            archiveSha256: archiveHashes[entry.key] ?? '',
            payloadSha256: payloadHashes[entry.key] ?? '',
            payload: entry.value.payload,
          ),
      },
    );
  }
}

/// Artifact metadata from the YAML config.
final class NativePrebuiltArtifactConfig {
  const NativePrebuiltArtifactConfig({
    required this.archiveName,
    required this.payload,
  });

  final String archiveName;
  final ArtifactPayload payload;
}
