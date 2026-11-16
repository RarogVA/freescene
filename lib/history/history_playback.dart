import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../catalog/catalog_models.dart';
import '../catalog/watched.dart';
import '../domain/provider_display.dart';
import 'watch_history.dart';

class HistorySource {
  const HistorySource(this.title, this.source);
  final CatalogTitle title;
  final CatalogSource source;
}

/// Resolve stable catalogue/source identities to fresh playback data. Legacy
/// records must match their original hash, never just a similarly named film.
Future<HistorySource> resolveHistorySource(
  WatchEntry entry,
  CatalogRepository repository,
) async {
  final kind = switch (entry.data['catalogKind']) {
    'movies' => CatalogKind.movies,
    'series' => CatalogKind.series,
    _ => null,
  };
  final catalogId = entry.data['catalogId'] as String?;
  final providerId = entry.data['sourceProvider'] as String?;
  final sourceId = entry.data['sourceId'] as String?;
  final known =
      kind != null &&
      catalogId != null &&
      providerId != null &&
      sourceId != null;
  final titles = <CatalogTitle>[];
  if (known) {
    titles.add(
      CatalogTitle(
        id: catalogId,
        kind: kind,
        name: entry.data['catalogName'] as String? ?? entry.title,
        englishName: entry.data['catalogEnglishName'] as String?,
        year: entry.data['catalogYear'] as int?,
      ),
    );
  } else {
    String normalized(String s) => s.trim().toLowerCase().replaceAll('ё', 'е');
    // Repositories may cancel an earlier list request when starting another.
    for (final k in [CatalogKind.movies, CatalogKind.series]) {
      final page = await repository.list(k, search: entry.title);
      titles.addAll(
        page.items.where(
          (t) => [t.name, t.englishName].whereType<String>().any(
            (s) => normalized(s) == normalized(entry.title),
          ),
        ),
      );
    }
  }
  String hash(String s) => sha256.convert(utf8.encode(s)).toString();
  for (final title in titles) {
    for (final provider
        in repository
            .providers(title)
            .where(
              (p) => known
                  ? p.name == providerId
                  : p.label == entry.provider ||
                        p.name == entry.provider ||
                        providerDisplayLabel(p) == entry.provider,
            )) {
      var start = 0;
      for (var pageCount = 0; pageCount < 20; pageCount++) {
        final page = await repository.providerSources(
          title,
          provider,
          start: start,
        );
        for (final source in page.items) {
          if (source.row.isTorrent) continue;
          if (known) {
            if (source.row.id == sourceId) return HistorySource(title, source);
            continue;
          }
          final key = watchedIdentity(title, source)['watchedSource'];
          if (key == null) continue;
          if (hash(key) == entry.id || hash('$key:episode:-1:') == entry.id) {
            return HistorySource(title, source);
          }
          if (source.row.watch != SourceKind.embed || entry.subtitle == null) {
            continue;
          }
          final resolved = await repository.resolve(source);
          for (var i = 0; i < resolved.webEpisodes.length; i++) {
            if (hash('$key:episode:$i:${resolved.webEpisodes[i].title}') ==
                entry.id) {
              return HistorySource(title, resolved);
            }
          }
        }
        if (!page.hasMore || page.next <= start) break;
        start = page.next;
      }
    }
  }
  throw const FormatException('History source is unavailable');
}

Uri historyPlaybackUrl(
  WatchEntry? entry,
  Uri fallback,
  List<CatalogWebEpisode> episodes,
) {
  if (entry == null) return fallback;
  final index = entry.data['webEpisodeIndex'] as int?;
  final name = entry.subtitle;
  if (index == null && name == null) return fallback;
  if (index != null &&
      index < episodes.length &&
      episodes[index].title == name) {
    return episodes[index].url;
  }
  final matches = episodes.where((e) => e.title == name).toList();
  if (matches.length == 1) return matches.single.url;
  throw const FormatException('History episode is unavailable');
}
