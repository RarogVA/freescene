import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'catalog_models.dart';

abstract class FavoriteStorage {
  Future<List<CatalogTitle>> load();
  Future<void> save(List<CatalogTitle> titles);
}

/// Public catalogue metadata only, separate from settings and account data.
class FavoritesStore implements FavoriteStorage {
  FavoritesStore(this.directory);
  final Directory directory;
  @protected
  String get storageFileName => 'favorites.json';
  File get _file => File('${directory.path}/$storageFileName');
  Future<void> _pending = Future.value();

  static Map<String, dynamic> _encode(CatalogTitle t) => {
    'id': t.id,
    'kind': t.kind.name,
    'name': t.name,
    'englishName': t.englishName,
    'description': t.description,
    'englishDescription': t.englishDescription,
    'year': t.year,
    'rating': t.rating,
    'genres': t.genres,
    'country': t.country,
    'poster': t.poster?.toString(),
    'posterFallback': t.posterFallback?.toString(),
    if (t.trailer != null) 'trailer': t.trailer!.toJson(),
  };

  static CatalogTitle _decode(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid favorite');
    }
    String? string(String key, {bool required = false}) {
      final v = value[key];
      if (v == null && !required) return null;
      if (v is! String || v.length > 100000 || (required && v.trim().isEmpty)) {
        throw const FormatException('Invalid favorite field');
      }
      return v;
    }

    Uri? url(String key) {
      final s = string(key);
      if (s == null) return null;
      final u = Uri.tryParse(s);
      if (u == null ||
          !['http', 'https'].contains(u.scheme) ||
          u.host.isEmpty ||
          u.userInfo.isNotEmpty) {
        throw const FormatException('Invalid favorite poster');
      }
      return u;
    }

    final kind = switch (value['kind']) {
      'movies' => CatalogKind.movies,
      'series' => CatalogKind.series,
      _ => throw const FormatException('Invalid favorite kind'),
    };
    final year = value['year'], rating = value['rating'];
    if (year != null && (year is! int || year < 0 || year > 9999) ||
        rating != null &&
            (rating is! num || !rating.isFinite || rating < 0 || rating > 10)) {
      throw const FormatException('Invalid favorite metadata');
    }
    return CatalogTitle(
      id: string('id', required: true)!,
      kind: kind,
      name: string('name', required: true)!,
      englishName: string('englishName'),
      description: string('description') ?? '',
      englishDescription: string('englishDescription'),
      year: year as int?,
      rating: (rating as num?)?.toDouble(),
      genres: string('genres'),
      country: string('country'),
      poster: url('poster'),
      posterFallback: url('posterFallback'),
      trailer: CatalogTrailer.fromJson(value['trailer']),
    );
  }

  @override
  Future<List<CatalogTitle>> load() async {
    if (!await _file.exists()) return [];
    if (await _file.length() > 8 * 1024 * 1024) {
      throw const FormatException('Favorites file too large');
    }
    final data = jsonDecode(await _file.readAsString());
    if (data is! Map<String, dynamic> ||
        data['version'] != 1 ||
        data['titles'] is! List ||
        (data['titles'] as List).length > 10000) {
      throw const FormatException('Invalid favorites document');
    }
    return (data['titles'] as List).map(_decode).toList();
  }

  @override
  Future<void> save(List<CatalogTitle> titles) {
    final encoded = titles.map(_encode).toList();
    final contents = jsonEncode({'version': 1, 'titles': encoded});
    final write = _pending.then((_) async {
      if (encoded.length > 10000 ||
          utf8.encode(contents).length > 8 * 1024 * 1024) {
        throw const FormatException('Favorites file too large');
      }
      for (final value in encoded) {
        _decode(value);
      }
      await directory.create(recursive: true);
      final temporary = File('${_file.path}.tmp');
      await temporary.writeAsString('$contents\n', flush: true);
      await temporary.rename(_file.path);
    });
    _pending = write.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return write;
  }
}

class FavoritesController extends ChangeNotifier {
  FavoritesController({this.store}) : ready = store == null;
  final FavoriteStorage? store;
  Map<String, CatalogTitle> _titles = {};
  bool ready, loading = false, saving = false;
  Object? error;
  bool _disposed = false;
  static String key(CatalogTitle title) => '${title.kind.name}:${title.id}';
  static bool eligible(CatalogTitle title) => title.kind != CatalogKind.games;
  List<CatalogTitle> get titles =>
      List.unmodifiable(_titles.values.toList().reversed);
  bool contains(CatalogTitle title) => _titles.containsKey(key(title));
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> restore() async {
    if (store == null || loading || saving || _disposed) return;
    loading = true;
    error = null;
    _changed();
    try {
      final titles = await store!.load();
      if (_disposed) return;
      _titles = {for (final t in titles.where(eligible)) key(t): t};
      ready = true;
    } catch (e) {
      if (!_disposed) {
        ready = false;
        error = e;
      }
    } finally {
      loading = false;
      _changed();
    }
  }

  Future<void> toggle(CatalogTitle title) async {
    if (_disposed || !ready || loading || saving || !eligible(title)) return;
    final previous = Map<String, CatalogTitle>.of(_titles);
    if (contains(title)) {
      _titles.remove(key(title));
    } else {
      _titles[key(title)] = title;
    }
    saving = true;
    _changed();
    try {
      await store?.save(_titles.values.toList());
    } catch (_) {
      if (!_disposed) _titles = previous;
      rethrow;
    } finally {
      saving = false;
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
