import 'dart:async';
import 'dart:io';

import 'catalog_models.dart';
import '../torrent/native_torrent.dart';

/// Copies remote metadata into the engine, which owns its persistent copy.
/// Temporary files are removed on success, cancellation, and failure.
Future<String> importCatalogSource(
  TorrentController controller,
  CatalogSource source,
) async {
  final uri = source.uri;
  if (uri == null && source.torrentBytes == null) {
    throw const FormatException('Source is unavailable');
  }
  final args = <String, dynamic>{
    'source': uri?.toString() ?? '',
    'origin': {'provider': source.row.provider.name},
    if (source.torrentBytes != null && uri?.scheme == 'magnet')
      'expectedMagnet': uri.toString(),
  };
  Directory? temporary;
  HttpClient? client;
  HttpClientRequest? request;
  try {
    if (source.torrentBytes != null) {
      final bytes = source.torrentBytes!;
      if (bytes.isEmpty ||
          bytes.first != 100 ||
          bytes.length > 16 * 1024 * 1024) {
        throw const FormatException('Invalid torrent metadata');
      }
      temporary = await Directory.systemTemp.createTemp('freescene-source-');
      final file = File('${temporary.path}/source.torrent');
      await file.writeAsBytes(bytes, flush: true);
      args['source'] = file.path;
    } else if (uri!.scheme != 'magnet') {
      if (!['https', 'http'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw const FormatException('Invalid torrent URL');
      }
      client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
      final data = await (() async {
        request = await client!.getUrl(uri);
        // Redirects are handled by HttpClient without forwarding app credentials.
        final response = await request!.close();
        if (response.statusCode != 200) {
          throw HttpException('Torrent HTTP ${response.statusCode}');
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 16 * 1024 * 1024) {
            throw const FormatException('Torrent exceeds 16 MiB');
          }
          bytes.addAll(chunk);
        }
        if (bytes.isEmpty || bytes.first != 100) {
          throw const FormatException('Invalid torrent metadata');
        }
        return bytes;
      })().timeout(const Duration(seconds: 30));
      temporary = await Directory.systemTemp.createTemp('freescene-source-');
      final file = File('${temporary.path}/source.torrent');
      await file.writeAsBytes(data, flush: true);
      args['source'] = file.path;
    }
    final response = await controller.command('add', args) as Map;
    return response['id'] as String;
  } finally {
    request?.abort();
    client?.close(force: true);
    if (temporary != null) await temporary.delete(recursive: true);
  }
}
