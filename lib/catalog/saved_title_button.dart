import 'dart:async';

import 'package:flutter/material.dart';

import 'catalog_models.dart';
import 'catalog_tile.dart';
import 'favorites.dart';

/// Shared appearance and rollback feedback for independently saved collections.
class SavedTitleButton extends StatelessWidget {
  const SavedTitleButton({
    required this.title,
    required this.controller,
    required this.addLabel,
    required this.removeLabel,
    required this.failureLabel,
    required this.icon,
    required this.selectedIcon,
    this.overPoster = false,
    super.key,
  });
  final CatalogTitle title;
  final FavoritesController controller;
  final String addLabel, removeLabel, failureLabel;
  final IconData icon, selectedIcon;
  final bool overPoster;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final selected = controller.contains(title);
      final colors = Theme.of(context).colorScheme;
      final button = IconButton.filledTonal(
        tooltip: selected ? removeLabel : addLabel,
        isSelected: selected,
        onPressed: controller.ready && !controller.loading && !controller.saving
            ? () => unawaited(_toggle(context))
            : null,
        style: IconButton.styleFrom(
          fixedSize: const Size.square(38),
          backgroundColor: overPoster
              ? colors.surface.withValues(alpha: 0.94)
              : null,
          foregroundColor: colors.primary,
          shape: const CircleBorder(),
          side: BorderSide(
            color: colors.primary.withValues(alpha: selected ? 0.8 : 0.35),
          ),
        ),
        icon: Icon(selected ? selectedIcon : icon, size: 21),
      );
      return overPoster
          ? CatalogTileAction(selected: selected, child: button)
          : button;
    },
  );

  Future<void> _toggle(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await controller.toggle(title);
    } catch (_) {
      if (messenger.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(failureLabel)));
      }
    }
  }
}
