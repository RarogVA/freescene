import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freescene/app.dart';
import 'package:freescene/android/android_app.dart';
import 'package:freescene/android/android_runtime.dart';
import 'package:freescene/android/remote_focus.dart';
import 'package:freescene/catalog/catalog_models.dart';
import 'package:freescene/history/watch_history.dart';
import 'package:freescene/history/watch_history_page.dart';
import 'package:freescene/settings/preferences.dart';
import 'package:freescene/theme/freescene_theme.dart';
import 'package:freescene/torrent/native_torrent.dart';

class EmptyCatalog extends CatalogRepository {
  @override
  Future<CatalogPage<CatalogTitle>> list(
    CatalogKind kind, {
    String search = '',
    CatalogFilter filter = const CatalogFilter(),
    int start = 0,
  }) async => const CatalogPage(items: [], total: 0, start: 0);
  @override
  Future<CatalogTitle> details(CatalogTitle title) async => title;
  @override
  Future<CatalogPage<CatalogSource>> sources(
    CatalogTitle title, {
    int start = 0,
  }) async => const CatalogPage(items: [], total: 0, start: 0);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/watch-history');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<Map<String, Object?>> entries;
  bool failRead = false, failDelete = false;
  final calls = <MethodCall>[];
  Map<String, Object?> entry(int index, DateTime day) => {
    'id': index.toRadixString(16).padLeft(64, '0'),
    'title': 'Сериал $index',
    'subtitle': 'Series.S01E0$index.1080p.mkv',
    'provider': 'Zona',
    'sizeBytes': 1000000000,
    'sourceType': 'torrent',
    'watchedAt': day.millisecondsSinceEpoch,
  };
  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    if (call.method == 'watchHistorySnapshot') {
      if (failRead) throw PlatformException(code: 'read');
      return {'entries': entries};
    }
    if (call.method == 'watchHistoryRemove') {
      if (failDelete) throw PlatformException(code: 'delete');
      final ids = (call.arguments as Map)['ids'] as List;
      final count = entries.length;
      entries.removeWhere((e) => ids.contains(e['id']));
      return {'removed': count - entries.length};
    }
    if (call.method == 'checkUpdate') return {'available': false};
    return <String, Object>{};
  }

  setUp(() {
    calls.clear();
    entries = [
      entry(1, DateTime(2026, 1, 3, 10)),
      entry(2, DateTime(2026, 1, 2, 20)),
      entry(3, DateTime(2026, 1, 3, 19)),
    ];
    failRead = failDelete = false;
    for (final c in [
      channel,
      AndroidRuntime.channel,
      NativeTorrentService.channel,
    ]) {
      messenger.setMockMethodCallHandler(c, handle);
    }
  });
  tearDown(() {
    for (final c in [
      channel,
      AndroidRuntime.channel,
      NativeTorrentService.channel,
    ]) {
      messenger.setMockMethodCallHandler(c, null);
    }
  });
  void size(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  test('sorts by timestamp and groups by local calendar day', () async {
    final controller = WatchHistoryController(channel);
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.entries.map((e) => e.title), [
      'Сериал 3',
      'Сериал 1',
      'Сериал 2',
    ]);
    expect(watchHistoryDay(controller.entries.first.watchedAt), '03.01.2026');
    expect(controller.entries.first.episodeLabel, 'S01E03');
    expect(controller.entries.first.quality, '1080p');
    await controller.remove({controller.entries[1].id});
    expect(controller.entries.length, 2);
    failRead = true;
    await controller.refresh();
    expect(controller.error, isNotNull);
    expect(controller.entries.length, 2);
  });
  Finder dialogLabel(String label) =>
      find.descendant(of: find.byType(AlertDialog), matching: find.text(label));

  for (final scenario in [
    (320.0, false, false),
    (960.0, true, false),
    (1280.0, false, true),
  ]) {
    testWidgets('date headers without times; selection/removal $scenario', (
      tester,
    ) async {
      size(tester, Size(scenario.$1, 800));
      final controller = WatchHistoryController(channel);
      addTearDown(controller.dispose);
      await controller.refresh();
      final remote = scenario.$3 ? RemoteFocus() : null;
      if (remote != null) addTearDown(remote.dispose);
      var plays = 0;
      final key = GlobalKey<WatchHistoryPageState>();
      await tester.pumpWidget(
        MaterialApp(
          theme: FreeSceneTheme.create(!scenario.$2),
          home: Scaffold(
            body: WatchHistoryPage(
              key: key,
              mobile: scenario.$1 == 320,
              controller: controller,
              english: scenario.$2,
              remote: remote,
              onBack: () {},
              onPlay: (_) async {
                plays++;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('03.01.2026'), findsOneWidget);
      final topEntry = controller.entries.first.id;
      final titleRect = tester.getRect(
        find.byKey(ValueKey('history-title-$topEntry')),
      );
      final badgeRect = tester.getRect(
        find.byKey(ValueKey('history-badges-$topEntry')),
      );
      if (scenario.$1 == 320) {
        expect(badgeRect.top, greaterThan(titleRect.bottom));
      } else {
        expect(badgeRect.left, greaterThan(titleRect.right));
      }

      await tester.tap(find.byKey(ValueKey('history-row-$topEntry')));
      await tester.pumpAndSettle();
      expect(plays, 1);
      expect(key.currentState!.selecting, isFalse);
      expect(find.textContaining('19:00'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('history-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('history-all')));
      await tester.pumpAndSettle();
      expect(
        find.text(scenario.$2 ? 'Selected: 3' : 'Выбрано: 3'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('history-delete')));
      await tester.pumpAndSettle();
      expect(entries.length, 3);
      final cancel = dialogLabel(scenario.$2 ? 'Cancel' : 'Отмена');
      expect(Focus.of(tester.element(cancel)).hasFocus, isTrue);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(
        calls.where((call) => call.method == 'watchHistoryRemove'),
        isEmpty,
      );
      expect(key.currentState!.selected, hasLength(3));
      await tester.tap(find.byKey(const ValueKey('history-delete')));
      await tester.pumpAndSettle();
      await tester.tap(dialogLabel(scenario.$2 ? 'Delete' : 'Удалить'));
      await tester.pumpAndSettle();
      expect(entries, isEmpty);
      expect(find.byKey(const ValueKey('watch-history-list')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'deletion error keeps selection and Back cancels selection first',
    (tester) async {
      final controller = WatchHistoryController(channel);
      addTearDown(controller.dispose);
      await controller.refresh();
      var back = 0;
      final key = GlobalKey<WatchHistoryPageState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WatchHistoryPage(
              key: key,
              controller: controller,
              english: false,
              onBack: () => back++,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('history-select')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('history-all')));
      await tester.pump();
      failDelete = true;
      await tester.tap(find.byKey(const ValueKey('history-delete')));
      await tester.pumpAndSettle();
      await tester.tap(dialogLabel('Удалить'));
      await tester.pumpAndSettle();
      expect(find.text('Выбрано: 3'), findsOneWidget);
      expect(entries.length, 3);
      await tester.tap(find.byKey(const ValueKey('history-back')));
      await tester.pump();
      expect(back, 0);
      await tester.tap(find.byKey(const ValueKey('history-back')));
      expect(back, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final tv in [false, true]) {
    testWidgets('Android history navigation and lists menu tv=$tv', (
      tester,
    ) async {
      size(tester, tv ? const Size(1280, 720) : const Size(390, 844));
      await tester.pumpWidget(
        AndroidApp(
          runtime: AndroidRuntime(
            profile: Directory('/tmp/freescene-history-test'),
            cache: Directory('/tmp/freescene-history-cache'),
            tv: tv,
            lowRam: false,
            version: '1.8.6',
          ),
          initialPreferences: Preferences(),
          savePreferences: (_) async {},
          repository: EmptyCatalog(),
        ),
      );
      await tester.pumpAndSettle();
      if (tv) {
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('remote-history'))).dy,
          lessThan(
            tester.getTopLeft(find.byKey(const ValueKey('remote-settings'))).dy,
          ),
        );
        await tester.tap(find.byKey(const ValueKey('remote-history')));
      } else {
        final nav = find.byKey(const ValueKey('android-mobile-navigation'));
        expect(
          find.descendant(of: nav, matching: find.byType(RemoteButton)),
          findsNWidgets(4),
        );
        await tester.tap(find.byKey(const ValueKey('remote-lists')));
        await tester.pumpAndSettle();
        for (final id in ['favorites', 'queue', 'history']) {
          expect(find.byKey(ValueKey('lists-$id')), findsOneWidget);
        }
        await tester.tap(find.byKey(const ValueKey('lists-history')));
      }
      await tester.pumpAndSettle();
      expect(find.text('История просмотра'), findsOneWidget);
      final owner = 3.toRadixString(16).padLeft(64, '0');
      await tester.tap(find.byKey(ValueKey('history-row-$owner')));
      await tester.pumpAndSettle();
      expect(
        calls
            .where((c) => c.method == 'torrentHistoryPlay')
            .single
            .arguments['owner'],
        owner,
      );
      expect(
        calls
            .where((c) => c.method == 'torrentHistoryPlay')
            .single
            .arguments['series'],
        true,
      );
      expect(find.text('История просмотра'), findsOneWidget);
      if (!tv) {
        expect(
          find.byKey(const ValueKey('android-mobile-navigation')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('remote-lists')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('lists-favorites')));
        await tester.pumpAndSettle();
        expect(find.text('История просмотра'), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('desktop history sits between downloads and settings', (
    tester,
  ) async {
    size(tester, const Size(1280, 800));
    await tester.pumpWidget(
      FreeSceneApp(
        initialPreferences: Preferences(),
        savePreferences: (_) async {},
      ),
    );
    await tester.pumpAndSettle();
    final history = find.byKey(const ValueKey('sidebar-history'));
    expect(
      tester.getTopLeft(history).dy,
      greaterThan(
        tester.getTopLeft(find.byKey(const ValueKey('sidebar-downloads'))).dy,
      ),
    );
    expect(
      tester.getTopLeft(history).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('sidebar-settings'))).dy,
      ),
    );
    await tester.tap(history);
    await tester.pumpAndSettle();
    expect(find.text('История просмотра'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
