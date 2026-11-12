import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freescene/android/android_downloads.dart';
import 'package:freescene/android/android_runtime.dart';
import 'package:freescene/android/android_theme.dart';
import 'package:freescene/android/remote_focus.dart';

void main() {
  var tasks = <Map<String, Object>>[];
  final calls = <MethodCall>[];
  setUp(() {
    tasks = [];
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidRuntime.channel, (call) async {
          calls.add(call);
          return {'tasks': tasks};
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidRuntime.channel, null);
  });

  Future<void> show(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    bool english = false,
    double textScale = 1,
    VoidCallback? back,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final focus = RemoteFocus(enabled: false);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: androidTheme(dark: true, tv: false),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: SafeArea(
            child: AndroidDownloads(
              focus: focus,
              back: back ?? () {},
              english: english,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder button(String id) => find.byKey(ValueKey('remote-$id'));

  for (final scenario in [
    (const Size(320, 640), false, 1.0),
    (const Size(390, 844), false, 1.0),
    (const Size(800, 360), false, 1.0),
    (const Size(320, 640), false, 1.5),
    (const Size(320, 640), true, 1.5),
  ]) {
    testWidgets('mobile downloads header stays in one row $scenario', (
      tester,
    ) async {
      final (size, english, textScale) = scenario;
      await show(tester, size: size, english: english, textScale: textScale);
      expect(button('download-import'), findsNothing);
      expect(button('download-magnet'), findsNothing);
      expect(find.byType(OutlinedButton), findsNWidgets(2));
      expect(find.byTooltip(english ? 'Back' : 'Назад'), findsOneWidget);
      expect(find.byTooltip(english ? 'Refresh' : 'Обновить'), findsOneWidget);
      final back = tester.getRect(button('downloads-back'));
      final refresh = tester.getRect(button('download-refresh'));
      final title = tester.getRect(
        find.text(english ? 'Downloads' : 'Загрузки'),
      );
      final empty = tester.getRect(
        find.text(english ? 'No downloads yet' : 'Загрузок пока нет'),
      );
      expect(back.center.dy, title.center.dy);
      expect(refresh.center.dy, title.center.dy);
      expect(back.width, greaterThanOrEqualTo(48));
      expect(refresh.width, greaterThanOrEqualTo(48));
      expect(back.right, lessThan(title.left));
      expect(title.right, lessThan(refresh.left));
      expect(back.left, empty.left);
      expect(refresh.right, size.width - back.left);
      expect(empty.top, greaterThan(back.bottom));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('mobile refresh loads tasks and back remains usable', (
    tester,
  ) async {
    var backCount = 0;
    await show(tester, size: const Size(320, 640), back: () => backCount++);
    final header = tester.getRect(button('download-refresh'));
    final initialCalls = calls.length;
    tasks = [
      for (final phase in ['downloading', 'completed'])
        {
          'id': phase,
          'title': 'Длинное название фильма с дополнительными сведениями о качестве и переводе',
          'origin': {'local': 'torrentFile'},
          'phase': phase,
          'done': phase == 'completed' ? 2048 : 1024,
          'total': 2048,
          'rate': 1024,
          'seeds': 3,
          'peers': 2,
          'error': '',
          'event': '',
          'metadata': true,
          'files': <Object>[],
        },
    ];
    await tester.tap(button('download-refresh'));
    await tester.pumpAndSettle();
    expect(calls.length, initialCalls + 1);
    expect(calls.last.method, 'torrentCommand');
    expect(calls.last.arguments['request']['method'], 'status');
    expect(find.text('Загрузок пока нет'), findsNothing);
    expect(find.byType(Card), findsNWidgets(2));
    expect(tester.getRect(button('download-refresh')), header);
    await tester.ensureVisible(button('remove-completed'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(button('downloads-back'));
    await tester.pumpAndSettle();
    expect(backCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
