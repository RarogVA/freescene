import 'dart:async';

import 'package:flutter/material.dart';

import 'catalog_models.dart';
import 'favorites.dart';
import '../widgets/desktop_controls.dart';

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
    this.addGlyph,
    super.key,
  });
  final CatalogTitle title;
  final FavoritesController controller;
  final String addLabel, removeLabel, failureLabel;
  final IconData icon, selectedIcon;
  final Widget? addGlyph;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final selected = controller.contains(title);
      return DesktopActionButton(
        label: selected ? removeLabel : addLabel,
        selected: selected,
        icon: selected ? selectedIcon : icon,
        glyph: selected ? null : addGlyph,
        onPressed: controller.ready && !controller.loading && !controller.saving
            ? () => unawaited(_toggle(context))
            : null,
      );
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
