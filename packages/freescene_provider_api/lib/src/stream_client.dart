import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'provider_error.dart';

class StreamDownloadError implements ProviderError {
  const StreamDownloadError(this.code);
  final String code;
  @override
  String label(bool en) => switch (code) {
    'restricted' =>
      en
          ? 'The provider does not allow downloading this video.'
          : 'Провайдер не предоставил доступ к скачиванию этого видео.',
    'unsupported' =>
      en
          ? 'This video cannot be saved: a complete, unencrypted stream with audio is required.'
          : 'Это видео нельзя сохранить: нужен завершённый незашифрованный поток со звуком.',
    'changed' =>
      en
          ? 'The video has changed. Remove this download and add it again.'
          : 'Видео изменилось. Удалите эту загрузку и добавьте заново.',
    'disk' =>
      en
          ? 'Could not save the file. Check free space and access to Downloads.'
          : 'Не удалось сохранить файл. Проверьте свободное место и доступ к Загрузкам.',
    'missing' =>
      en
          ? 'The downloaded file is missing or has changed. Add the download again.'
          : 'Скачанный файл отсутствует или изменён. Добавьте загрузку заново.',
    'cancelled' => en ? 'Download paused.' : 'Загрузка приостановлена.',
    _ =>
      en
          ? 'Video download failed. Check the connection and retry.'
          : 'Не удалось скачать видео. Проверьте подключение и повторите.',
  };
}

class StreamQuality {
  const StreamQuality(this.height, this.bandwidth, this.urls);
  final int height, bandwidth;
  final List<Uri> urls;
  String get key => '$height-$bandwidth';
  String get label => '${height}p';
}

class StreamPlaylist {
  const StreamPlaylist(this.segments, this.fingerprint, {required this.url});
  final Uri url;
  final List<Uri> segments;
  final String fingerprint;
}

/// Anonymous public VOD only. URLs from API/manifests and every redirect are
/// checked before requesting them. No account cookies, player impersonation,
/// encrypted streams, adverts or external downloader executables are used.
class StreamClient {
  StreamClient({required this.allows, Uri? testBase}) : _testBase = testBase {
    if (testBase != null &&
        (testBase.scheme != 'http' || testBase.host != '127.0.0.1')) {
      throw ArgumentError('Loopback test server required');
    }
    _client.connectionTimeout = const Duration(seconds: 15);
    _client.userAgent = 'FreeScene/1.2.8 macOS';
  }
  final Uri? _testBase;
  final HttpClient _client = HttpClient();
  bool _closed = false;
  void close() {
    _closed = true;
    _client.close(force: true);
  }

  final bool Function(Uri) allows;
  static bool allowed(Uri uri) =>
      uri.scheme == 'https' &&
      uri.port == 443 &&
      uri.userInfo.isEmpty &&
      uri.host.isNotEmpty;

  void _check(Uri uri) {
    if (allowed(uri) && allows(uri)) return;
    if (_testBase != null &&
        uri.origin == _testBase.origin &&
        uri.userInfo.isEmpty) {
      return;
    }
    throw const StreamDownloadError('restricted');
  }

  Future<Uint8List> bytes(
    Uri uri, {
    int limit = 2 * 1024 * 1024,
    Future<void> Function(int)? received,
  }) async {
    try {
      for (var hop = 0; hop < 4; hop++) {
        if (_closed) throw const StreamDownloadError('cancelled');
        _check(uri);
        final request = await _client
            .getUrl(uri)
            .timeout(const Duration(seconds: 20));
        request.followRedirects = false;
        final response = await request.close().timeout(
          const Duration(seconds: 30),
        );
        if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          request.abort();
          if (location == null) break;
          uri = uri.resolve(location);
          continue;
        }
        if (response.statusCode != 200) {
          request.abort();
          throw StreamDownloadError(
            [401, 403, 451].contains(response.statusCode)
                ? 'restricted'
                : 'network',
          );
        }
        if (response.contentLength > limit) {
          request.abort();
          throw const StreamDownloadError('unsupported');
        }
        final data = BytesBuilder(copy: false);
        try {
          await for (final chunk in response.timeout(
            const Duration(seconds: 30),
          )) {
            if (_closed) throw const StreamDownloadError('cancelled');
            if (data.length + chunk.length > limit) {
              throw const StreamDownloadError('unsupported');
            }
            data.add(chunk);
            await received?.call(chunk.length);
          }
        } finally {
          request.abort();
        }
        if (response.compressionState !=
                HttpClientResponseCompressionState.decompressed &&
            response.contentLength >= 0 &&
            data.length != response.contentLength) {
          throw const StreamDownloadError('network');
        }
        return data.takeBytes();
      }
    } on StreamDownloadError {
      rethrow;
    } catch (_) {
      throw StreamDownloadError(_closed ? 'cancelled' : 'network');
    }
    throw const StreamDownloadError('network');
  }

  Future<String> text(Uri uri) async {
    try {
      return utf8.decode(await bytes(uri));
    } on FormatException {
      throw const StreamDownloadError('unsupported');
    }
  }

  Future<List<StreamQuality>> qualities(String id) =>
      Future.error(const StreamDownloadError('unsupported'));

  static Map<String, String> _attributes(String line) => {
    for (final match in RegExp(
      r'([A-Z0-9-]+)=("[^"]*"|[^,]*)',
    ).allMatches(line))
      match[1]!: match[2]!.replaceAll('"', ''),
  };

  static List<StreamQuality> parseMaster(String source, Uri base) {
    if (!source.trimLeft().startsWith('#EXTM3U')) {
      throw const StreamDownloadError('unsupported');
    }
    final variants = <String, StreamQuality>{};
    Map<String, String>? attributes;
    for (final raw in const LineSplitter().convert(source)) {
      final line = raw.trim();
      if (line.startsWith('#EXT-X-SESSION-KEY:')) {
        throw const StreamDownloadError('unsupported');
      }
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        attributes = _attributes(line);
        continue;
      }
      if (line.isEmpty || line.startsWith('#') || attributes == null) continue;
      final a = attributes;
      attributes = null;
      // A muxed MPEG-TS variant contains both tracks. Separate audio requires
      // a real remuxer; never save a silent file and call it a finished video.
      if (a.containsKey('AUDIO')) continue;
      final height = int.tryParse(a['RESOLUTION']?.split('x').last ?? '');
      final bandwidth = int.tryParse(a['BANDWIDTH'] ?? '');
      if (height == null ||
          height < 1 ||
          height > 4320 ||
          bandwidth == null ||
          bandwidth < 1) {
        continue;
      }
      final variant = StreamQuality(height, bandwidth, [base.resolve(line)]);
      final previous = variants[variant.key];
      if (previous == null) {
        variants[variant.key] = variant;
      } else {
        previous.urls.addAll(variant.urls);
      }
    }
    if (variants.isEmpty) throw const StreamDownloadError('unsupported');
    return variants.values.toList()
      ..sort((a, b) => b.height.compareTo(a.height));
  }

  Future<StreamPlaylist> playlist(StreamQuality quality) async {
    for (var i = 0; i < quality.urls.length; i++) {
      try {
        return parseMedia(await text(quality.urls[i]), quality.urls[i]);
      } on StreamDownloadError catch (e) {
        if (e.code != 'network' || i == quality.urls.length - 1) rethrow;
      }
    }
    throw const StreamDownloadError('network');
  }

  static StreamPlaylist parseMedia(String source, Uri base) {
    final lines = const LineSplitter()
        .convert(source)
        .map((l) => l.trim())
        .toList();
    if (lines.firstOrNull != '#EXTM3U' || !lines.contains('#EXT-X-ENDLIST')) {
      throw const StreamDownloadError('unsupported');
    }
    final segments = <Uri>[];
    final identity = <String>[];
    var hasDuration = false;
    for (final line in lines) {
      if (line.startsWith('#EXT-X-KEY:') &&
              _attributes(line)['METHOD'] != 'NONE' ||
          line.startsWith('#EXT-X-MAP:') ||
          line.startsWith('#EXT-X-BYTERANGE:') ||
          line.startsWith('#EXT-X-DISCONTINUITY') ||
          line.startsWith('#EXT-X-GAP') ||
          line.startsWith('#EXT-X-STREAM-INF:')) {
        throw const StreamDownloadError('unsupported');
      }
      if (line.startsWith('#EXTINF:')) {
        final duration = double.tryParse(line.substring(8).split(',').first);
        if (duration == null || !duration.isFinite || duration <= 0) {
          throw const StreamDownloadError('unsupported');
        }
        identity.add(line);
        hasDuration = true;
      }
      if (line.startsWith('#EXT-X-MEDIA-SEQUENCE:')) identity.add(line);
      if (line.isEmpty || line.startsWith('#')) continue;
      if (!hasDuration || segments.length >= 100000) {
        throw const StreamDownloadError('unsupported');
      }
      hasDuration = false;
      segments.add(base.resolve(line));
    }
    if (segments.isEmpty || hasDuration) {
      throw const StreamDownloadError('unsupported');
    }
    return StreamPlaylist(
      segments,
      sha256.convert(utf8.encode(identity.join('\n'))).toString(),
      url: base,
    );
  }

  Future<Uint8List> segment(
    Uri uri, {
    Future<void> Function(int)? received,
  }) async {
    final data = await bytes(uri, limit: 64 * 1024 * 1024, received: received);
    // Reject HTML/challenges, encrypted data and partial TS packets.
    if (data.length < 188 || data.length % 188 != 0) {
      throw const StreamDownloadError('unsupported');
    }
    for (var offset = 0; offset < data.length; offset += 188) {
      if (data[offset] != 0x47) throw const StreamDownloadError('unsupported');
    }
    return data;
  }
}
