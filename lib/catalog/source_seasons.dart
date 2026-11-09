import 'catalog_models.dart';

bool _validSeason(int value) => value >= 0 && value <= 999;

List<int> _sorted(Iterable<int> values) =>
    List.unmodifiable(values.where(_validSeason).toSet().toList()..sort());

/// Provider season fields and enumerated episodes take priority over filenames.
/// Provider adapters and raw titles share the same bounded coverage parser.
List<int> sourceSeasons(CatalogSource source) {
  final explicit = <int>{
    if (source.row.season case final season? when _validSeason(season)) season,
    for (final episode in source.episodes)
      ...?SeriesCoverage.parse(episode)?.seasons,
  };
  if (explicit.isNotEmpty) {
    return _sorted(explicit);
  }
  return _sorted(
    (source.seriesCoverage ?? SeriesCoverage.parse(source.row.title))
            ?.seasons ??
        <int>{},
  );
}

List<int> availableSourceSeasons(Iterable<CatalogSource> sources) =>
    _sorted(sources.expand(sourceSeasons));

bool sourceMatchesSeason(CatalogSource source, int season) {
  final known = sourceSeasons(source);
  return season < 0 ? known.isEmpty : known.contains(season);
}

int? inferredSourceEpisode(CatalogSource source) {
  final explicit = source.row.episode;
  if (explicit != null && explicit >= 0 && explicit <= 9999) {
    return explicit;
  }
  for (final episode in source.episodes) {
    final value = SeriesCoverage.parse(episode)?.firstEpisode;
    if (value != null) {
      return value;
    }
  }
  return source.seriesCoverage?.firstEpisode ??
      SeriesCoverage.parse(source.row.title)?.firstEpisode ??
      SeriesCoverage.episodeNumber(source.row.title);
}

/// Episode menus use explicit provider lists first, then bounded title ranges.
List<int> sourceEpisodes(CatalogSource source, {int? season}) {
  if (season != null && !sourceMatchesSeason(source, season)) return const [];
  final listed = <int>{
    for (final item in source.episodes)
      ...?SeriesCoverage.parse(item)?.episodesForSeason(season),
  };
  final explicit = source.row.episode;
  final values = listed.isNotEmpty
      ? listed
      : explicit != null
      ? {explicit}
      : (source.seriesCoverage ?? SeriesCoverage.parse(source.row.title))
                ?.episodesForSeason(season) ??
            {?SeriesCoverage.episodeNumber(source.row.title)};
  return values.where((value) => value >= 0 && value <= 9999).toSet().toList()
    ..sort();
}

List<int> availableSourceEpisodes(
  Iterable<CatalogSource> sources, {
  int? season,
}) =>
    sources
        .expand((source) => sourceEpisodes(source, season: season))
        .toSet()
        .toList()
      ..sort();
