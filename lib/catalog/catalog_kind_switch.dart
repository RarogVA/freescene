import 'package:flutter/material.dart';

import '../widgets/catalog_style.dart';
import 'catalog_models.dart';

/// A single moving thumb keeps the three catalogue sections mutually exclusive.
class CatalogKindSwitch extends StatelessWidget {
  const CatalogKindSwitch({
    required this.value,
    required this.onChanged,
    required this.english,
    this.kinds = CatalogKind.values,
    super.key,
  });
  final CatalogKind value;
  final ValueChanged<CatalogKind> onChanged;
  final bool english;
  final List<CatalogKind> kinds;

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
              CatalogSelectionThumb(
                index: kinds.indexOf(value),
                count: kinds.length,
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final kind in kinds)
                    Expanded(
                      child: Semantics(
                        selected: value == kind,
                        child: TextButton(
                          key: ValueKey('catalog-kind-${kind.name}'),
                          onPressed: () => onChanged(kind),
                          style: TextButton.styleFrom(
                            foregroundColor: value == kind
                                ? colors.surface
                                : colors.onSecondaryContainer,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.standard,
                            padding: EdgeInsets.symmetric(
                              horizontal: compact ? 0 : 8,
                            ),
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
