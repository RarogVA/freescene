import 'package:flutter/material.dart';

import 'catalog_models.dart';
import 'source_filter.dart';

class SourceChoices {
  const SourceChoices({this.providers, this.qualities, this.seasons});
  final Set<SourceProvider>? providers;
  final Set<String>? qualities;
  final Set<int>? seasons;
  bool matches(CatalogSource s) =>
      (providers == null || providers!.contains(s.row.provider)) &&
      (s.row.provider.descriptor?.qualityInPlayer == true ||
          qualities == null ||
          qualities!.contains(s.row.quality ?? '—')) &&
      (seasons == null || sourceSeasons(s).any(seasons!.contains));
}

class SourceFilterDialog extends StatefulWidget {
  const SourceFilterDialog({
    required this.sources,
    required this.value,
    required this.english,
    required this.series,
    super.key,
  });
  final List<CatalogSource> sources;
  final SourceChoices value;
  final bool english, series;
  @override
  State<SourceFilterDialog> createState() => _SourceFilterDialogState();
}

class _SourceFilterDialogState extends State<SourceFilterDialog> {
  late final providers =
      widget.sources.map((s) => s.row.provider).toSet().toList()
        ..sort((a, b) => a.label.compareTo(b.label));
  late final qualities =
      widget.sources
          .where((s) => s.row.provider.descriptor?.qualityInPlayer != true)
          .map((s) => s.row.quality ?? '—')
          .toSet()
          .toList()
        ..sort();
  late final seasons = widget.sources.expand(sourceSeasons).toSet().toList()
    ..sort();
  late Set<SourceProvider> selectedProviders = {
    ...?widget.value.providers,
    if (widget.value.providers == null) ...providers,
  };
  late Set<String> selectedQualities = {
    ...?widget.value.qualities,
    if (widget.value.qualities == null) ...qualities,
  };
  late Set<int> selectedSeasons = {
    ...?widget.value.seasons,
    if (widget.value.seasons == null) ...seasons,
  };
  String tr(String ru, String en) => widget.english ? en : ru;
  Widget group<T>(
    String title,
    List<T> values,
    Set<T> selected,
    String Function(T) label,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      for (final value in values)
        CheckboxListTile(
          dense: true,
          title: Text(label(value)),
          value: selected.contains(value),
          onChanged: (checked) => setState(
            () =>
                checked == true ? selected.add(value) : selected.remove(value),
          ),
        ),
    ],
  );
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr('Фильтр источников', 'Source filters')),
    content: SizedBox(
      width: 460,
      height: 460,
      child: ListView(
        children: [
          group(
            tr('Провайдер', 'Provider'),
            providers,
            selectedProviders,
            (p) => p.label,
          ),
          if (widget.sources.any(
            (s) =>
                s.row.provider.descriptor?.qualityInPlayer != true &&
                selectedProviders.contains(s.row.provider),
          ))
            group(
              tr('Качество', 'Quality'),
              qualities,
              selectedQualities,
              (q) => q,
            ),
          if (widget.series)
            group(
              tr('Сезон', 'Season'),
              seasons,
              selectedSeasons,
              (s) => s < 0 ? tr('Не указан', 'Unknown') : '$s',
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => setState(() {
          selectedProviders = providers.toSet();
          selectedQualities = qualities.toSet();
          selectedSeasons = seasons.toSet();
        }),
        child: Text(tr('Выбрать всё', 'Select all')),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr('Отмена', 'Cancel')),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          SourceChoices(
            providers: selectedProviders.containsAll(providers)
                ? null
                : selectedProviders,
            qualities: selectedQualities.containsAll(qualities)
                ? null
                : selectedQualities,
            seasons: !widget.series || selectedSeasons.containsAll(seasons)
                ? null
                : selectedSeasons,
          ),
        ),
        child: Text(tr('Применить', 'Apply')),
      ),
    ],
  );
}
