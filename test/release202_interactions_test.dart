import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freescene/android/android_app.dart';
import 'package:freescene/android/android_runtime.dart';
import 'package:freescene/android/remote_focus.dart';
import 'package:freescene/app.dart';
import 'package:freescene/catalog/catalog_models.dart';
import 'package:freescene/catalog/catalog_tile.dart';
import 'package:freescene/catalog/favorite_button.dart';
import 'package:freescene/catalog/queue_button.dart';
import 'package:freescene/navigation/catalog_section_swipe.dart';
import 'package:freescene/providers/demo.dart';
import 'package:freescene/settings/preferences.dart';
import 'package:freescene/torrent/native_torrent.dart';
import 'package:freescene/widgets/desktop_controls.dart';
import 'package:freescene/widgets/voice_search_dialog.dart';

class InteractionCatalog extends DemoCatalog {
  final searches = <String>[];
  CatalogKind lastKind = CatalogKind.movies;
  @override
  Future<CatalogPage<CatalogTitle>> list(
    CatalogKind kind, {
    String search = '',
    CatalogFilter filter = const CatalogFilter(),
    int start = 0,
  }) {
    lastKind = kind;
    searches.add(search);
    return super.list(kind, search: search, filter: filter, start: start);
  }

  @override
  Future<CatalogTitle> details(CatalogTitle title) async => CatalogTitle(
    id: title.id,
    kind: title.kind,
    name: title.name,
    trailer: const CatalogTrailer('demo', 'trailer'),
  );
  @override
  List<SourceProvider> providers(CatalogTitle title) => [demoProvider];
  @override
  Future<CatalogPage<CatalogSource>> sources(
    CatalogTitle title, {
    int start = 0,
  }) async => CatalogPage(
    items: [
      for (var i = 0; i < 8; i++)
        CatalogSource(
          row: SourceRow(
            id: 'video$i',
            provider: demoProvider,
            title: 'Источник $i',
            watch: SourceKind.direct,
            download: DownloadKind.unavailable,
          ),
          uri: Uri.https('example.test', '/$i.mp4'),
        ),
    ],
    total: 8,
    start: 0,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const voiceChannel = MethodChannel('freescene/desktop_voice');
  const voiceEvents = MethodChannel('freescene/desktop_voice/events');
  final historyId = '1'.padLeft(64, '0');
  final nativeCalls = <MethodCall>[];
  final watchedMarks = <String, String>{};
  setUp(() {
    nativeCalls.clear();
    watchedMarks.clear();
    for (final channel in [
      AndroidRuntime.channel,
      NativeTorrentService.channel,
    ]) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        nativeCalls.add(call);
        if (call.method == 'watchHistorySnapshot') {
          return {
            'entries': [
              {
                'id': historyId,
                'title': 'История фильма',
                'sourceType': 'torrent',
                'catalogId': 'demo:movies:1',
                'catalogKind': 'movies',
                'catalogName': 'Демонстрация 1',
                'watchedAt': 1000,
              },
            ],
          };
        }
        if (call.method == 'status') {
          return {'tasks': [], 'persistenceError': ''};
        }
        if (call.method == 'watchedSnapshot') {
          return Map<String, String>.of(watchedMarks);
        }
        if (call.method == 'setWatched') {
          final args = call.arguments as Map;
          if (args['watched'] == true) {
            watchedMarks[args['watchedSource'] as String] =
                args['watchedTitle'] as String;
          } else {
            watchedMarks.remove(args['watchedSource']);
          }
        }
        return null;
      });
    }
    messenger.setMockMethodCallHandler(voiceEvents, (_) async => null);
  });
  tearDown(() {
    for (final channel in [
      AndroidRuntime.channel,
      NativeTorrentService.channel,
      voiceChannel,
      voiceEvents,
    ]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });
  void size(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
  }

  Widget android(InteractionCatalog repository, {bool tv = false}) =>
      AndroidApp(
        runtime: AndroidRuntime(
          profile: Directory('/fixture'),
          cache: Directory('/fixture/cache'),
          tv: tv,
          lowRam: true,
          version: '2.0.2',
        ),
        initialPreferences: Preferences(),
        savePreferences: (_) async {},
        repository: repository,
      );
  Finder control(String id) => find.byKey(ValueKey('remote-$id'));
  Future<void> focus(WidgetTester tester, String id) async {
    tester.widget<OutlinedButton>(control(id)).focusNode!.requestFocus();
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 430.0]) {
    testWidgets(
      'phone search overlays sections and retains actions at $width',
      (tester) async {
        size(tester, Size(width, 800));
        final repository = InteractionCatalog();
        await tester.pumpWidget(android(repository));
        await tester.pumpAndSettle();
        final kinds = find.byKey(const ValueKey('android-kind-switch'));
        final before = tester.getRect(kinds);
        final search = find.byKey(const ValueKey('mobile-search-pill'));
        expect(tester.getRect(search).left, greaterThan(before.right));
        await tester.tap(find.byKey(const ValueKey('mobile-search-open')));
        await tester.pumpAndSettle();
        expect(tester.getRect(kinds), before);
        expect(tester.getRect(search).left, before.left);
        await tester.enterText(
          find.byKey(const ValueKey('mobile-search-input')),
          'Демонстрация 2',
        );
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        expect(repository.searches.last, 'Демонстрация 2');
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Очистить поиск'));
        await tester.pumpAndSettle();
        expect(repository.searches.last, '');
        await tester.tap(find.byKey(const ValueKey('mobile-search-filter')));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.text('Отмена'));
        await tester.pumpAndSettle();
        final swipe = find.byType(CatalogSectionSwipe);
        await tester.drag(swipe, const Offset(-160, 0));
        await tester.pumpAndSettle();
        expect(repository.lastKind, CatalogKind.series);
        await tester.drag(swipe, const Offset(-160, 0));
        await tester.pumpAndSettle();
        expect(repository.lastKind, CatalogKind.series);
        await tester.drag(swipe, const Offset(160, 0));
        await tester.pumpAndSettle();
        expect(repository.lastKind, CatalogKind.movies);
        await tester.drag(swipe, const Offset(0, -180));
        await tester.pumpAndSettle();
        expect(repository.lastKind, CatalogKind.movies);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'desktop voice final result applies once; cancel ignores late result; search icons stay compact',
    (tester) async {
      size(tester, const Size(1280, 900));
      final repository = InteractionCatalog();
      var speech = Completer<String?>();
      var starts = 0, cancels = 0;
      messenger.setMockMethodCallHandler(voiceChannel, (call) async {
        if (call.method == 'voiceListen') {
          starts++;
          return speech.future;
        }
        if (call.method == 'voiceCancel') cancels++;
        return null;
      });
      await tester.pumpWidget(
        FreeSceneApp(
          initialPreferences: Preferences(),
          savePreferences: (_) async {},
          catalogRepository: repository,
        ),
      );
      await tester.pumpAndSettle();
      final search = find.byType(DesktopSearchField).first;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        Offset(
          tester.getRect(search).right - 22,
          tester.getRect(search).center.dy,
        ),
      );
      await tester.pumpAndSettle();
      final voice = find.byKey(const ValueKey('catalog-voice'));
      final before = tester.getSize(voice);
      await mouse.moveTo(tester.getCenter(voice));
      await tester.pumpAndSettle();
      expect(tester.getSize(voice), before);
      expect(
        find.descendant(of: search, matching: find.byType(DesktopActionButton)),
        findsNothing,
      );
      await tester.tap(voice);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(VoiceSearchDialog), findsOneWidget);
      expect(starts, 1);
      speech.complete('Демонстрация 3');
      await tester.pumpAndSettle();
      expect(repository.searches.last, 'Демонстрация 3');
      speech = Completer<String?>();
      await tester.tap(voice);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(cancels, greaterThan(0));
      speech.complete('Демонстрация 7');
      await tester.pumpAndSettle();
      expect(repository.searches.last, 'Демонстрация 3');
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'TV history hold chooses card or playback, release cannot activate menu',
    (tester) async {
      size(tester, const Size(1280, 900));
      await tester.pumpWidget(android(InteractionCatalog(), tv: true));
      await tester.pumpAndSettle();
      await tester.tap(control('history'));
      await tester.pumpAndSettle();
      await focus(tester, 'history-row-$historyId');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 650));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.text('Перейти к карточке'), findsOneWidget);
      expect(find.text('Смотреть'), findsOneWidget);
      expect(
        nativeCalls.where((c) => c.method == 'torrentHistoryPlay'),
        isEmpty,
      );
      await tester.tap(find.byKey(const ValueKey('history-menu-watch')));
      await tester.pumpAndSettle();
      expect(
        nativeCalls.where((c) => c.method == 'torrentHistoryPlay'),
        hasLength(1),
      );
      expect(
        (FocusManager.instance.primaryFocus as RemoteFocusNode).id,
        'history-row-$historyId',
      );
      await tester.longPress(control('history-row-$historyId'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('history-menu-title')));
      await tester.pumpAndSettle();
      expect(control('detail-back'), findsOneWidget);
      expect(find.text('Демонстрация 1'), findsOneWidget);
      expect(
        nativeCalls.where((c) => c.method == 'torrentHistoryPlay'),
        hasLength(1),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('TV Back restores first source and resets after moving focus', (
    tester,
  ) async {
    size(tester, const Size(1280, 900));
    await tester.pumpWidget(android(InteractionCatalog(), tv: true));
    await tester.pumpAndSettle();
    await tester.tap(control('title-movies-demo:movies:1'));
    await tester.pumpAndSettle();
    for (final id in ['source-demo-video5', 'watched-demo-video3']) {
      await focus(tester, id);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(control('detail-back'), findsOneWidget);
      expect(
        (FocusManager.instance.primaryFocus as RemoteFocusNode).id,
        'source-demo-video0',
      );
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(control('detail-back'), findsNothing);
    expect(control('title-movies-demo:movies:1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'desktop section swipes respect direction, boundaries and text editing',
    (tester) async {
      size(tester, const Size(1280, 900));
      final repository = InteractionCatalog();
      await tester.pumpWidget(
        FreeSceneApp(
          initialPreferences: Preferences(),
          savePreferences: (_) async {},
          catalogRepository: repository,
          nativeService: const NativeTorrentService(),
        ),
      );
      await tester.pumpAndSettle();
      Future<bool> nativeSwipe(int direction) async {
        final point = tester.getCenter(find.byType(CatalogSectionSwipe));
        final result = Completer<bool>();
        tester.binding.channelBuffers.push(
          'freescene/native',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('navigateBack', {
              'x': point.dx,
              'y': point.dy,
              'direction': direction,
            }),
          ),
          (data) => result.complete(
            const StandardMethodCodec().decodeEnvelope(data!) as bool,
          ),
        );
        await tester.pumpAndSettle();
        return result.future;
      }

      expect(await nativeSwipe(-1), isTrue);
      expect(repository.lastKind, CatalogKind.movies);
      expect(await nativeSwipe(1), isTrue);
      expect(repository.lastKind, CatalogKind.series);
      expect(await nativeSwipe(1), isTrue);
      expect(repository.lastKind, CatalogKind.games);
      expect(await nativeSwipe(1), isTrue);
      expect(repository.lastKind, CatalogKind.games);
      expect(await nativeSwipe(-1), isTrue);
      expect(repository.lastKind, CatalogKind.series);
      await tester.drag(find.byType(CatalogSectionSwipe), const Offset(180, 0));
      await tester.pumpAndSettle();
      expect(repository.lastKind, CatalogKind.movies);
      await tester.enterText(
        find.byKey(const ValueKey('catalog-search')),
        'Демонстрация',
      );
      await tester.pumpAndSettle();
      expect(await nativeSwipe(1), isFalse);
      expect(repository.lastKind, CatalogKind.movies);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final platform in ['desktop', 'phone', 'tv']) {
    testWidgets(
      'selected providers, favorites, queue and watched share accent on $platform',
      (tester) async {
        final desktop = platform == 'desktop';
        size(
          tester,
          desktop || platform == 'tv'
              ? const Size(1280, 900)
              : const Size(430, 900),
        );
        final repository = InteractionCatalog();
        await tester.pumpWidget(
          desktop
              ? FreeSceneApp(
                  initialPreferences: Preferences(),
                  savePreferences: (_) async {},
                  catalogRepository: repository,
                )
              : android(repository, tv: platform == 'tv'),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          desktop
              ? find.byType(CatalogTile).first
              : control('title-movies-demo:movies:1'),
        );
        await tester.pumpAndSettle();
        final provider = find.byKey(const ValueKey('source-provider-demo'));
        final providerControl = desktop
            ? provider
            : control('source-provider-demo');
        final colors = Theme.of(tester.element(providerControl)).colorScheme;
        if (desktop) {
          final chip = tester.widget<FilterChip>(provider);
          expect(chip.showCheckmark, isFalse);
          expect(chip.selected, isTrue);
          expect(chip.selectedColor, colors.primaryContainer);
          expect(chip.labelStyle!.color, colors.primary);
          final trailer = tester.getRect(
            find.byKey(const ValueKey('catalog-trailer')),
          );
          final favorite = tester.getRect(find.byType(FavoriteButton));
          final queue = tester.getRect(find.byType(QueueButton));
          expect(favorite.left, trailer.right + 16);
          expect(queue.left, favorite.right + 16);
          expect(favorite.top, trailer.top);
        } else {
          expect(
            find.descendant(of: providerControl, matching: find.byType(Icon)),
            findsNothing,
          );
          final style = tester.widget<OutlinedButton>(providerControl).style!;
          expect(style.backgroundColor!.resolve({}), colors.primaryContainer);
          expect(style.foregroundColor!.resolve({}), colors.primary);
        }
        await tester.ensureVisible(providerControl);
        await tester.tap(providerControl);
        await tester.pumpAndSettle();
        expect(find.text('Источник 0'), findsNothing);
        await tester.tap(providerControl);
        await tester.pumpAndSettle();
        for (final button in [
          desktop ? find.byType(FavoriteButton) : control('favorite-title'),
          desktop ? find.byType(QueueButton) : control('queue-title'),
          desktop
              ? find.byKey(const ValueKey('source-watched-demo/video0'))
              : control('watched-demo-video0'),
        ]) {
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.pumpAndSettle();
          ButtonStyle style;
          if (desktop) {
            style = tester
                .widget<FilledButton>(
                  find.descendant(
                    of: button,
                    matching: find.byType(FilledButton),
                  ),
                )
                .style!;
          } else {
            style = tester.widget<OutlinedButton>(button).style!;
          }
          expect(
            style.backgroundColor!.resolve({}),
            colors.primaryContainer,
            reason: button.toString(),
          );
          expect(style.foregroundColor!.resolve({}), colors.primary);
          await tester.tap(button);
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final reduced in [false, true]) {
    testWidgets(
      'poster hover matches TV and respects reduced motion $reduced',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 180,
                    height: 260,
                    child: CatalogTile(
                      onTap: () {},
                      child: const Text('Poster'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(find.byType(CatalogTile)));
        await tester.pumpAndSettle();
        expect(
          tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
          reduced ? 1 : 1.035,
        );
        final card = tester.widget<Card>(find.byType(Card));
        final side = (card.shape! as RoundedRectangleBorder).side;
        expect(side.width, 3);
        expect(
          side.color,
          Theme.of(tester.element(find.byType(Card))).colorScheme.primary,
        );
        await mouse.removePointer();
      },
    );
  }
}
