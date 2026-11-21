import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freescene/app.dart';
import 'package:freescene/providers/demo.dart';
import 'package:freescene/settings/preferences.dart';
import 'package:freescene/torrent/native_torrent.dart';
import 'package:freescene/widgets/desktop_controls.dart';

class _Native extends NativeTorrentService {
  final calls = <String>[];
  @override
  Future<dynamic> call(String method, [Map<String, dynamic>? args]) async {
    calls.add(method);
    if (method == 'status') {
      return {
        'tasks': [
          {
            'id': 'paused',
            'title': 'Paused download',
            'origin': {'local': 'torrentFile'},
            'phase': 'paused',
            'done': 100,
            'total': 1000,
            'rate': 0,
            'error': '',
            'event': '',
            'metadata': false,
            'files': [],
          },
        ],
        'persistenceError': '',
      };
    }
    return null;
  }
}

void main() {
  for (final size in [const Size(1280, 900), const Size(800, 700)]) {
    for (final page in ['history', 'settings', 'downloads']) {
      testWidgets(
        '$page title stays anchored during hover and focus at $size',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final messenger =
              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
          messenger.setMockMethodCallHandler(
            NativeTorrentService.channel,
            (call) async => call.method == 'watchHistorySnapshot'
                ? {'entries': []}
                : <String, String>{},
          );
          addTearDown(
            () => messenger.setMockMethodCallHandler(
              NativeTorrentService.channel,
              null,
            ),
          );
          final native = _Native();
          await tester.pumpWidget(
            FreeSceneApp(
              initialPreferences: Preferences(
                scale: size.width == 800 ? 150 : 100,
              ),
              savePreferences: (_) async {},
              nativeService: native,
              catalogRepository: DemoCatalog(),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(ValueKey('sidebar-$page')));
          await tester.pumpAndSettle();
          final back = find.byKey(ValueKey('$page-back'));
          final title = find.byKey(ValueKey('$page-title'));
          final rect = tester.getRect(title);
          expect(tester.widget<DesktopActionButton>(back).label, 'Назад');
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          await mouse.moveTo(tester.getCenter(back));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.getRect(title), rect);
          await tester.pumpAndSettle();
          expect(tester.getRect(title), rect);
          expect(tester.getSize(back).width, greaterThan(44));
          expect(tester.getRect(back).overlaps(rect), isFalse);
          expect(
            find.descendant(of: back, matching: find.byType(Tooltip)),
            findsNothing,
          );
          if (page == 'downloads') {
            final torrent = find.byKey(
              const ValueKey('downloads-open-torrent'),
            );
            final magnet = find.byKey(const ValueKey('downloads-add-magnet'));
            final header = find.byKey(const ValueKey('downloads-header'));
            expect(
              tester.widget<DesktopActionButton>(torrent).label,
              'Добавить torrent',
            );
            expect(tester.getRect(magnet).right, tester.getRect(header).right);
            for (final action in [torrent, magnet]) {
              await mouse.moveTo(tester.getCenter(action));
              await tester.pumpAndSettle();
              expect(tester.getRect(title), rect);
              expect(
                tester.getRect(magnet).right,
                tester.getRect(header).right,
              );
              expect(tester.takeException(), isNull);
            }
            final watch = tester.widget<DesktopActionButton>(
              find.widgetWithText(DesktopActionButton, 'Смотреть'),
            );
            final resume = tester.widget<DesktopActionButton>(
              find.widgetWithText(DesktopActionButton, 'Продолжить'),
            );
            expect(watch.icon, Icons.play_arrow_rounded);
            expect(resume.icon, Icons.download_rounded);
            await tester.tap(torrent);
            await tester.pumpAndSettle();
            expect(native.calls, contains('chooseTorrent'));
          }
          await mouse.moveTo(Offset.zero);
          await tester.pumpAndSettle();
          Focus.of(
            tester.element(
              find.descendant(of: back, matching: find.text('Назад')),
            ),
          ).requestFocus();
          await tester.pumpAndSettle();
          expect(tester.getRect(title), rect);
          await tester.tap(back);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('catalog-listing-toolbar')),
            findsOneWidget,
          );
          await mouse.removePointer();
          await tester.pumpWidget(const SizedBox());
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
