import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:test/test.dart';

void main() {
  group('NativeTarget', () {
    test('label generation', () {
      expect(
        const NativeTarget(
          os: OS.linux,
          architecture: Architecture.x64,
        ).label,
        'linux-x64',
      );

      expect(
        const NativeTarget(
          os: OS.macOS,
          architecture: Architecture.arm64,
        ).label,
        'macos-arm64',
      );

      expect(
        const NativeTarget(
          os: OS.iOS,
          architecture: Architecture.arm64,
          iOSSdk: IOSSdk.iPhoneSimulator,
        ).label,
        'ios-sim-arm64',
      );

      expect(
        const NativeTarget(
          os: OS.windows,
          architecture: Architecture.x64,
        ).label,
        'windows-x64',
      );
    });

    test('equality', () {
      const a = NativeTarget(
        os: OS.linux,
        architecture: Architecture.x64,
      );
      const b = NativeTarget(
        os: OS.linux,
        architecture: Architecture.x64,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('inequality', () {
      const a = NativeTarget(
        os: OS.linux,
        architecture: Architecture.x64,
      );
      const b = NativeTarget(
        os: OS.linux,
        architecture: Architecture.arm64,
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('PrebuiltManifest', () {
    test('lookup by platform', () {
      const manifest = PrebuiltManifest(
        schemaVersion: 1,
        release: GitHubReleaseSource(
          owner: 'test',
          repository: 'repo',
          tag: 'lib-v1.0.0',
        ),
        artifacts: {
          'linux-x64': PrebuiltArtifact(
            archiveName: 'lib-linux-x64.tar.gz',
            archiveSha256: 'aabb',
            payloadSha256: 'ccdd',
            payload: DynamicLibraryPayload(libraryStem: 'mylib'),
          ),
        },
      );

      expect(manifest.supports('linux-x64'), isTrue);
      expect(manifest.supports('macos-arm64'), isFalse);
      expect(manifest['linux-x64']?.archiveName, 'lib-linux-x64.tar.gz');
      expect(manifest['macos-arm64'], isNull);
    });
  });

  group('GitHubReleaseSource', () {
    test('artifact URL construction', () {
      const source = GitHubReleaseSource(
        owner: 'kingwill101',
        repository: 'dart_terminal',
        tag: 'portable_pty-v0.0.6',
      );

      final url = source.artifactUrl('pty-linux-x64.tar.gz');
      expect(
        url.toString(),
        'https://github.com/kingwill101/dart_terminal/releases/download/'
        'portable_pty-v0.0.6/pty-linux-x64.tar.gz',
      );
    });
  });

  group('ArtifactPayload', () {
    test('DynamicLibraryPayload', () {
      const payload = DynamicLibraryPayload(libraryStem: 'mylib');
      expect(payload.libraryStem, 'mylib');
      expect(payload.acceptVersionedNames, isTrue);
    });

    test('StaticLibraryPayload', () {
      const payload = StaticLibraryPayload(libraryStem: 'mylib');
      expect(payload.libraryStem, 'mylib');
    });
  });

  group('ResolutionAttempt', () {
    test('toString', () {
      const attempt = ResolutionAttempt(
        source: PrebuiltSource.download,
        success: true,
        path: '/path/to/lib.so',
      );
      expect(attempt.toString(), contains('download: found'));
      expect(attempt.toString(), contains('/path/to/lib.so'));
    });
  });
}
