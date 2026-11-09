import 'package:flutter/material.dart';

import 'catalog_models.dart';

/// A single moving thumb keeps the three catalogue sections mutually exclusive.
class CatalogKindSwitch extends StatelessWidget {
  const CatalogKindSwitch({
    required this.value,
    required this.onChanged,
    required this.english,
    super.key,
  });
  final CatalogKind value;
  final ValueChanged<CatalogKind> onChanged;
  final bool english;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 270;
          return Stack(
            children: [
              AnimatedAlign(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOutCubic,
                alignment: Alignment(value.index - 1.0, 0),
                child: FractionallySizedBox(
                  widthFactor: 1 / 3,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final kind in CatalogKind.values)
                    Expanded(
                      child: Semantics(
                        selected: value == kind,
                        child: TextButton(
                          key: ValueKey('catalog-kind-${kind.name}'),
                          onPressed: () => onChanged(kind),
                          style: TextButton.styleFrom(
                            foregroundColor: value == kind
                                ? colors.onPrimary
                                : colors.onSecondaryContainer,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.standard,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            shape: const StadiumBorder(),
                          ),
                          child: Tooltip(
                            message: compact
                                ? switch (kind) {
                                    CatalogKind.movies =>
                                      english ? 'Films' : 'Фильмы',
                                    CatalogKind.series =>
                                      english ? 'Series' : 'Сериалы',
                                    CatalogKind.games =>
                                      english ? 'Games' : 'Игры',
                                  }
                                : '',
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(switch (kind) {
                                  CatalogKind.movies =>
                                    Icons.local_movies_outlined,
                                  CatalogKind.series => Icons.tv_outlined,
                                  CatalogKind.games =>
                                    Icons.sports_esports_outlined,
                                }, size: 19),
                                if (!compact) ...[
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      switch (kind) {
                                        CatalogKind.movies =>
                                          english ? 'Films' : 'Фильмы',
                                        CatalogKind.series =>
                                          english ? 'Series' : 'Сериалы',
                                        CatalogKind.games =>
                                          english ? 'Games' : 'Игры',
                                      },
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
