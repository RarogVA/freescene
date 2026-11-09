import 'package:flutter/material.dart';

import '../catalog/availability_indicator.dart';
import '../catalog/catalog_models.dart';
import '../catalog/cached_poster.dart';
import '../catalog/poster_cache.dart';
import '../catalog/source_format.dart';
import 'remote_focus.dart';

/// A whole source is one remote target; metadata wraps on narrow screens.
class AndroidSourceCard extends StatelessWidget {
  const AndroidSourceCard({
    required this.source,
    required this.focus,
    required this.english,
    required this.series,
    required this.onPlay,
    this.onDownload,
    this.posterCache,
    this.previewDecodeWidth = 240,
    super.key,
  });
  final CatalogSource source;
  final RemoteFocus focus;
  final bool english, series;
  final VoidCallback? onPlay, onDownload;
  final PosterDiskCache? posterCache;
  final int previewDecodeWidth;
  String tr(String ru, String en) => english ? en : ru;

  Widget _preview(BuildContext context, double width) {
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.ondemand_video, size: 28)),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: width,
        height: width * 9 / 16,
        child: source.thumbnail == null
            ? placeholder
            : CachedPoster(
                uri: source.thumbnail!,
                cache: posterCache,
                decodeWidth: previewDecodeWidth,
                placeholder: placeholder,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final row = source.row;
    final card = RemoteButton(
      id: 'source-${row.provider.name}-${row.id}',
      focus: focus,
      onPressed: onPlay,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            if (row.provider.descriptor?.showThumbnail == true)
              _preview(context, constraints.maxWidth >= 600 ? 160 : 88)
            else
              const Icon(Icons.play_arrow, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Tooltip(
                    message: row.title,
                    child: Text(
                      row.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 20,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(row.provider.label),
                      if (row.provider.descriptor?.qualityInPlayer != true)
                        Text(
                          '${tr('Качество', 'Quality')}: ${row.quality ?? '—'}',
                        ),
                      Text(
                        '${tr('Длительность', 'Duration')}: ${sourceDuration(row.durationSeconds)}',
                      ),
                      Text(
                        '${tr('Размер', 'Size')}: ${catalogBytes(row.sizeBytes)}',
                      ),
                      if (series)
                        Text(
                          '${tr('Сезон / серия', 'Season / episode')}: ${sourceEpisodeDisplay(source)}',
                        ),
                      if (row.isTorrent)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${tr('Доступность', 'Availability')}: '),
                            AvailabilityIndicator(
                              source: row,
                              english: english,
                            ),
                          ],
                        ),
                    ],
                  ),
                  if (source.channel != null || source.audio != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      [
                        source.channel,
                        source.audio,
                      ].whereType<String>().join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (onDownload == null) return card;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        RemoteButton(
          id: 'download-${row.provider.name}-${row.id}',
          focus: focus,
          onPressed: onDownload,
          radius: 28,
          child: Tooltip(
            message: tr('Скачать', 'Download'),
            child: const Icon(Icons.download),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: card),
      ],
    );
  }
}
