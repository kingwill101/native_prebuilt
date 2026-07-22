import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:test/test.dart';

void main() {
  test('GitHubReleaseSource artifact URL construction', () {
    const source = GitHubReleaseSource(
      owner: 'kingwill101',
      repository: 'dart_terminal',
      tag: 'portable_pty-v0.0.6',
    );

    expect(
      source.artifactUrl('pty-linux-x64.tar.gz').toString(),
      'https://github.com/kingwill101/dart_terminal/releases/download/'
      'portable_pty-v0.0.6/pty-linux-x64.tar.gz',
    );
  });

  test('manifest lookup', () {
    const manifest = PrebuiltManifest(
      schemaVersion: 1,
      release: GitHubReleaseSource(
        owner: 'test',
        repository: 'repo',
        tag: 'v1',
      ),
      artifacts: {
        'linux-x64': PrebuiltArtifact(
          archiveName: 'linux.tar.gz',
          archiveSha256: 'a',
          payloadSha256: 'b',
          payload: DynamicLibraryPayload(libraryStem: 'mylib'),
        ),
      },
    );

    expect(manifest.supports('linux-x64'), isTrue);
    expect(manifest['linux-x64']?.archiveName, 'linux.tar.gz');
    expect(manifest['macos-arm64'], isNull);
  });

  test('artifact payloads stringify', () {
    expect(
      const DynamicLibraryPayload(libraryStem: 'mylib').toString(),
      contains('mylib'),
    );
    expect(
      const StaticLibraryPayload(libraryStem: 'mylib').toString(),
      contains('mylib'),
    );
  });
}
