import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'catalog_models.dart';

/// Catalogue identities remain stable across temporary stream URLs and retries.
Map<String, String> watchedIdentity(
  CatalogTitle? title,
  CatalogSource source,
) => title == null || title.kind == CatalogKind.games
    ? {}
    : {
        'watchedTitle': jsonEncode([title.kind.name, title.id]),
        'watchedSource': jsonEncode([
          title.kind.name,
          title.id,
          source.row.provider.name,
          source.row.id,
        ]),
      };

class WatchedController extends ChangeNotifier {
  WatchedController(this.channel);
  final MethodChannel channel;
  Map<String, String> _entries = {};
  Timer? _timer;
  final _saving = <String>{};
  bool _disposed = false, _loading = false;
  int _revision = 0;
  void start() {
    refresh();
    _timer ??= Timer.periodic(const Duration(seconds: 2), (_) => refresh());
  }

  bool titleWatched(CatalogTitle title) =>
      _entries.containsValue(jsonEncode([title.kind.name, title.id]));
  bool sourceWatched(CatalogTitle title, CatalogSource source) =>
      _entries.containsKey(watchedIdentity(title, source)['watchedSource']);
  Future<void> refresh() async {
    if (_loading || _disposed || _saving.isNotEmpty) return;
    _loading = true;
    final revision = _revision;
    try {
      final raw = await channel.invokeMapMethod<Object?, Object?>(
        'watchedSnapshot',
      );
      final result = raw == null
          ? null
          : <String, String>{
              for (final entry in raw.entries)
                if (entry.key is String && entry.value is String)
                  entry.key as String: entry.value as String,
            };
      if (!_disposed &&
          revision == _revision &&
          result != null &&
          (result.length != _entries.length ||
              result.entries.any((e) => _entries[e.key] != e.value))) {
        _entries = result;
        notifyListeners();
      }
    } on MissingPluginException {
      // Allows catalogue-only hosts.
    } on PlatformException {
      // Retain the last successfully read state.
    } finally {
      _loading = false;
    }
  }

  Future<void> toggle(CatalogTitle title, CatalogSource source) async {
    final identity = watchedIdentity(title, source);
    if (identity.isEmpty) return;
    final sourceKey = identity['watchedSource']!;
    if (!_saving.add(sourceKey)) return;
    final marked = !sourceWatched(title, source);
    ++_revision;
    try {
      await channel.invokeMethod<void>('setWatched', {
        ...identity,
        'watched': marked,
      });
      if (_disposed) return;
      if (marked) {
        _entries[sourceKey] = identity['watchedTitle']!;
      } else {
        _entries.remove(sourceKey);
      }
      notifyListeners();
    } finally {
      _saving.remove(sourceKey);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

class WatchedScope extends InheritedNotifier<WatchedController> {
  const WatchedScope({
    required WatchedController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);
  static WatchedController? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WatchedScope>()?.notifier;
}

class TitleMetadata extends StatelessWidget {
  const TitleMetadata({required this.title, required this.english, super.key});
  final CatalogTitle title;
  final bool english;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Flexible(
        child: Text(
          [
            if (title.year != null) '${title.year}',
            if (title.rating != null) '★ ${title.rating!.toStringAsFixed(1)}',
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      if (WatchedScope.of(context)?.titleWatched(title) == true) ...[
        const SizedBox(width: 6),
        Tooltip(
          message: english ? 'Watched' : 'Просмотрено',
          child: Icon(
            Icons.visibility_outlined,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    ],
  );
}
