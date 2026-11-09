import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'native_torrent.dart';
import '../widgets/middle_ellipsis_text.dart';

import 'package:freescene_provider_api/freescene_provider_api.dart';

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({
    required this.controller,
    required this.english,
    this.onBack,
    super.key,
  });
  final TorrentController controller;
  final bool english;
  final VoidCallback? onBack;
  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  String tr(String ru, String en) => widget.english ? en : ru;

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is StreamDownloadError
                ? e.label(widget.english)
                : e is PlatformException
                ? e.message ?? e.code
                : e.toString(),
          ),
        ),
      );
    }
  }

  Future<void> _addTorrent() => _run(() async {
    final source =
        await widget.controller.service.call('chooseTorrent') as String?;
    if (source != null) {
      await widget.controller.command('add', {'source': source});
    }
  });
  Future<void> _addMagnet() async {
    final input = TextEditingController();
    final source = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Добавить magnet', 'Add magnet')),
        content: SizedBox(
          width: 500,
          child: TextField(
            controller: input,
            autofocus: true,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'magnet:?xt=urn:btih:…',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Отмена', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text.trim()),
            child: Text(tr('Добавить', 'Add')),
          ),
        ],
      ),
    );
    // Dispose after the dialog's exit animation releases its text field.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    input.dispose();
    if (source == null || !mounted) return;
    await _run(() async {
      if (!source.startsWith('magnet:?')) {
        throw FormatException(tr('Нужна magnet-ссылка', 'Enter a magnet link'));
      }
      await widget.controller.command('add', {'source': source});
    });
  }

  Future<void> _watch(TorrentTask task) =>
      _run(() => widget.controller.watch(task.id));
  Future<void> _remove(TorrentTask task) async {
    final removeFiles = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        constraints: const BoxConstraints.tightFor(width: 560, height: 180),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 16, 16),
        title: Text(tr('Удалить загрузку?', 'Remove download?')),
        content: SizedBox(
          width: 520,
          height: 40,
          child: MiddleEllipsisText(task.title),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Отмена', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Оставить файлы', 'Keep files')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: Text(tr('Удалить с файлами', 'Delete files')),
          ),
        ],
      ),
    );
    if (removeFiles != null) {
      await _run(() async {
        await widget.controller.command('remove', {
          'id': task.id,
          'deleteFiles': removeFiles,
        });
      });
    }
  }

  static String _bytes(int bytes) => bytes >= 1024 * 1024 * 1024
      ? '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  String _rate(int bytes) => bytes >= 1048576
      ? '${(bytes / 1048576).toStringAsFixed(1)} ${tr('МиБ/с', 'MiB/s')}'
      : bytes >= 1024
      ? '${(bytes / 1024).toStringAsFixed(0)} ${tr('КиБ/с', 'KiB/s')}'
      : '$bytes ${tr('Б/с', 'B/s')}';
  String _phase(String phase) => switch (phase) {
    'metadata' => tr('Получение метаданных', 'Retrieving metadata'),
    'checking' => tr('Проверка файлов', 'Checking files'),
    'queued' => tr('В очереди', 'Queued'),
    'paused' => tr('На паузе', 'Paused'),
    'seeding' => tr('Раздача', 'Seeding'),
    'completed' => tr('Завершено', 'Completed'),
    'failed' => tr('Ошибка', 'Failed'),
    _ => tr('Загрузка', 'Downloading'),
  };

  Widget _header() => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 640;
      final openTorrent = tr('Открыть .torrent', 'Open .torrent');
      final addMagnet = tr('Добавить magnet', 'Add magnet');
      return Row(
        key: const ValueKey('downloads-header'),
        children: [
          IconButton(
            key: const ValueKey('downloads-back'),
            tooltip: tr('Назад', 'Back'),
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr('Загрузки', 'Downloads'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 24 : 28,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (compact) ...[
            IconButton.filled(
              key: const ValueKey('downloads-open-torrent'),
              tooltip: openTorrent,
              onPressed: _addTorrent,
              icon: const Icon(Icons.add),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              key: const ValueKey('downloads-add-magnet'),
              tooltip: addMagnet,
              onPressed: _addMagnet,
              icon: const Icon(Icons.link),
            ),
          ] else ...[
            FilledButton.icon(
              key: const ValueKey('downloads-open-torrent'),
              onPressed: _addTorrent,
              icon: const Icon(Icons.add),
              label: Text(openTorrent),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              key: const ValueKey('downloads-add-magnet'),
              onPressed: _addMagnet,
              icon: const Icon(Icons.link),
              label: Text(addMagnet),
            ),
          ],
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: _header(),
          ),
          Expanded(
            child: ListView(
              key: const ValueKey('downloads-list'),
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              children: [
                if (controller.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      controller.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (controller.loading)
                  const Center(child: CircularProgressIndicator()),
                if (!controller.loading && controller.tasks.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 60),
                    child: Center(
                      child: Text(
                        tr(
                          'Добавьте .torrent или magnet-ссылку',
                          'Add a .torrent or magnet link',
                        ),
                      ),
                    ),
                  ),
                for (final task in controller.tasks)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${tr('Провайдер', 'Provider')}: ${task.origin.localizedLabel(widget.english)} · ${_phase(task.phase)}',
                          ),
                          const SizedBox(height: 12),
                          LinearProgressIndicator(value: task.progress),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 20,
                            runSpacing: 8,
                            children: [
                              if (task.isVideoDownload) ...[
                                Text('${task.quality} · TS'),
                                Text(_bytes(task.done)),
                                if (task.segmentCount > 0)
                                  Text(
                                    '${(100 * task.segments / task.segmentCount).floor()} %',
                                  ),
                                if (task.active) Text('↓ ${_rate(task.rate)}'),
                              ] else ...[
                                Text(
                                  'info: ${task.metadata ? tr('получена', 'received') : tr('ожидание', 'waiting')}',
                                ),
                                Text(
                                  'DHT: ${switch (task.dht) {
                                    'ready' => tr('готова', 'ready'),
                                    'searching' => tr('поиск узлов', 'finding nodes'),
                                    'starting' => tr('запуск', 'starting'),
                                    'disabled' => tr('выключена', 'off'),
                                    'private' => tr('приватный торрент', 'private torrent'),
                                    'error' => tr('недоступна', 'unavailable'),
                                    _ => '—',
                                  }}',
                                ),
                                Text(
                                  '${_bytes(task.done)} / ${task.total > 0 ? _bytes(task.total) : '—'}',
                                ),
                                if (task.active) Text('↓ ${_rate(task.rate)}'),
                                Text(
                                  '${tr('Сиды', 'Seeds')}: ${task.active ? task.seeds?.toString() ?? '—' : '—'}',
                                ),
                                Text(
                                  '${tr('Пиры', 'Peers')}: ${task.active ? task.peers?.toString() ?? '—' : '—'}',
                                ),
                                if (task.active &&
                                    task.rate > 0 &&
                                    task.total > task.done)
                                  Text(
                                    '${tr('Осталось', 'Remaining')}: ${((task.total - task.done) / task.rate / 60).ceil()} ${tr('мин', 'min')}',
                                  ),
                              ],
                            ],
                          ),
                          if (task.error.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: SelectableText(
                                task.error,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed:
                                    (task.isVideoDownload
                                        ? task.phase == 'completed'
                                        : !task.metadata ||
                                              task.videos.isNotEmpty)
                                    ? () => _watch(task)
                                    : null,
                                icon: const Icon(Icons.play_arrow),
                                label: Text(tr('Смотреть', 'Watch')),
                              ),
                              if (!task.isVideoDownload ||
                                  task.phase != 'completed')
                                OutlinedButton(
                                  onPressed: () => _run(() async {
                                    await controller.command(
                                      task.phase == 'paused' ||
                                              task.phase == 'failed' ||
                                              task.error.isNotEmpty
                                          ? 'resume'
                                          : 'pause',
                                      {'id': task.id},
                                    );
                                  }),
                                  child: Text(
                                    task.phase == 'paused'
                                        ? tr('Продолжить', 'Resume')
                                        : task.error.isNotEmpty
                                        ? tr('Повторить', 'Retry')
                                        : tr('Пауза', 'Pause'),
                                  ),
                                ),
                              IconButton(
                                tooltip: tr('Удалить', 'Remove'),
                                onPressed: () => _remove(task),
                                color: Theme.of(context).colorScheme.error,
                                icon: const Icon(Icons.delete_outline),
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
        ],
      );
    },
  );
}

class DownloadLimitsCard extends StatefulWidget {
  const DownloadLimitsCard({
    required this.controller,
    required this.english,
    super.key,
  });
  final TorrentController controller;
  final bool english;
  @override
  State<DownloadLimitsCard> createState() => _DownloadLimitsCardState();
}

class _DownloadLimitsCardState extends State<DownloadLimitsCard> {
  // Stored and transmitted in bytes/s. One decimal Mbit/s = 125000 bytes/s.
  static const speeds = [125000, 375000, 625000, 1250000, 2500000, 0];
  static const counts = [1, 3, 5, 0];
  late int down = widget.controller.limits['download'] as int;
  late int up = widget.controller.limits['upload'] as int;
  late int active = widget.controller.limits['active'] as int;
  String? error;
  bool busy = false, dirty = false;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
  }

  void _sync() {
    if (dirty || busy || !mounted) return;
    setState(() {
      down = widget.controller.limits['download'] as int;
      up = widget.controller.limits['upload'] as int;
      active = widget.controller.limits['active'] as int;
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    super.dispose();
  }

  String tr(String ru, String en) => widget.english ? en : ru;
  Future<void> save() async {
    setState(() => busy = true);
    try {
      await widget.controller.command('limits', {
        'download': down,
        'upload': up,
        'active': active,
      });
      if (mounted) {
        setState(() {
          busy = false;
          dirty = false;
          error = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Ограничения сохранены', 'Limits saved'))),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          busy = false;
        });
      }
    }
  }

  String speedLabel(int bytes) =>
      '${(bytes / 125000).toStringAsFixed(bytes % 125000 == 0 ? 0 : 2)} ${tr('Мбит/с', 'Mbit/s')}';

  Widget field(
    String id,
    String label,
    int value,
    List<int> options,
    void Function(int) changed,
    String Function(int) format,
  ) => SizedBox(
    width: 320,
    child: InputDecorator(
      decoration: InputDecoration(
        enabled: !busy,
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          key: ValueKey('limit-$id'),
          value: value,
          isExpanded: true,
          isDense: true,
          items: [
            // Keep a legacy custom limit until the user chooses a preset.
            if (!options.contains(value))
              DropdownMenuItem(
                value: value,
                child: Text('${tr('Текущее', 'Current')}: ${format(value)}'),
              ),
            for (final option in options)
              DropdownMenuItem(
                value: option,
                child: option == 0
                    ? Semantics(
                        label: tr('Без ограничений', 'Unlimited'),
                        excludeSemantics: true,
                        child: const Icon(Icons.all_inclusive, size: 24),
                      )
                    : Text(format(option)),
              ),
          ],
          onChanged: busy
              ? null
              : (v) => setState(() {
                  dirty = true;
                  changed(v!);
                }),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Ограничения загрузки', 'Download limits'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 24),
          field(
            'active',
            tr('Одновременных загрузок', 'Simultaneous downloads'),
            active,
            counts,
            (v) => active = v,
            (v) => '$v',
          ),
          const SizedBox(height: 20),
          field(
            'download',
            tr('Скорость загрузки', 'Download speed'),
            down,
            speeds,
            (v) => down = v,
            speedLabel,
          ),
          const SizedBox(height: 20),
          field(
            'upload',
            tr('Скорость отдачи', 'Upload speed'),
            up,
            speeds,
            (v) => up = v,
            speedLabel,
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: busy ? null : save,
              child: Text(
                busy ? tr('Сохранение…', 'Saving…') : tr('Сохранить', 'Save'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
