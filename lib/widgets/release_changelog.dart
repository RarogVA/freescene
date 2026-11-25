import 'package:flutter/material.dart';

import 'catalog_style.dart';

/// A new set of release notes gets its own version and acknowledgement.
class ReleaseChangelog extends StatelessWidget {
  const ReleaseChangelog({
    required this.english,
    this.tv = false,
    this.mobile = false,
    super.key,
  });

  static const version = '2.0.4';
  final bool english, tv, mobile;

  @override
  Widget build(BuildContext context) {
    final title = Theme.of(context).textTheme;
    final entries = [
      (
        Icons.audiotrack_outlined,
        english
            ? 'With English selected in FreeScene, the player prefers English audio, then a track marked as original. You can still choose another track.'
            : 'Если в FreeScene выбран английский язык, плеер предпочитает английскую дорожку, а затем оригинальную. Дорожку можно сменить вручную.',
      ),
      (
        Icons.translate_rounded,
        english
            ? 'Player controls, menus and torrent status follow the app language. Title pages show English genres and descriptions when available.'
            : 'Кнопки и меню плеера, а также статус торрента учитывают язык приложения. В английском режиме карточки показывают жанры и доступные описания на английском.',
      ),
      if (!tv && !mobile)
        (
          Icons.movie_outlined,
          english
              ? 'Title pages and search results now follow the TV layout. Hover over a result to watch or download. Season and episode filters appear below the result count.'
              : 'Карточки и список найденного оформлены в стиле ТВ. Наведите курсор на результат, чтобы посмотреть или скачать. Фильтры сезона и серии находятся под счётчиком результатов.',
        ),
      if (!tv && !mobile)
        (
          Icons.favorite_outline,
          english
              ? 'Posters show watched, favorite and queue status. Right-click or press and hold to manage these from the tile menu.'
              : 'На постерах видны отметки просмотра, избранного и очереди. Для действий с плиткой откройте меню правым кликом или долгим нажатием.',
        ),
      if (tv)
        (
          Icons.live_tv_outlined,
          english
              ? 'The Play button appears when a search result receives focus. Pressing and holding a tile shows the hold animation again.'
              : 'Кнопка воспроизведения появляется при фокусе на результате поиска. При удержании плитки снова видна анимация.',
        ),
      (
        Icons.delete_outline_rounded,
        english
            ? 'The dialogs for deleting history entries and downloads now use matching buttons. Cancel receives focus first.'
            : 'Окна удаления записей истории и загрузок получили единые кнопки. При открытии выбрана «Отмена».',
      ),
    ];
    return AlertDialog(
      scrollable: true,
      title: Row(
        children: [
          const BrandIcon(size: 44),
          const SizedBox(width: 14),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Changelog'),
                Text('FreeScene $version', style: title.bodyMedium),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      entry.$1,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(entry.$2)),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context),
          child: Text(english ? 'Got it' : 'Понятно'),
        ),
      ],
    );
  }
}
