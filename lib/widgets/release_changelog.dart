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

  static const version = '2.0.0';
  final bool english, tv, mobile;

  @override
  Widget build(BuildContext context) {
    final title = Theme.of(context).textTheme;
    final entries = [
      (
        Icons.palette_outlined,
        english
            ? 'New light and dark themes, rounded posters and an F icon that follows your theme.'
            : 'Светлая и тёмная темы, скруглённые постеры и знак F, который меняет цвета вместе с темой.',
      ),
      if (tv)
        (
          Icons.settings_remote_outlined,
          english
              ? 'Press OK to open a title. Hold OK to watch, save to favorites or add to your queue.'
              : 'Нажмите ОК, чтобы открыть карточку. Удерживайте ОК, чтобы начать просмотр, добавить в избранное или в очередь.',
        )
      else if (mobile)
        (
          Icons.touch_app_outlined,
          english
              ? 'Tap a poster to open it. Hold it to see actions. Your lists are in the bottom navigation.'
              : 'Касание постера открывает карточку, удержание — меню действий. Избранное и очередь доступны в «Списках» на нижней панели.',
        )
      else
        (
          Icons.mouse_outlined,
          english
              ? 'Hover over a poster to add a title to favorites or your queue.'
              : 'Наведите указатель на постер, чтобы добавить фильм в избранное или в очередь.',
        ),
      (
        Icons.motion_photos_on_outlined,
        english
            ? 'You can turn interface animations off in Settings.'
            : 'Анимации интерфейса можно отключить в настройках.',
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
