import 'dart:async';

import 'package:flutter/foundation.dart';

import '../catalog/catalog_models.dart';

/// A successful check means video bytes arrived, not that the whole film is available.
enum SourceCheckState { checking, data, timeout, unavailable }

class SourceCheck {
  SourceCheck(this.state, this.at);
  final SourceCheckState state;
  final DateTime at;
}

String sourceCheckKey(CatalogSource source) =>
    '${source.row.provider.name}:${source.row.id}';
final sourceCheckResults = ValueNotifier<Map<String, SourceCheck>>({});
SourceCheck? recentSourceCheck(String key, {DateTime? now}) {
  final value = sourceCheckResults.value[key];
  return value != null &&
          (now ?? DateTime.now()).difference(value.at) <
              const Duration(minutes: 5)
      ? value
      : null;
}

class SourceChecks {
  SourceChecks({required this.probe, required this.cancelProbe});
  final Future<SourceCheckState> Function(CatalogSource) probe;
  final Future<void> Function() cancelProbe;
  final _queue = <CatalogSource>[];
  final _attempted = <String>{};
  int _epoch = 0;
  bool _busy = false, _disposed = false;
  String? _title;
  void select(String? title, List<CatalogSource> sources) {
    if (_disposed) return;
    if (title != _title) {
      stop();
      _title = title;
      _attempted.clear();
      // Results describe the selected title/episode/quality, not every file in a torrent.
      sourceCheckResults.value = {};
    }
    if (title == null) return;
    for (final source in sources.where((s) => s.row.isTorrent && s.canWatch)) {
      if (_attempted.length >= 3) break;
      final key = sourceCheckKey(source);
      if (!_attempted.add(key) || recentSourceCheck(key) != null) continue;
      _queue.add(source);
    }
    unawaited(_drain());
  }

  void retry(CatalogSource source) {
    if (_disposed) return;
    final key = sourceCheckKey(source);
    if (recentSourceCheck(key)?.state == SourceCheckState.checking) return;
    _queue.removeWhere((s) => sourceCheckKey(s) == key);
    _queue.insert(0, source);
    unawaited(_drain());
  }

  void _set(String key, SourceCheckState state) {
    final values = Map<String, SourceCheck>.of(sourceCheckResults.value);
    values.remove(key);
    values[key] = SourceCheck(state, DateTime.now());
    while (values.length > 100) {
      values.remove(values.keys.first);
    }
    sourceCheckResults.value = values;
  }

  Future<void> _drain() async {
    if (_busy || _disposed) return;
    _busy = true;
    try {
      while (_queue.isNotEmpty && !_disposed) {
        final source = _queue.removeAt(0), epoch = _epoch;
        final key = sourceCheckKey(source);
        _set(key, SourceCheckState.checking);
        SourceCheckState result;
        try {
          result = await probe(source);
        } on TimeoutException {
          result = SourceCheckState.timeout;
        } catch (_) {
          result = SourceCheckState.unavailable;
        }
        if (!_disposed && epoch == _epoch) {
          _set(key, result);
        } else if (sourceCheckResults.value[key]?.state ==
            SourceCheckState.checking) {
          sourceCheckResults.value = {...sourceCheckResults.value}..remove(key);
        }
      }
    } finally {
      _busy = false;
    }
  }

  void stop() {
    ++_epoch;
    _queue.clear();
    unawaited(cancelProbe().catchError((_) {}));
  }

  void dispose() {
    _disposed = true;
    stop();
  }
}
