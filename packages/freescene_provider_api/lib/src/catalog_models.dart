import 'dart:typed_data';

import 'source.dart';
import 'series_coverage.dart';
import 'playback.dart';

enum CatalogKind { movies, series, games }

enum CatalogSort { popularity, newest, rating, title }

class CatalogFilter {
  const CatalogFilter({
    this.year,
    this.minRating = 0,
    this.sort = CatalogSort.popularity,
    this.yearTo,
    this.maxRating = 10,
    this.genre,
    this.country,
    this.countryIds = const [],
    this.highQualityOnly = false,
    this.ended,
  });
  final int? year;
  final int? yearTo;
  final double minRating;
  final double maxRating;
  final CatalogSort sort;
  final String? genre, country;
  final List<String> countryIds;
  final bool highQualityOnly;
  final bool? ended;
  bool get active =>
      year != null ||
      yearTo != null ||
      minRating > 0 ||
      maxRating < 10 ||
      genre != null ||
      country != null ||
      countryIds.isNotEmpty ||
      highQualityOnly ||
      ended != null ||
      sort != CatalogSort.popularity;
}

String? catalogString(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return value.trim();
}

int? catalogInt(Object? value) {
  final n = value is int
      ? value
      : value is String
      ? int.tryParse(value)
      : null;
  return n != null && n >= 0 ? n : null;
}

double? catalogRating(Object? value) {
  final n = value is num ? value.toDouble() : double.tryParse('$value');
  return n != null && n.isFinite && n > 0 && n <= 10 ? n : null;
}

/// A public trailer reference, never an arbitrary player URL.
/// Provider pages and temporary media URLs are resolved only on user action.
class CatalogTrailer {
  const CatalogTrailer(this.kind, this.videoId);
  final String kind;
  static Map<String, bool Function(String)> validators = const {};

  /// Opaque provider ID; serialized unchanged for saved titles.
  final String videoId;

  static CatalogTrailer? fromJson(Object? value) {
    if (value is! Map || value['kind'] is! String || value['id'] is! String) {
      return null;
    }
    final kind = value['kind'] as String, id = value['id'] as String;
    if (!RegExp(r'^[a-z][a-z0-9_-]{0,63}$').hasMatch(kind) ||
        id.isEmpty ||
        id.length > 512) {
      return null;
    }
    if (RegExp(r'[\x00-\x1f]').hasMatch(id) ||
        validators[kind]?.call(id) == false) {
      return null;
    }
    return CatalogTrailer(kind, id);
  }

  Map<String, String> toJson() => {'kind': kind, 'id': videoId};
}

class CatalogTitle {
  const CatalogTitle({
    required this.id,
    required this.kind,
    required this.name,
    this.englishName,
    this.description = '',
    this.englishDescription,
    this.year,
    this.rating,
    this.genres,
    this.country,
    this.poster,
    this.posterFallback,
    this.trailer,
  });
  final String id, name, description;
  final String? englishName, englishDescription, genres, country;
  final CatalogKind kind;
  final int? year;
  final double? rating;
  final Uri? poster, posterFallback;
  final CatalogTrailer? trailer;
  String title(bool english) => (english ? englishName : null) ?? name;
  String synopsis(bool english) =>
      (english ? englishDescription : null) ?? description;

  CatalogTitle withTrailer(CatalogTrailer value) => CatalogTitle(
    id: id,
    kind: kind,
    name: name,
    englishName: englishName,
    description: description,
    englishDescription: englishDescription,
    year: year,
    rating: rating,
    genres: genres,
    country: country,
    poster: poster,
    posterFallback: posterFallback,
    trailer: value,
  );
}

class CatalogPage<T> {
  const CatalogPage({
    required this.items,
    required this.total,
    required this.start,
    this.nextStart,
  });
  final List<T> items;
  final int total, start;
  final int? nextStart;
  int get next => nextStart ?? start + items.length;
  bool get hasMore =>
      nextStart != null ? nextStart! > start : items.isNotEmpty && next < total;
}

class CatalogWebEpisode {
  const CatalogWebEpisode({required this.url, required this.title});
  final Uri url;
  final String title;
  Map<String, String> toJson() => {'url': url.toString(), 'title': title};
}

class CatalogSource {
  const CatalogSource({
    required this.row,
    this.uri,
    this.audio,
    this.episodes = const [],
    this.seriesCoverage,
    this.topic,
    this.torrentDownload,
    this.torrentBytes,
    this.channel,
    this.thumbnail,
    this.restriction,
    this.webPlayer,
    this.webEpisodes = const [],
  });
  final SourceRow row;
  final Uri? uri;
  final Uri? topic, torrentDownload;
  final Uint8List? torrentBytes;
  final String? audio;
  final String? channel, restriction;

  /// Provider-supplied preview of this specific source video.
  final Uri? thumbnail;
  final int? webPlayer;
  final List<CatalogWebEpisode> webEpisodes;
  bool get canWatch => restriction == null;
  final List<String> episodes;
  final SeriesCoverage? seriesCoverage;
  String get episodeLabel {
    if (seriesCoverage != null) return seriesCoverage!.label;
    if (episodes.isEmpty) {
      if (row.season == null) return '—';
      return 'S${row.season!.toString().padLeft(2, '0')}'
          '${row.episode == null ? '' : 'E${row.episode!.toString().padLeft(2, '0')}'}';
    }
    if (episodes.length == 1) return episodes.single;
    return '${episodes.first}–${episodes.last} (${episodes.length})';
  }
}

abstract class CatalogRepository {
  String get label => 'Catalogue';
  List<SourceProvider> providers(CatalogTitle title) =>
      SourceProvider.values.take(1).toList();
  void configureProviders(Set<SourceProvider> enabled) {}
  Future<CatalogPage<CatalogSource>> providerSources(
    CatalogTitle title,
    SourceProvider provider, {
    int start = 0,
  }) => sources(title, start: start);
  Future<CatalogSource> resolve(CatalogSource source) async => source;
  void cancelSources() {}
  void cancelPlayback() {}
  Future<CatalogPage<CatalogTitle>> list(
    CatalogKind kind, {
    String search = '',
    CatalogFilter filter = const CatalogFilter(),
    int start = 0,
  });
  Future<CatalogTitle> details(CatalogTitle title);
  Future<CatalogPage<CatalogSource>> sources(
    CatalogTitle title, {
    int start = 0,
  });
  Future<PlaybackRequest> playback(
    CatalogSource source, {
    bool lowRam = false,
  }) async => PlaybackRequest(
    url: source.uri!,
    provider: source.row.provider.name,
    kind: source.row.watch,
    webPlayer: source.webPlayer,
    episodes: source.webEpisodes,
  );
  void close() {}
}

abstract interface class SourceLinkCatalog {
  Future<CatalogPage<CatalogSource>> fromLink(String link, {int start = 0});
  void cancel();
  void close();
}
