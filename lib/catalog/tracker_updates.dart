import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/provider_display.dart';
import 'catalog_models.dart';
import 'favorites.dart';
import 'source_policy.dart';
import 'source_seasons.dart';

Set<String> _coverage(CatalogTitle title, CatalogSource source) {
  if (!source.row.isTorrent) return {};
  if (title.kind == CatalogKind.movies) return {'film'};
  String number(int value) => value.toString().padLeft(2, '0');
  return {
    for (final season in sourceSeasons(source)) ...{
      'S${number(season)}',
      for (final episode in sourceEpisodes(source, season: season))
        'S${number(season)}E${number(episode)}',
    },
  };
}

class _TrackerHistory {
  _TrackerHistory(this.known, this.pending, this.byTracker);
  final Map<String, Set<String>> byTracker;
  final Set<String> known, pending;
  Map<String, Object> toJson() => {
    'known': known.toList(),
    'pending': pending.toList(),
    'trackers': {for (final e in byTracker.entries) e.key: e.value.toList()},
  };
}

/// One history per saved title, shared between the two collections. The scan
/// owns a separate repository so opening a card cannot cancel its page requests.
class TrackerUpdates extends ChangeNotifier {
  TrackerUpdates(this.repository, this.favorites, this.queue, {this.file});
  final CatalogRepository repository;
  final FavoritesController favorites, queue;
  final File? file;
  final _history = <String, _TrackerHistory>{};
  Map<String, CatalogTitle> _titles = {};
  Set<SourceProvider> _trackers = {};
  Timer? _timer;
  Future<void>? _scan;
  bool _again = false, _disposed = false;
  int _generation = 0;
  late final Future<void> _ready = _restore();
  Future<void> _writes = Future.value();

  void configure(Set<SourceProvider> enabled) {
    final trackers = enabled
        .where(
          (p) => p.descriptor?.torrentTracker == true && !providerIsHidden(p),
        )
        .toSet();
    if (setEquals(_trackers, trackers)) return;
    _trackers = trackers;
    ++_generation;
    repository.configureProviders(trackers);
    _again = true;
    unawaited(refresh());
  }

  void sync() {
    if (!favorites.ready ||
        !queue.ready ||
        favorites.saving ||
        queue.saving ||
        favorites.loading ||
        queue.loading) {
      return;
    }
    final titles = {
      for (final t in [...favorites.titles, ...queue.titles])
        FavoritesController.key(t): t,
    };
    if (setEquals(_titles.keys.toSet(), titles.keys.toSet()) &&
        _timer != null) {
      return;
    }
    _titles = titles;
    _again = true;
    ++_generation;
    _timer?.cancel();
    _timer = titles.isEmpty
        ? null
        : Timer.periodic(const Duration(minutes: 15), (_) => refresh());
    unawaited(refresh());
  }

  Future<void> _restore() async {
    final path = file;
    if (path == null) return;
    try {
      final data = jsonDecode(await path.readAsString()) as Map;
      for (final entry in data.entries) {
        final row = entry.value;
        if (entry.key is String &&
            row is Map &&
            row['known'] is List &&
            row['pending'] is List) {
          _history[entry.key as String] = _TrackerHistory(
            (row['known'] as List).whereType<String>().toSet(),
            (row['pending'] as List).whereType<String>().toSet(),
            {
              if (row['trackers'] case final Map trackers)
                for (final e in trackers.entries)
                  if (e.key is String && e.value is List)
                    e.key as String: (e.value as List)
                        .whereType<String>()
                        .toSet(),
            },
          );
        }
      }
      if (!_disposed) notifyListeners();
    } on FileSystemException {
      /* First launch or an unavailable profile. */
    } on FormatException {
      /* Reestablish the baseline from the trackers. */
    } on TypeError {
      /* An older or invalid profile. */
    }
  }

  void _save() {
    final path = file;
    if (path == null) return;
    final contents = jsonEncode(_history);
    _writes = _writes
        .then((_) async {
          await path.parent.create(recursive: true);
          final tmp = File('${path.path}.tmp');
          await tmp.writeAsString(contents, flush: true);
          await tmp.rename(path.path);
        })
        .catchError((Object error) {
          debugPrint('Tracker history write failed: $error');
        });
  }

  Future<void> refresh() {
    if (_disposed) return Future.value();
    return _scan ??= _refresh().whenComplete(() {
      _scan = null;
    });
  }

  Future<Set<String>> _scanProvider(
    CatalogTitle title,
    SourceProvider provider,
    int generation,
  ) async {
    final current = <String>{};
    final ids = <String>{};
    var start = 0;
    while (!_disposed && generation == _generation) {
      final page = await repository.providerSources(
        title,
        provider,
        start: start,
      );
      var hasFreshRow = false;
      for (final source in page.items) {
        if (ids.add(source.row.id)) hasFreshRow = true;
        if (source.row.provider == provider &&
            includeCatalogSource(title.kind, source, title: title)) {
          current.addAll(_coverage(title, source));
        }
      }
      if (!page.hasMore) break;
      if (page.next <= start || (page.items.isNotEmpty && !hasFreshRow)) {
        throw const FormatException('Tracker repeated a result page');
      }
      start = page.next;
    }
    return current;
  }

  Future<void> _refresh() async {
    await _ready;
    do {
      _again = false;
      if (_disposed ||
          !favorites.ready ||
          !queue.ready ||
          favorites.saving ||
          queue.saving ||
          favorites.loading ||
          queue.loading) {
        return;
      }
      final removed = _history.keys
          .where((key) => !_titles.containsKey(key))
          .toList();
      if (removed.isNotEmpty) {
        for (final key in removed) {
          _history.remove(key);
        }
        _save();
      }
      final generation = _generation;
      if (_trackers.isEmpty) continue;
      for (final entry in _titles.entries) {
        if (_disposed || generation != _generation) break;
        final title = entry.value;
        final providers = repository
            .providers(title)
            .where(_trackers.contains)
            .toList();
        if (providers.isEmpty) continue;
        final history = _history[entry.key] ?? _TrackerHistory({}, {}, {});
        final additions = <String>{};
        final snapshots = <String, Set<String>>{};
        for (final provider in providers) {
          if (_disposed || generation != _generation) break;
          try {
            final snapshot = await _scanProvider(title, provider, generation);
            if (history.byTracker[provider.name]?.containsAll(snapshot) ==
                true) {
              continue;
            }
            snapshots[provider.name] = snapshot;
            if (history.byTracker.containsKey(provider.name)) {
              additions.addAll(snapshot.difference(history.known));
            }
          } catch (_) {
            // A failed tracker keeps its last successful snapshot.
          }
        }
        if (_disposed || generation != _generation) break;
        if (snapshots.isEmpty) continue;
        _history[entry.key] = history;
        history.pending.addAll(additions.difference(history.known));
        for (final snapshot in snapshots.entries) {
          (history.byTracker[snapshot.key] ??= {}).addAll(snapshot.value);
          history.known.addAll(snapshot.value);
        }
        _save();
        notifyListeners();
      }
      await _writes;
    } while (_again && !_disposed);
  }

  String? label(CatalogTitle title, bool english) {
    final history = _history[FavoritesController.key(title)];
    if (history == null || history.pending.isEmpty) return null;
    final pending = history.pending
        .where(
          (event) => _trackers.any(
            (p) => history.byTracker[p.name]?.contains(event) == true,
          ),
        )
        .toSet();
    if (pending.isEmpty) return null;
    if (pending.contains('film')) {
      return english
          ? 'Film appeared on trackers'
          : 'Фильм появился на трекерах';
    }
    final seasons = pending.where((s) => !s.contains('E')).toList()..sort();
    if (seasons.isNotEmpty) {
      return '${english ? "New season" : "Новый сезон"} · ${seasons.last}';
    }
    return '${english ? "New episode" : "Новая серия"} · ${pending.last}';
  }

  Set<String> shownEvents(CatalogTitle title, CatalogSource source) {
    final history = _history[FavoritesController.key(title)];
    if (history == null || !_trackers.contains(source.row.provider)) return {};
    final coverage = _coverage(title, source);
    return {
      ...coverage.difference(history.known),
      ...coverage.intersection(history.pending),
    };
  }

  void acknowledge(CatalogTitle title, Set<String> shown) {
    final history = _history[FavoritesController.key(title)];
    if (_disposed || history == null || shown.isEmpty) return;
    if (history.known.containsAll(shown) &&
        !shown.any(history.pending.contains)) {
      return;
    }
    history.known.addAll(shown);
    history.pending.removeAll(shown);
    _save();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    repository.close();
    super.dispose();
  }
}
