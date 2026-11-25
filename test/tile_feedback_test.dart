import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freescene/android/remote_focus.dart';
import 'package:freescene/catalog/catalog_tile.dart';

void main() {
  double scale(WidgetTester tester) => tester
      .widget<ScaleTransition>(
        find
            .descendant(
              of: find.byType(AnimatedScale),
              matching: find.byType(ScaleTransition),
            )
            .first,
      )
      .scale
      .value;

  for (final reduced in [false, true]) {
    testWidgets('desktop hold feedback and cancellation, reduced=$reduced', (
      tester,
    ) async {
      var taps = 0, menus = 0;
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
                    onTap: () => taps++,
                    onContextMenu: () async {
                      menus++;
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
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(tile));
      await tester.pumpAndSettle();
      final resting = scale(tester);
      await mouse.down(tester.getCenter(tile));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 90));
      expect(scale(tester), reduced ? resting : lessThan(resting));
      expect(menus, 0);
      await mouse.cancel();
      await tester.pumpAndSettle();
      expect(taps, 0);
      expect(scale(tester), resting);
      await tester.longPress(tile);
      await tester.pumpAndSettle();
      expect(menus, 1);
      expect(taps, 0);
      await tester.tap(tile);
      expect(taps, 1);
      await mouse.removePointer();
    });

    testWidgets(
      'TV OK hold animates and release does not activate menu, reduced=$reduced',
      (tester) async {
        final remote = RemoteFocus();
        var taps = 0, menus = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 180,
                    height: 260,
                    child: RemoteButton(
                      id: 'poster',
                      focus: remote,
                      tile: true,
                      onPressed: () => taps++,
                      onLongPress: () => menus++,
                      child: const Text('Poster'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        tester
            .widget<OutlinedButton>(find.byType(OutlinedButton))
            .focusNode!
            .requestFocus();
        await tester.pumpAndSettle();
        final resting = scale(tester);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 90));
        expect(scale(tester), reduced ? resting : lessThan(resting));
        expect(menus, 0);
        await tester.pump(const Duration(milliseconds: 450));
        expect(menus, 1);
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(menus, 1);
        expect(taps, 0);
        expect(scale(tester), resting);
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(taps, 1);
        await tester.pumpWidget(const SizedBox());
        remote.dispose();
      },
    );
  }
}
