import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freescene/android/android_updates.dart';
import 'package:freescene/android/android_runtime.dart';
import 'package:freescene/android/android_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidRuntime.channel, null),
  );
  Future<void> show(WidgetTester tester, {bool tv = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: androidTheme(dark: true, tv: tv),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) =>
                  AndroidAboutDialog(version: '1.3.4', english: false, tv: tv),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  for (final tv in [false, true]) {
    testWidgets('two token-free actions check, download and install TV=$tv', (
      tester,
    ) async {
      final calls = <String>[];
      var needsPermission = true;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        AndroidRuntime.channel,
        (call) async {
          calls.add(call.method);
          return switch (call.method) {
            'updateCheck' => {'available': true, 'version': '1.4.0'},
            'updateDownload' => {'ready': true},
            'updateInstall' => {'permissionRequired': needsPermission},
            _ => throw StateError(
              'Unexpected account or updater call: ${call.method}',
            ),
          };
        },
      );
      await show(tester, tv: tv);
      expect(calls, isEmpty);
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('токен'), findsNothing);
      expect(find.byType(FilledButton), findsNWidgets(2));
      expect(find.text('Проверить обновления'), findsOneWidget);
      expect(find.text('Лицензии открытого ПО'), findsOneWidget);
      await tester.tap(find.text('Проверить обновления'));
      await tester.pumpAndSettle();
      expect(find.text('Установить обновления'), findsOneWidget);
      await tester.tap(find.text('Установить обновления'));
      await tester.pumpAndSettle();
      expect(calls, ['updateCheck', 'updateDownload', 'updateInstall']);
      expect(find.textContaining('Разрешите установку'), findsOneWidget);
      needsPermission = false;
      await tester.tap(find.text('Установить обновления'));
      await tester.pumpAndSettle();
      expect(calls, [
        'updateCheck',
        'updateDownload',
        'updateInstall',
        'updateInstall',
      ]);
      expect(find.textContaining('Подтвердите установку'), findsOneWidget);
    });
  }
  testWidgets(
    'busy checking cannot repeat and network failure offers retry without tokens',
    (tester) async {
      final response = Completer<Map<String, Object>>();
      var calls = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        AndroidRuntime.channel,
        (call) {
          expect(call.method, 'updateCheck');
          calls++;
          return response.future;
        },
      );
      await show(tester);
      await tester.tap(find.text('Проверить обновления'));
      await tester.pump();
      expect(find.text('Проверка…'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('android-about-check')),
            )
            .onPressed,
        isNull,
      );
      response.completeError(PlatformException(code: 'github_access'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('Проверить обновления'), findsOneWidget);
      expect(
        find.textContaining('Выпуски FreeScene сейчас недоступны'),
        findsOneWidget,
      );
      expect(find.textContaining('токен'), findsNothing);
    },
  );
  testWidgets('licenses open without a network request', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      AndroidRuntime.channel,
      (_) async => throw StateError('Licenses must be local'),
    );
    LicenseRegistry.addLicense(
      () => Stream.value(
        const LicenseEntryWithLineBreaks([
          'fixture-library',
        ], 'Fixture open-source notice'),
      ),
    );
    await show(tester);
    await tester.tap(find.text('Лицензии открытого ПО'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Fixture open-source notice'), findsOneWidget);
    expect(find.text('Закрыть'), findsOneWidget);
  });
  for (final size in [
    const Size(390, 844),
    const Size(960, 540),
    const Size(1280, 720),
  ]) {
    testWidgets('two equal-width update actions fit $size', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await show(tester, tv: size.width > 500);
      final check = tester.getRect(
        find.byKey(const ValueKey('android-about-check')),
      );
      final licenses = tester.getRect(
        find.byKey(const ValueKey('android-about-licenses')),
      );
      expect(check.width, licenses.width);
      expect(check.left, licenses.left);
      expect(licenses.top, greaterThan(check.bottom));
      expect(tester.takeException(), isNull);
    });
  }
}
