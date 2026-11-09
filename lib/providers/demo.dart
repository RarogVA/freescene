import 'package:freescene_provider_api/freescene_provider_api.dart';

const demoProvider = SourceProvider('demo');
final demoProviders = ProviderSetup(
  descriptors: const [
    ProviderDescriptor(demoProvider, 'Demo', enabledByDefault: true),
  ],
  createCatalog: ({required bool android}) => DemoCatalog(),
  createTrailerResolver: (_) => _NoTrailers(),
  loadDictionaries: () async =>
      CatalogDictionaries({'genres': [], 'gameGenres': [], 'countries': []}),
);

class DemoCatalog extends CatalogRepository {
  bool active = true;
  @override
  String get label => 'Demo';
  @override
  void configureProviders(Set<SourceProvider> enabled) =>
      active = enabled.contains(demoProvider);
  @override
  List<SourceProvider> providers(CatalogTitle title) => const [];
  @override
  Future<CatalogPage<CatalogTitle>> list(
    CatalogKind kind, {
    String search = '',
    CatalogFilter filter = const CatalogFilter(),
    int start = 0,
  }) async {
    final entries =
        [
              for (var i = 1; i <= 12; i++)
                CatalogTitle(
                  id: 'demo:${kind.name}:$i',
                  kind: kind,
                  name: 'Демонстрация $i',
                  englishName: 'Demo $i',
                  description: 'Пример карточки FreeScene. Локальное видео и импорт торрентов доступны в меню приложения.',
                  englishDescription: 'A FreeScene sample. Open local video or import a torrent using the application menu.',
                  year: 2020 + i % 6,
                ),
            ]
            .where(
              (t) =>
                  active &&
                  (search.isEmpty ||
                      '${t.name} ${t.englishName}'.toLowerCase().contains(
                        search.toLowerCase(),
                      )) &&
                  (filter.year == null || t.year! >= filter.year!) &&
                  (filter.yearTo == null || t.year! <= filter.yearTo!),
            )
            .toList();
    return CatalogPage(
      items: entries.skip(start).take(24).toList(),
      total: entries.length,
      start: start,
    );
  }

  @override
  Future<CatalogTitle> details(CatalogTitle title) async => title;
  @override
  Future<CatalogPage<CatalogSource>> sources(
    CatalogTitle title, {
    int start = 0,
  }) async => CatalogPage(items: [], total: 0, start: start);
}

class _NoTrailers implements TrailerResolver {
  @override
  Future<TrailerMedia> resolve(CatalogTrailer trailer) =>
      Future.error(const FormatException('Trailer unavailable'));
  @override
  void close() {}
}
