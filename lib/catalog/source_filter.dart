import 'catalog_models.dart';
import 'source_seasons.dart' as seasons;

int? sourceHeight(CatalogSource source) {
  if (source.row.provider.descriptor?.qualityInPlayer == true) return null;
  final quality = source.row.quality ?? '';
  final dimensions = RegExp(
    r'\d{3,5}[x×](\d{3,5})',
    caseSensitive: false,
  ).firstMatch(quality);
  if (dimensions != null) return int.tryParse(dimensions[1]!);
  final height = RegExp(
    r'(\d{3,4})[piр]',
    caseSensitive: false,
  ).firstMatch(quality);
  if (height != null) return int.tryParse(height[1]!);
  return switch (quality.toUpperCase()) {
    '4K' => 2160,
    '8K' => 4320,
    '2K' => 1440,
    _ => null,
  };
}

Set<int> sourceSeasons(CatalogSource source) {
  final values = seasons.sourceSeasons(source).toSet();
  return values.isEmpty ? {-1} : values;
}

int? sourceSeason(CatalogSource source) {
  final values = sourceSeasons(source).where((s) => s >= 0).toList()..sort();
  return values.firstOrNull;
}

int sourceEpisode(CatalogSource source) =>
    seasons.inferredSourceEpisode(source) ?? 0;

class SourceFilter {
  const SourceFilter({
    this.provider,
    this.minHeight = 0,
    this.audio = '',
    this.withSeeds = false,
    this.maxGiB = 0,
  });
  final SourceProvider? provider;
  final int minHeight, maxGiB;
  final String audio;
  final bool withSeeds;
  bool matches(CatalogSource source) =>
      (provider == null || provider == source.row.provider) &&
      (source.row.provider.descriptor?.qualityInPlayer == true ||
          minHeight == 0 ||
          (sourceHeight(source) ?? 0) >= minHeight) &&
      (audio.trim().isEmpty ||
          (source.audio ?? '').toLowerCase().contains(
            audio.trim().toLowerCase(),
          )) &&
      (!withSeeds || (source.row.catalogueCounts.seeds ?? 0) > 0) &&
      (maxGiB == 0 ||
          (source.row.sizeBytes != null &&
              source.row.sizeBytes! <= maxGiB * 1024 * 1024 * 1024));
}
