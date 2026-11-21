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

  static const version = '2.0.1';
  final bool english, tv, mobile;

  @override
  Widget build(BuildContext context) {
    final title = Theme.of(context).textTheme;
    final entries = [
      (
        Icons.filter_alt_outlined,
        english
            ? 'Filter fields no longer overlap. The country picker now includes “Exclude Russia” on phones and desktop.'
            : 'Поля фильтра больше не накладываются друг на друга. «Не Россия» теперь доступна на телефонах и компьютерах.',
      ),
      if (!tv && !mobile) ...[
        (
          Icons.touch_app_outlined,
          english
              ? 'Hold a poster, use a secondary click or Force Click on the trackpad to open its action menu.'
              : 'Удерживайте постер или используйте вторичный клик либо Force Click трекпада, чтобы открыть меню действий.',
        ),
        (
          Icons.motion_photos_on_outlined,
          english
              ? 'A TV-style catalogue header and rounded controls with animated labels, search, season and episode filters. Turn animations off in Settings.'
              : 'Шапка каталога в стиле ТВ и круглые кнопки с раскрытием подписей. Обновлены поиск, сезоны, серии и список найденного. Анимации можно отключить в настройках.',
        ),
      ],
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
