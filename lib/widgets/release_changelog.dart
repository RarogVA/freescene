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

  static const version = '2.0.2';
  final bool english, tv, mobile;

  @override
  Widget build(BuildContext context) {
    final title = Theme.of(context).textTheme;
    final entries = [
      (
        Icons.favorite_rounded,
        english
            ? 'Saved favorites, queue items and selected source providers now use the purple focus accent. Provider filters no longer have checkboxes.'
            : 'Избранное, очередь и выбранные провайдеры выделены фиолетовым акцентом фокуса. У фильтров провайдеров убраны галочки.',
      ),
      if (!tv)
        (
          Icons.swipe,
          english
              ? 'Swipe left or right in the catalogue to switch between Films, Series and Games where available.'
              : 'Свайпайте влево и вправо в каталоге для перехода между фильмами, сериалами и играми, если они доступны.',
        ),
      if (mobile)
        (
          Icons.search,
          english
              ? 'Compact search opens over the section switch, with voice search, filters and refresh in one pill.'
              : 'Компактный поиск раскрывается поверх переключателя разделов. Голосовой поиск, фильтры и обновление находятся внутри.',
        ),
      if (!tv && !mobile) ...[
        (
          Icons.mic,
          english
              ? 'Voice search on macOS and fixed icon actions inside search. Poster hover and context menus match TV.'
              : 'Голосовой поиск на macOS и компактные кнопки внутри поиска. Наведение на постеры и контекстное меню приведены к стилю ТВ.',
        ),
        (
          Icons.tune,
          english
              ? 'Back buttons keep page titles in place. Downloads, About and animation settings now use the shared controls style.'
              : 'Кнопка «Назад» больше не сдвигает заголовки. Обновлён стиль кнопок загрузок, «О приложении» и переключателя анимаций.',
        ),
      ],
      if (tv)
        (
          Icons.history,
          english
              ? 'Hold a history entry to open its title or watch. In source results, the first Back press returns focus to the start of the list.'
              : 'Удерживайте запись истории, чтобы перейти к карточке или смотреть. В найденных источниках первое нажатие «Назад» возвращает фокус к началу списка.',
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
