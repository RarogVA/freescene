import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../catalog/catalog_models.dart';
import '../catalog/source_metadata.dart';
import '../catalog/source_seasons.dart';
import '../domain/provider_display.dart';

Map<String, Object?> sourceWatchHistory(
  CatalogTitle? title,
  CatalogSource source,
  bool english,
) => {
  'title': title?.title(english) ?? source.row.title,
  'provider': providerDisplayLabel(source.row.provider),
  if (title != null) ...{
    'catalogId': title.id,
    'catalogKind': title.kind.name,
    'catalogName': title.name,
    if (title.englishName != null) 'catalogEnglishName': title.englishName,
    if (title.year != null) 'catalogYear': title.year,
    'sourceProvider': source.row.provider.name,
    'sourceId': source.row.id,
  },
  if (!source.row.isTorrent) ...{
    'quality': compactQuality(source.row.quality),
    'season': source.row.season,
    'episode': inferredSourceEpisode(source),
    'sizeBytes': source.row.sizeBytes,
  },
  'sourceType': source.row.isTorrent ? 'torrent' : 'provider',
};

class WatchEntry {
  WatchEntry._(this.data);
  final Map<String, Object?> data;
  String get id => data['id']! as String;
  String get title => data['title']! as String;
  String? get subtitle => data['subtitle'] as String?;
  String? get provider => data['provider'] as String?;
  String? get quality => compactQuality(data['quality'] as String? ?? subtitle);
  int? get sizeBytes => data['sizeBytes'] as int?;
  int get watchedAt => data['watchedAt']! as int;
  Map<String, String> get watchedIdentity {
    final parts = [
      'catalogKind',
      'catalogId',
      'sourceProvider',
      'sourceId',
    ].map((k) => data[k]).toList();
    if (parts.any((p) => p is! String)) return {};
    return {
      'watchedTitle': jsonEncode(parts.take(2).toList()),
      'watchedSource': jsonEncode(parts),
    };
  }

  int? get season =>
      data['season'] as int? ??
      SeriesCoverage.parse(subtitle ?? '')?.seasons.singleOrNull;
  int? get episode =>
      data['episode'] as int? ??
      SeriesCoverage.parse(subtitle ?? '')?.firstEpisode;
  String? get episodeLabel => episode == null
      ? null
      : '${season == null ? '' : 'S${season.toString().padLeft(2, '0')}'}E${episode.toString().padLeft(2, '0')}';
  static WatchEntry? parse(Object? value) {
    if (value is! Map) return null;
    final data = <String, Object?>{};
    for (final field in [
      'id',
      'title',
      'subtitle',
      'provider',
      'quality',
      'sourceType',
      'catalogId',
      'catalogKind',
      'catalogName',
      'catalogEnglishName',
      'sourceProvider',
      'sourceId',
      'downloadDirectory',
    ]) {
      final v = value[field];
      if (v is String && v.trim().isNotEmpty && v.length <= 1024) {
        data[field] = v;
      }
    }
    for (final field in [
      'watchedAt',
      'season',
      'episode',
      'sizeBytes',
      'catalogYear',
      'webEpisodeIndex',
      'webPlayer',
    ]) {
      final v = value[field];
      if (v is int && v >= 0 && v <= 8640000000000000) data[field] = v;
    }
    if (data['id'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(data['id'] as String) ||
        data['title'] == null ||
        data['watchedAt'] == null ||
        !['torrent', 'provider', 'download'].contains(data['sourceType'])) {
      return null;
    }
    if ((data['season'] as int? ?? 0) > 999) data.remove('season');
    if ((data['episode'] as int? ?? 0) > 9999) data.remove('episode');
    return WatchEntry._(data);
  }
}

class WatchHistoryController extends ChangeNotifier {
  WatchHistoryController(this.channel);
  final MethodChannel channel;
  List<WatchEntry> entries = [];
  bool loading = false, removing = false, _disposed = false;
  String? error;
  Future<void> refresh() async {
    if (loading || removing || _disposed) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await channel.invokeMapMethod<String, dynamic>(
        'watchHistorySnapshot',
      );
      final raw = result?['entries'];
      if (raw is! List) throw const FormatException('Invalid history snapshot');
      final next = raw.map(WatchEntry.parse).whereType<WatchEntry>().toList()
        ..sort((a, b) {
          final time = b.watchedAt.compareTo(a.watchedAt);
          return time == 0 ? a.id.compareTo(b.id) : time;
        });
      if (!_disposed) {
        final ids = <String>{};
        entries = next.where((e) => ids.add(e.id)).take(500).toList();
      }
    } catch (_) {
      if (!_disposed) error = 'read';
    } finally {
      if (!_disposed) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<int> remove(Set<String> ids) async {
    if (loading || removing || ids.isEmpty || ids.length > 500) {
      throw StateError('History busy');
    }
    removing = true;
    notifyListeners();
    try {
      final result = await channel.invokeMapMethod<String, dynamic>(
        'watchHistoryRemove',
        {'ids': ids.toList()},
      );
      final removed = result?['removed'];
      if (removed is! int) {
        throw const FormatException('Invalid history removal');
      }
      if (!_disposed) {
        entries = entries.where((e) => !ids.contains(e.id)).toList();
      }
      return removed;
    } finally {
      if (!_disposed) {
        removing = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Group by local calendar date, keeping the stored timestamp only for ordering.
String watchHistoryDay(int watchedAt) {
  final date = DateTime.fromMillisecondsSinceEpoch(watchedAt).toLocal();
  return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year.toString().padLeft(4, '0')}';
}
