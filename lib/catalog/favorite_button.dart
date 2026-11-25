import 'package:flutter/material.dart';

import 'catalog_models.dart';
import 'favorites.dart';
import 'saved_title_button.dart';

class FavoriteButton extends StatelessWidget {
  const FavoriteButton({
    required this.title,
    required this.favorites,
    required this.english,
    super.key,
  });
  final CatalogTitle title;
  final FavoritesController favorites;
  final bool english;

  @override
  Widget build(BuildContext context) => SavedTitleButton(
    title: title,
    controller: favorites,
    icon: Icons.favorite_border,
    addGlyph: const AddFavoriteIcon(),
    selectedIcon: Icons.favorite,
    addLabel: english ? 'Add to favorites' : 'Добавить в избранное',
    removeLabel: english ? 'Remove from favorites' : 'Убрать из избранного',
    failureLabel: english
        ? 'Could not save favorites. Try again.'
        : 'Не удалось сохранить избранное. Повторите попытку.',
  );
}

/// The add badge distinguishes saving a title from opening the favorites list.
class AddFavoriteIcon extends StatelessWidget {
  const AddFavoriteIcon({super.key});
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 20,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(Icons.favorite_border_rounded, size: 20),
        Positioned(
          right: -3,
          bottom: -2,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.add_rounded, size: 12),
          ),
        ),
      ],
    ),
  );
}
