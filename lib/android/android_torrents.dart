import 'dart:typed_data';

import '../catalog/catalog_models.dart';
import '../torrent/native_torrent.dart';
import 'android_runtime.dart';

class AndroidTorrents {
  const AndroidTorrents();
  Future<Map<String, dynamic>> command(
    String method, [
    Map<String, dynamic> args = const {},
  ]) async => Map<String, dynamic>.from(
    await AndroidRuntime.channel.invokeMethod('torrentCommand', {
      'request': {'method': method, ...args},
    }) as Map,
  );
  Future<void> open(
    CatalogSource source, {
    String? title,
    Map<String, Object?> playback = const {},
  }) => AndroidRuntime.channel.invokeMethod<void>('torrentOpen', {
    ...playback,
    'title': title ?? source.row.title,
    if (source.torrentBytes != null)
      'bytes': Uint8List.fromList(source.torrentBytes!),
    if (source.uri?.scheme == 'magnet') 'magnet': source.uri.toString(),
    'origin': {'provider': source.row.provider.name},
  });
  Future<String> add(CatalogSource source) async {
    final result = await AndroidRuntime.channel
        .invokeMapMethod<String, dynamic>('torrentAdd', {
          if (source.torrentBytes != null)
            'bytes': Uint8List.fromList(source.torrentBytes!),
          if (source.uri?.scheme == 'magnet') 'magnet': source.uri.toString(),
          'origin': {'provider': source.row.provider.name},
        });
    return result!['id'] as String;
  }

  Future<List<TorrentTask>> tasks() async =>
      ((await command('status'))['tasks'] as List)
          .map((v) => TorrentTask(Map<String, dynamic>.from(v as Map)))
          .toList();
  Future<void> play(
    String id, {
    String? title,
    Map<String, Object?> playback = const {},
  }) => AndroidRuntime.channel.invokeMethod<void>('torrentPlay', {
    'id': id,
    'title': title,
    ...playback,
  });
}
