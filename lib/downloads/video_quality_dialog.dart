import 'package:flutter/material.dart';

import 'package:freescene_provider_api/freescene_provider_api.dart';

Future<StreamQuality?> chooseStreamQuality(
  BuildContext context,
  List<StreamQuality> qualities,
  bool english,
) => showDialog<StreamQuality>(
  context: context,
  builder: (context) => AlertDialog(
    scrollable: true,
    title: Text(english ? 'Download video' : 'Скачать видео'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            english
                ? 'Choose quality. The video and audio will be saved as a .ts file in Downloads/FreeScene.'
                : 'Выберите качество. Видео со звуком сохранится в файл .ts в Загрузки/FreeScene.',
          ),
          const SizedBox(height: 16),
          Column(
            children: [
              for (final quality in qualities)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonal(
                      onPressed: () => Navigator.pop(context, quality),
                      child: Text(quality.label),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(english ? 'Cancel' : 'Отмена'),
      ),
    ],
  ),
);
