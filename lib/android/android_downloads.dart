import 'dart:async';

import 'package:flutter/material.dart';

import '../catalog/source_format.dart';
import '../torrent/native_torrent.dart';
import 'android_runtime.dart';
import 'android_search_dialog.dart';
import 'android_torrents.dart';
import 'remote_focus.dart';

class AndroidDownloads extends StatefulWidget {
  const AndroidDownloads({
    required this.focus,
    required this.back,
    required this.english,
    super.key,
  });
  final RemoteFocus focus;
  final VoidCallback back;
  final bool english;
  @override
  State<AndroidDownloads> createState() => _AndroidDownloadsState();
}

class _AndroidDownloadsState extends State<AndroidDownloads> {
  final torrents = const AndroidTorrents();
  List<TorrentTask> tasks = [];
  Timer? timer;
  bool refreshing = false, busy = false;
  String? error;
  String tr(String ru, String en) => widget.english ? en : ru;
  String phase(String value) => widget.english
      ? value
      : switch (value) {
          'metadata' => 'Получение списка файлов',
          'checking' => 'Проверка',
          'downloading' => 'Загрузка',
          'queued' => 'В очереди',
          'paused' => 'На паузе',
          'seeding' => 'Раздача',
          'failed' => 'Ошибка',
          'completed' => 'Завершено',
          _ => value,
        };
  @override
  void initState() {
    super.initState();
    refresh();
    timer = Timer.periodic(const Duration(seconds: 2), (_) => refresh());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    if (refreshing) return;
    refreshing = true;
    try {
      final value = await torrents.tasks();
      if (mounted) {
        setState(() {
          tasks = value;
          error = null;
        });
      }
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = tr(
            'Не удалось получить загрузки. Повторите.',
            'Could not load downloads. Retry.',
          ),
        );
      }
    } finally {
      refreshing = false;
    }
  }

  Future<void> action(Future<void> Function() body) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await body();
      await refresh();
    } catch (failure) {
      if (mounted) setState(() => error = failure.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> addMagnet() async {
    final link = await showDialog<String>(
      context: context,
      builder: (_) => AndroidSearchDialog(
        initial: '',
        english: widget.english,
        allowVoice: false,
        label: 'Magnet',
      ),
    );
    if (!mounted || link == null || link.isEmpty) return;
    await action(() async {
      await AndroidRuntime.channel.invokeMethod('torrentAdd', {
        'magnet': link,
        'origin': {'local': 'magnet'},
      });
    });
    widget.focus.restore('download-magnet');
  }

  Future<void> remove(TorrentTask task) async {
    final choice = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Удалить загрузку?', 'Remove download?')),
        content: SizedBox(
          width: 480,
          child: Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        actions: [
          TextButton(
            autofocus: widget.focus.enabled,
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Отмена', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Оставить файлы', 'Keep files')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Удалить с файлами', 'Delete files')),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) {
      widget.focus.restore('remove-${task.id}');
      return;
    }
    await action(() async {
      await torrents.command('remove', {'id': task.id, 'deleteFiles': choice});
    });
    widget.focus.restore('downloads-back');
  }

  Widget button(
    String id,
    IconData icon,
    String text,
    VoidCallback onPressed,
  ) => RemoteButton(
    id: id,
    focus: widget.focus,
    onPressed: onPressed,
    radius: 20,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon),
        if (text.isNotEmpty) ...[const SizedBox(width: 8), Text(text)],
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            button('downloads-back', Icons.arrow_back, '', widget.back),
            Text(
              tr('Загрузки', 'Downloads'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            button(
              'download-import',
              Icons.add,
              '.torrent',
              () => action(() async {
                await AndroidRuntime.channel.invokeMethod('torrentImport');
              }),
            ),
            button('download-magnet', Icons.link, 'Magnet', addMagnet),
            button('download-refresh', Icons.refresh, '', refresh),
          ],
        ),
      ),
      if (busy) const LinearProgressIndicator(),
      if (error != null)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (tasks.isEmpty)
                Text(tr('Загрузок пока нет', 'No downloads yet')),
              for (final task in tasks)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${task.origin.localizedLabel(widget.english)} · ${phase(task.phase)}',
                        ),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(value: task.progress),
                        const SizedBox(height: 8),
                        Text(
                          '${catalogBytes(task.done)} / ${catalogBytes(task.total)} · ↓ ${task.rate ~/ 1024} КиБ/с · ${tr('Сиды', 'Seeds')}: ${task.seeds ?? '—'} · ${tr('Пиры', 'Peers')}: ${task.peers ?? '—'}',
                        ),
                        if (task.error.isNotEmpty)
                          Text(
                            task.error,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            button(
                              'watch-${task.id}',
                              Icons.play_arrow,
                              tr('Смотреть', 'Watch'),
                              () => action(() => torrents.play(task.id)),
                            ),
                            button(
                              'pause-${task.id}',
                              task.phase == 'paused'
                                  ? Icons.download
                                  : Icons.pause,
                              task.phase == 'paused'
                                  ? tr('Продолжить', 'Resume')
                                  : tr('Пауза', 'Pause'),
                              () => action(() async {
                                await torrents.command(
                                  task.phase == 'paused' ? 'resume' : 'pause',
                                  {'id': task.id},
                                );
                              }),
                            ),
                            RemoteButton(
                              id: 'remove-${task.id}',
                              focus: widget.focus,
                              onPressed: () => remove(task),
                              child: Tooltip(
                                message: tr('Удалить', 'Remove'),
                                child: Icon(
                                  Icons.delete_outline,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}
