import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freescene/catalog/poster_cache.dart';

final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jxZkAAAAASUVORK5CYII=',
);
Future<void> until(bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(ready(), true);
}

void main() {
  late Directory directory;
  late HttpServer server;
  late PosterDiskCache cache;
  late Uri uri;
  late int calls, status;
  late String? conditional;
  late bool html;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('freescene-posters-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    uri = Uri.parse('http://127.0.0.1:${server.port}/poster');
    cache = PosterDiskCache(directory);
    calls = 0;
    status = 200;
    conditional = null;
    html = false;
    server.listen((request) async {
      calls++;
      conditional = request.headers.value(HttpHeaders.ifNoneMatchHeader);
      request.response.statusCode = status;
      request.response.headers.contentType = html
          ? ContentType.html
          : ContentType('image', 'png');
      request.response.headers.set(HttpHeaders.etagHeader, 'fixture');
      if (status == 200) {
        request.response.add(
          html ? utf8.encode('<html>challenge</html>') : png,
        );
      }
      await request.response.close();
    });
  });
  tearDown(() async {
    cache.close();
    await server.close(force: true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await directory.delete(recursive: true);
  });
  test(
    'concurrent tiles share one request; a reopened cache works offline',
    () async {
      final files = await Future.wait([
        for (var i = 0; i < 12; i++) cache.get(uri),
      ]);
      expect(calls, 1);
      expect(files.map((f) => f!.path).toSet().length, 1);
      cache.close();
      status = 500;
      cache = PosterDiskCache(directory);
      expect(await (await cache.get(uri))!.readAsBytes(), png);
      expect(calls, 1);
    },
  );
  test(
    'stale image is returned while conditional refresh revalidates it',
    () async {
      final first = (await cache.get(uri))!;
      cache.close();
      status = 304;
      cache = PosterDiskCache(directory, maxAge: Duration.zero);
      expect((await cache.get(uri))!.path, first.path);
      await until(() => calls == 2 && conditional == 'fixture');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(await first.readAsBytes(), png);
    },
  );
  test('an unavailable refresh preserves the usable cached image', () async {
    final first = (await cache.get(uri))!;
    cache.close();
    status = 500;
    cache = PosterDiskCache(directory, maxAge: Duration.zero);
    expect((await cache.get(uri))!.path, first.path);
    await until(() => calls == 2);
    expect(await first.readAsBytes(), png);
  });
  test(
    'HTML is never stored as a preview and failures are cooled down',
    () async {
      html = true;
      expect(await cache.get(uri), isNull);
      expect(await cache.get(uri), isNull);
      expect(calls, 1);
      expect(directory.listSync(), isEmpty);
      await cache.invalidate(uri);
      html = false;
      expect(await cache.get(uri), isNotNull);
    },
  );
  test('a corrupted cached image is downloaded again', () async {
    final first = (await cache.get(uri))!;
    await first.writeAsBytes(utf8.encode('damaged file contents'));
    final second = (await cache.get(uri))!;
    expect(calls, 2);
    expect(second.path, isNot(first.path));
    expect(await second.readAsBytes(), png);
  });
  test(
    'eviction removes the least recently used image and its manifest',
    () async {
      cache.close();
      cache = PosterDiskCache(directory, maxEntries: 2);
      final a = (await cache.get(uri.resolve('/a')))!;
      final b = (await cache.get(uri.resolve('/b')))!;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await cache.get(uri.resolve('/a'));
      await cache.get(uri.resolve('/c'));
      await until(() => !b.existsSync());
      expect(a.existsSync(), true);
      expect(
        directory.listSync().where((f) => f.path.endsWith('.json')).length,
        2,
      );
    },
  );
  test('plain remote HTTP and credential URLs never cause a request', () async {
    expect(await cache.get(Uri.parse('http://example.com/a.jpg')), isNull);
    expect(await cache.get(uri.replace(userInfo: 'secret')), isNull);
    expect(calls, 0);
  });
}
