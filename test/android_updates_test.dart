import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freescene/android/android_updates.dart';
import 'package:freescene/android/android_runtime.dart';
import 'package:freescene/android/android_theme.dart';
import 'package:freescene/android/android_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidRuntime.channel, null),
  );
  Future<void> show(
    WidgetTester tester, {
    bool tv = false,
    bool english = false,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: androidTheme(dark: true, tv: tv),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => AndroidAboutDialog(
                version: '1.3.4',
                english: english,
                tv: tv,
              ),
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
    testWidgets('About actions check, download and install TV=$tv', (
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
      expect(find.byType(FilledButton), findsNWidgets(3));
      expect(find.text('Проверить обновления'), findsOneWidget);
      expect(find.text('Лицензии открытого ПО'), findsOneWidget);
      expect(find.text('Поддержать разработчика'), findsOneWidget);
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
    testWidgets('three equal-width About actions fit $size', (tester) async {
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
      final support = tester.getRect(
        find.byKey(const ValueKey('android-about-support')),
      );
      expect(check.width, licenses.width);
      expect(check.left, licenses.left);
      expect(licenses.top, greaterThan(check.bottom));
      expect(support.width, check.width);
      expect(support.left, check.left);
      expect(support.top, greaterThan(licenses.bottom));
      expect(support.bottom, lessThanOrEqualTo(size.height));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('mobile support opens the external page only on request', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      AndroidRuntime.channel,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    await show(tester);
    expect(calls, isEmpty);
    await tester.tap(find.byKey(const ValueKey('android-about-support')));
    await tester.pumpAndSettle();
    expect(calls.map((call) => call.method), ['supportDeveloper']);
    expect(find.byKey(const ValueKey('developer-support-qr')), findsNothing);
    expect(find.byType(AndroidAboutDialog), findsOneWidget);
  });

  testWidgets('missing browser leaves the support link available to copy', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      AndroidRuntime.channel,
      (_) async => throw PlatformException(code: 'browser_unavailable'),
    );
    await show(tester, english: true);
    await tester.tap(find.text('Support the developer'));
    await tester.pumpAndSettle();
    expect(find.text('Could not open browser'), findsOneWidget);
    expect(find.text(developerSupportUrl), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final scenario in [
    (const Size(960, 540), false, 1.0),
    (const Size(1280, 720), true, 1.0),
    (const Size(960, 540), true, 1.5),
  ]) {
    final (size, english, textScale) = scenario;
    testWidgets('TV support is offline and remote accessible $scenario', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        AndroidRuntime.channel,
        (_) async => throw StateError('TV support must not open a browser'),
      );
      await show(tester, tv: true, english: english, textScale: textScale);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      final support = find.byKey(const ValueKey('android-about-support'));
      expect(
        Focus.of(
          tester.element(
            find.descendant(of: support, matching: find.byType(Text)),
          ),
        ).hasPrimaryFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final qr = find.byKey(const ValueKey('developer-support-qr'));
      expect(
        tester.widget<Image>(qr).image,
        const AssetImage(developerSupportQrAsset),
      );
      expect(find.text(developerSupportUrl), findsOneWidget);
      final bounds = tester.getRect(qr);
      expect(bounds.top, greaterThanOrEqualTo(0));
      expect(bounds.bottom, lessThanOrEqualTo(size.height));
      expect(tester.takeException(), isNull);
      // The only TV dialog action has initial focus, so OK closes it.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(qr, findsNothing);
      expect(find.byType(AndroidAboutDialog), findsOneWidget);
      expect(
        Focus.of(
          tester.element(
            find.descendant(of: support, matching: find.byType(Text)),
          ),
        ).hasPrimaryFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(qr, findsNothing);
      expect(find.byType(AndroidAboutDialog), findsOneWidget);
    });
  }
  for (final scenario in [
    (const Size(960, 540), false, 1.0),
    (const Size(1280, 720), false, 1.0),
    (const Size(960, 540), true, 1.5),
    (const Size(1280, 720), false, 1.5),
  ]) {
    final (size, english, textScale) = scenario;
    testWidgets('TV About geometry is stable through update states $scenario', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var response = Completer<Map<String, Object>>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        AndroidRuntime.channel,
        (call) => response.future,
      );
      await show(tester, tv: true, english: english, textScale: textScale);
      final panel = tester.getRect(find.byType(AlertDialog));
      final check = tester.getRect(
        find.byKey(const ValueKey('android-about-check')),
      );
      final licenses = tester.getRect(
        find.byKey(const ValueKey('android-about-licenses')),
      );
      void unchanged() {
        expect(tester.getRect(find.byType(AlertDialog)), panel);
        expect(
          tester.getRect(find.byKey(const ValueKey('android-about-check'))),
          check,
        );
        expect(
          tester.getRect(find.byKey(const ValueKey('android-about-licenses'))),
          licenses,
        );
        expect(tester.takeException(), isNull);
      }

      await tester.tap(find.byKey(const ValueKey('android-about-check')));
      await tester.pump();
      unchanged();
      response.complete({'available': false});
      await tester.pumpAndSettle();
      unchanged();
      response = Completer<Map<String, Object>>();
      await tester.tap(find.byKey(const ValueKey('android-about-check')));
      await tester.pump();
      unchanged();
      response.completeError(PlatformException(code: 'signature_or_version'));
      await tester.pumpAndSettle();
      unchanged();
      response = Completer<Map<String, Object>>();
      await tester.tap(find.byKey(const ValueKey('android-about-check')));
      await tester.pump();
      response.complete({'available': true, 'version': '1.8.2'});
      await tester.pumpAndSettle();
      unchanged();
      final download = Completer<Map<String, Object>>();
      final install = Completer<Map<String, Object>>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        AndroidRuntime.channel,
        (call) =>
            call.method == 'updateDownload' ? download.future : install.future,
      );
      await tester.tap(find.byKey(const ValueKey('android-about-check')));
      await tester.pump();
      unchanged();
      download.complete({'ready': true});
      await tester.pump();
      await tester.pump();
      unchanged();
      install.complete({'permissionRequired': true});
      await tester.pumpAndSettle();
      unchanged();
      expect(
        find.textContaining(english ? 'Allow installs' : 'Разрешите установку'),
        findsOneWidget,
      );
      expect(
        FocusManager.instance.primaryFocus,
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('android-about-check')),
            )
            .focusNode,
      );
    });
  }

  for (final size in [const Size(960, 540), const Size(1280, 720)]) {
    for (final failure in [false, true]) {
      testWidgets('TV update result skips status focus $size error=$failure', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          AndroidRuntime.channel,
          (call) async {
            if (failure) throw PlatformException(code: 'network');
            return {'available': false};
          },
        );
        await show(tester, tv: true);
        final check = find.byKey(const ValueKey('android-about-check'));
        final primary = tester.widget<FilledButton>(check).focusNode;
        expect(FocusManager.instance.primaryFocus, primary);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus, primary);
        expect(
          find.textContaining(
            failure ? 'Проверьте сеть' : 'Новых Android-сборок нет',
          ),
          findsOneWidget,
        );
        final logo = tester.getRect(find.byType(Image));
        final status = tester.getRect(
          find.byKey(const ValueKey('android-about-status-area')),
        );
        final scrollables = tester
            .stateList<ScrollableState>(
              find.descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(Scrollable),
              ),
            )
            .toList();
        final offsets = scrollables
            .map((state) => state.position.pixels)
            .toList();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(
          Focus.of(tester.element(find.byIcon(Icons.close))).hasPrimaryFocus,
          isTrue,
        );
        expect(tester.getRect(find.byType(Image)), logo);
        expect(
          tester.getRect(
            find.byKey(const ValueKey('android-about-status-area')),
          ),
          status,
        );
        expect(
          scrollables.map((state) => state.position.pixels).toList(),
          offsets,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus, primary);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
