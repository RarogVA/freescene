import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Own, bounded disk cache. Filenames contain a URL hash, never titles or tokens.
class PosterDiskCache {
  PosterDiskCache(
    this.directory, {
    HttpClient? client,
    this.maxBytes = 256 * 1024 * 1024,
    this.maxEntries = 1000,
    this.maxAge = const Duration(days: 30),
    this.maxImageBytes = 8 * 1024 * 1024,
    this.maxConcurrent = 6,
  }) : assert(maxConcurrent > 0),
       _client = client ?? HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 10);
    _client.userAgent = 'FreeScene/0.5';
  }
  factory PosterDiskCache.application() {
    final env = Platform.environment;
    final root =
        env['FREESCENE_CACHE'] ??
        (env['FREESCENE_DATA'] != null
            ? '${env['FREESCENE_DATA']}/cache'
            : '${env['HOME'] ?? Directory.systemTemp.path}/Library/Caches/FreeScene');
    return PosterDiskCache(Directory('$root/posters'));
  }
  static final shared = PosterDiskCache.application();
  final Directory directory;
  final HttpClient _client;
  final int maxBytes, maxEntries, maxImageBytes, maxConcurrent;
  final Duration maxAge;
  final _pending = <String, Future<File?>>{},
      _refreshing = <String, Future<File?>>{};
  final _retryAfter = <String, DateTime>{};
  final _waiting = Queue<Completer<void>>();
  int _active = 0;
  bool _closed = false;
  Future<void> _pruning = Future.value();
  static String _key(Uri uri) =>
      sha256.convert(utf8.encode(uri.toString())).toString();
  static bool _allowed(Uri uri) =>
      uri.userInfo.isEmpty &&
      uri.host.isNotEmpty &&
      (uri.scheme == 'https' ||
          (uri.scheme == 'http' &&
              ['127.0.0.1', 'localhost', '::1'].contains(uri.host)));

  Future<File?> get(Uri uri) {
    if (_closed || !_allowed(uri)) return Future.value();
    final key = _key(uri);
    return _pending.putIfAbsent(
      key,
      () => _load(uri, key).whenComplete(() {
        _pending.remove(key);
      }),
    );
  }

  Future<({File file, Map<String, dynamic> meta})?> _read(String key) async {
    try {
      final raw = await File('${directory.path}/$key.json').readAsString();
      if (raw.length > 8192) return null;
      final meta = jsonDecode(raw);
      if (meta is! Map<String, dynamic> ||
          meta['file'] is! String ||
          !RegExp('^$key-[0-9]+\\.image\$').hasMatch(meta['file'] as String)) {
        return null;
      }
      final file = File('${directory.path}/${meta['file']}');
      final length = await file.length();
      if (length == 0 || length > maxImageBytes) return null;
      final handle = await file.open();
      try {
        if (!_image(await handle.read(12))) return null;
      } finally {
        await handle.close();
      }
      return (file: file, meta: meta);
    } on IOException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<File?> _load(Uri uri, String key) async {
    final entry = await _read(key);
    if (entry != null) {
      try {
        await entry.file.setLastModified(DateTime.now());
      } on IOException {
        /* A concurrent prune is harmless. */
      }
      final fetched = DateTime.tryParse('${entry.meta['fetchedAt']}');
      if (fetched == null || DateTime.now().difference(fetched) > maxAge) {
        unawaited(_refresh(uri, key, entry).then<void>((_) {}));
      }
      return entry.file;
    }
    return _refresh(uri, key, null);
  }

  Future<void> _acquire() async {
    if (_active < maxConcurrent) {
      ++_active;
      return;
    }
    final ready = Completer<void>();
    _waiting.add(ready);
    await ready.future;
  }

  void _release() {
    if (_waiting.isEmpty) {
      --_active;
    } else {
      _waiting.removeFirst().complete();
    }
  }

  Future<File?> _refresh(
    Uri uri,
    String key,
    ({File file, Map<String, dynamic> meta})? old,
  ) => _refreshing.putIfAbsent(
    key,
    () => _download(uri, key, old).whenComplete(() {
      _refreshing.remove(key);
    }),
  );

  Future<File?> _download(
    Uri uri,
    String key,
    ({File file, Map<String, dynamic> meta})? old,
  ) async {
    if ((_retryAfter[key]?.isAfter(DateTime.now()) ?? false) || _closed) {
      return old?.file;
    }
    await _acquire();
    HttpClientRequest? request;
    File? partial;
    var finished = false;
    try {
      return await (() async {
        if (_closed) return old?.file;
        var target = uri;
        HttpClientResponse? response;
        for (var redirects = 0; redirects <= 3; ++redirects) {
          request = await _client.getUrl(target);
          if (finished) {
            request!.abort();
            return old?.file;
          }
          request!.followRedirects = false;
          if (old?.meta['etag'] is String) {
            request!.headers.set(
              HttpHeaders.ifNoneMatchHeader,
              old!.meta['etag'],
            );
          }
          if (old?.meta['modified'] is String) {
            request!.headers.set(
              HttpHeaders.ifModifiedSinceHeader,
              old!.meta['modified'],
            );
          }
          response = await request!.close();
          if (![301, 302, 303, 307, 308].contains(response.statusCode)) break;
          final location = response.headers.value(HttpHeaders.locationHeader);
          request!.abort();
          if (location == null || redirects == 3) {
            throw const HttpException('Poster redirect failed');
          }
          target = target.resolve(location);
          if (!_allowed(target)) {
            throw const HttpException('Invalid poster redirect');
          }
        }
        await directory.create(recursive: true);
        if (response!.statusCode == 304 && old != null) {
          await _writeMeta(key, {
            ...old.meta,
            'fetchedAt': DateTime.now().toUtc().toIso8601String(),
          });
          return old.file;
        }
        if (response.statusCode != 200 ||
            response.contentLength > maxImageBytes ||
            (response.headers.contentType != null &&
                response.headers.contentType!.primaryType != 'image')) {
          throw const HttpException('Poster is unavailable');
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > maxImageBytes) {
            throw const HttpException('Poster too large');
          }
          bytes.addAll(chunk);
        }
        if (!_image(bytes)) throw const FormatException('Invalid poster bytes');
        final file = File(
          '${directory.path}/$key-${DateTime.now().microsecondsSinceEpoch}.image',
        );
        partial = File('${file.path}.part');
        await partial!.writeAsBytes(bytes, flush: true);
        await partial!.rename(file.path);
        partial = null;
        await _writeMeta(key, {
          'file': file.uri.pathSegments.last,
          'fetchedAt': DateTime.now().toUtc().toIso8601String(),
          'etag': response.headers.value(HttpHeaders.etagHeader),
          'modified': response.headers.value(HttpHeaders.lastModifiedHeader),
        });
        _retryAfter.remove(key);
        _pruning = _pruning.then((_) => _prune()).catchError((_) {});
        return file;
      })().timeout(const Duration(seconds: 20));
    } catch (_) {
      _retryAfter[key] = DateTime.now().add(const Duration(minutes: 1));
      return old?.file;
    } finally {
      finished = true;
      request?.abort();
      _release();
      if (partial != null) {
        try {
          await partial!.delete();
        } on IOException {
          /* No partial cache entry. */
        }
      }
    }
  }

  static bool _image(List<int> b) =>
      b.length >= 12 &&
      ((b[0] == 0xff && b[1] == 0xd8 && b[2] == 0xff) ||
          (b[0] == 0x89 &&
              ascii.decode(b.sublist(1, 4), allowInvalid: true) == 'PNG') ||
          ascii
              .decode(b.sublist(0, 6), allowInvalid: true)
              .startsWith('GIF8') ||
          (ascii.decode(b.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
              ascii.decode(b.sublist(8, 12), allowInvalid: true) == 'WEBP'));
  Future<void> _writeMeta(String key, Map<String, dynamic> value) async {
    final file = File('${directory.path}/$key.json');
    final temporary = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.part',
    );
    try {
      await temporary.writeAsString(jsonEncode(value), flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> invalidate(Uri uri, {File? expected}) async {
    final key = _key(uri);
    final entry = await _read(key);
    if (entry != null &&
        (expected == null || expected.path == entry.file.path)) {
      for (final file in [entry.file, File('${directory.path}/$key.json')]) {
        try {
          await file.delete();
        } on IOException {
          /* Already evicted. */
        }
      }
    }
    _retryAfter.remove(key);
  }

  Future<void> _prune() async {
    final images = <({File file, FileStat stat})>[];
    final manifests = <String, String>{};
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (RegExp(r'^[a-f0-9]{64}\.json$').hasMatch(name)) {
        final key = name.substring(0, 64);
        final entry = await _read(key);
        if (entry != null) {
          manifests[key] = entry.file.path;
        } else if (!_pending.containsKey(key) &&
            !_refreshing.containsKey(key)) {
          await entity.delete();
        }
      } else if (RegExp(r'^[a-f0-9]{64}-[0-9]+\.image$').hasMatch(name)) {
        images.add((file: entity, stat: await entity.stat()));
      } else if (RegExp(r'^[a-f0-9]{64}.*\.part$').hasMatch(name) &&
          DateTime.now().difference(await entity.lastModified()) >
              const Duration(days: 1)) {
        await entity.delete();
      }
    }
    images.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
    var bytes = images.fold<int>(0, (sum, e) => sum + e.stat.size),
        count = images.length;
    for (final entry in images) {
      final key = entry.file.uri.pathSegments.last.split('-').first;
      if (_pending.containsKey(key) || _refreshing.containsKey(key)) continue;
      if (bytes <= maxBytes &&
          count <= maxEntries &&
          manifests[key] == entry.file.path) {
        continue;
      }
      try {
        await entry.file.delete();
        bytes -= entry.stat.size;
        --count;
        if (manifests[key] == entry.file.path) {
          await File('${directory.path}/$key.json').delete();
        }
      } on IOException {
        /* Concurrent use. */
      }
    }
  }

  void close() {
    _closed = true;
    _client.close(force: true);
  }
}
