import 'package:flutter/material.dart';

import 'catalog_models.dart';
import 'saved_title_button.dart';
import 'watch_queue.dart';

class QueueButton extends StatelessWidget {
  const QueueButton({
    required this.title,
    required this.queue,
    required this.english,
    super.key,
  });
  final CatalogTitle title;
  final QueueController queue;
  final bool english;

  @override
  Widget build(BuildContext context) => SavedTitleButton(
    title: title,
    controller: queue,
    icon: Icons.playlist_add,
    selectedIcon: Icons.playlist_add_check,
    addLabel: english ? 'Add to queue' : 'Добавить в очередь',
    removeLabel: english ? 'Remove from queue' : 'Убрать из очереди',
    failureLabel: english
        ? 'Could not save the queue. Try again.'
        : 'Не удалось сохранить очередь. Повторите попытку.',
  );
}
