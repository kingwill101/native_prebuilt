import 'package:native_prebuilt/native_prebuilt.dart';

void main() {
  const release = GitHubReleaseSource(
    owner: 'kingwill101',
    repository: 'dart_terminal',
    tag: 'demo-v1.0.0',
  );

  const manifest = PrebuiltManifest(
    schemaVersion: 1,
    release: release,
    artifacts: {
      'linux-x64': PrebuiltArtifact(
        archiveName: 'demo-linux-x64.tar.gz',
        archiveSha256: '0000000000000000000000000000000000000000000000000000000000000000',
        payloadSha256: '0000000000000000000000000000000000000000000000000000000000000000',
        payload: DynamicLibraryPayload(libraryStem: 'demo'),
      ),
    },
  );

  final target = const NativeTarget(
    os: OS.linux,
    architecture: Architecture.x64,
  );

  print('Target: ${target.label}');
  print('Artifacts: ${manifest.artifacts.length}');
  print('Release URL: ${release.artifactUrl('demo-linux-x64.tar.gz')}');
}
