import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../android/remote_focus.dart';
import '../android/tv_widgets.dart';
import '../catalog/source_format.dart';
import '../domain/provider_display.dart';
import 'watch_history.dart';
import '../widgets/desktop_controls.dart';

class WatchHistoryPage extends StatefulWidget {
  const WatchHistoryPage({
    required this.controller,
    required this.english,
    required this.onBack,
    this.onPlay,
    this.remote,
    this.mobile = false,
    super.key,
  });
  final WatchHistoryController controller;
  final bool english, mobile;
  final VoidCallback onBack;
  final Future<void> Function(WatchEntry)? onPlay;
  final RemoteFocus? remote;
  @override
  State<WatchHistoryPage> createState() => WatchHistoryPageState();
}

class WatchHistoryPageState extends State<WatchHistoryPage> {
  bool selecting = false, confirming = false;
  String? opening;
  final selected = <String>{};
  String tr(String ru, String en) => widget.english ? en : ru;
  bool get tv => widget.remote?.enabled == true;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(changed);
    super.dispose();
  }

  void changed() {
    if (!mounted) return;
    setState(
      () => selected.retainAll(widget.controller.entries.map((e) => e.id)),
    );
    if (!confirming) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.remote?.repair();
      });
    }
  }

  bool exitSelection() {
    if (!selecting || confirming || widget.controller.removing) return false;
    setState(() {
      selecting = false;
      selected.clear();
    });
    widget.remote?.restore('history-select', fallback: 'history-back');
    return true;
  }

  void toggle(String id) {
    if (widget.controller.removing) return;
    setState(() {
      selecting = true;
      if (!selected.add(id)) selected.remove(id);
    });
  }

  Future<void> activateEntry(WatchEntry entry) async {
    if (opening != null || widget.controller.removing) return;
    if (selecting) {
      toggle(entry.id);
      return;
    }
    if (widget.onPlay == null) return;
    setState(() => opening = entry.id);
    try {
      await widget.onPlay!(entry);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                'Не удалось открыть этот источник. Он мог стать недоступен.',
                'Could not open this source. It may no longer be available.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => opening = null);
        widget.remote?.restore(
          'history-row-${entry.id}',
          fallback: 'history-back',
        );
      }
    }
  }

  Widget action(
    String id,
    String label,
    VoidCallback? onPressed, {
    IconData? icon,
  }) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
        Text(label),
      ],
    );
    if (widget.remote != null) {
      if (tv && id == 'history-back') {
        return TvBackButton(
          key: ValueKey(id),
          id: id,
          focus: widget.remote!,
          label: label,
          onPressed: onPressed,
        );
      }
      return RemoteButton(
        key: ValueKey(id),
        id: id,
        focus: widget.remote!,
        radius: tv ? 24 : 12,
        onPressed: onPressed,
        child: child,
      );
    }
    return DesktopActionButton(
      key: ValueKey(id),
      onPressed: onPressed,
      icon: icon ?? Icons.check_rounded,
      label: label,
    );
  }

  Future<void> remove() async {
    final ids = Set<String>.of(selected);
    setState(() => confirming = true);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Удалить записи?', 'Delete entries?')),
        content: Text(
          tr(
            'Будут удалены только записи истории. Загрузки и файлы останутся.',
            'Only history entries will be deleted. Downloads and files will remain.',
          ),
        ),
        actions: [
          TextButton(
            autofocus: tv,
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Отмена', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Удалить', 'Delete')),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => confirming = false);
    if (yes != true) {
      widget.remote?.restore('history-delete');
      return;
    }
    try {
      final count = await widget.controller.remove(ids);
      if (!mounted) return;
      setState(() {
        selected.clear();
        selecting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr('Удалено записей: $count', 'Entries deleted: $count'),
          ),
        ),
      );
      widget.remote?.restore('history-select', fallback: 'history-back');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr('Не удалось удалить записи', 'Could not delete entries'),
            ),
          ),
        );
        widget.remote?.restore('history-delete');
      }
    }
  }

  Widget bubble(String text, Color tint) => Container(
    height: 32,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: tint.withValues(alpha: .1),
      border: Border.all(color: tint.withValues(alpha: .28)),
      borderRadius: BorderRadius.circular(12),
    ),
    constraints: const BoxConstraints(maxWidth: 240),
    child: Tooltip(
      message: text,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: tint),
      ),
    ),
  );
  Widget row(WatchEntry entry) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final stored = storedProviderDisplayLabel(
      entry.provider,
      providerId: entry.data['sourceProvider'] as String?,
    );
    final provider = switch (stored) {
      'Локальный .torrent' ||
      'Local .torrent' => tr('Локальный .torrent', 'Local .torrent'),
      _ => stored,
    };
    final description = [
      if (entry.episodeLabel != null) entry.episodeLabel!,
      if (entry.subtitle != null) entry.subtitle!,
    ].join(' · ');
    final badges = <Widget>[
      if (provider != null && provider != '—')
        bubble(
          provider,
          dark ? const Color(0xff9cb8d6) : const Color(0xff42698e),
        ),
      if (entry.quality != null)
        bubble(entry.quality!, Theme.of(context).colorScheme.primary),
      if (entry.episodeLabel != null)
        bubble(entry.episodeLabel!, Theme.of(context).colorScheme.secondary),
      if ((entry.sizeBytes ?? 0) > 0)
        bubble(
          catalogBytes(entry.sizeBytes),
          dark ? const Color(0xffc1addb) : const Color(0xff70508c),
        ),
    ];
    Widget metadata() => Wrap(
      key: ValueKey('history-badges-${entry.id}'),
      alignment: widget.mobile ? WrapAlignment.start : WrapAlignment.end,
      spacing: 6,
      runSpacing: 6,
      children: badges,
    );
    final content = LayoutBuilder(
      builder: (context, constraints) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (selecting) ...[
            ExcludeFocus(
              child: Checkbox(
                value: selected.contains(entry.id),
                onChanged: widget.controller.removing
                    ? null
                    : (_) => toggle(entry.id),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tooltip(
                  message: entry.title,
                  child: Text(
                    entry.title,
                    key: ValueKey('history-title-${entry.id}'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17),
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Tooltip(
                    message: description,
                    child: Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                if (widget.mobile && badges.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  metadata(),
                ],
              ],
            ),
          ),
          if (!widget.mobile && badges.isNotEmpty) ...[
            const SizedBox(width: 16),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: (constraints.maxWidth - (selecting ? 64 : 0)) * .5,
              ),
              child: metadata(),
            ),
          ],
        ],
      ),
    );
    if (widget.remote != null) {
      return RemoteButton(
        key: ValueKey('history-row-${entry.id}'),
        id: 'history-row-${entry.id}',
        focus: widget.remote!,
        radius: tv ? 22 : 12,
        selected: selected.contains(entry.id),
        onPressed: widget.controller.removing || opening != null
            ? null
            : () => activateEntry(entry),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.all(16),
        child: content,
      );
    }
    return Card(
      child: InkWell(
        key: ValueKey('history-row-${entry.id}'),
        onTap: !widget.controller.removing && opening == null
            ? () => activateEntry(entry)
            : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(padding: const EdgeInsets.all(16), child: content),
      ),
    );
  }

  Widget header(List<Widget> children) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 620) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 8,
                runSpacing: 8,
                children: [children.first, children.last],
              ),
            ),
            const SizedBox(height: 12),
            children[1],
          ],
        );
      }
      return Row(
        children: [
          children.first,
          const SizedBox(width: 16),
          Expanded(child: Center(child: children[1])),
          const SizedBox(width: 16),
          children.last,
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final busy = controller.loading || controller.removing || opening != null;
    final rows = <Object>[];
    String? previousDay;
    for (final entry in controller.entries) {
      final day = watchHistoryDay(entry.watchedAt);
      if (day != previousDay) {
        rows.add(day);
        previousDay = day;
      }
      rows.add(entry);
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!exitSelection() && !confirming) widget.onBack();
        },
      },
      child: Padding(
        padding: EdgeInsets.all(tv ? 24 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header([
              action(
                'history-back',
                tr('Назад', 'Back'),
                controller.removing
                    ? null
                    : () {
                        if (!exitSelection()) widget.onBack();
                      },
                icon: Icons.arrow_back,
              ),
              Text(
                selecting
                    ? tr(
                        'Выбрано: ${selected.length}',
                        'Selected: ${selected.length}',
                      )
                    : tr('История просмотра', 'Watch history'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              action(
                'history-select',
                selecting ? tr('Отмена', 'Cancel') : tr('Выбрать', 'Select'),
                busy || controller.error != null || controller.entries.isEmpty
                    ? null
                    : () {
                        if (!exitSelection()) {
                          setState(() => selecting = true);
                        }
                      },
              ),
            ]),
            if (selecting) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  action(
                    'history-all',
                    tr('Выбрать всё', 'Select all'),
                    busy || selected.length == controller.entries.length
                        ? null
                        : () => setState(
                            () => selected.addAll(
                              controller.entries.map((e) => e.id),
                            ),
                          ),
                  ),
                  action(
                    'history-none',
                    tr('Снять всё', 'Clear selection'),
                    busy || selected.isEmpty
                        ? null
                        : () => setState(selected.clear),
                  ),
                  Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: Theme.of(context).colorScheme.copyWith(
                        primary: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    child: action(
                      'history-delete',
                      tr('Удалить', 'Delete'),
                      busy || selected.isEmpty ? null : remove,
                      icon: Icons.delete_outline,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            if (opening != null) const LinearProgressIndicator(),
            Expanded(
              child: controller.loading && controller.entries.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : controller.error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            tr(
                              'Не удалось загрузить историю',
                              'Could not load history',
                            ),
                          ),
                          const SizedBox(height: 12),
                          action(
                            'history-retry',
                            tr('Повторить', 'Retry'),
                            controller.refresh,
                          ),
                        ],
                      ),
                    )
                  : controller.entries.isEmpty
                  ? Center(
                      child: Text(
                        tr(
                          'История пока пуста. Здесь появятся фильмы и серии после трёх секунд просмотра.',
                          'History is empty. Films and episodes appear after three seconds of playback.',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      key: const ValueKey('watch-history-list'),
                      itemCount: rows.length,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: rows[index] is WatchEntry
                            ? row(rows[index] as WatchEntry)
                            : Padding(
                                padding: const EdgeInsets.only(
                                  top: 12,
                                  bottom: 4,
                                ),
                                child: Semantics(
                                  header: true,
                                  child: Text(
                                    rows[index] as String,
                                    key: ValueKey('history-day-${rows[index]}'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                ),
                              ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
