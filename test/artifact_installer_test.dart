import 'dart:io';

import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  late HttpServer server;
  late Uri baseUri;
  var hitCount = 0;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUri = Uri.parse('http://127.0.0.1:${server.port}/');

    final archiveBytes = makeTarGz({
      'libdemo.so': makeElfBytes('demo-binary'),
    });

    server.listen((request) async {
      if (request.uri.path == '/artifact.tar.gz') {
        hitCount++;
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.binary
          ..add(archiveBytes)
          ..close();
      } else {
        request.response..statusCode = 404..close();
      }
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('installs and caches a downloaded artifact', () async {
    final temp = await Directory.systemTemp.createTemp('native_prebuilt_installer_');
    try {
      final archiveBytes = makeTarGz({
        'libdemo.so': makeElfBytes('demo-binary'),
      });
      final archiveHash = sha256Hash(archiveBytes);
      final payloadHash = sha256Hash(makeElfBytes('demo-binary'));

      final manifest = PrebuiltManifest(
        schemaVersion: 1,
        release: GitHubReleaseSource(
          owner: 'kingwill101',
          repository: 'dart_terminal',
          tag: 'v1',
          baseUri: baseUri,
        ),
        artifacts: {
          'linux-x64': PrebuiltArtifact(
            archiveName: 'artifact.tar.gz',
            archiveSha256: archiveHash,
            payloadSha256: payloadHash,
            payload: const DynamicLibraryPayload(libraryStem: 'demo'),
          ),
        },
      );

      final installer = DefaultArtifactInstaller();
      final target = const NativeTarget(
        os: OS.linux,
        architecture: Architecture.x64,
      );
      final cacheDir = Directory('${temp.path}/cache');

      final first = await installer.install(
        manifest: manifest,
        target: target,
        libraryStem: 'demo',
        payload: const DynamicLibraryPayload(libraryStem: 'demo'),
        cacheDirectory: cacheDir,
      );
      expect(first, isNotNull);
      expect(first!.readAsBytesSync().sublist(0, 4), [0x7F, 0x45, 0x4C, 0x46]);

      final second = await installer.install(
        manifest: manifest,
        target: target,
        libraryStem: 'demo',
        payload: const DynamicLibraryPayload(libraryStem: 'demo'),
        cacheDirectory: cacheDir,
      );
      expect(second, isNotNull);
      expect(second!.path, first.path);
      expect(hitCount, 1);
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('returns null for unsupported target', () async {
    final temp = await Directory.systemTemp.createTemp('native_prebuilt_installer_');
    try {
      final manifest = PrebuiltManifest(
        schemaVersion: 1,
        release: GitHubReleaseSource(
          owner: 'kingwill101',
          repository: 'dart_terminal',
          tag: 'v1',
          baseUri: baseUri,
        ),
        artifacts: const {},
      );

      final result = await DefaultArtifactInstaller().install(
        manifest: manifest,
        target: const NativeTarget(os: OS.linux, architecture: Architecture.x64),
        libraryStem: 'demo',
        payload: const DynamicLibraryPayload(libraryStem: 'demo'),
        cacheDirectory: Directory('${temp.path}/cache'),
      );
      expect(result, isNull);
    } finally {
      temp.deleteSync(recursive: true);
    }
  });
}
