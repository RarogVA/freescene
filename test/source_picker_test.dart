import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freescene/android/source_picker.dart';
import 'package:freescene/android/remote_focus.dart';
import 'package:freescene/catalog/catalog_models.dart';
import 'package:freescene/catalog/source_checks.dart';
import 'package:freescene/catalog/source_choices.dart';

import 'source_choices_test.dart' show candidate;

void main() {
  setUp(() => sourceCheckResults.value = {});
  for (final tv in [true, false]) {
    testWidgets(
      'quality selects voice rows, direct launch and explicit alternatives tv=$tv',
      (tester) async {
        await tester.binding.setSurfaceSize(
          Size(tv ? 960 : 390, tv ? 540 : 844),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final focus = RemoteFocus(enabled: tv);
        final played = <String>[];
        var stopped = 0;
        final probes = <List<CatalogSource>>[];
        final sources = [
          candidate('1080-a', seeds: 10),
          candidate('1080-b', seeds: 1),
          candidate('720', audio: 'NewStudio', quality: '720p'),
          candidate('unknown', audio: null, quality: null),
        ];
        await tester.pumpWidget(
          MaterialApp(
            shortcuts: {
              ...WidgetsApp.defaultShortcuts,
              const SingleActivator(LogicalKeyboardKey.select):
                  const ActivateIntent(),
            },
            home: Scaffold(
              body: SingleChildScrollView(
                child: AndroidSourcePicker(
                  title: const CatalogTitle(
                    id: 'movie',
                    kind: CatalogKind.movies,
                    name: 'Movie',
                  ),
                  sources: sources,
                  focus: focus,
                  english: false,
                  limit: 8,
                  onPlay: (source) => played.add(source.row.id),
                  onCandidates: (_, values) => probes.add(values),
                  onStop: () => stopped++,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('LostFilm'), findsOneWidget);
        expect(find.text('NewStudio'), findsNothing);
        expect(probes.last.map((s) => s.row.id), ['1080-a', '1080-b']);
        final group = sourceVoiceChoices(
          sources.take(2).toList(),
          series: false,
        ).single;
        if (tv) {
          final button = tester.widget<OutlinedButton>(
            find.byKey(ValueKey('remote-source-voice-${group.key}')),
          );
          button.focusNode!.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.select);
        } else {
          await tester.tap(find.text('LostFilm'));
        }
        await tester.pump();
        expect(played, ['1080-a']);
        await tester.tap(
          find.byKey(ValueKey('remote-alternatives-voice-${group.key}')),
        );
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey('remote-source-test-1080-b')),
        );
        await tester.tap(
          find.byKey(const ValueKey('remote-source-test-1080-b')),
        );
        await tester.pump();
        expect(played, ['1080-a', '1080-b']);
        await tester.ensureVisible(
          find.byKey(const ValueKey('remote-quality-hd')),
        );
        await tester.tap(find.byKey(const ValueKey('remote-quality-hd')));
        await tester.pump();
        expect(find.text('NewStudio'), findsOneWidget);
        expect(find.text('LostFilm'), findsNothing);
        expect(probes.last.map((s) => s.row.id), ['720']);
        await tester.tap(find.byKey(const ValueKey('remote-quality-unknown')));
        await tester.pump();
        expect(find.text('Озвучка не указана'), findsOneWidget);
        expect(probes.last.single.row.id, 'unknown');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        expect(stopped, 1);
        focus.dispose();
      },
    );
  }
  testWidgets(
    'probe result changes the chosen source without losing remote focus',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final remote = RemoteFocus(enabled: true);
      final sources = [candidate('a', seeds: 100), candidate('b', seeds: 1)];
      final played = <String>[];
      var selections = 0;
      await tester.pumpWidget(
        MaterialApp(
          shortcuts: {
            ...WidgetsApp.defaultShortcuts,
            const SingleActivator(LogicalKeyboardKey.select):
                const ActivateIntent(),
          },
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: sourceCheckResults,
              builder: (context, _, _) => AndroidSourcePicker(
                title: const CatalogTitle(
                  id: 'movie',
                  kind: CatalogKind.movies,
                  name: 'Movie',
                ),
                sources: sources,
                focus: remote,
                english: false,
                limit: 8,
                onPlay: (source) => played.add(source.row.id),
                onCandidates: (_, _) => selections++,
                onStop: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final group = sourceVoiceChoices(sources, series: false).single;
      final button = find.byKey(ValueKey('remote-source-voice-${group.key}'));
      final node = tester.widget<OutlinedButton>(button).focusNode!;
      node.requestFocus();
      await tester.pump();
      sourceCheckResults.value = {
        sourceCheckKey(sources[1]): SourceCheck(
          SourceCheckState.data,
          DateTime.now(),
        ),
      };
      await tester.pump();
      expect(tester.widget<OutlinedButton>(button).focusNode, same(node));
      expect(node.hasPrimaryFocus, isTrue);
      expect(selections, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      expect(played, ['b']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      remote.dispose();
    },
  );
  testWidgets(
    'catalogue pagination preserves an in-flight probe but a new filter cancels it',
    (tester) async {
      final pending = Completer<SourceCheckState>();
      var cancellations = 0;
      final checks = SourceChecks(
        probe: (_) => pending.future,
        cancelProbe: () async {
          cancellations++;
        },
      );
      final focus = RemoteFocus(enabled: false);
      Future<void> show(List<CatalogSource> sources, String filter) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AndroidSourcePicker(
                title: const CatalogTitle(
                  id: 'movie',
                  kind: CatalogKind.movies,
                  name: 'Movie',
                ),
                sources: sources,
                selectionKey: filter,
                focus: focus,
                english: false,
                limit: 8,
                onPlay: (_) {},
                onCandidates: checks.select,
                onStop: checks.stop,
              ),
            ),
          ),
        );
        await tester.pump();
      }

      await show([candidate('a')], '1:1');
      final initialCancellations = cancellations;
      await show([candidate('a'), candidate('b', audio: 'NewStudio')], '1:1');
      expect(cancellations, initialCancellations);
      expect(recentSourceCheck('test:a')?.state, SourceCheckState.checking);
      await show([candidate('a')], '1:2');
      expect(cancellations, initialCancellations + 1);
      checks.dispose();
      pending.complete(SourceCheckState.data);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      focus.dispose();
    },
  );
}
