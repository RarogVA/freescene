import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freescene/app.dart';
import 'package:freescene/android/android_app.dart';
import 'package:freescene/android/android_runtime.dart';
import 'package:freescene/catalog/catalog_tile.dart';
import 'package:freescene/catalog/catalog_kind_switch.dart';
import 'package:freescene/catalog/catalog_models.dart';
import 'package:freescene/catalog/favorites.dart';
import 'package:freescene/catalog/title_context_menu.dart';
import 'package:freescene/catalog/watch_queue.dart';
import 'package:freescene/catalog/watched.dart';
import 'package:freescene/providers/demo.dart';
import 'package:freescene/settings/preferences.dart';
import 'package:freescene/torrent/native_torrent.dart';

void main() {
  for (final language in AppLanguage.values) {
    testWidgets(
      'games follow the enabled catalogue provider (${language.name})',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1280, 1000);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          FreeSceneApp(
            initialPreferences: Preferences(language: language, providers: {}),
            catalogRepository: DemoCatalog(),
            savePreferences: (_) async {},
          ),
        );
        await tester.pumpAndSettle();
        final games = find.byKey(const ValueKey('catalog-kind-games'));
        Future<void> toggleProvider() async {
          await tester.tap(find.byKey(const ValueKey('sidebar-settings')));
          await tester.pumpAndSettle();
          final checkbox = find.byKey(const ValueKey('provider-demo'));
          await tester.ensureVisible(checkbox);
          await tester.tap(checkbox);
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('settings-back')));
          await tester.pumpAndSettle();
        }

        expect(games, findsNothing);
        await toggleProvider();
        expect(games, findsOneWidget);
        await tester.tap(games);
        await tester.pumpAndSettle();
        await toggleProvider();
        expect(games, findsNothing);
        final selected = tester.widget<CatalogKindSwitch>(
          find.byType(CatalogKindSwitch),
        );
        expect(selected.value, CatalogKind.movies);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final tv in [false, true]) {
    for (final dark in [false, true]) {
      testWidgets(
        'desktop and TV share poster menu actions tv=$tv dark=$dark',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(1280, 900);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final channel = tv
              ? AndroidRuntime.channel
              : NativeTorrentService.channel;
          final messenger =
              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
          final marks = <MethodCall>[];
          final watched = <String, String>{};
          messenger.setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'watchedSnapshot') return watched;
            if (call.method == 'setWatched') {
              marks.add(call);
              final key = call.arguments['watchedSource'] as String;
              if (call.arguments['watched'] == true) {
                watched[key] = call.arguments['watchedTitle'] as String;
              } else {
                watched.remove(key);
              }
            }
            return null;
          });
          addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
          final favorites = FavoritesController(), queue = QueueController();
          final preferences = Preferences(
            appearance: dark ? AppAppearance.dark : AppAppearance.light,
          );
          await tester.pumpWidget(
            tv
                ? AndroidApp(
                    runtime: AndroidRuntime(
                      profile: Directory('/fixture'),
                      cache: Directory('/fixture/cache'),
                      tv: true,
                      lowRam: true,
                      version: '2.0.1',
                    ),
                    initialPreferences: preferences,
                    savePreferences: (_) async {},
                    repository: DemoCatalog(),
                    favorites: favorites,
                    queue: queue,
                  )
                : FreeSceneApp(
                    initialPreferences: preferences,
                    savePreferences: (_) async {},
                    catalogRepository: DemoCatalog(),
                    favorites: favorites,
                    queue: queue,
                  ),
          );
          await tester.pumpAndSettle();
          final poster = tv
              ? find.byKey(const ValueKey('remote-title-movies-demo:movies:1'))
              : find.byType(CatalogTile).first;
          Future<void> open() async {
            await tester.longPress(poster);
            await tester.pumpAndSettle();
            expect(find.byType(TitleContextMenu), findsOneWidget);
          }

          await open();
          expect(find.text('Открыть карточку'), findsNothing);
          expect(find.text('Смотреть'), findsOneWidget);
          expect(find.text('Добавить в'), findsNWidgets(2));
          expect(find.text('Отметить'), findsOneWidget);
          for (final pair in [
            ('watch', 'Смотреть', Icons.play_arrow_rounded),
            ('favorite', 'Добавить в', Icons.favorite_rounded),
            ('queue', 'Добавить в', Icons.playlist_play_rounded),
            ('watched', 'Отметить', Icons.visibility_outlined),
          ]) {
            final button = find.byKey(ValueKey('title-menu-${pair.$1}'));
            expect(tester.getSize(button).height, 48);
            final label = find.descendant(
              of: button,
              matching: find.text(pair.$2),
            );
            final icon = find.descendant(
              of: button,
              matching: find.byIcon(pair.$3),
            );
            expect(tester.getRect(label).right + 10, tester.getRect(icon).left);
          }
          await tester.tap(find.byKey(const ValueKey('title-menu-favorite')));
          await tester.pumpAndSettle();
          expect(favorites.titles.single.id, 'demo:movies:1');
          await open();
          expect(find.text('Убрать из'), findsOneWidget);
          final savedButton = tester.widget<FilledButton>(
            find.byKey(const ValueKey('title-menu-favorite')),
          );
          final colors = Theme.of(tester.element(find.byType(TitleContextMenu)))
              .colorScheme;
          expect(
            savedButton.style!.backgroundColor!.resolve({}),
            colors.primaryContainer,
          );
          expect(
            savedButton.style!.foregroundColor!.resolve({}),
            colors.primary,
          );
          await tester.tap(find.byKey(const ValueKey('title-menu-queue')));
          await tester.pumpAndSettle();
          expect(queue.titles.single.id, 'demo:movies:1');
          await open();
          await tester.tap(find.byKey(const ValueKey('title-menu-watched')));
          await tester.pumpAndSettle();
          expect(marks, hasLength(1));
          await open();
          expect(find.text('Снять отметку'), findsOneWidget);
          final titleKey = watched.keys.single;
          if (dark) {
            watched['source-1'] = titleKey;
            await tester
                .widget<WatchedScope>(find.byType(WatchedScope))
                .notifier!
                .refresh();
          }
          await tester.tap(find.byKey(const ValueKey('title-menu-unwatch')));
          await tester.pumpAndSettle();
          expect(marks.last.arguments['watched'], isFalse);
          expect(watched, dark ? {'source-1': titleKey} : isEmpty);
          await open();
          expect(find.text(dark ? 'Просмотрено' : 'Отметить'), findsOneWidget);
          expect(
            tester
                .widget<FilledButton>(
                  find.byKey(const ValueKey('title-menu-watched')),
                )
                .onPressed,
            dark ? isNull : isNotNull,
          );
          await tester.tap(find.byKey(const ValueKey('title-menu-watch')));
          await tester.pumpAndSettle();
          expect(find.byType(TitleContextMenu), findsNothing);
          expect(
            find.byKey(ValueKey(tv ? 'remote-detail-back' : 'catalog-back')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
