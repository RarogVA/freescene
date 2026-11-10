import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/download.dart';
import '../domain/notifications.dart';
import '../downloads/video_downloads.dart';

import 'package:freescene_provider_api/freescene_provider_api.dart';

class TorrentFile {
  TorrentFile(Map<String, dynamic> json)
    : index = json['index'] as int,
      name = json['name'] as String,
      size = json['size'] as int,
      done = json['done'] as int,
      video = json['video'] as bool;
  final int index, size, done;
  final String name;
  final bool video;
}

class TorrentTask {
  TorrentTask(Map<String, dynamic> json)
    : id = json['id'] as String,
      title = json['title'] as String,
      origin = DownloadOrigin.fromJson(
        Map<String, dynamic>.from(json['origin'] as Map),
      ),
      phase = json['phase'] as String,
      done = json['done'] as int,
      total = json['total'] as int,
      rate = json['rate'] as int,
      seeds = json['seeds'] as int?,
      peers = json['peers'] as int?,
      error = json['error'] as String,
      event = json['event'] as String,
      metadata = json['metadata'] as bool,
      dht = json['dht'] as String? ?? 'unknown',
      buffering = json['buffering'] as bool? ?? false,
      isVideoDownload = json['kind'] == 'hls',
      quality = json['quality'] as String? ?? '',
      segments = json['segments'] as int? ?? 0,
      segmentCount = json['segmentCount'] as int? ?? 0,
      files = (json['files'] as List)
          .map((e) => TorrentFile(Map<String, dynamic>.from(e as Map)))
          .toList();
  final String id, title, phase, error, event;
  final DownloadOrigin origin;
  final int done, total, rate;
  final int? seeds, peers;
  final bool metadata;
  final bool buffering;
  final String dht;
  final bool isVideoDownload;
  final String quality;
  final int segments, segmentCount;
  final List<TorrentFile> files;
  bool get active =>
      phase != 'paused' &&
      phase != 'queued' &&
      phase != 'failed' &&
      phase != 'completed';
  double? get progress => active && (!metadata || buffering)
      ? null
      : isVideoDownload
      ? (segmentCount > 0 ? segments / segmentCount : 0)
      : total > 0
      ? (done / total).clamp(0, 1)
      : 0;
  List<TorrentFile> get videos => files.where((f) => f.video).toList();
}

class NativeTorrentService extends NativeProviderTransport {
  const NativeTorrentService();
  static const channel = MethodChannel('freescene/native');
  @override
  Future<dynamic> call(String method, [Map<String, dynamic>? args]) =>
      channel.invokeMethod<dynamic>(method, args);
}

class TorrentController extends ChangeNotifier {
  TorrentController(
    this.service,
    this.enabledNotifications, {
    this.english,
    this.chooseVideo,
    this.videoDownloads,
  });
  final bool Function()? english;
  final Future<TorrentFile?> Function(TorrentTask)? chooseVideo;
  final NativeTorrentService service;
  final Set<NotificationEvent> Function() enabledNotifications;
  final Map<String, NotificationGate> _gates = {};
  final Map<String, String> _phases = {};
  Timer? _timer;
  bool _refreshing = false, _disposed = false, _stopping = false;
  List<TorrentTask> tasks = [];
  Map<String, dynamic> limits = {'download': 0, 'upload': 0, 'active': 3};
  String? error;
  bool loading = true;
  String? _pendingWatch;
  int _watchEpoch = 0;
  bool _startingVideo = false;
  VideoDownloads? videoDownloads;
  bool _downloadsLoaded = false;
  String? _downloadsError;
  Future<VideoDownloads>? _openingDownloads;

  Future<VideoDownloads> _downloads() async {
    if (videoDownloads != null) return videoDownloads!;
    if (_openingDownloads != null) return _openingDownloads!;
    final future = _openDownloads();
    _openingDownloads = future;
    try {
      return await future;
    } finally {
      _openingDownloads = null;
    }
  }

  Future<VideoDownloads> _openDownloads() async {
    final setup = ProviderSetup.current;
    if (setup.createStreamClient == null || setup.downloadProvider == null) {
      throw MissingPluginException('Video downloads unavailable');
    }
    final paths = await service.call('videoDownloadLocations', {
      'directory': setup.downloadDirectory ?? setup.downloadProvider!.name,
    });
    if (paths is! Map) {
      throw MissingPluginException('Video downloads unavailable');
    }
    final manager = VideoDownloads(
      provider: setup.downloadProvider!.name,
      clientFactory: setup.createStreamClient!,
      profile: Directory(paths['profile'] as String),
      directory: Directory(paths['downloads'] as String),
    );
    manager.load();
    if (_disposed || _stopping) {
      manager.close();
      throw const StreamDownloadError('cancelled');
    }
    videoDownloads = manager;
    _downloadsError = null;
    return manager;
  }

  Future<List<StreamQuality>> videoQualities(String id) async =>
      (await _downloads()).qualities(id);
  Future<void> downloadVideo(
    String video,
    String title,
    StreamQuality quality,
  ) async {
    (await _downloads()).add(video, title, quality);
    await refresh();
  }

  Future<void> watchProvider({
    required String url,
    required String title,
    required String provider,
    String? providerName,
    required String kind,
    Map<String, String> identity = const {},
    int? webPlayer,
    List<Map<String, String>> webEpisodes = const [],
  }) async {
    ++_watchEpoch;
    _pendingWatch = null;
    await service.call('openProvider', {
      ...identity,
      'url': url,
      'title': title,
      'provider': provider,
      'providerName': providerName ?? provider,
      'kind': kind,
      'webPlayer': ?webPlayer,
      if (webEpisodes.isNotEmpty) 'webEpisodes': webEpisodes,
    });
  }

  Future<void> watch(
    String id, {
    Map<String, String> identity = const {},
  }) async {
    final epoch = ++_watchEpoch;
    _pendingWatch = null;
    final task = tasks.where((t) => t.id == id).firstOrNull;
    if (task == null) throw const FormatException('Torrent no longer exists');
    if (task.isVideoDownload) {
      final filename = (await _downloads()).completedFile(id);
      if (_disposed || _stopping || epoch != _watchEpoch) return;
      await service.call('openDownloadedVideo', {
        'filename': filename,
        'directory':
            ProviderSetup.current.downloadDirectory ??
            ProviderSetup.current.downloadProvider!.name,
        'title': task.title,
      });
      return;
    }
    await service.call('preparePlayer', {
      'id': id,
      'title': task.title,
      ...identity,
    });
    if (_disposed || epoch != _watchEpoch) return;
    _pendingWatch = id;
    try {
      await command('prepareStream', {'id': id});
    } catch (_) {
      if (epoch == _watchEpoch) _pendingWatch = null;
      rethrow;
    }
  }

  Future<void> _startVideoWhenReady() async {
    if (_disposed || _stopping || _startingVideo || _pendingWatch == null) {
      return;
    }
    final task = tasks.where((t) => t.id == _pendingWatch).firstOrNull;
    if (task == null || !task.metadata) return;
    final epoch = _watchEpoch;
    _startingVideo = true;
    try {
      if (task.videos.isEmpty) {
        throw FormatException(
          english?.call() == true
              ? 'No supported video in this torrent'
              : 'В раздаче нет поддерживаемого видео',
        );
      }
      final file = task.videos.length == 1
          ? task.videos.single
          : chooseVideo == null
          ? task.videos.first
          : await chooseVideo!(task);
      if (_disposed || epoch != _watchEpoch) return;
      _pendingWatch = null;
      if (file == null) {
        await service.call('cancelPreparedPlayer', {'id': task.id});
        return;
      }
      await service.call('stream', {
        'id': task.id,
        'file': file.index,
        'title': file.name,
        'prepared': true,
      });
    } catch (e) {
      if (!_disposed && epoch == _watchEpoch) {
        _pendingWatch = null;
        error = e is PlatformException ? e.message : e.toString();
        await service
            .call('playerMessage', {'id': task.id, 'message': error})
            .catchError((_) => null);
        if (!_disposed) notifyListeners();
      }
    } finally {
      _startingVideo = false;
    }
  }

  void start() {
    if (_disposed || _stopping) return;
    refresh();
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => refresh());
  }

  /// Stop before the native engine saves its session and disconnects.
  void stopForShutdown() {
    _stopping = true;
    _timer?.cancel();
    _timer = null;
    _pendingWatch = null;
    ++_watchEpoch;
    videoDownloads?.close();
  }

  Future<dynamic> command(String method, [Map<String, dynamic>? args]) async {
    final id = args?['id'];
    if (id is String && (videoDownloads?.owns(id) ?? false)) {
      (await _downloads()).command(
        method,
        id,
        deleteFiles: args?['deleteFiles'] == true,
      );
      await refresh();
      return null;
    }
    final result = await service.call(method, args);
    await refresh();
    return result;
  }

  Future<void> refresh() async {
    if (_refreshing || _disposed || _stopping) return;
    _refreshing = true;
    try {
      final data = Map<String, dynamic>.from(
        await service.call('status') as Map,
      );
      if (_disposed || _stopping) return;
      if (data['shuttingDown'] == true) {
        stopForShutdown();
        return;
      }
      final next = (data['tasks'] as List)
          .map((e) => TorrentTask(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (!_downloadsLoaded) {
        _downloadsLoaded = true;
        try {
          await _downloads();
        } on MissingPluginException {
          /* Older native hosts and UI fixtures. */
        } catch (_) {
          _downloadsError = StreamDownloadError('disk')
              .label(english?.call() ?? false);
        }
      }
      if (_disposed || _stopping) return;
      limits = Map<String, dynamic>.from(data['limits'] as Map? ?? limits);
      videoDownloads?.limits(
        active: limits['active'] as int,
        download: limits['download'] as int,
        nativeActive: next
            .where((t) => t.active && t.phase != 'seeding')
            .length,
        nativeRate: next.fold<int>(
          0,
          (sum, t) => sum + (t.active ? t.rate : 0),
        ),
      );
      next.addAll(
        (videoDownloads?.snapshots(english?.call() ?? false) ?? []).map(
          TorrentTask.new,
        ),
      );
      if (_disposed) return;
      if (_pendingWatch != null &&
          data.containsKey('playerTaskId') &&
          data['playerTaskId'] != _pendingWatch) {
        _pendingWatch = null;
        ++_watchEpoch;
      }
      for (final task in next) {
        final gate = _gates.putIfAbsent(task.id, NotificationGate.new);
        final previous = _phases[task.id];
        if (task.event.isEmpty) gate.recoveredOrRetried();
        NotificationEvent? event;
        if (task.event.isNotEmpty) {
          event = NotificationEvent.fromNative(task.event);
        } else if ((task.phase == 'seeding' || task.phase == 'completed') &&
            previous != null &&
            previous != 'seeding' &&
            previous != 'completed') {
          event = NotificationEvent.downloadCompleted;
        }
        if (event != null && gate.shouldNotify(event, enabledNotifications())) {
          final isMetadata = event == NotificationEvent.metadataFailed;
          final localized = english?.call() ?? false;
          unawaited(
            service
                .call('notify', {
                  'title': isMetadata ? event.label(localized) : task.title,
                  'body':
                      '${isMetadata ? '${task.title} · ' : ''}${task.origin.localizedLabel(localized)}: ${task.error.isEmpty ? event.label(localized) : task.error}',
                  'id': '${task.id}-${event.name}',
                })
                .catchError((_) => null),
          );
        }
        _phases[task.id] = task.phase;
      }
      final ids = next.map((t) => t.id).toSet();
      _gates.removeWhere((id, _) => !ids.contains(id));
      _phases.removeWhere((id, _) => !ids.contains(id));
      tasks = next;
      limits = Map<String, dynamic>.from(data['limits'] as Map? ?? limits);
      final persistence = data['persistenceError'] as String?;
      error = persistence == null || persistence.isEmpty
          ? _downloadsError
          : persistence;
      if (videoDownloads?.persistenceError != null) {
        error = StreamDownloadError('disk').label(english?.call() ?? false);
      }
    } catch (e) {
      if (e is PlatformException && e.code == 'app_closing') {
        stopForShutdown();
      } else if (!_disposed && !_stopping) {
        error = e is PlatformException ? e.message : e.toString();
      }
    } finally {
      _refreshing = false;
      if (!_disposed && !_stopping) {
        loading = false;
        notifyListeners();
        unawaited(_startVideoWhenReady());
      }
    }
  }

  @override
  void dispose() {
    stopForShutdown();
    _disposed = true;
    super.dispose();
  }
}
