import 'package:flutter/material.dart';

import 'catalog_models.dart';

/// One poster menu for desktop, phones and TV. The complete action meaning
/// remains available to accessibility while the visible label stays compact.
class TitleContextMenu extends StatelessWidget {
  const TitleContextMenu({
    required this.title,
    required this.english,
    this.favorite,
    this.queued,
    this.watched,
    this.favoriteEnabled = true,
    this.queueEnabled = true,
    super.key,
  });

  final CatalogTitle title;
  final bool english;
  final bool? favorite, queued, watched;
  final bool favoriteEnabled, queueEnabled;

  String tr(String ru, String en) => english ? en : ru;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final style =
        FilledButton.styleFrom(
          backgroundColor: colors.surfaceContainerHigh,
          foregroundColor: colors.onSurface,
          minimumSize: const Size(48, 48),
          shape: const StadiumBorder(),
          textStyle: theme.textTheme.labelLarge?.copyWith(fontSize: 14),
          animationDuration: Duration.zero,
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.focused)
                ? Colors.transparent
                : null,
          ),
          side: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.focused) &&
                    !states.contains(WidgetState.disabled)
                ? BorderSide(color: colors.primary, width: 3)
                : null,
          ),
        );

    Widget item(
      String id,
      IconData icon,
      String verb,
      String meaning, {
      bool first = false,
      bool selected = false,
      bool enabled = true,
    }) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Semantics(
        label: meaning,
        child: FilledButton(
          key: ValueKey('title-menu-$id'),
          autofocus: first,
          style: selected
              ? style.copyWith(
                  backgroundColor: WidgetStatePropertyAll(
                    colors.primaryContainer,
                  ),
                  foregroundColor: WidgetStatePropertyAll(colors.primary),
                )
              : style,
          onPressed: enabled ? () => Navigator.pop(context, id) : null,
          child: ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(verb),
                const SizedBox(width: 10),
                Icon(icon, size: 22),
              ],
            ),
          ),
        ),
      ),
    );

    Widget listItem(
      String id,
      bool saved,
      IconData icon,
      String add,
      String remove,
      bool enabled,
    ) => item(
      id,
      icon,
      saved ? tr('Убрать из', 'Remove from') : tr('Добавить в', 'Add to'),
      saved ? remove : add,
      enabled: enabled,
      selected: saved,
    );

    return AlertDialog(
      scrollable: true,
      title: Text(
        title.title(english),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      content: SizedBox(
        width: 310,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            item(
              'watch',
              Icons.play_arrow_rounded,
              tr('Смотреть', 'Watch'),
              tr('Смотреть', 'Watch'),
              first: true,
            ),
            if (favorite case final saved?)
              listItem(
                'favorite',
                saved,
                Icons.favorite_rounded,
                tr('Добавить в избранное', 'Add to favorites'),
                tr('Убрать из избранного', 'Remove from favorites'),
                favoriteEnabled,
              ),
            if (queued case final saved?)
              listItem(
                'queue',
                saved,
                Icons.playlist_play_rounded,
                tr('Добавить в очередь', 'Add to queue'),
                tr('Убрать из очереди', 'Remove from queue'),
                queueEnabled,
              ),
            if (watched case final marked?)
              item(
                'watched',
                Icons.visibility_outlined,
                marked ? tr('Просмотрено', 'Watched') : tr('Отметить', 'Mark'),
                marked
                    ? tr('Просмотрено', 'Watched')
                    : tr('Отметить просмотренным', 'Mark as watched'),
                enabled: !marked,
                selected: marked,
              ),
          ],
        ),
      ),
    );
  }
}
