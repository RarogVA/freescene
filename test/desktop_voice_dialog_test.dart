import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freescene/widgets/voice_search_dialog.dart';

void main() {
  for (final english in [false, true]) {
    testWidgets(
      'disabled Dictation explains recovery and retry succeeds english=$english',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(620, 700);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var attempts = 0, settingsOpened = 0;
        String? recognized;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  child: const Text('Open'),
                  onPressed: () async {
                    recognized = await showDialog<String>(
                      context: context,
                      builder: (_) => VoiceSearchDialog(
                        english: english,
                        desktop: true,
                        listen: () async {
                          if (++attempts == 1) {
                            throw PlatformException(
                              code: 'voice_dictation_disabled',
                            );
                          }
                          return 'Дюна';
                        },
                        cancel: () async {},
                        openSettings: () async {
                          settingsOpened++;
                        },
                        events: const Stream.empty(),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            english ? 'Dictation is turned off' : 'В macOS отключена Диктовка',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            english ? 'Could not hear you' : 'Не удалось расслышать',
          ),
          findsNothing,
        );
        expect(attempts, 1);
        await tester.tap(find.byKey(const ValueKey('voice-settings')));
        await tester.pumpAndSettle();
        expect(settingsOpened, 1);
        expect(attempts, 1); // Settings must not silently restart recording.
        await tester.tap(find.byKey(const ValueKey('voice-retry')));
        await tester.pumpAndSettle();
        expect(attempts, 2);
        expect(recognized, 'Дюна');
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final code in [
    'voice_assets_missing',
    'voice_permission',
    'voice_no_match',
    'voice_unavailable',
  ]) {
    testWidgets('desktop failure $code offers only relevant recovery action', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                child: const Text('Open'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => VoiceSearchDialog(
                    english: false,
                    desktop: true,
                    listen: () async => throw PlatformException(code: code),
                    cancel: () async {},
                    openSettings: () async {},
                    events: const Stream.empty(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('voice-settings')),
        code == 'voice_assets_missing' ? findsOneWidget : findsNothing,
      );
      expect(
        find.textContaining('Не удалось расслышать'),
        code == 'voice_no_match' ? findsOneWidget : findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('voice-cancel')));
      await tester.pumpAndSettle();
      expect(find.byType(VoiceSearchDialog), findsNothing);
    });
  }
}
