import 'package:flutter/material.dart';

class RemovalDialog extends StatelessWidget {
  const RemovalDialog({
    required this.title,
    required this.content,
    required this.cancelLabel,
    required this.deleteLabel,
    this.keepFilesLabel,
    super.key,
  });

  final String title;
  final Widget content;
  final String cancelLabel;
  final String deleteLabel;
  final String? keepFilesLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      backgroundColor: colors.surfaceContainerHigh,
      foregroundColor: colors.onSurface,
      side: BorderSide(color: colors.outlineVariant),
      shape: const StadiumBorder(),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    );
    return AlertDialog(
      constraints: const BoxConstraints(maxWidth: 608),
      backgroundColor: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colors.outlineVariant),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      actionsOverflowButtonSpacing: 8,
      title: Text(title),
      titleTextStyle: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: colors.onSurface,
      ),
      content: SizedBox(width: 560, child: content),
      actions: [
        OutlinedButton.icon(
          autofocus: true,
          style: style,
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded, size: 20),
          label: Text(cancelLabel),
        ),
        if (keepFilesLabel case final label?)
          OutlinedButton.icon(
            style: style,
            onPressed: () => Navigator.pop(context, false),
            icon: const Icon(Icons.folder_outlined, size: 20),
            label: Text(label),
          ),
        OutlinedButton.icon(
          style: style.copyWith(
            backgroundColor: WidgetStatePropertyAll(colors.errorContainer),
            foregroundColor: WidgetStatePropertyAll(colors.onErrorContainer),
            side: WidgetStatePropertyAll(
              BorderSide(color: colors.error.withValues(alpha: .5)),
            ),
          ),
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.delete_outline_rounded, size: 20),
          label: Text(deleteLabel),
        ),
      ],
    );
  }
}
