import 'dart:convert';

import 'package:flutter/material.dart';

import '../catalog/catalog_models.dart';
import '../catalog/poster_cache.dart';
import '../catalog/source_checks.dart';
import '../catalog/source_choices.dart';
import 'remote_focus.dart';
import 'source_card.dart';

/// Quality chooses the list; a voice row directly launches its best candidate.
class AndroidSourcePicker extends StatefulWidget {
  const AndroidSourcePicker({
    super.key,
    required this.title,
    required this.sources,
    required this.focus,
    required this.english,
    required this.limit,
    required this.onPlay,
    required this.onCandidates,
    required this.onStop,
    this.selectionKey = '',
    this.onCheck,
    this.onDownload,
    this.posterCache,
    this.previewDecodeWidth = 240,
    this.enabled = true,
  });
  final CatalogTitle title;
  final String selectionKey;
  final List<CatalogSource> sources;
  final RemoteFocus focus;
  final bool english, enabled;
  final int limit, previewDecodeWidth;
  final void Function(CatalogSource) onPlay;
  final void Function(CatalogSource)? onCheck, onDownload;
  final void Function(String, List<CatalogSource>) onCandidates;
  final VoidCallback onStop;
  final PosterDiskCache? posterCache;
  @override
  State<AndroidSourcePicker> createState() => _AndroidSourcePickerState();
}

class _AndroidSourcePickerState extends State<AndroidSourcePicker> {
  SourceQuality? selected;
  final expanded = <String>{};
  String? notified;
  int generation = 0;
  String tr(String ru, String en) => widget.english ? en : ru;

  @override
  void didUpdateWidget(AndroidSourcePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) widget.onStop();
  }

  @override
  void dispose() {
    generation++;
    widget.onStop();
    super.dispose();
  }

  void notifyCandidates(
    SourceQuality? quality,
    List<SourceVoiceChoice> groups,
  ) {
    final candidates = <CatalogSource>[];
    // Check different voices before spending the budget on one voice's backups.
    for (var layer = 0; candidates.length < 3; layer++) {
      var added = false;
      for (final group in groups) {
        final ranked = group
            .ranked()
            .where((s) => s.row.isTorrent && s.canWatch)
            .toList();
        if (layer < ranked.length) {
          candidates.add(ranked[layer]);
          added = true;
        }
        if (candidates.length == 3) break;
      }
      if (!added) break;
    }
    final scope = jsonEncode([
      widget.title.kind.name,
      widget.title.id,
      quality?.name,
      widget.selectionKey,
    ]);
    final inventory = jsonEncode([
      scope,
      for (final group in groups)
        [group.key, for (final s in group.sources) sourceCheckKey(s)],
    ]);
    if (!widget.enabled) {
      notified = null;
      generation++;
      return;
    }
    if (inventory == notified) return;
    notified = inventory;
    final current = ++generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.enabled && generation == current) {
        widget.onCandidates(scope, candidates);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final available = widget.sources.map(sourceQuality).toSet();
    final quality = selected ?? automaticQuality(available);
    final groups = sourceVoiceChoices(
      widget.sources.where((s) => sourceQuality(s) == quality).toList(),
      series: widget.title.kind == CatalogKind.series,
    );
    notifyCandidates(quality, groups);
    Widget qualityButton(SourceQuality? value, String label) => RemoteButton(
      id: 'quality-${value?.name ?? 'auto'}',
      focus: widget.focus,
      selected: selected == value,
      onPressed: widget.enabled
          ? () {
              setState(() {
                selected = value;
                expanded.clear();
              });
            }
          : null,
      child: Text(label),
    );
    Widget card(
      CatalogSource source, {
      SourceVoiceChoice? group,
    }) => AndroidSourceCard(
      source: source,
      title: widget.title,
      focus: widget.focus,
      english: widget.english,
      series: widget.title.kind == CatalogKind.series,
      posterCache: widget.posterCache,
      previewDecodeWidth: widget.previewDecodeWidth,
      displayTitle: group?.label(widget.english),
      actionId: group == null ? null : 'voice-${group.key}',
      onPlay: widget.enabled && source.canWatch
          ? () => widget.onPlay(source)
          : null,
      onCheck: widget.enabled && source.row.isTorrent && widget.onCheck != null
          ? () => widget.onCheck!(source)
          : null,
      onDownload:
          widget.enabled && source.row.isTorrent && widget.onDownload != null
          ? () => widget.onDownload!(source)
          : null,
      alternativesCount: group?.sources.length ?? 0,
      expanded: group != null && expanded.contains(group.key),
      onAlternatives: group != null && group.sources.length > 1
          ? () {
              setState(() {
                if (!expanded.add(group.key)) expanded.remove(group.key);
              });
            }
          : null,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr('Качество', 'Quality'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            qualityButton(
              null,
              '${tr('Авто', 'Auto')}${quality == null || selected != null ? '' : ' · ${quality.label(widget.english)}'}',
            ),
            for (final value in SourceQuality.values)
              if (available.contains(value) || selected == value)
                qualityButton(value, value.label(widget.english)),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          tr('Озвучка', 'Voice'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        if (groups.isEmpty)
          Text(
            tr(
              'Для этого качества вариантов пока нет.',
              'No options for this quality yet.',
            ),
          ),
        for (final group in groups.take(widget.limit))
          Padding(
            key: ValueKey('voice-group-${group.key}'),
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                card(group.ranked().first, group: group),
                if (expanded.contains(group.key))
                  for (final source in group.ranked())
                    Padding(
                      padding: const EdgeInsets.only(left: 16, top: 6),
                      child: card(source),
                    ),
              ],
            ),
          ),
      ],
    );
  }
}
