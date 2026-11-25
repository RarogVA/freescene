import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:freescene/catalog/catalog_controller.dart';
import 'package:freescene/providers/demo.dart';
import 'package:freescene_provider_api/freescene_provider_api.dart';

class _Catalog extends DemoCatalog {
  final requests = <String, Completer<String?>>{};
  @override
  Future<CatalogTitle> details(CatalogTitle title) async => title;
  @override
  Future<String?> englishSynopsis(CatalogTitle title) =>
      (requests[title.id] = Completer<String?>()).future;
  @override
  List<SourceProvider> providers(CatalogTitle title) => [];
}

void main() {
  test('language switch localizes the open card and a late synopsis cannot replace the next film', () async {
    final oldLoader = CatalogDictionaries.loader;
    addTearDown(() => CatalogDictionaries.loader = oldLoader);
    CatalogDictionaries.loader = () async => CatalogDictionaries({
      'genres': [
        {'id': 1, 'ru': 'Драма', 'en': 'Drama'},
      ],
      'gameGenres': [],
      'countries': [
        {'id': 1, 'ru': 'США', 'en': 'USA'},
        {'id': 35, 'ru': 'Новая Зеландия', 'en': 'New Zealand'},
        {'id': 6, 'ru': 'Канада', 'en': 'Canada'},
      ],
    });
    final repo = _Catalog();
    final controller = CatalogController(repo);
    addTearDown(controller.dispose);
    const one = CatalogTitle(
      id: 'one',
      kind: CatalogKind.movies,
      name: 'Первый',
      genres: 'драма, новый жанр',
      country: 'США, Новая Зеландия, Канада',
      description: 'Первый синопсис',
    );
    const two = CatalogTitle(
      id: 'two',
      kind: CatalogKind.movies,
      name: 'Второй',
      description: 'Второй синопсис',
      englishDescription: 'The second film',
    );
    await controller.open(one);
    expect(repo.requests, isEmpty);
    controller.setEnglish(true);
    await Future<void>.delayed(Duration.zero);
    expect(controller.selected!.genreLabel(true), 'Drama, новый жанр');
    expect(controller.selected!.countryLabel(true), 'USA, New Zealand, Canada');
    expect(controller.selected!.synopsis(true), isEmpty);
    await controller.open(two);
    repo.requests['one']!.complete('First film');
    await Future<void>.delayed(Duration.zero);
    expect(controller.selected!.id, two.id);
    expect(controller.selected!.synopsis(true), 'The second film');
    controller.setEnglish(false);
    expect(controller.selected!.synopsis(false), 'Второй синопсис');
    expect(repo.requests.keys, ['one']);
  });
}
