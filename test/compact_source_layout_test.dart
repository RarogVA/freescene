import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freescene/android/android_theme.dart';
import 'package:freescene/android/remote_focus.dart';
import 'package:freescene/android/source_card.dart';
import 'package:freescene/catalog/catalog_models.dart';
import 'package:freescene/catalog/catalog_page.dart';
import 'package:freescene/catalog/watched.dart';

const title = CatalogTitle(
  id: 'series',
  kind: CatalogKind.series,
  name: 'Series',
);
CatalogSource source(String id) => CatalogSource(
  row: SourceRow(
    id: id,
    provider: const SourceProvider('fixture'),
    title: 'A long release title with audio information S01E02',
    watch: SourceKind.magnet,
    download: DownloadKind.magnet,
    quality: '1920x800',
    sizeBytes: 3400000000,
    durationSeconds: 3600,
    season: 1,
    episode: 2,
    catalogueCounts: const PeerCounts(seeds: 20),
  ),
  uri: Uri.parse('https://example.test/video.torrent'),
);
void main() {
  for (final dark in [true, false]) {
    testWidgets(
      'TV single row, themed outline and independent watched action dark=$dark',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(960, 540));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        const channel = MethodChannel('fixture/compact');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final writes = <MethodCall>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          writes.add(call);
          return null;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        final watched = WatchedController(channel), remote = RemoteFocus();
        var plays = 0;
        final theme = androidTheme(dark: dark, tv: true);
        await tester.pumpWidget(
          WatchedScope(
            controller: watched,
            child: MaterialApp(
              theme: theme,
              shortcuts: {
                ...WidgetsApp.defaultShortcuts,
                const SingleActivator(LogicalKeyboardKey.select):
                    ActivateIntent(),
              },
              home: Scaffold(
                body: FocusTraversalGroup(
                  policy: RemoteTraversalPolicy(remote),
                  child: Column(
                    children: [
                      for (final id in ['a', 'b'])
                        AndroidSourceCard(
                          source: source(id),
                          title: title,
                          focus: remote,
                          english: true,
                          series: true,
                          onPlay: () => plays++,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        final row = find.byKey(const ValueKey('remote-source-fixture-a'));
        final eye = find.byKey(const ValueKey('remote-watched-fixture-a'));
        tester.widget<OutlinedButton>(row).focusNode!.requestFocus();
        await tester.pump();
        expect(tester.getSize(row).height, lessThanOrEqualTo(60));
        final center = tester.getCenter(row).dy;
        for (final item in [
          'provider',
          'quality',
          'size',
          'duration',
          'availability',
        ]) {
          expect(
            tester.getCenter(find.byKey(ValueKey('bubble-$item')).first).dy,
            closeTo(center, 1),
          );
        }
        expect(
          tester
              .getCenter(find.byKey(const ValueKey('source-episode-fixture-a')))
              .dy,
          closeTo(center, 1),
        );
        expect(tester.getCenter(eye).dy, closeTo(center, 1));
        expect(find.text('Watch'), findsNothing);
        expect(
          tester.widget<OutlinedButton>(row).style!.side!.resolve({})!.color,
          theme.colorScheme.primary,
        );
        expect(
          tester
              .widget<OutlinedButton>(row)
              .style!
              .backgroundColor
              ?.resolve({}),
          isNot(theme.colorScheme.primary),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        expect(plays, 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(
          tester.widget<OutlinedButton>(eye).focusNode!.hasPrimaryFocus,
          isTrue,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pump();
        expect(writes.single.method, 'setWatched');
        expect(watched.sourceWatched(title, source('a')), isTrue);
        expect(plays, 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const ValueKey('remote-watched-fixture-b')),
              )
              .focusNode!
              .hasPrimaryFocus,
          isTrue,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        watched.dispose();
        remote.dispose();
      },
    );
  }
  testWidgets(
    'desktop stacked actions switch to icons without losing their actions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final actions = <bool>[];
      for (final compact in [false, true, false]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SourceTable(
                sources: [source('a'), source('b')],
                english: true,
                game: false,
                series: true,
                compactActions: compact,
                onUseSource: (_, watch) async => actions.add(watch),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final watch = find.byKey(const ValueKey('source-watch-fixture/a'));
        final download = find.byKey(
          const ValueKey('source-download-fixture/a'),
        );
        expect(tester.getCenter(watch).dx, tester.getCenter(download).dx);
        expect(
          tester.getRect(watch).bottom,
          lessThan(tester.getRect(download).top),
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('source-fixture-a'))).height,
          lessThanOrEqualTo(88),
        );
        final y = tester
            .getCenter(find.byKey(const ValueKey('bubble-provider')).first)
            .dy;
        for (final kind in ['quality', 'size', 'duration', 'availability']) {
          expect(
            tester.getCenter(find.byKey(ValueKey('bubble-$kind')).first).dy,
            closeTo(y, 1),
          );
        }
        expect(find.text('Watch'), compact ? findsNothing : findsNWidgets(2));
        final badges = find.byKey(const ValueKey('bubble-availability'));
        expect(
          tester.getRect(badges.first).right,
          tester.getRect(badges.last).right,
        );
        expect(
          tester.getRect(badges.first).right,
          closeTo(
            tester
                    .getRect(
                      find.byKey(const ValueKey('source-watched-fixture/a')),
                    )
                    .left -
                8 -
                12 -
                100,
            1,
          ),
        );
        if (compact) {
          expect(find.byTooltip('Watch'), findsNWidgets(2));
          expect(tester.getSize(watch), const Size(32, 32));
        }
        await tester.tap(watch);
        await tester.pumpAndSettle();
        await tester.tap(download);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(actions, [true, false, true, false, true, false]);
    },
  );
}
