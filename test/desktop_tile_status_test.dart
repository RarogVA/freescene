import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freescene/catalog/catalog_controller.dart';
import 'package:freescene/catalog/catalog_page.dart';
import 'package:freescene/catalog/catalog_tile.dart';
import 'package:freescene/catalog/favorite_button.dart';
import 'package:freescene/catalog/favorites.dart';
import 'package:freescene/catalog/queue_button.dart';
import 'package:freescene/catalog/watch_queue.dart';
import 'package:freescene/catalog/watched.dart';
import 'package:freescene/providers/demo.dart';
import 'package:freescene/widgets/catalog_style.dart';

void main() {
  testWidgets(
    'desktop statuses update together in the shared TV poster badge',
    (tester) async {
      const channel = MethodChannel('test/tile-status');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final favorites = FavoritesController(), queue = QueueController();
      final watched = WatchedController(channel);
      final controller = CatalogController(
        DemoCatalog(),
        favorites: favorites,
        queue: queue,
      );
      addTearDown(favorites.dispose);
      addTearDown(queue.dispose);
      addTearDown(watched.dispose);
      addTearDown(controller.dispose);
      await controller.browse();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WatchedScope(
              controller: watched,
              child: CatalogPageView(controller: controller, english: false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final title = controller.items.first;
      final poster = find.byType(PosterCardContent).first;
      Finder badge(IconData icon) =>
          find.descendant(of: poster, matching: find.byIcon(icon));
      expect(badge(Icons.favorite), findsNothing);
      await favorites.toggle(title);
      await queue.toggle(title);
      await watched.markTitle(title);
      await tester.pumpAndSettle();
      final icons = [
        Icons.visibility_outlined,
        Icons.favorite,
        Icons.playlist_play,
      ];
      for (final icon in icons) {
        expect(badge(icon), findsOneWidget);
      }
      final rects = icons.map((icon) => tester.getRect(badge(icon))).toList();
      expect(rects.map((rect) => rect.center.dy).toSet(), hasLength(1));
      expect(rects[0].right, lessThan(rects[1].left));
      expect(rects[1].right, lessThan(rects[2].left));
      final tile = find.byType(CatalogTile).first;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(tile));
      await tester.pumpAndSettle();
      void expectStatusOnly() {
        for (final control in [FavoriteButton, QueueButton, IconButton]) {
          expect(
            find.descendant(of: tile, matching: find.byType(control)),
            findsNothing,
          );
        }
        for (final icon in icons) {
          expect(badge(icon), findsOneWidget);
        }
      }

      expectStatusOnly();
      await mouse.removePointer();
      final focus = Focus.of(tester.element(poster));
      focus.requestFocus();
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      expectStatusOnly();
      await favorites.toggle(title);
      await tester.pumpAndSettle();
      expect(badge(Icons.favorite), findsNothing);
      expect(badge(Icons.playlist_play), findsOneWidget);
      expect(badge(Icons.visibility_outlined), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
