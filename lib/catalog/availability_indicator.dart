import 'package:flutter/material.dart';

import '../domain/availability.dart';
import '../domain/source.dart';

class AvailabilityIndicator extends StatelessWidget {
  const AvailabilityIndicator({
    required this.source,
    required this.english,
    super.key,
  });

  final SourceRow source;
  final bool english;

  @override
  Widget build(BuildContext context) {
    if (!source.isTorrent) return const Text('—');
    final counts = source.visibleCounts;
    final bars = TorrentAvailability(counts).bars;
    final level = bars == null
        ? (english ? 'Unknown' : 'Неизвестна')
        : '$bars/5';
    final label = english
        ? 'Availability: $level · Seeds: ${counts.seedsLabel} · Peers: ${counts.peersLabel}\nEstimate from provider data'
        : 'Доступность: $level · Сиды: ${counts.seedsLabel} · Пиры: ${counts.peersLabel}\nОценка по данным провайдера';
    const colors = [
      Color(0xffe05a59),
      Color(0xffe89449),
      Color(0xffd4b34e),
      Color(0xff92b953),
      Color(0xff48af78),
    ];
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        label: label,
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 5; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: Container(
                    width: 5,
                    height: 6.0 + i * 4,
                    decoration: BoxDecoration(
                      color: i < (bars ?? 0)
                          ? colors[i]
                          : Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                ),
              if (bars == null) const Text(' —'),
            ],
          ),
        ),
      ),
    );
  }
}
