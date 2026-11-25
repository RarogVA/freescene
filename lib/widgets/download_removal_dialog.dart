import 'package:flutter/material.dart';

import 'middle_ellipsis_text.dart';
import 'removal_dialog.dart';

class DownloadRemovalDialog extends StatelessWidget {
  const DownloadRemovalDialog({
    required this.title,
    required this.english,
    super.key,
  });

  final String title;
  final bool english;

  @override
  Widget build(BuildContext context) {
    return RemovalDialog(
      title: english ? 'Remove download?' : 'Удалить загрузку?',
      content: SizedBox(
        height: MediaQuery.textScalerOf(context).scale(48),
        child: MiddleEllipsisText(title),
      ),
      cancelLabel: english ? 'Cancel' : 'Отмена',
      keepFilesLabel: english ? 'Keep files' : 'Оставить файлы',
      deleteLabel: english ? 'Delete files' : 'Удалить с файлами',
    );
  }
}
