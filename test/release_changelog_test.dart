import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freescene/android/android_app.dart';
import 'package:freescene/android/android_runtime.dart';
import 'package:freescene/app.dart';
import 'package:freescene/providers/demo.dart';
import 'package:freescene/settings/preferences.dart';
import 'package:freescene/widgets/release_changelog.dart';

void main() {
  for (final platform in ['macOS', 'mobile', 'TV']) {
    testWidgets(
      '$platform opens Changelog once for an existing profile on upgrade',
      (tester) async {
        final tv = platform == 'TV';
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = platform == 'mobile'
            ? const Size(320, 640)
            : const Size(960, 540);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              AndroidRuntime.channel,
              (call) async => call.method == 'watchedSnapshot'
                  ? <String, String>{}
                  : {'available': false},
            );
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(AndroidRuntime.channel, null),
        );
        var profile = Preferences(language: AppLanguage.en).toJson();
        Future<void> save(Preferences value) async {
          profile = value.toJson();
        }

        Future<void> launch() async {
          final prefs = Preferences.fromJson(profile);
          await tester.pumpWidget(
            platform == 'macOS'
                ? FreeSceneApp(
                    initialPreferences: prefs,
                    savePreferences: save,
                    showChangelogOnStartup: true,
                    catalogRepository: DemoCatalog(),
                  )
                : AndroidApp(
                    runtime: AndroidRuntime(
                      profile: Directory('/fixture'),
                      cache: Directory('/fixture/cache'),
                      tv: tv,
                      lowRam: tv,
                      version: ReleaseChangelog.version,
                    ),
                    initialPreferences: prefs,
                    savePreferences: save,
                    showChangelogOnStartup: true,
                    repository: DemoCatalog(),
                  ),
          );
          await tester.pumpAndSettle();
        }

        await launch();
        expect(find.text('Changelog'), findsOneWidget);
        expect(
          find.text('FreeScene ${ReleaseChangelog.version}'),
          findsOneWidget,
        );
        if (tv) {
          await tester.sendKeyEvent(LogicalKeyboardKey.select);
        } else {
          await tester.tap(find.text('Got it'));
        }
        await tester.pumpAndSettle();
        expect(find.text('Changelog'), findsNothing);
        expect(profile['lastSeenChangelog'], ReleaseChangelog.version);
        expect(profile['language'], 'en');
        await tester.pumpWidget(const SizedBox());
        await launch();
        expect(find.text('Changelog'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }
}
