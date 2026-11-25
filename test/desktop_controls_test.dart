import 'dart:ui' show SemanticsAction;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freescene/app.dart';
import 'package:freescene/catalog/catalog_filter_dialog.dart';
import 'package:freescene/catalog/catalog_models.dart';
import 'package:freescene/catalog/catalog_tile.dart';
import 'package:freescene/catalog/catalog_page.dart';
import 'package:freescene/catalog/favorite_button.dart';
import 'package:freescene/catalog/queue_button.dart';
import 'package:freescene/providers/demo.dart';
import 'package:freescene/settings/preferences.dart';
import 'package:freescene/theme/freescene_theme.dart';
import 'package:freescene/widgets/desktop_controls.dart';

void main() {
  for (final size in [const Size(360, 800), const Size(1200, 800)]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets(
        'filter fields stay separated and country exclusion applies $size $scale',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          CatalogFilter? applied;
          await tester.pumpWidget(
            MaterialApp(
              theme: FreeSceneTheme.create(true),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () async =>
                        applied = await showDialog<CatalogFilter>(
                          context: context,
                          builder: (_) => const CatalogFilterDialog(
                            initial: CatalogFilter(),
                            english: false,
                            kind: CatalogKind.series,
                          ),
                        ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          final fields = find.byWidgetPredicate(
            (w) => w is DropdownButtonFormField,
          );
          expect(fields, findsNWidgets(4));
          expect(
            tester.getRect(fields.at(1)).top -
                tester.getRect(fields.at(0)).bottom,
            greaterThanOrEqualTo(20),
          );
          expect(
            tester.getRect(fields.at(3)).top -
                tester.getRect(fields.at(2)).bottom,
            greaterThanOrEqualTo(20),
          );
          await tester.ensureVisible(fields.at(1));
          await tester.tap(fields.at(1));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Не Россия').last);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Применить'));
          await tester.pumpAndSettle();
          expect(applied?.country, CatalogFilter.outsideFourCountries);
          expect(applied?.active, isTrue);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'circular action expands on hover and keyboard focus and respects reduced motion',
    (tester) async {
      for (final reduced in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Scaffold(
                body: Center(
                  child: DesktopActionButton(
                    key: ValueKey(reduced),
                    icon: Icons.arrow_back_rounded,
                    label: 'Назад',
                    onPressed: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final button = find.byType(DesktopActionButton);
        expect(tester.getSize(button), const Size(44, 44));
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(button));
        await tester.pump();
        if (!reduced) await tester.pump(const Duration(milliseconds: 250));
        expect(tester.getSize(button).width, greaterThan(44));
        await mouse.moveTo(Offset.zero);
        await tester.pumpAndSettle();
        expect(tester.getSize(button).width, 44);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(tester.getSize(button).width, greaterThan(44));
        await mouse.removePointer();
      }
    },
  );

  testWidgets(
    'trackpad secondary click, hold, control click and native pressure open one menu without navigation',
    (tester) async {
      var opened = 0, menus = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: SizedBox(
                  width: 180,
                  height: 260,
                  child: CatalogTile(
                    onTap: () => opened++,
                    onContextMenu: () async {
                      menus++;
                      await showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Actions'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                    },
                    child: const Text('Poster'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final tile = find.byType(CatalogTile);
      Future<void> close() async {
        await tester.pumpAndSettle();
        expect(find.text('Actions'), findsOneWidget);
        expect(opened, 0);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
      }

      await tester.tap(
        tile,
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await close();
      await tester.longPress(tile);
      await close();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(tile);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await close();
      final point = tester.getCenter(tile);
      final press = await tester.startGesture(
        point,
        kind: PointerDeviceKind.mouse,
      );
      tester.binding.channelBuffers.push(
        'freescene/context_menu',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('forceClick', {'x': point.dx, 'y': point.dy}),
        ),
        (_) {},
      );
      await tester.pump();
      await press.up();
      await close();
      expect(menus, 4);
      await tester.tap(tile);
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('desktop actions expose one accessible press target', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var pressed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopActionButton(
            icon: Icons.filter_alt_outlined,
            label: 'Filter',
            onPressed: () => pressed++,
          ),
        ),
      ),
    );
    final target = find.bySemanticsLabel('Filter');
    expect(target, findsOneWidget);
    final node = tester.getSemantics(target);
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pump();
    expect(pressed, 1);
    semantics.dispose();
  });

  testWidgets(
    'restyled source search, seasons and episodes retain their filtering',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1100, 700);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: FreeSceneTheme.create(false),
          home: Scaffold(
            body: SourceTable(
              english: false,
              game: false,
              series: true,
              sources: [
                for (var i = 1; i <= 2; i++)
                  CatalogSource(
                    row: SourceRow(
                      id: '$i',
                      title: 'Release $i',
                      provider: demoProvider,
                      season: i,
                      episode: i,
                      watch: SourceKind.direct,
                      download: DownloadKind.unavailable,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('source-search-pill'));
      final reset = find.byKey(const ValueKey('source-reset'));
      final searchRect = tester.getRect(search);
      expect(searchRect.width, 44);
      expect(
        searchRect.left,
        tester.getRect(find.byKey(const ValueKey('source-filters'))).left,
      );
      expect(reset, findsNothing);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(search));
      await tester.pumpAndSettle();
      expect(tester.getRect(search).left, searchRect.left);
      expect(tester.getSize(search).width, 360);
      expect(reset, findsNothing);
      expect(
        find.widgetWithText(DesktopActionButton, 'Сезон / серия'),
        findsNothing,
      );
      final counter = find.text('Найдено: 2 / 2');
      final season = find.byKey(const ValueKey('source-season'));
      final episode = find.byKey(const ValueKey('source-episode'));
      expect(
        tester.getRect(season).top,
        greaterThan(tester.getRect(counter).bottom),
      );
      expect(tester.getCenter(season).dy, tester.getCenter(episode).dy);
      await mouse.removePointer();
      await tester.tap(find.byKey(const ValueKey('source-season')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сезон 2').last);
      await tester.pumpAndSettle();
      expect(find.text('Release 1'), findsNothing);
      expect(find.text('Release 2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('source-episode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Серия 2').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('source-search')),
        'absent',
      );
      await tester.pumpAndSettle();
      expect(find.text('Release 2'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('source-search-clear')));
      await tester.pumpAndSettle();
      expect(find.text('Release 1'), findsNothing);
      expect(find.text('Release 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('desktop animation segments persist and apply immediately', (
    tester,
  ) async {
    Preferences? saved;
    await tester.pumpWidget(
      FreeSceneApp(
        initialPreferences: Preferences(),
        savePreferences: (value) async => saved = value,
        catalogRepository: DemoCatalog(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sidebar-settings')));
    await tester.pumpAndSettle();
    final off = find.byKey(const ValueKey('settings-animations-false'));
    await tester.ensureVisible(off);
    await tester.tap(off);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SegmentedButton<bool>>(
            find.byKey(const ValueKey('settings-animations')),
          )
          .selected,
      {false},
    );
    expect(saved?.tvAnimations, isFalse);
    expect(Preferences.fromJson(saved!.toJson()).tvAnimations, isFalse);
    expect(MediaQuery.disableAnimationsOf(tester.element(off)), isTrue);
    expect(
      tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .themeAnimationDuration,
      Duration.zero,
    );
    final on = find.byKey(const ValueKey('settings-animations-true'));
    await tester.ensureVisible(on);
    await tester.pumpAndSettle();
    await tester.tap(on);
    await tester.pumpAndSettle();
    expect(saved?.tvAnimations, isTrue);
    expect(MediaQuery.disableAnimationsOf(tester.element(on)), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in [const Size(700, 600), const Size(1280, 800)]) {
    testWidgets('desktop header actions and title navigation fit $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        FreeSceneApp(
          initialPreferences: Preferences(),
          savePreferences: (_) async {},
          catalogRepository: DemoCatalog(),
        ),
      );
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      expect(find.byKey(const ValueKey('catalog-filter')), findsNothing);
      expect(find.byKey(const ValueKey('catalog-refresh')), findsNothing);
      final favorite = find.byKey(const ValueKey('catalog-favorites'));
      final queueButton = find.byKey(const ValueKey('catalog-queue'));
      final favoriteLeft = tester.getTopLeft(favorite).dx;
      final queueLeft = tester.getTopLeft(queueButton).dx;
      final segment = find.byKey(const ValueKey('catalog-kind-movies'));
      final segmentRect = tester.getRect(segment);
      await mouse.moveTo(tester.getCenter(favorite));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(favorite).dx, favoriteLeft);
      expect(tester.getTopLeft(queueButton).dx, greaterThan(queueLeft));
      expect(tester.getRect(segment), segmentRect);
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      await mouse.moveTo(
        tester.getTopLeft(find.byKey(const ValueKey('catalog-search'))) +
            const Offset(20, 20),
      );
      await tester.pumpAndSettle();
      for (final id in ['catalog-filter', 'catalog-refresh']) {
        final action = find.byKey(ValueKey(id));
        expect(
          find.ancestor(of: action, matching: find.byType(DesktopSearchField)),
          findsOneWidget,
        );
        await mouse.moveTo(tester.getCenter(action));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: id);
      }
      await mouse.moveTo(Offset.zero);
      await tester.tap(find.byType(CatalogTile).first);
      await tester.pumpAndSettle();
      final back = find.byKey(const ValueKey('catalog-back'));
      expect(tester.getSize(back), const Size(44, 44));
      final favoriteRect = tester.getRect(find.byType(FavoriteButton));
      final queueRect = tester.getRect(find.byType(QueueButton));
      final toolbar = find.byKey(const ValueKey('catalog-details-toolbar'));
      expect(
        find.descendant(of: toolbar, matching: find.byType(FavoriteButton)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: toolbar,
          matching: find.byKey(const ValueKey('source-search-pill')),
        ),
        findsOneWidget,
      );
      expect(favoriteRect.top, greaterThan(tester.getRect(toolbar).bottom));
      expect(queueRect.left, greaterThanOrEqualTo(favoriteRect.right + 16));
      expect(find.byType(AddFavoriteIcon), findsOneWidget);
      await mouse.moveTo(tester.getCenter(back));
      await tester.pumpAndSettle();
      expect(tester.getSize(back).width, greaterThan(44));
      expect(tester.getRect(find.byType(FavoriteButton)), favoriteRect);
      expect(tester.getRect(find.byType(QueueButton)), queueRect);
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.byType(CatalogTile), findsWidgets);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }
}
