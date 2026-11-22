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

  static const version = '2.0.3';
  final bool english, tv, mobile;

  @override
  Widget build(BuildContext context) {
    final title = Theme.of(context).textTheme;
    final entries = [
      (
        Icons.info_outline,
        english
            ? 'Updated the About screen.'
            : 'Обновлено окно «О приложении».',
      ),
      if (!tv && !mobile)
        (
          Icons.mic,
          english
              ? 'Voice search now explains when macOS Dictation is disabled or speech recognition files are missing, and offers a shortcut to settings.'
              : 'Голосовой поиск объясняет, когда в macOS отключена Диктовка или отсутствуют файлы распознавания, и предлагает перейти к настройкам.',
        ),
      if (tv)
        (
          Icons.sync_rounded,
          english
              ? 'Update and license buttons now have icons matching the desktop app.'
              : 'Кнопки обновлений и лицензий получили значки в стиле десктопного приложения.',
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
