import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freescene/android/android_app.dart';
import 'package:freescene/android/android_runtime.dart';
import 'package:freescene/android/remote_focus.dart';
import 'package:freescene/android/tv_widgets.dart';
import 'package:freescene/catalog/catalog_models.dart';
import 'package:freescene/catalog/catalog_controller.dart';
import 'package:freescene/providers/demo.dart';
import 'package:freescene/settings/preferences.dart';
import 'package:freescene/settings/settings_store.dart';
import 'package:freescene/widgets/catalog_style.dart';

class _Catalogue extends DemoCatalog {
  _Catalogue({this.count = 18, this.withTrailer = false});
  final bool withTrailer;
  final int count;
  @override
  Future<CatalogPage<CatalogTitle>> list(
    CatalogKind kind, {
    String search = '',
    CatalogFilter filter = const CatalogFilter(),
    int start = 0,
  }) async => CatalogPage(
    items: [
      for (var i = 0; i < count; i++)
        CatalogTitle(
          id: '$i',
          kind: kind,
          name: 'Фильм с длинным названием $i',
          englishName: 'A film with a long title $i',
          trailer: withTrailer
              ? const CatalogTrailer('demo', 'trailer-1')
              : null,
          year: 2025,
          rating: 8.2,
          description: List.filled(
            12,
            'История о путешествии и неожиданных открытиях.',
          ).join(' '),
        ),
    ],
    total: count,
    start: 0,
  );
  @override
  List<SourceProvider> providers(CatalogTitle title) => [demoProvider];
  @override
  Future<CatalogPage<CatalogSource>> sources(
    CatalogTitle title, {
    int start = 0,
  }) async => CatalogPage(
    items: [
      CatalogSource(
        row: SourceRow(
          id: 'video',
          provider: demoProvider,
          title: 'Вариант просмотра',
          quality: '1080p',
          watch: SourceKind.direct,
          download: DownloadKind.unavailable,
        ),
        uri: Uri.https('example.test', '/video.mp4'),
      ),
    ],
    total: 1,
    start: 0,
  );
}

class _CountryPages extends DemoCatalog {
  final starts = <int>[];
  @override
  Future<CatalogPage<CatalogTitle>> list(
    CatalogKind kind, {
    String search = '',
    CatalogFilter filter = const CatalogFilter(),
    int start = 0,
  }) async {
    starts.add(start);
    expect(filter.country, isNull);
    expect(filter.year, 2020);
    final countries = [
      'Россия',
      'Казахстан',
      'Россия, Беларусь',
      'Украина',
      'Австралия, Россия',
    ];
    return CatalogPage(
      start: start,
      total: countries.length,
      items: [
        CatalogTitle(
          id: '$start',
          name: '$start',
          kind: kind,
          country: countries[start],
        ),
      ],
    );
  }
}

Finder control(String id) => find.byKey(ValueKey('remote-$id'));
FocusNode focusNode(WidgetTester tester, String id) =>
    tester.widget<OutlinedButton>(control(id)).focusNode!;
Future<void> activate(WidgetTester tester, String id) async {
  focusNode(tester, id).requestFocus();
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.select);
  await tester.pumpAndSettle();
}

Future<void> holdPoster(WidgetTester tester) async {
  focusNode(tester, 'title-movies-0').requestFocus();
  await tester.pumpAndSettle();
  await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
  await tester.pump(const Duration(milliseconds: 650));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('title-menu-watch')), findsOneWidget);
  await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('title-menu-watch')), findsOneWidget);
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          AndroidRuntime.channel,
          (call) async => call.method == 'watchedSnapshot'
              ? <String, String>{}
              : {'available': false, 'entries': []},
        );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidRuntime.channel, null),
  );

  Future<void> launch(
    WidgetTester tester, {
    Size size = const Size(960, 540),
    int count = 18,
    bool withTrailer = false,
    Preferences? preferences,
    Future<void> Function(Preferences)? save,
    Future<void> Function(CatalogSource)? play,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      AndroidApp(
        runtime: AndroidRuntime(
          profile: Directory('/fixture'),
          cache: Directory('/fixture/cache'),
          tv: true,
          lowRam: true,
          version: 'preview',
        ),
        initialPreferences: preferences ?? Preferences(),
        savePreferences: save ?? (_) async {},
        repository: _Catalogue(count: count, withTrailer: withTrailer),
        play: play ?? (_) async {},
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'collection buttons expand on remote focus and collapse on departure',
    (tester) async {
      await launch(tester);
      final favorite = control('favorites'), queue = control('queue');
      final closed = tester.getSize(favorite).width;
      expect(closed, tester.getSize(queue).width);
      expect(closed, closeTo(tester.getSize(control('search')).width, 1));
      focusNode(tester, 'favorites').requestFocus();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final intermediate = tester.getSize(favorite).width;
      await tester.pumpAndSettle();
      expect(intermediate, greaterThan(closed));
      expect(tester.getSize(favorite).width, greaterThan(intermediate));
      expect(
        find.descendant(of: favorite, matching: find.text('Избранное')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(tester.getSize(favorite).width, closed);
      expect(tester.getSize(queue).width, greaterThan(closed));
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.text('Список пуст'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(tester.getSize(queue).width, closed);
      expect(FocusManager.instance.primaryFocus, focusNode(tester, 'search'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'search reverses on focus changes without rebuilding the poster grid',
    (tester) async {
      await launch(tester);
      final poster = find.byWidgetPredicate(
        (widget) => widget is RemoteButton && widget.id == 'title-movies-0',
      );
      final initialPoster = tester.widget(poster);
      final search = control('search');
      final closedX = tester.getTopLeft(search).dx;
      focusNode(tester, 'search').requestFocus();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      final halfway = tester.getTopLeft(search).dx;
      expect(halfway, lessThan(closedX));
      expect(identical(tester.widget(poster), initialPoster), isTrue);
      focusNode(tester, 'kind-movies').requestFocus();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(search).dx, closeTo(closedX, .1));
      expect(control('filter'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'TV film and series selection updates on the first frame with animations enabled',
    (tester) async {
      await launch(tester, preferences: Preferences(tvAnimations: true));
      final controlGroup = find.byType(CatalogSelectionThumb);
      final thumb = find.descendant(
        of: controlGroup,
        matching: find.byType(DecoratedBox),
      );
      expect(
        find.descendant(of: controlGroup, matching: find.byType(AnimatedSlide)),
        findsNothing,
      );
      for (final id in ['kind-series', 'kind-movies']) {
        focusNode(tester, id).requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pump();
        expect(
          tester.getCenter(thumb).dx,
          closeTo(tester.getCenter(control(id)).dx, .1),
        );
      }
    },
  );

  testWidgets('disabled animation expands a focused collection in one frame', (
    tester,
  ) async {
    await launch(tester, preferences: Preferences(tvAnimations: false));
    final closed = tester.getSize(control('queue')).width;
    focusNode(tester, 'queue').requestFocus();
    await tester.pump();
    await tester.pump();
    final expanded = tester.getSize(control('queue')).width;
    expect(expanded, greaterThan(closed));
    await tester.pumpAndSettle();
    expect(tester.getSize(control('queue')).width, expanded);
  });

  for (final withTrailer in [false, true]) {
    testWidgets(
      'Up from the first provider reaches the bordered hero actions, trailer=$withTrailer',
      (tester) async {
        await launch(tester, withTrailer: withTrailer);
        await activate(tester, 'title-movies-0');
        final desc = control('detail-description');
        final button = tester.widget<OutlinedButton>(desc);
        final side = button.style!.side!.resolve({});
        expect(side!.color.a, greaterThan(0));
        if (withTrailer) {
          final trailer = tester.getRect(control('trailer'));
          expect(tester.getRect(desc).left, greaterThan(trailer.right));
          expect(tester.getRect(desc).center.dy, closeTo(trailer.center.dy, 1));
        }
        focusNode(tester, 'source-provider-demo').requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus,
          focusNode(tester, withTrailer ? 'trailer' : 'detail-description'),
        );
        if (withTrailer) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();
          expect(
            FocusManager.instance.primaryFocus,
            focusNode(tester, 'detail-description'),
          );
        }
      },
    );
  }

  for (final size in [
    const Size(960, 540),
    const Size(1280, 720),
    const Size(1920, 1080),
  ]) {
    testWidgets(
      'TV catalogue and details fit $size, remote returns to the title',
      (tester) async {
        var plays = 0;
        await launch(tester, size: size, play: (_) async => plays++);
        expect(tester.takeException(), isNull);
        focusNode(tester, 'kind-movies').requestFocus();
        await tester.pumpAndSettle();
        for (final id in [
          'kind-series',
          'favorites',
          'queue',
          'search',
          'voice',
          'filter',
          'refresh',
        ]) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();
          expect(FocusManager.instance.primaryFocus, focusNode(tester, id));
        }
        await activate(tester, 'title-movies-0');
        expect(find.byType(TvDetailHero), findsOneWidget);
        expect(control('detail-description'), findsOneWidget);
        await activate(tester, 'detail-description');
        expect(find.text('Свернуть'), findsOneWidget);
        await activate(tester, 'detail-description');
        await activate(tester, 'source-demo-video');
        expect(plays, 1);
        expect(
          FocusManager.instance.primaryFocus,
          focusNode(tester, 'source-demo-video'),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(TvDetailHero), findsOneWidget);
        expect(
          FocusManager.instance.primaryFocus,
          focusNode(tester, 'source-demo-video'),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus,
          focusNode(tester, 'title-movies-0'),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  test(
    'country exclusion continues across empty pages and retains co-productions',
    () async {
      final repo = _CountryPages();
      final catalog = CatalogController(repo);
      addTearDown(catalog.dispose);
      await catalog.browse(
        filter: const CatalogFilter(
          year: 2020,
          country: CatalogFilter.outsideFourCountries,
        ),
      );
      expect(catalog.items.map((t) => t.country), ['Россия, Беларусь']);
      expect(catalog.hasMore, isTrue);
      await catalog.loadMore();
      expect(catalog.items.map((t) => t.country), [
        'Россия, Беларусь',
        'Австралия, Россия',
      ]);
      expect(catalog.hasMore, isFalse);
      expect(repo.starts, [0, 1, 2, 3, 4]);
    },
  );

  test(
    'Не Россия excludes only a sole matching country, never a co-production',
    () {
      const filter = CatalogFilter(country: CatalogFilter.outsideFourCountries);
      for (final sole in [
        'Россия',
        'Беларусь',
        'Украина',
        'Казахстан',
        ' Belarus ',
        'RU',
      ]) {
        expect(filter.includesCountry(sole), isFalse, reason: sole);
      }
      for (final other in [
        null,
        'Франция',
        'Австралия, Россия',
        'Россия, Беларусь',
        'Украина / Казахстан',
        'СССР',
      ]) {
        expect(filter.includesCountry(other), isTrue, reason: other);
      }
    },
  );

  for (final appearance in AppAppearance.values) {
    testWidgets(
      'TV filter rows and focused options are distinct in ${appearance.name}',
      (tester) async {
        final oldLoader = CatalogDictionaries.loader;
        addTearDown(() => CatalogDictionaries.loader = oldLoader);
        CatalogDictionaries.loader = () async => CatalogDictionaries({
          'genres': [
            for (var i = 0; i < 18; i++)
              {'id': '$i', 'ru': 'Жанр $i', 'en': 'Genre $i'},
          ],
          'countries': [],
          'gameGenres': [],
        });
        await launch(tester, preferences: Preferences(appearance: appearance));
        focusNode(tester, 'search').requestFocus();
        await tester.pumpAndSettle();
        await activate(tester, 'filter');
        Finder field(String label) => find.widgetWithText(FilledButton, label);
        final genre = field('Жанр'), country = field('Страна');
        expect(
          tester.getRect(country).top - tester.getRect(genre).bottom,
          greaterThanOrEqualTo(12),
        );
        final colors = Theme.of(tester.element(genre)).colorScheme;
        Future<void> key(LogicalKeyboardKey key) async {
          await tester.sendKeyEvent(key);
          await tester.pumpAndSettle();
        }

        Finder option(String label) => find.descendant(
          of: find.byType(SimpleDialog),
          matching: field(label),
        );
        Color? fill(String label) => tester
            .widget<Material>(
              find
                  .descendant(
                    of: option(label),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .color;
        final trigger = Focus.of(tester.element(find.text('Жанр')));
        trigger.requestFocus();
        await tester.pumpAndSettle();
        await key(LogicalKeyboardKey.select);
        expect(fill('Все'), colors.primary);
        for (var i = 0; i < 12; i++) {
          await key(LogicalKeyboardKey.arrowDown);
        }
        expect(fill('Жанр 11'), colors.primary);
        expect(fill('Все'), colors.surfaceContainerHigh);
        expect(option('Жанр 11').hitTestable(), findsOneWidget);
        await key(LogicalKeyboardKey.select);
        expect(trigger.hasFocus, isTrue);
        expect(
          find.descendant(of: genre, matching: find.text('Жанр 11')),
          findsOneWidget,
        );
        await key(LogicalKeyboardKey.select);
        expect(fill('Жанр 11'), colors.primary);
        expect(option('Жанр 11').hitTestable(), findsOneWidget);
        await key(LogicalKeyboardKey.escape);
        await key(LogicalKeyboardKey.arrowDown);
        await key(LogicalKeyboardKey.select);
        expect(fill('Все'), colors.primary);
        await key(LogicalKeyboardKey.arrowUp);
        expect(fill('Не Россия'), colors.primary);
        expect(
          find.descendant(
            of: option('Все'),
            matching: find.byIcon(Icons.check_rounded),
          ),
          findsOneWidget,
        );
        await key(LogicalKeyboardKey.select);
        expect(
          find.descendant(of: country, matching: find.text('Не Россия')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'TV year controls navigate vertically and open the editor only on OK',
    (tester) async {
      await launch(tester);
      focusNode(tester, 'search').requestFocus();
      await tester.pumpAndSettle();
      await activate(tester, 'filter');
      for (final id in ['filter-year', 'filter-year-to']) {
        final field = find.byKey(ValueKey(id));
        final node = Focus.of(
          tester.element(
            find.descendant(of: field, matching: find.byType(Text)),
          ),
        );
        for (final arrow in [
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.arrowDown,
        ]) {
          node.requestFocus();
          await tester.pumpAndSettle();
          expect(node.hasFocus, isTrue);
          await tester.sendKeyEvent(arrow);
          await tester.pumpAndSettle();
          expect(node.hasFocus, isFalse);
          expect(find.byType(EditableText), findsNothing);
        }
        node.requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(find.byType(EditableText), findsOneWidget);
        await tester.enterText(find.byType(EditableText), '2020');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: field, matching: find.textContaining('2020')),
          findsOneWidget,
        );
      }
    },
  );

  testWidgets(
    'TV poster menu saves collections and restores focus; sidebar keeps icon actions',
    (tester) async {
      Preferences? saved;
      await launch(tester, save: (p) async => saved = p);
      for (final choice in ['favorite', 'queue', 'watched']) {
        await holdPoster(tester);
        await tester.tap(find.byKey(ValueKey('title-menu-$choice')));
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus,
          focusNode(tester, 'title-movies-0'),
        );
      }
      await holdPoster(tester);
      expect(find.text('Убрать из'), findsNWidgets(2));
      expect(find.text('Снять отметку'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await activate(tester, 'settings');
      await activate(tester, 'sidebar-collapse');
      expect(saved!.sidebarCollapsed, isTrue);
      expect(
        find.descendant(of: control('home'), matching: find.byType(Text)),
        findsNothing,
      );
      expect(control('about-brand'), findsOneWidget);
    },
  );

  testWidgets('TV motion and theme persist; icon follows theme after restart', (
    tester,
  ) async {
    Preferences? saved;
    Future<void> save(Preferences value) async {
      saved = Preferences.fromJson(value.toJson());
    }

    await launch(tester, save: save);
    await activate(tester, 'settings');
    await activate(tester, 'animations');
    expect(find.text('Анимации: выкл.'), findsOneWidget);
    await activate(tester, 'appearance');
    expect(find.byKey(const ValueKey('tv-brand-light')), findsOneWidget);
    expect(saved!.tvAnimations, isFalse);
    expect(saved!.appearance, AppAppearance.light);
    await tester.pumpWidget(const SizedBox.shrink());
    await launch(tester, preferences: saved, save: save);
    expect(find.byKey(const ValueKey('tv-brand-light')), findsOneWidget);
    expect(
      MediaQuery.disableAnimationsOf(tester.element(control('home'))),
      isTrue,
    );
    focusNode(tester, 'title-movies-0').requestFocus();
    await tester.pumpAndSettle();
    final scale = tester.widget<AnimatedScale>(
      find
          .ancestor(
            of: control('title-movies-0'),
            matching: find.byType(AnimatedScale),
          )
          .first,
    );
    expect(scale.duration, Duration.zero);
    expect(scale.scale, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('D-pad can reach every catalogue and detail action', (
    tester,
  ) async {
    await launch(tester, count: 6);
    Future<void> checkReachability(String start) async {
      final expected = tester
          .widgetList<RemoteButton>(find.byType(RemoteButton))
          .where((button) => button.onPressed != null)
          .map((button) => button.id)
          .toSet();
      final visited = <String>{start};
      final pending = <String>[start];
      while (pending.isNotEmpty) {
        final current = pending.removeAt(0);
        for (final direction in [
          LogicalKeyboardKey.arrowLeft,
          LogicalKeyboardKey.arrowRight,
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.arrowDown,
        ]) {
          if (control(current).evaluate().isEmpty) {
            focusNode(tester, 'search').requestFocus();
            await tester.pumpAndSettle();
          }
          focusNode(tester, current).requestFocus();
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(direction);
          await tester.pumpAndSettle();
          final focused = FocusManager.instance.primaryFocus;
          expect(focused, isA<RemoteFocusNode>());
          final id = (focused as RemoteFocusNode).id;
          if (visited.add(id)) pending.add(id);
        }
      }
      expect(
        visited,
        containsAll(expected),
        reason: 'Unreachable: ${expected.difference(visited)}',
      );
    }

    await checkReachability('home');
    await activate(tester, 'title-movies-0');
    await checkReachability('detail-back');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'TV animation choice survives writing and reopening the profile',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'freescene-tv-settings-',
      );
      addTearDown(() => dir.delete(recursive: true));
      await SettingsStore(dir).save(Preferences(tvAnimations: false));
      expect((await SettingsStore(dir).load()).tvAnimations, isFalse);
    },
  );

  test('existing profiles enable TV animation by default', () {
    final old = Preferences().toJson()..remove('tvAnimations');
    expect(Preferences.fromJson(old).tvAnimations, isTrue);
  });
}
