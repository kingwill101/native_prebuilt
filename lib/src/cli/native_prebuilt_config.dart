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
  final GitHubReleaseSource release;
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

    final releaseMap = _asMap(yaml['release'], 'release');
    final repository = _asString(releaseMap['repository'], 'release.repository');
    final tag = _asString(releaseMap['tag'], 'release.tag');
    final parts = repository.split('/');
    if (parts.length != 2) {
      throw FormatException(
        'release.repository must be "owner/repo" (got "$repository")',
      );
    }

    final artifactsMap = _asMap(yaml['artifacts'], 'artifacts');
    final artifacts = <String, NativePrebuiltArtifactConfig>{};
    for (final entry in artifactsMap.entries) {
      final platform = entry.key.toString();
      final artifactMap = _asMap(entry.value, 'artifacts.$platform');
      final archive = _asString(artifactMap['archive'], 'artifacts.$platform.archive');
      final payloadMap = _asMap(artifactMap['payload'], 'artifacts.$platform.payload');
      final type = _asString(payloadMap['type'], 'artifacts.$platform.payload.type');
      final acceptVersionedNames = payloadMap['accept_versioned_names'] != false;
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
      release: GitHubReleaseSource(
        owner: parts.first,
        repository: parts.last,
        tag: tag,
      ),
      artifacts: artifacts,
    );
  }

  static Map<String, dynamic> _asMap(Object? value, String name) {
    if (value is YamlMap) {
      return Map<String, dynamic>.from(value);
    }
    throw FormatException('$name must be a YAML mapping');
  }

  static String _asString(Object? value, String name) {
    if (value is String && value.isNotEmpty) return value;
    throw FormatException('$name must be a non-empty string');
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
