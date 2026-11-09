import 'package:flutter/material.dart';

import 'catalog_models.dart';
import 'favorites.dart';
import 'saved_title_button.dart';

class FavoriteButton extends StatelessWidget {
  const FavoriteButton({
    required this.title,
    required this.favorites,
    required this.english,
    this.overPoster = false,
    super.key,
  });
  final CatalogTitle title;
  final FavoritesController favorites;
  final bool english, overPoster;

  @override
  Widget build(BuildContext context) => SavedTitleButton(
    title: title,
    controller: favorites,
    overPoster: overPoster,
    icon: Icons.favorite_border,
    selectedIcon: Icons.favorite,
    addLabel: english ? 'Add to favorites' : 'Добавить в избранное',
    removeLabel: english ? 'Remove from favorites' : 'Убрать из избранного',
    failureLabel: english
        ? 'Could not save favorites. Try again.'
        : 'Не удалось сохранить избранное. Повторите попытку.',
  );
}
