import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as p;

import '../../build.dart';
import '../archive/archive_entry.dart';
import '../archive/archive_reader.dart';
import '../binary/library_name.dart';
import '../download/http_downloader.dart';
import '../manifest/prebuilt_artifact.dart';
import '../manifest/prebuilt_manifest.dart';
import '../manifest/release_source.dart';
import '../config/native_prebuilt_config.dart';

/// Compute a project-scoped cache key for a target.
///
/// Uses SHA-256 over the resolved project definition and target identity so
/// distinct projects/configurations do not share a cache directory.
String computeCacheKey(NativeProject project, NativeTarget target) {
  final buffer = StringBuffer()
    ..write(project.toJson())
    ..write('|')
    ..write(target.label);
  return sha256
      .convert(buffer.toString().codeUnits)
      .toString()
      .substring(0, 16);
}

Iterable<NativeTarget> supportedTargets(NativeProject project) sync* {
  for (final os in OS.values) {
    final iosSdks = os == OS.iOS ? IOSSdk.values : const <IOSSdk?>[null];
    for (final sdk in iosSdks) {
      for (final architecture in Architecture.values) {
        final target = NativeTarget(
          os: os,
          architecture: architecture,
          iOSSdk: sdk,
        );
        if (project.build.recipeFor(target) != null) {
          yield target;
        }
      }
    }
  }
}

List<String> supportedTargetLabels(NativeProject project) {
  final labels = supportedTargets(project).map((t) => t.label).toSet().toList();
  labels.sort();
  return labels;
}

/// Expected library filename for a given [target] and library [stem].
///
/// Uses [target] to determine the platform-specific naming convention
/// and [stem] as the library's base name (e.g., `tdjson`).
String expectedLibraryName({
  required NativeTarget target,
  required String stem,
}) {
  return canonicalLibraryName(
    target: target,
    libraryStem: stem,
    payload: DynamicLibraryPayload(libraryStem: stem),
  );
}

/// Parse a target label into a NativeTarget.
NativeTarget? parseTarget(String label) {
  try {
    return targetFromPlatformLabel(label);
  } on FormatException {
    return null;
  }
}

/// Reads the `build_from_source` user-defined flag from [input].
///
/// Returns `true` if the user has set `hooks.user_defines.<package>.build_from_source`
/// to `true`, or `false` otherwise.
bool shouldBuildFromSource(HookInput input) {
  final buildFromSource = input.userDefines['build_from_source'];
  if (buildFromSource is bool) {
    return buildFromSource;
  }
  return false;
}

Future<PrebuiltManifest> generateManifest({
  required NativePrebuiltConfig config,
  required String tag,
  required bool allowMissing,
  Directory? builtLibraryDir,
  Directory? releaseAssetsDir,
  bool toleratePartialBuiltLibrary = false,
}) async {
  final downloader = HttpDownloader();
  final archiveReader = ArchiveReader();
  final tempDir = await Directory.systemTemp.createTemp(
    'native_prebuilt_manifest_',
  );
  if (releaseAssetsDir != null) {
    releaseAssetsDir.createSync(recursive: true);
  }
  try {
    final payloadHashes = <String, String>{};
    final artifacts = <String, PrebuiltArtifact>{};

    for (final entry in config.artifacts.entries) {
      final platform = entry.key;
      final artifactConfig = entry.value;
      final target = targetFromPlatformLabel(platform);
      final payload = artifactConfig.payload.toArtifactPayload(
        config.libraryStem,
      );
      final canonicalName = canonicalLibraryName(
        target: target,
        libraryStem: config.libraryStem,
        payload: payload,
      );

      final archiveFile = File(
        p.join((releaseAssetsDir ?? tempDir).path, artifactConfig.archive),
      );
      if (builtLibraryDir != null) {
        final builtFileSearch = _findBuiltLibraryFile(
          builtLibraryDir: builtLibraryDir,
          platform: platform,
          canonicalName: canonicalName,
        );

        if (builtFileSearch == null) {
          if (allowMissing || toleratePartialBuiltLibrary) continue;

          throw StateError(
            'Missing built library for $platform. Checked:\n'
            '  ${p.join(builtLibraryDir.path, platform, canonicalName)}\n'
            '  ${p.join(builtLibraryDir.path, canonicalName)}\n'
            '  ${p.join(builtLibraryDir.path, platform)}/**/$canonicalName',
          );
        }

        await packageBuiltLibrary(
          builtFile: builtFileSearch,
          archiveFile: archiveFile,
        );
      } else {
        try {
          await downloader.downloadReleaseArtifact(
            source: config.release.toReleaseSource().withTag(tag),
            archiveName: artifactConfig.archive,
            targetPath: archiveFile,
          );
        } catch (e) {
          if (allowMissing) continue;
          rethrow;
        }
      }

      final archiveHash = await ArchiveReader.sha256Hash(archiveFile);

      final extractedDir = Directory(p.join(tempDir.path, 'extract_$platform'))
        ..createSync(recursive: true);
      final extracted = archiveReader.extractMatchingEntry(
        archiveFile: archiveFile,
        outputDir: extractedDir,
        selection: ArchiveSelectionContext(
          canonicalName: canonicalName,
          acceptVersionedNames: payload is DynamicLibraryPayload,
        ),
      );
      if (extracted == null) {
        if (allowMissing) continue;
        throw StateError('No payload found for $platform');
      }
      payloadHashes[platform] = await ArchiveReader.sha256Hash(extracted);

      artifacts[platform] = PrebuiltArtifact(
        archiveName: artifactConfig.archive,
        archiveSha256: archiveHash,
        payloadSha256: payloadHashes[platform]!,
        payload: payload,
      );
    }

    return PrebuiltManifest(
      schemaVersion: config.schema,
      release: config.release.toReleaseSource().withTag(tag),
      artifacts: artifacts,
    );
  } finally {
    tempDir.deleteSync(recursive: true);
  }
}

String renderManifest(
  NativePrebuiltConfig config,
  PrebuiltManifest manifest,
  String tag,
) {
  final b = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND.')
    ..writeln(
      '// ignore_for_file: constant_identifier_names, depend_on_referenced_packages',
    )
    ..writeln()
    ..writeln("import 'package:native_prebuilt/native_prebuilt.dart';")
    ..writeln()
    ..writeln('const ${config.package}Prebuilts = PrebuiltManifest(')
    ..writeln('  schemaVersion: ${manifest.schemaVersion},')
    ..writeln(
      '  release: ${renderReleaseSource(config.release.toReleaseSource().withTag(tag))},',
    )
    ..writeln('  artifacts: {');

  for (final entry in manifest.artifacts.entries) {
    final platform = entry.key;
    final artifact = entry.value;
    b.writeln("    '$platform': PrebuiltArtifact(");
    b.writeln("      archiveName: '${artifact.archiveName}',");
    b.writeln("      archiveSha256: '${artifact.archiveSha256}',");
    b.writeln("      payloadSha256: '${artifact.payloadSha256}',");
    b.writeln('      payload: ${renderPayload(artifact.payload)},');
    b.writeln('    ),');
  }

  b
    ..writeln('  },')
    ..writeln(');')
    ..writeln();
  return b.toString();
}

Future<void> packageBuiltLibrary({
  required File builtFile,
  required File archiveFile,
}) async {
  final result = await ProcessRunner().runStreaming('tar', [
    'czf',
    archiveFile.path,
    '-C',
    builtFile.parent.path,
    p.basename(builtFile.path),
  ], requireSuccess: false);
  if (result.exitCode != 0) {
    throw StateError(
      'tar create failed for ${builtFile.path}: ${result.stderr.trim()}',
    );
  }
}

File? _findBuiltLibraryFile({
  required Directory builtLibraryDir,
  required String platform,
  required String canonicalName,
}) {
  final platformDir = Directory(p.join(builtLibraryDir.path, platform));

  final directCandidates = [
    File(p.join(platformDir.path, canonicalName)),
    File(p.join(builtLibraryDir.path, canonicalName)),
  ];
  for (final candidate in directCandidates) {
    if (candidate.existsSync()) {
      return candidate;
    }
  }

  if (!platformDir.existsSync()) {
    return null;
  }

  final recursiveMatches =
      platformDir
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => p.basename(file.path) == canonicalName)
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  return recursiveMatches.isEmpty ? null : recursiveMatches.first;
}

String renderPayload(ArtifactPayload payload) => switch (payload) {
  DynamicLibraryPayload(:final libraryStem, :final acceptVersionedNames) =>
    'DynamicLibraryPayload(libraryStem: \'$libraryStem\', acceptVersionedNames: $acceptVersionedNames)',
  StaticLibraryPayload(:final libraryStem) =>
    'StaticLibraryPayload(libraryStem: \'$libraryStem\')',
};

String renderReleaseSource(ReleaseSource source) => switch (source) {
  GitHubReleaseSource(:final owner, :final repository, :final tag) =>
    'GitHubReleaseSource(owner: \'$owner\', repository: \'$repository\', tag: \'$tag\')',
  GitLabReleaseSource(:final projectPath, :final tag) =>
    'GitLabReleaseSource(projectPath: \'$projectPath\', tag: \'$tag\')',
};

NativeTarget targetFromPlatformLabel(String label) {
  final parts = label.split('-');
  if (label.startsWith('ios-sim-') && parts.length == 3) {
    return NativeTarget(
      os: OS.iOS,
      architecture: Architecture.fromString(parts[2]),
      iOSSdk: IOSSdk.iPhoneSimulator,
    );
  }
  if (parts.length != 2) {
    throw FormatException('Unsupported platform label: $label');
  }
  return NativeTarget(
    os: OS.fromString(parts[0]),
    architecture: Architecture.fromString(parts[1]),
  );
}
