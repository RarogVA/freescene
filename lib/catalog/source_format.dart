import 'catalog_models.dart';
import 'source_seasons.dart' as seasons;

String catalogBytes(int? size) {
  if (size == null) return '—';
  if (size >= 1024 * 1024 * 1024) {
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String sourceDuration(int? value) {
  if (value == null || value <= 0) return '—';
  final s = '${value % 60}'.padLeft(2, '0');
  final m = '${value ~/ 60 % 60}'.padLeft(value >= 3600 ? 2 : 1, '0');
  return value >= 3600 ? '${value ~/ 3600}:$m:$s' : '$m:$s';
}

String sourceEpisodeDisplay(CatalogSource source) {
  final provided = source.episodeLabel.trim();
  if (provided.isNotEmpty && provided != '—') return provided;
  final inferredSeasons = seasons.sourceSeasons(source);
  if (inferredSeasons.isEmpty) return '—';
  final coverage = SeriesCoverage.parse(source.row.title);
  // Keep episode ranges intact; season-only collections use compact spans below.
  if (coverage != null &&
      coverage.label.contains('E') &&
      coverage.seasons.length == inferredSeasons.length &&
      coverage.seasons.containsAll(inferredSeasons)) {
    return coverage.label;
  }
  String mark(int season) => 'S${season.toString().padLeft(2, '0')}';
  final spans = <String>[];
  var first = inferredSeasons.first, last = first;
  void append() =>
      spans.add(first == last ? mark(first) : '${mark(first)}–${mark(last)}');
  for (final season in inferredSeasons.skip(1)) {
    if (season == last + 1) {
      last = season;
    } else {
      append();
      first = last = season;
    }
  }
  append();
  return spans.join(', ');
}
