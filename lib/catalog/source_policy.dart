import 'catalog_models.dart';

final _excludedVideoTitle = RegExp('обзор|тизер|трейлер', caseSensitive: false);

/// These rules apply to film/episode sources, not games or the trailer action.
/// A missing/nonpositive duration is unknown, rather than a short video.
bool includeCatalogSource(CatalogKind kind, CatalogSource source) {
  if (kind == CatalogKind.games) return true;
  final duration = source.row.durationSeconds;
  return !_excludedVideoTitle.hasMatch(source.row.title) &&
      (duration == null || duration <= 0 || duration >= 10 * 60);
}
