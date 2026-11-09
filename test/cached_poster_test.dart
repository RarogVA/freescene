import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freescene/catalog/cached_poster.dart';
import 'package:freescene/catalog/poster_cache.dart';

class _PosterFiles extends PosterDiskCache {
  _PosterFiles(super.directory, this.files);
  final List<File> files;
  int requests = 0, invalidations = 0;

  @override
  Future<File?> get(Uri uri) async =>
      files[(requests++).clamp(0, files.length - 1)];

  @override
  Future<void> invalidate(Uri uri, {File? expected}) async {
    invalidations++;
  }
}

void main() {
  late Directory directory;
  late File broken, valid;
  late _PosterFiles cache;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('freescene-poster-widget-');
    broken = File('${directory.path}/broken.image')
      ..writeAsStringSync('not a decodable image');
    valid = File('${directory.path}/valid.image')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNQSFjwHwAD5AIge4YO3AAAAABJRU5ErkJggg==',
        ),
      );
  });
  tearDown(() {
    cache.close();
    PaintingBinding.instance.imageCache.clear();
    directory.deleteSync(recursive: true);
  });

  Future<void> mount(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 160,
          height: 90,
          child: CachedPoster(
            uri: Uri.parse('https://posters.example/fixture.jpg'),
            cache: cache,
            placeholder: const Text('No preview'),
          ),
        ),
      ),
    ),
  );

  Future<void> pumpUntil(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 100 && !ready(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(ready(), isTrue);
  }

  testWidgets(
    'a corrupt cached poster is replaced by a decoded image without a framework error',
    (tester) async {
      cache = _PosterFiles(directory, [broken, valid]);
      await mount(tester);
      await pumpUntil(
        tester,
        () => tester
            .widgetList<RawImage>(find.byType(RawImage))
            .any((image) => image.image != null),
      );
      expect(cache.requests, 2);
      expect(cache.invalidations, 1);
      expect(find.text('No preview'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'an undecodable replacement keeps the placeholder without an endless retry',
    (tester) async {
      cache = _PosterFiles(directory, [broken]);
      await mount(tester);
      await pumpUntil(tester, () => cache.requests == 2);
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(cache.requests, 2);
      expect(cache.invalidations, 1);
      expect(find.text('No preview'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
