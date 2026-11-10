import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:freescene/catalog/catalog_controller.dart';
import 'package:freescene/catalog/catalog_models.dart';
import 'package:freescene/catalog/source_policy.dart';

const provider = SourceProvider('fixture');
CatalogSource source(String id, {String? name, int? seconds}) => CatalogSource(
  row: SourceRow(
    id: id,
    provider: provider,
    title: name ?? 'Film $id',
    watch: SourceKind.direct,
    download: DownloadKind.file,
    durationSeconds: seconds,
  ),
);
CatalogTitle title(CatalogKind kind) =>
    CatalogTitle(id: 'title', kind: kind, name: 'Film');

class Pages extends CatalogRepository {
  final requests = <int>[];
  final pages = <int, CatalogPage<CatalogSource>>{};
  bool failNext = false;
  Completer<CatalogPage<CatalogSource>>? pending;
  @override
  List<SourceProvider> providers(CatalogTitle title) => [provider];
  @override
  Future<CatalogPage<CatalogTitle>> list(
    CatalogKind kind, {
    String search = '',
    CatalogFilter filter = const CatalogFilter(),
    int start = 0,
  }) async => CatalogPage(items: [], total: 0, start: start);
  @override
  Future<CatalogTitle> details(CatalogTitle title) async => title;
  @override
  Future<CatalogPage<CatalogSource>> sources(
    CatalogTitle title, {
    int start = 0,
  }) async {
    requests.add(start);
    if (failNext && start > 0) {
      failNext = false;
      throw StateError('offline');
    }
    return pending?.future ?? pages[start]!;
  }
}

CatalogPage<CatalogSource> page(
  int start,
  List<CatalogSource> rows, {
  int? next,
  int total = 10,
}) => CatalogPage(
  items: rows,
  total: total,
  start: start,
  nextStart: next ?? start,
);
void main() {
  for (final kind in [CatalogKind.movies, CatalogKind.series]) {
    test(
      '$kind excludes either short duration or forbidden title, independent of other metadata',
      () {
        for (final seconds in [1, 60, 599]) {
          expect(
            includeCatalogSource(kind, source('short', seconds: seconds)),
            isFalse,
          );
        }
        for (final seconds in [null, 0, 600, 601, 7200]) {
          expect(
            includeCatalogSource(kind, source('full', seconds: seconds)),
            isTrue,
          );
        }
        for (final name in [
          'Фильм: Обзор',
          'ОБЗОР фильма',
          'Кино_тИзЕр_2026',
          'Фильм — Трейлер №2',
          'Обзоры новых серий',
        ]) {
          for (final seconds in [null, 600, 7200]) {
            expect(
              includeCatalogSource(
                kind,
                source('clip', name: name, seconds: seconds),
              ),
              isFalse,
              reason: name,
            );
          }
        }
        expect(
          includeCatalogSource(
            kind,
            source('full', name: 'Фильм — серия 1', seconds: 600),
          ),
          isTrue,
        );
      },
    );
    test(
      '$kind filters initial pages and later pages without losing provider cursor or totals',
      () async {
        final repo = Pages();
        repo.pages[0] = page(
          0,
          [
            source('short', seconds: 599),
            source('review', name: 'Обзор фильма', seconds: 900),
          ],
          next: 20,
          total: 6,
        );
        repo.pages[20] = page(
          20,
          [source('exact', seconds: 600), source('unknown')],
          next: 40,
          total: 6,
        );
        repo.pages[40] = page(40, [
          source('teaser', name: 'Тизер'),
          source('long', seconds: 3600),
        ], total: 6);
        final c = CatalogController(repo);
        addTearDown(c.dispose);
        await c.open(title(kind));
        expect(repo.requests, [0, 20]);
        expect(c.sources.map((s) => s.row.id), ['exact', 'unknown']);
        expect(c.providerStates[provider]!.next, 40);
        expect(c.providerStates[provider]!.hasMore, isTrue);
        await c.loadMoreSources(provider);
        expect(c.sources.map((s) => s.row.id), ['exact', 'unknown', 'long']);
        expect(c.providerStates[provider]!.items, c.sources);
        expect(c.sourceTotal, 3);
        expect(c.moreSources, isFalse);
      },
    );
  }
  test('games are not filtered by video rules', () async {
    final rows = [source('game', name: 'Трейлер — обзор игры', seconds: 30)];
    final repo = Pages()..pages[0] = page(0, rows, total: 1);
    final c = CatalogController(repo);
    addTearDown(c.dispose);
    await c.open(title(CatalogKind.games));
    expect(c.sources, rows);
  });
  test(
    'repeated rejected page cannot loop, even with an advancing cursor',
    () async {
      final rows = [source('clip', seconds: 10)];
      final repo = Pages()
        ..pages[0] = page(0, rows, next: 10)
        ..pages[10] = page(10, rows, next: 20);
      final c = CatalogController(repo);
      addTearDown(c.dispose);
      await c.open(title(CatalogKind.movies));
      expect(repo.requests, [0, 10]);
      expect(c.sources, isEmpty);
      expect(c.moreSources, isFalse);
    },
  );
  test(
    'empty batches remain bounded and can continue on the next request',
    () async {
      final repo = Pages();
      for (var i = 0; i < 4; i++) {
        repo.pages[i * 10] = page(i * 10, [
          source('$i', seconds: 60),
        ], next: (i + 1) * 10);
      }
      repo.pages[40] = page(40, [source('film', seconds: 600)], total: 5);
      final c = CatalogController(repo);
      addTearDown(c.dispose);
      await c.open(title(CatalogKind.movies));
      expect(repo.requests, [0, 10, 20]);
      expect(c.moreSources, isTrue);
      await c.loadMoreSources(provider);
      expect(repo.requests, [0, 10, 20, 30, 40]);
      expect(c.sources.single.row.id, 'film');
    },
  );
  test(
    'failed page retries at its raw cursor after an excluded page',
    () async {
      final repo = Pages()
        ..failNext = true
        ..pages[0] = page(0, [source('short', seconds: 5)], next: 20)
        ..pages[20] = page(20, [source('film', seconds: 600)], total: 2);
      final c = CatalogController(repo);
      addTearDown(c.dispose);
      await c.open(title(CatalogKind.series));
      expect(c.sourcesError, isNotNull);
      expect(c.providerStates[provider]!.next, 20);
      await c.loadMoreSources(provider);
      expect(repo.requests, [0, 20, 20]);
      expect(c.sources.single.row.id, 'film');
      expect(c.sourcesError, isNull);
    },
  );
  test(
    'late results after leaving details do not start another request',
    () async {
      final repo = Pages()..pending = Completer<CatalogPage<CatalogSource>>();
      final c = CatalogController(repo);
      addTearDown(c.dispose);
      final opening = c.open(title(CatalogKind.movies));
      c.back();
      repo.pending!.complete(page(0, [source('short', seconds: 5)], next: 20));
      await opening;
      expect(repo.requests, [0]);
      expect(c.sources, isEmpty);
    },
  );
}
