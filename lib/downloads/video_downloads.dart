import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import 'package:freescene_provider_api/freescene_provider_api.dart';

class _Job {
  _Job(
    this.provider,
    this.video,
    this.title,
    this.height,
    this.bandwidth,
    this.filename,
  );
  final String provider, video, title, filename;
  final int height, bandwidth;
  String get id => '$provider-$video-$height-$bandwidth';
  String phase = 'queued', error = '', fingerprint = '', lastHash = '';
  int done = 0, segments = 0, count = 0, lastSize = 0, rate = 0;
  int generation = 0;
  bool wanted = true, running = false;
  StreamClient? client;
  Map<String, dynamic> toJson() => {
    'video': video,
    'title': title,
    'height': height,
    'bandwidth': bandwidth,
    'filename': filename,
    'phase': phase,
    'error': error,
    'fingerprint': fingerprint,
    'lastHash': lastHash,
    'done': done,
    'segments': segments,
    'count': count,
    'lastSize': lastSize,
  };
}

/// Segment-boundary checkpoints make pause/relaunch safe. CDN URLs are never
/// persisted: resuming resolves a fresh public playlist and checks its identity
/// plus the last completed segment before appending to the partial file.
class VideoDownloads {
  VideoDownloads({
    required this.profile,
    required this.directory,
    required this.provider,
    required this.clientFactory,
  }) {
    if (!RegExp(r'^[a-z][a-z0-9_-]{0,63}$').hasMatch(provider)) {
      throw ArgumentError('Invalid provider ID');
    }
  }
  final String provider;
  final Directory profile, directory;
  final StreamClient Function() clientFactory;
  final List<_Job> _jobs = [];
  final Set<StreamClient> _probes = {};
  bool _closed = false;
  int? _slots = 0;
  int _speed = 0;
  int _budgetBytes = 0;
  final Stopwatch _budgetTime = Stopwatch()..start();
  String? persistenceError;
  File get _state => File('${profile.path}/$provider-downloads.json');
  File _file(_Job job, {bool partial = false}) =>
      File('${directory.path}/${job.filename}${partial ? '.part' : ''}');

  bool owns(String id) => _jobs.any((job) => job.id == id);

  void load() {
    try {
      profile.createSync(recursive: true);
      directory.createSync(recursive: true);
      if (!_state.existsSync()) return;
      if (_state.lengthSync() > 4 * 1024 * 1024) throw const FormatException();
      final data = jsonDecode(_state.readAsStringSync()) as Map;
      if (data['version'] != 1) throw const FormatException();
      final restored = <_Job>[];
      for (final row in data['jobs'] as List) {
        final job = _Job(
          provider,
          row['video'] as String,
          row['title'] as String,
          row['height'] as int,
          row['bandwidth'] as int,
          row['filename'] as String,
        );
        if (!RegExp(r'^[a-zA-Z0-9_-]{1,200}$').hasMatch(job.video) ||
            job.height < 1 ||
            job.height > 4320 ||
            job.bandwidth < 1 ||
            job.title.length > 4096 ||
            !job.filename.endsWith('.ts') ||
            job.filename.contains(RegExp(r'[/\\\x00]')) ||
            job.filename.startsWith('.') ||
            restored.any((j) => j.id == job.id)) {
          throw const FormatException();
        }
        job.phase = row['phase'] as String;
        if (![
          'queued',
          'metadata',
          'downloading',
          'paused',
          'completed',
          'failed',
        ].contains(job.phase)) {
          throw const FormatException();
        }
        job.wanted = ['queued', 'metadata', 'downloading'].contains(job.phase);
        if (job.wanted) job.phase = 'queued';
        job.error = row['error'] as String;
        job.done = row['done'] as int;
        job.segments = row['segments'] as int;
        job.count = row['count'] as int;
        job.lastSize = row['lastSize'] as int;
        job.fingerprint = row['fingerprint'] as String;
        job.lastHash = row['lastHash'] as String;
        if (job.done < 0 ||
            job.segments < 0 ||
            job.count < job.segments ||
            job.count > 100000 ||
            job.lastSize < 0 ||
            job.lastSize > job.done ||
            job.segments > 0 &&
                (!RegExp(r'^[a-f0-9]{64}$').hasMatch(job.lastHash) ||
                    !RegExp(r'^[a-f0-9]{64}$').hasMatch(job.fingerprint))) {
          throw const FormatException();
        }
        // Recover a crash between the final rename and the completed checkpoint.
        if (job.count > 0 &&
            job.segments == job.count &&
            _regular(_file(job)) &&
            _file(job).lengthSync() == job.done) {
          job.phase = 'completed';
          job.wanted = false;
        }
        restored.add(job);
      }
      _jobs.addAll(restored);
    } catch (_) {
      throw const StreamDownloadError('disk');
    }
  }

  static bool _regular(File file) =>
      FileSystemEntity.typeSync(file.path, followLinks: false) ==
      FileSystemEntityType.file;

  void _persist() {
    try {
      final temporary = File('${_state.path}.tmp');
      if (FileSystemEntity.isLinkSync(temporary.path) ||
          FileSystemEntity.isLinkSync(_state.path)) {
        throw const FormatException();
      }
      temporary.writeAsStringSync(
        jsonEncode({
          'version': 1,
          'jobs': _jobs.map((j) => j.toJson()).toList(),
        }),
        flush: true,
      );
      temporary.renameSync(_state.path);
      persistenceError = null;
    } catch (_) {
      persistenceError = 'disk';
      throw const StreamDownloadError('disk');
    }
  }

  Future<List<StreamQuality>> qualities(String video) async {
    if (_closed) throw const StreamDownloadError('cancelled');
    final client = clientFactory();
    _probes.add(client);
    try {
      return await client.qualities(video);
    } finally {
      _probes.remove(client);
      client.close();
    }
  }

  String add(String video, String title, StreamQuality quality) {
    if (_closed) throw const StreamDownloadError('cancelled');
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,200}$').hasMatch(video) ||
        quality.height < 1 ||
        quality.height > 4320 ||
        quality.bandwidth < 1) {
      throw const StreamDownloadError('unsupported');
    }
    var safeTitle = '';
    for (final rune
        in title.replaceAll(RegExp(r'[/\\:\x00-\x1f]'), '_').runes) {
      final next = safeTitle + String.fromCharCode(rune);
      if (utf8.encode(next).length > 100) break;
      safeTitle = next;
    }
    safeTitle = safeTitle.replaceFirst(RegExp(r'^[.\s]+'), '').trim();
    if (safeTitle.isEmpty) safeTitle = 'Video';
    final job = _Job(
      provider,
      video,
      title,
      quality.height,
      quality.bandwidth,
      '$safeTitle - ${quality.label} - $video-${DateTime.now().microsecondsSinceEpoch}.ts',
    );
    final existing = _jobs.where((j) => j.id == job.id).firstOrNull;
    if (existing != null) return existing.id;
    _jobs.add(job);
    try {
      _persist();
    } catch (_) {
      _jobs.remove(job);
      rethrow;
    }
    _schedule();
    return job.id;
  }

  void limits({
    required int active,
    required int download,
    int nativeActive = 0,
    int nativeRate = 0,
  }) {
    _slots = active == 0 ? null : math.max(0, active - nativeActive);
    // Reserve the bandwidth currently consumed by torrents. Zero means no cap,
    // while -1 means torrents are already using all available bandwidth.
    _speed = download == 0 ? 0 : math.max(1, download - nativeRate);
    if (download > 0 && nativeRate >= download) _speed = -1;
    _schedule();
  }

  void _schedule() {
    if (_closed) return;
    final eligible = _jobs
        .where((j) => j.wanted)
        .take(_slots ?? _jobs.length)
        .toSet();
    for (final job in _jobs) {
      if (job.running && !eligible.contains(job)) {
        job.generation++;
        job.client?.close();
        if (job.wanted) job.phase = 'queued';
        job.rate = 0;
      }
      if (eligible.contains(job) && !job.running) {
        job.running = true;
        unawaited(_run(job));
      }
    }
  }

  void command(String method, String id, {bool deleteFiles = false}) {
    final job = _jobs.where((j) => j.id == id).firstOrNull;
    if (job == null || _closed) return;
    if (!['pause', 'resume', 'remove'].contains(method)) {
      throw const StreamDownloadError('unsupported');
    }
    job.generation++;
    job.client?.close();
    job.rate = 0;
    if (method == 'remove') {
      job.wanted = false;
      // The filename is generated locally and validated on restore. Never
      // follow symlinks or delete another download's directory.
      try {
        if (deleteFiles) {
          for (final file in [_file(job), _file(job, partial: true)]) {
            if (_regular(file)) file.deleteSync();
          }
        }
      } catch (_) {
        throw const StreamDownloadError('disk');
      }
      _jobs.remove(job);
    } else if (job.phase != 'completed') {
      job.wanted = method == 'resume';
      job.phase = job.wanted ? 'queued' : 'paused';
      job.error = '';
    }
    _persist();
    _schedule();
  }

  String completedFile(String id) {
    final job = _jobs.where((j) => j.id == id).firstOrNull;
    if (job == null ||
        job.phase != 'completed' ||
        !_regular(_file(job)) ||
        _file(job).lengthSync() != job.done) {
      throw const StreamDownloadError('missing');
    }
    return job.filename;
  }

  List<Map<String, dynamic>> snapshots(bool english) => _jobs
      .map(
        (job) => {
          'id': job.id,
          'title': job.title,
          'origin': {'provider': provider},
          'kind': 'hls',
          'phase': job.phase,
          'done': job.done,
          'total': job.phase == 'completed' ? job.done : 0,
          'rate': job.rate,
          'error': job.error.isEmpty
              ? ''
              : StreamDownloadError(job.error).label(english),
          'event': job.phase == 'failed' ? 'downloadFailed' : '',
          'metadata': job.count > 0,
          'quality': '${job.height}p',
          'segments': job.segments,
          'segmentCount': job.count,
          'files': [
            if (job.phase == 'completed')
              {
                'index': 0,
                'name': job.filename,
                'size': job.done,
                'done': job.done,
                'video': true,
              },
          ],
        },
      )
      .toList();

  Future<void> _run(_Job job) async {
    final generation = job.generation;
    final client = clientFactory();
    job.client = client;
    void check() {
      if (_closed || !job.wanted || generation != job.generation) {
        throw const StreamDownloadError('cancelled');
      }
    }

    final clock = Stopwatch()..start();
    var receivedBytes = 0;
    Future<void> received(int length) async {
      check();
      receivedBytes += length;
      _budgetBytes += length;
      job.rate = clock.elapsedMilliseconds < 1
          ? 0
          : receivedBytes * 1000 ~/ clock.elapsedMilliseconds;
      while (!_closed) {
        check();
        final elapsed = _budgetTime.elapsedMilliseconds;
        if (elapsed >= 1000) {
          _budgetBytes = 0;
          _budgetTime.reset();
        }
        if (_speed == 0 || _speed > 0 && _budgetBytes <= _speed) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      check();
    }

    try {
      job.phase = 'metadata';
      job.error = '';
      final qualities = await client.qualities(job.video);
      check();
      final quality = qualities
          .where((q) => q.height == job.height && q.bandwidth == job.bandwidth)
          .firstOrNull;
      if (quality == null) throw const StreamDownloadError('changed');
      final playlist = await client.playlist(quality);
      check();
      final partial = _file(job, partial: true);
      if (job.segments > 0) {
        if (job.fingerprint != playlist.fingerprint ||
            job.count != playlist.segments.length) {
          throw const StreamDownloadError('changed');
        }
        if (!_regular(partial) || partial.lengthSync() < job.done) {
          throw const StreamDownloadError('missing');
        }
        // Verify the local checkpoint too, including edits while the app was off.
        final handle = partial.openSync(mode: FileMode.append);
        try {
          handle.truncateSync(job.done);
        } finally {
          handle.closeSync();
        }
        final input = partial.openSync();
        try {
          input.setPositionSync(job.done - job.lastSize);
          if (sha256.convert(input.readSync(job.lastSize)).toString() !=
              job.lastHash) {
            throw const StreamDownloadError('missing');
          }
        } finally {
          input.closeSync();
        }
        final previous = await client.segment(
          playlist.segments[job.segments - 1],
          received: received,
        );
        check();
        if (sha256.convert(previous).toString() != job.lastHash) {
          throw const StreamDownloadError('changed');
        }
      } else {
        if (FileSystemEntity.isLinkSync(partial.path) ||
            _file(job).existsSync()) {
          throw const StreamDownloadError('disk');
        }
        partial.writeAsBytesSync([], flush: true);
      }
      job.count = playlist.segments.length;
      job.fingerprint = playlist.fingerprint;
      job.phase = 'downloading';
      _persist();
      while (job.segments < job.count) {
        check();
        final data = await client.segment(
          playlist.segments[job.segments],
          received: received,
        );
        check();
        if (!_regular(partial) || partial.lengthSync() != job.done) {
          throw const StreamDownloadError('missing');
        }
        partial.writeAsBytesSync(data, mode: FileMode.append, flush: true);
        job.done += data.length;
        job.segments++;
        job.lastSize = data.length;
        job.lastHash = sha256.convert(data).toString();
        _persist();
      }
      check();
      if (_file(job).existsSync() ||
          FileSystemEntity.isLinkSync(_file(job).path)) {
        throw const StreamDownloadError('disk');
      }
      partial.renameSync(_file(job).path);
      job.phase = 'completed';
      job.wanted = false;
      job.rate = 0;
      _persist();
    } catch (error) {
      if (!_closed && generation == job.generation) {
        job.error = error is StreamDownloadError
            ? error.code
            : error is FileSystemException
            ? 'disk'
            : 'network';
        job.phase = 'failed';
        job.wanted = false;
        job.rate = 0;
        try {
          _persist();
        } catch (_) {
          /* The in-memory error remains visible. */
        }
      }
    } finally {
      client.close();
      job.client = null;
      job.running = false;
      _schedule();
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final client in _probes) {
      client.close();
    }
    for (final job in _jobs) {
      job.generation++;
      job.client?.close();
    }
    // Every committed segment was already persisted, even if macOS terminates
    // the process before Dart receives the shutdown notification.
  }
}
