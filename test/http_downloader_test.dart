import 'dart:io';

import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late Uri baseUri;
  var retryCount = 0;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUri = Uri.parse('http://127.0.0.1:${server.port}/');
    retryCount = 0;
    server.listen((request) async {
      switch (request.uri.path) {
        case '/artifact.tar.gz':
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.binary
            ..add([1, 2, 3, 4])
            ..close();
        case '/redirect.tar.gz':
          request.response
            ..statusCode = 302
            ..headers.set(HttpHeaders.locationHeader, '/artifact.tar.gz')
            ..close();
        case '/retry.tar.gz':
          retryCount++;
          if (retryCount < 2) {
            request.response
              ..statusCode = 500
              ..close();
          } else {
            request.response
              ..statusCode = 200
              ..add([9, 8, 7])
              ..close();
          }
        case '/large.tar.gz':
          request.response
            ..statusCode = 200
            ..add(List<int>.filled(32, 0))
            ..close();
        default:
          request.response..statusCode = 404..close();
      }
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('downloads a file', () async {
    final file = File('${Directory.systemTemp.path}/native_prebuilt_download.bin');
    if (file.existsSync()) file.deleteSync();

    await const HttpDownloader().download(
      baseUri.resolve('artifact.tar.gz'),
      file,
    );

    expect(file.readAsBytesSync(), [1, 2, 3, 4]);
  });

  test('follows redirects', () async {
    final file = File('${Directory.systemTemp.path}/native_prebuilt_redirect.bin');
    if (file.existsSync()) file.deleteSync();

    await const HttpDownloader().download(
      baseUri.resolve('redirect.tar.gz'),
      file,
    );

    expect(file.readAsBytesSync(), [1, 2, 3, 4]);
  });

  test('retries transient failures', () async {
    final file = File('${Directory.systemTemp.path}/native_prebuilt_retry.bin');
    if (file.existsSync()) file.deleteSync();

    await const HttpDownloader(
      policy: HttpDownloadPolicy(maxAttempts: 3),
    ).download(
      baseUri.resolve('retry.tar.gz'),
      file,
    );

    expect(file.readAsBytesSync(), [9, 8, 7]);
    expect(retryCount, 2);
  });

  test('enforces maximum download size', () async {
    final file = File('${Directory.systemTemp.path}/native_prebuilt_large.bin');
    if (file.existsSync()) file.deleteSync();

    expect(
      () => const HttpDownloader(
        policy: HttpDownloadPolicy(maximumBytes: 8),
      ).download(baseUri.resolve('large.tar.gz'), file),
      throwsA(isA<HttpDownloadException>()),
    );
  });

  test('downloads release artifacts using baseUri', () async {
    final file = File('${Directory.systemTemp.path}/native_prebuilt_release.bin');
    if (file.existsSync()) file.deleteSync();

    final source = GitHubReleaseSource(
      owner: 'kingwill101',
      repository: 'dart_terminal',
      tag: 'v1',
      baseUri: baseUri,
    );

    await const HttpDownloader().downloadReleaseArtifact(
      source: source,
      archiveName: 'artifact.tar.gz',
      targetPath: file,
    );

    expect(file.readAsBytesSync(), [1, 2, 3, 4]);
  });
}
