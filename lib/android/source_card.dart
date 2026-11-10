import 'package:flutter/material.dart';

import '../catalog/source_metadata.dart';
import '../catalog/watched.dart';
import '../catalog/catalog_models.dart';
import '../catalog/cached_poster.dart';
import '../catalog/poster_cache.dart';
import '../catalog/source_format.dart';
import 'remote_focus.dart';

/// Source metadata and remote/touch actions share one card boundary.
class AndroidSourceCard extends StatelessWidget {
  const AndroidSourceCard({
    required this.source,
    required this.focus,
    required this.english,
    required this.series,
    required this.onPlay,
    this.onDownload,
    this.title,
    this.posterCache,
    this.previewDecodeWidth = 240,
    super.key,
  });
  final CatalogSource source;
  final CatalogTitle? title;
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
    final colors = Theme.of(context).colorScheme;
    final watched = WatchedScope.of(context);
    final marked =
        title != null && watched?.sourceWatched(title!, source) == true;
    Widget action(
      String id,
      IconData icon,
      String label,
      VoidCallback? onPressed,
    ) => RemoteButton(
      id: id,
      focus: focus,
      onPressed: onPressed,
      radius: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 20), const SizedBox(width: 6), Text(label)],
      ),
    );
    return Container(
      key: ValueKey('source-card-${row.provider.name}-${row.id}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, box) {
              final name = Column(
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
                  if (source.channel != null || source.audio != null)
                    Text(
                      [
                        source.channel,
                        source.audio,
                      ].whereType<String>().join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              );
              final metadata = SourceMetadata(source: source, english: english);
              return Row(
                children: [
                  if (row.provider.descriptor?.showThumbnail == true) ...[
                    _preview(context, box.maxWidth >= 600 ? 120 : 72),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: !focus.enabled
                        ? name
                        : box.maxWidth >= 620
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: name,
                                ),
                              ),
                              const SizedBox(width: 16),
                              SizedBox(width: 300, child: metadata),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              name,
                              const SizedBox(height: 8),
                              metadata,
                            ],
                          ),
                  ),
                  if (series && box.maxWidth >= 620)
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: SizedBox(
                        width: 100,
                        child: Text(
                          '${tr('Сезон / серия', 'Season / episode')}\n${sourceEpisodeDisplay(source)}',
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          if (!focus.enabled) ...[
            const SizedBox(height: 8),
            SourceMetadata(source: source, english: english, singleLine: true),
          ],
          if (series)
            LayoutBuilder(
              builder: (context, box) => box.maxWidth >= 620
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${tr('Сезон / серия', 'Season / episode')}: ${sourceEpisodeDisplay(source)}',
                      ),
                    ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    action(
                      'source-${row.provider.name}-${row.id}',
                      Icons.play_arrow,
                      tr('Смотреть', 'Watch'),
                      onPlay,
                    ),
                    if (onDownload != null)
                      action(
                        'download-${row.provider.name}-${row.id}',
                        Icons.download_outlined,
                        tr('Скачать', 'Download'),
                        onDownload,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: tr('Просмотрено', 'Watched'),
                child: RemoteButton(
                  id: 'watched-${row.provider.name}-${row.id}',
                  focus: focus,
                  radius: 24,
                  selected: marked,
                  selectedForeground: colors.primary,
                  onPressed: title == null || watched == null
                      ? null
                      : () async {
                          try {
                            await watched.toggle(title!, source);
                          } catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    tr(
                                      'Не удалось сохранить отметку',
                                      'Could not save watched status',
                                    ),
                                  ),
                                ),
                              );
                            }
                          }
                        },
                  child: Icon(Icons.visibility_outlined, size: 22),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
