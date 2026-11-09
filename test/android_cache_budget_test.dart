import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freescene/catalog/poster_cache.dart';

void main() {
  test(
    'low-memory poster loading keeps at most two network requests in flight',
    () async {
      final root = await Directory.systemTemp.createTemp('freescene-tv-cache-');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final cache = PosterDiskCache(root, maxConcurrent: 2);
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jxZkAAAAASUVORK5CYII=',
      );
      var active = 0, peak = 0, requests = 0;
      final firstPair = Completer<void>();
      final release = Completer<void>();
      server.listen((request) async {
        active++;
        requests++;
        if (active > peak) peak = active;
        if (requests == 2) firstPair.complete();
        await release.future;
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(png);
        await request.response.close();
        active--;
      });
      final work = Future.wait([
        for (var i = 0; i < 12; i++)
          cache.get(Uri.parse('http://127.0.0.1:${server.port}/$i.png')),
      ]);
      try {
        await firstPair.future.timeout(const Duration(seconds: 5));
        expect(requests, 2);
        release.complete();
        final images = await work;
        expect(images.whereType<File>().length, 12);
        expect(peak, 2);
      } finally {
        if (!release.isCompleted) release.complete();
        cache.close();
        await server.close(force: true);
        await work;
        // Let the existing serialized prune finish before removing the fixture.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await root.delete(recursive: true);
      }
    },
  );
}
