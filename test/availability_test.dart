import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freescene/catalog/availability_indicator.dart';
import 'package:freescene/domain/availability.dart';
import 'package:freescene/domain/source.dart';

void main() {
  test('availability distinguishes unknown, empty and well seeded swarms', () {
    expect(TorrentAvailability(const PeerCounts()).bars, isNull);
    expect(TorrentAvailability(const PeerCounts(seeds: 0, peers: 0)).bars, 0);
    expect(TorrentAvailability(const PeerCounts(seeds: 1)).bars, 1);
    expect(TorrentAvailability(const PeerCounts(seeds: 10)).bars, 3);
    expect(TorrentAvailability(const PeerCounts(seeds: 100)).bars, 5);
    expect(TorrentAvailability(const PeerCounts(seeds: 1000000)).bars, 5);
  });

  test('more peers cannot imply a complete copy without known seeds', () {
    for (final seeds in [null, 0]) {
      expect(
        TorrentAvailability(PeerCounts(seeds: seeds, peers: 1000000)).bars,
        2,
      );
    }
    double previous = -1;
    for (var seeds = 0; seeds <= 150; seeds++) {
      final score = TorrentAvailability(PeerCounts(seeds: seeds, peers: 3))
          .score!;
      expect(score, greaterThanOrEqualTo(previous));
      previous = score;
    }
    expect(
      TorrentAvailability(const PeerCounts(seeds: 10, peers: 20)).score,
      greaterThan(TorrentAvailability(const PeerCounts(seeds: 10)).score!),
    );
  });

  testWidgets(
    'availability retains exact counts and labels for accessibility',
    (tester) async {
      final semantics = tester.ensureSemantics();
      const label =
          'Доступность: 3/5 · Сиды: 10 · Пиры: 4\nОценка по данным провайдера';
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AvailabilityIndicator(
              source: SourceRow(
                id: 'torrent',
                provider: SourceProvider('demo'),
                title: 'Torrent',
                watch: SourceKind.magnet,
                download: DownloadKind.magnet,
                catalogueCounts: PeerCounts(seeds: 10, peers: 4),
              ),
              english: false,
            ),
          ),
        ),
      );
      expect(find.byTooltip(label), findsOneWidget);
      expect(find.bySemanticsLabel(label), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
}
