import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freescene/android/android_voice_dialog.dart';

Future<void> openVoice(
  WidgetTester tester, {
  required Future<String?> Function() listen,
  Future<void> Function()? cancel,
  Stream<dynamic>? events,
  void Function(String?)? result,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          return TextButton(
            onPressed: () async {
              final value = await showDialog<String>(
                context: context,
                builder: (_) => AndroidVoiceDialog(
                  english: false,
                  listen: listen,
                  cancel: cancel,
                  events: events,
                ),
              );
              result?.call(value);
            },
            child: const Text('Open'),
          );
        },
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets(
    'capture starts once, meter follows speech, only final result closes the dialog',
    (tester) async {
      final finalText = Completer<String?>();
      final events = StreamController<dynamic>();
      addTearDown(events.close);
      var starts = 0;
      String? submitted;
      await openVoice(
        tester,
        listen: () {
          starts++;
          return finalText.future;
        },
        events: events.stream,
        result: (value) => submitted = value,
      );
      expect(starts, 1);
      expect(find.byType(TextField), findsNothing);
      expect(
        find.descendant(
          of: find.byType(AndroidVoiceDialog),
          matching: find.byType(TextButton),
        ),
        findsOneWidget,
      );
      events.add({'phase': 'listening'});
      events.add({'level': .75, 'partial': 'Гангстер'});
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Говорите…'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const ValueKey('voice-level')),
            )
            .value,
        .75,
      );
      expect(find.text('Гангстер'), findsOneWidget);
      expect(submitted, isNull);
      events.add({'phase': 'recognizing'});
      await tester.pump();
      expect(find.text('Распознаю…'), findsOneWidget);
      finalText.complete('  Гангстерленд  ');
      await tester.pumpAndSettle();
      expect(submitted, 'Гангстерленд');
      expect(find.byType(AndroidVoiceDialog), findsNothing);
    },
  );

  for (final useBack in [true, false]) {
    testWidgets(
      '${useBack ? 'Back' : 'Cancel'} releases microphone and ignores a late result',
      (tester) async {
        final speech = Completer<String?>();
        var cancelled = 0, completed = 0;
        String? submitted;
        await openVoice(
          tester,
          listen: () => speech.future,
          cancel: () async {
            cancelled++;
          },
          result: (value) {
            completed++;
            submitted = value;
          },
        );
        if (useBack) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(find.byKey(const ValueKey('voice-cancel')));
        }
        await tester.pumpAndSettle();
        speech.complete('late text');
        await tester.pumpAndSettle();
        expect(cancelled, 1);
        expect(completed, 1);
        expect(submitted, isNull);
        expect(find.text('Open'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final code in [
    'voice_permission',
    'voice_unavailable',
    'voice_no_match',
    'voice_timeout',
    'voice_network',
    'voice_audio',
  ]) {
    testWidgets(
      '$code stays in the voice dialog and can retry without another input',
      (tester) async {
        var attempts = 0;
        String? submitted;
        await openVoice(
          tester,
          listen: () async {
            if (attempts++ == 0) throw PlatformException(code: code);
            return 'Дюна';
          },
          result: (text) => submitted = text,
        );
        await tester.pumpAndSettle();
        expect(find.byType(AndroidVoiceDialog), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'voice-retry');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(attempts, 2);
        expect(submitted, 'Дюна');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
