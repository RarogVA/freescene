import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freescene/catalog/catalog_models.dart';
import 'package:freescene/catalog/watched.dart';
import 'package:freescene/catalog/source_metadata.dart';
import 'package:freescene/android/source_card.dart';
import 'package:freescene/android/remote_focus.dart';
import 'package:freescene/theme/freescene_theme.dart';

const title = CatalogTitle(
  id: 'movie1',
  kind: CatalogKind.movies,
  name: 'Film',
);
CatalogSource source(String id, {bool metadata = true}) => CatalogSource(
  row: SourceRow(
    id: id,
    provider: const SourceProvider('fixture'),
    title: 'A source title',
    watch: SourceKind.magnet,
    download: DownloadKind.magnet,
    quality: metadata ? '1920x800' : null,
    sizeBytes: metadata ? 2300000000 : null,
    durationSeconds: metadata ? 7200 : null,
    catalogueCounts: metadata
        ? const PeerCounts(seeds: 10)
        : const PeerCounts(),
  ),
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('cropped, intermediate and missing resolutions', () {
    for (final entry in <String, String?>{
      '3840x1608': '4К',
      '1920x800': '1080p',
      '2560x1440': '2К',
      '1366x768': '720p',
      '1024x576': '480p',
      '360p': '360p',
      '480p': '480p',
      '2160p HEVC': '4К',
      'HD': '720p',
      'unknown': null,
      '': null,
    }.entries) {
      expect(compactQuality(entry.key), entry.value, reason: entry.key);
    }
  });
  test('marks survive restore and aggregate across variants without touching other titles', () async {
    const channel = MethodChannel('fixture/watched');
    final persisted = <String, String>{};
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'watchedSnapshot') return Map.of(persisted);
      final args = Map<String, dynamic>.from(call.arguments as Map);
      if (args['watched'] == true) {
        persisted[args['watchedSource']] = args['watchedTitle'];
      } else {
        persisted.remove(args['watchedSource']);
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final first = WatchedController(channel);
    await first.toggle(title, source('a'));
    await first.toggle(title, source('b'));
    first.dispose();
    final restored = WatchedController(channel);
    addTearDown(restored.dispose);
    await restored.refresh();
    expect(restored.titleWatched(title), isTrue);
    await restored.toggle(title, source('a'));
    expect(restored.sourceWatched(title, source('a')), isFalse);
    expect(restored.titleWatched(title), isTrue);
    expect(
      restored.titleWatched(
        const CatalogTitle(
          id: 'other',
          kind: CatalogKind.movies,
          name: 'Other',
        ),
      ),
      isFalse,
    );
    await restored.toggle(title, source('b'));
    expect(restored.titleWatched(title), isFalse);
  });
  for (final width in [320.0, 390.0, 960.0]) {
    testWidgets('one mobile metadata line and actions inside card at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final remote = RemoteFocus(enabled: false);
      addTearDown(remote.dispose);
      var plays = 0, downloads = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: FreeSceneTheme.create(true),
          home: Scaffold(
            body: AndroidSourceCard(
              source: source('a'),
              title: title,
              focus: remote,
              english: false,
              series: false,
              onPlay: () => plays++,
              onDownload: () => downloads++,
            ),
          ),
        ),
      );
      final provider = tester.getRect(
        find.byKey(const ValueKey('bubble-provider')),
      );
      final quality = tester.getRect(
        find.byKey(const ValueKey('bubble-quality')),
      );
      final size = tester.getRect(find.byKey(const ValueKey('bubble-size')));
      expect(provider.top, quality.top);
      expect(size.top, provider.top);
      expect(
        tester.getRect(find.byKey(const ValueKey('bubble-duration'))).top,
        size.top,
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('bubble-availability'))).top,
        size.top,
      );
      final card = tester.getRect(
        find.byKey(const ValueKey('source-card-fixture-a')),
      );
      for (final label in ['Смотреть', 'Скачать']) {
        expect(card.contains(tester.getCenter(find.text(label))), isTrue);
        await tester.tap(find.text(label));
      }
      expect(plays, 1);
      expect(downloads, 1);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('unknown metadata produces no placeholders', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SourceMetadata(
          source: source('a', metadata: false),
          english: true,
        ),
      ),
    );
    for (final type in ['quality', 'size', 'duration', 'availability']) {
      expect(find.byKey(ValueKey('bubble-$type')), findsNothing);
    }
    expect(find.text('—'), findsNothing);
  });
}
