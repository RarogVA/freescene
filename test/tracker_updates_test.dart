import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freescene/catalog/catalog_models.dart';
import 'package:freescene/catalog/favorites.dart';
import 'package:freescene/catalog/tracker_source_visibility.dart';
import 'package:freescene/catalog/tracker_updates.dart';
import 'package:freescene/providers/demo.dart';

const tracker = SourceProvider('tracker');
const mirror = SourceProvider('mirror');
const series = CatalogTitle(
  id: 'dark',
  kind: CatalogKind.series,
  name: 'Тёмная материя',
  year: 2024,
);
const film = CatalogTitle(
  id: 'film',
  kind: CatalogKind.movies,
  name: 'Фильм',
  year: 2023,
);

CatalogSource release(
  String name, {
  String id = 'topic',
  SourceProvider provider = tracker,
}) => CatalogSource(
  row: SourceRow(
    id: id,
    provider: provider,
    title: name,
    watch: SourceKind.magnet,
    download: DownloadKind.magnet,
  ),
);

class Tracker extends DemoCatalog {
  List<CatalogSource> rows = [];
  bool offline = false;
  Set<SourceProvider> disabled = {};
  @override
  List<SourceProvider> providers(CatalogTitle title) => [tracker, mirror];
  @override
  Future<CatalogPage<CatalogSource>> providerSources(
    CatalogTitle title,
    SourceProvider provider, {
    int start = 0,
  }) async {
    if (offline || disabled.contains(provider)) {
      throw const SocketException('offline');
    }
    final matches = rows.where((r) => r.row.provider == provider).toList();
    // Exercise later pages, including updates to the same topic.
    return CatalogPage(
      items: matches.skip(start).take(1).toList(),
      total: matches.length,
      start: start,
    );
  }
}

void main() {
  setUp(
    () => SourceProvider.register([
      const ProviderDescriptor(tracker, 'Tracker', torrentTracker: true),
      const ProviderDescriptor(mirror, 'Mirror', torrentTracker: true),
    ]),
  );
  test('first scan, offline, in-place episode updates, duplicate releases, and persisted acknowledgements', () async {
    final favorites = FavoritesController(), queue = FavoritesController();
    await favorites.toggle(series);
    await queue.toggle(series);
    final dir = await Directory.systemTemp.createTemp('tracker-test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/updates.json');
    final repo = Tracker();
    final old = release('Тёмная материя (2015) S03E01', id: 'wrong');
    final original = release('S01E01-E05');
    repo.rows = [old, original];
    TrackerUpdates monitor() =>
        TrackerUpdates(repo, favorites, queue, file: file)
          ..configure({tracker})
          ..sync();
    var updates = monitor();
    await updates.refresh();
    expect(updates.label(series, false), isNull);
    final next = release('S01E01-E06');
    repo.rows = [old, next];
    await updates.refresh();
    expect(updates.label(series, false), 'Новая серия · S01E06');
    expect(updates.shownEvents(series, original), isEmpty);
    repo.offline = true;
    await updates.refresh();
    updates.dispose();
    updates = monitor();
    await updates.refresh();
    expect(updates.label(series, true), 'New episode · S01E06');
    updates.acknowledge(series, updates.shownEvents(series, next));
    repo.offline = false;
    repo.rows = [next, release('S01E06', id: 'dub')];
    await updates.refresh();
    expect(updates.label(series, true), isNull);
    updates.dispose();
    updates = monitor();
    final secondSeason = release('S02E01', id: 'new-season');
    repo.rows = [...repo.rows, secondSeason];
    await updates.refresh();
    expect(updates.label(series, false), 'Новый сезон · S02');
    updates.dispose();
  });

  test('a failed tracker preserves pending events and another tracker can still report updates', () async {
    final saved = FavoritesController(), queue = FavoritesController();
    await saved.toggle(series);
    final repo = Tracker()..rows = [release('S01E01')];
    final updates = TrackerUpdates(repo, saved, queue)
      ..configure({tracker, mirror})
      ..sync();
    await updates.refresh();
    repo.disabled = {tracker};
    final duplicate = release('S01E01', provider: mirror);
    final fresh = release('S01E02', provider: mirror, id: 'later');
    repo.rows = [duplicate, fresh];
    await updates.refresh();
    expect(updates.label(series, true), 'New episode · S01E02');
    repo.rows = [];
    await updates.refresh();
    expect(updates.label(series, true), isNotNull);
    updates.acknowledge(series, updates.shownEvents(series, fresh));
    repo.disabled.clear();
    repo.rows = [release('S01E02')];
    await updates.refresh();
    expect(updates.label(series, true), isNull);
    updates.dispose();
  });
  testWidgets(
    'first movie release stays pending until its row enters the viewport',
    (tester) async {
      final favorites = FavoritesController(), queue = FavoritesController();
      await favorites.toggle(film);
      final repo = Tracker();
      final updates = TrackerUpdates(repo, favorites, queue)
        ..configure({tracker})
        ..sync();

      await updates.refresh();
      final row = release('Фильм (2023)');
      repo.rows = [row];
      await updates.refresh();
      expect(updates.label(film, false), 'Фильм появился на трекерах');
      final scroll = ScrollController();
      await tester.pumpWidget(
        MaterialApp(
          home: SingleChildScrollView(
            controller: scroll,
            child: Column(
              children: [
                const SizedBox(height: 1500),
                TrackerSourceVisibility.wrap(
                  const SizedBox(height: 80, width: 100),
                  updates,
                  film,
                  row,
                ),
              ],
            ),
          ),
        ),
      );
      expect(updates.label(film, false), isNotNull);
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      expect(updates.label(film, false), isNull);
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
      updates.dispose();
    },
  );
}
