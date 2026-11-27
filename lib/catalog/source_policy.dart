import 'catalog_models.dart';

final _excludedVideoTitle = RegExp('обзор|тизер|трейлер', caseSensitive: false);

/// These rules apply to film/episode sources, not games or the trailer action.
/// A missing/nonpositive duration is unknown, rather than a short video.
bool includeCatalogSource(
  CatalogKind kind,
  CatalogSource source, {
  CatalogTitle? title,
}) {
  if (kind == CatalogKind.games) return true;
  final duration = source.row.durationSeconds;
  return (title == null || !_predatesPremiere(title, source.row)) &&
      !_excludedVideoTitle.hasMatch(source.row.title) &&
      (duration == null || duration <= 0 || duration >= 10 * 60);
}

final _releaseMark = RegExp(
  r'(?<![\p{L}\p{N}])(?:(\d{2})[./-](\d{2})[./-])?((?:18|19|20)\d{2})(?:[-.](\d{2})[-.](\d{2}))?(?![\p{L}\p{N}])',
  unicode: true,
);

bool _predatesPremiere(CatalogTitle title, SourceRow row) {
  final premiere = title.premiere;
  final year = premiere?.year ?? title.year;
  if (year == null) return false;
  bool earlier(DateTime day) =>
      day.year < year ||
      (premiere != null &&
          day.isBefore(DateTime.utc(year, premiere.month, premiere.day)));
  if (row.releaseYear != null &&
      row.releaseYear! >= 1888 &&
      row.releaseYear! < year) {
    return true;
  }
  if ([row.releaseDate, row.publishedDate].whereType<DateTime>().any(earlier)) {
    return true;
  }

  // Remove the work's own name first, including numeric titles such as “1917”.
  var text = row.title.toLowerCase().replaceAll('ё', 'е');
  if (!_releaseMark.hasMatch(text)) return false;
  text = text.replaceAll(RegExp(r'\d{3,4}\s*[xх×]\s*\d{3,4}'), ' ');
  for (final name in [title.name, title.englishName].whereType<String>()) {
    final words = name
        .toLowerCase()
        .replaceAll('ё', 'е')
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        .where((s) => s.isNotEmpty)
        .map(RegExp.escape)
        .toList();
    if (words.isNotEmpty) {
      text = text.replaceFirst(
        RegExp(
          '(?<![\\p{L}\\p{N}])${words.join(r"[^\p{L}\p{N}]+")}(?![\\p{L}\\p{N}])',
          unicode: true,
        ),
        ' ',
      );
    }
  }
  for (final mark in _releaseMark.allMatches(text)) {
    final candidate = int.parse(mark[3]!);
    if (candidate < 1888) continue;
    final month = mark[2] ?? mark[4], day = mark[1] ?? mark[5];
    if (month != null && day != null) {
      final date = catalogDay('$candidate-$month-$day');
      if (date != null && earlier(date)) return true;
    } else if (candidate < year) {
      return true;
    }
  }
  return false;
}
