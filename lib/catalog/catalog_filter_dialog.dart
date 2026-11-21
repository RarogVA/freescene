import 'package:flutter/material.dart';

import 'catalog_models.dart';

class CatalogFilterDialog extends StatefulWidget {
  const CatalogFilterDialog({
    required this.initial,
    required this.english,
    this.tv = false,
    this.kind = CatalogKind.movies,
    super.key,
  });
  final CatalogFilter initial;
  final bool english, tv;
  final CatalogKind kind;
  @override
  State<CatalogFilterDialog> createState() => _CatalogFilterDialogState();
}

class _CatalogFilterDialogState extends State<CatalogFilterDialog> {
  late final year = TextEditingController(
    text: widget.initial.year?.toString() ?? '',
  );
  late final yearTo = TextEditingController(
    text: widget.initial.yearTo?.toString() ?? '',
  );
  late RangeValues rating = RangeValues(
    widget.initial.minRating,
    widget.initial.maxRating,
  );
  late CatalogSort sort = widget.initial.sort;
  late String? genre = widget.initial.genre, country = widget.initial.country;
  late bool hd = widget.initial.highQualityOnly;
  late bool? ended = widget.initial.ended;
  final dictionaries = CatalogDictionaries.load();
  CatalogDictionaries? loaded;
  String? error;
  String tr(String ru, String en) => widget.english ? en : ru;
  @override
  void dispose() {
    year.dispose();
    yearTo.dispose();
    super.dispose();
  }

  void apply() {
    final from = year.text.trim().isEmpty
        ? null
        : int.tryParse(year.text.trim());
    final to = yearTo.text.trim().isEmpty
        ? null
        : int.tryParse(yearTo.text.trim());
    if ((year.text.trim().isNotEmpty &&
            (from == null || from < 1888 || from > DateTime.now().year + 2)) ||
        (yearTo.text.trim().isNotEmpty &&
            (to == null ||
                to < (from ?? 1888) ||
                to > DateTime.now().year + 2))) {
      setState(
        () => error = tr('Проверьте диапазон годов', 'Check the year range'),
      );
      return;
    }
    Navigator.pop(
      context,
      CatalogFilter(
        year: from,
        yearTo: to,
        minRating: rating.start,
        maxRating: rating.end,
        sort: sort,
        genre: genre,
        country: country,
        countryIds:
            loaded?.countries.where((c) => c.id == country).firstOrNull?.ids ??
            [],
        highQualityOnly: hd,
        ended: ended,
      ),
    );
  }

  Widget yearField(String key, String label, TextEditingController value) {
    if (!widget.tv) {
      return TextField(
        key: ValueKey(key),
        controller: value,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
      );
    }
    return OutlinedButton(
      key: ValueKey(key),
      onPressed: () async {
        var draft = value.text;
        final result = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            scrollable: true,
            title: Text(label),
            content: TextFormField(
              initialValue: draft,
              autofocus: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onChanged: (v) => draft = v,
              onFieldSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('Отмена', 'Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, draft),
                child: Text(tr('Готово', 'Done')),
              ),
            ],
          ),
        );
        if (mounted && result != null) setState(() => value.text = result);
      },
      child: Text('$label · ${value.text.isEmpty ? '—' : value.text}'),
    );
  }

  Widget choiceField<T>({
    required String label,
    required T? value,
    required List<({T? value, String label})> choices,
    required ValueChanged<T?> onChanged,
  }) {
    final current = choices.indexWhere((entry) => entry.value == value);
    if (!widget.tv) {
      return DropdownButtonFormField<T>(
        initialValue: current < 0 ? null : value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final entry in choices)
            DropdownMenuItem(
              value: entry.value,
              child: Text(entry.label, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      );
    }
    final index = current < 0
        ? choices.indexWhere((entry) => entry.value == null)
        : current;
    return _TvFilterPicker(
      label: label,
      choices: [for (final e in choices) e.label],
      selected: index,
      onChanged: (i) => onChanged(choices[i].value),
    );
  }

  Widget options(
    String title,
    String? value,
    List<FilterOption> choices,
    ValueChanged<String?> change, {
    bool countryPicker = false,
  }) => choiceField<String>(
    label: title,
    value: value,
    onChanged: change,
    choices: [
      if (countryPicker)
        (
          value: CatalogFilter.outsideFourCountries,
          label: tr('Не Россия', 'Exclude Russia and selected countries'),
        ),
      (value: null, label: tr('Все', 'Any')),
      for (final c in choices) (value: c.id, label: c.label(widget.english)),
    ],
  );
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr('Фильтр', 'Filter')),
    scrollable: true,
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FutureBuilder<CatalogDictionaries>(
            future: dictionaries,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return snapshot.hasError
                    ? Text(
                        tr(
                          'Справочники недоступны',
                          'Dictionaries unavailable',
                        ),
                      )
                    : const LinearProgressIndicator();
              }
              loaded = snapshot.data!;
              return Column(
                children: [
                  options(
                    tr('Жанр', 'Genre'),
                    genre,
                    widget.kind == CatalogKind.games
                        ? loaded!.gameGenres
                        : loaded!.genres,
                    (v) => setState(() => genre = v),
                  ),
                  if (widget.kind != CatalogKind.games) ...[
                    const SizedBox(height: 20),
                    options(
                      tr('Страна', 'Country'),
                      country,
                      loaded!.countries,
                      (v) => setState(() => country = v),
                      countryPicker: true,
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: yearField(
                  'filter-year',
                  tr('Год от', 'From year'),
                  year,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: yearField(
                  'filter-year-to',
                  tr('Год до', 'To year'),
                  yearTo,
                ),
              ),
            ],
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 20),
          Text(
            '${tr('Рейтинг', 'Rating')}: ${rating.start.toStringAsFixed(1)}–${rating.end.toStringAsFixed(1)}',
          ),
          RangeSlider(
            values: rating,
            min: 0,
            max: 10,
            divisions: 20,
            labels: RangeLabels('${rating.start}', '${rating.end}'),
            onChanged: (v) => setState(() => rating = v),
          ),
          if (widget.kind != CatalogKind.games)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                tr(
                  'Высокое качество видео и звука',
                  'High video and audio quality',
                ),
              ),
              value: hd,
              onChanged: (v) => setState(() => hd = v!),
            ),
          const SizedBox(height: 20),
          if (widget.kind == CatalogKind.series)
            choiceField<bool>(
              value: ended,
              label: tr('Статус сериала', 'Series status'),
              choices: [
                (value: null, label: tr('Любой', 'Any')),
                (value: true, label: tr('Завершён', 'Completed')),
                (value: false, label: tr('Продолжается', 'Ongoing')),
              ],
              onChanged: (v) => setState(() => ended = v),
            ),
          if (widget.kind == CatalogKind.series) const SizedBox(height: 20),
          choiceField<CatalogSort>(
            value: sort,
            label: tr('Сортировка', 'Sort'),
            choices: [
              for (final v in CatalogSort.values)
                (
                  value: v,
                  label: switch (v) {
                    CatalogSort.popularity => tr('Популярность', 'Popularity'),
                    CatalogSort.newest => tr('Новые', 'Newest'),
                    CatalogSort.rating => tr('Рейтинг', 'Rating'),
                    CatalogSort.title => tr('Название', 'Title'),
                  },
                ),
            ],
            onChanged: (v) => setState(() => sort = v!),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, const CatalogFilter()),
        child: Text(tr('Сбросить', 'Reset')),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr('Отмена', 'Cancel')),
      ),
      FilledButton(onPressed: apply, child: Text(tr('Применить', 'Apply'))),
    ],
  );
}

class _TvFilterPicker extends StatelessWidget {
  const _TvFilterPicker({
    required this.label,
    required this.choices,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final List<String> choices;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = ButtonStyle(
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? colors.primary
            : colors.surfaceContainerHigh,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? colors.onPrimary
            : colors.onSurface,
      ),
    );
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: style,
        onPressed: () async {
          final choice = await showDialog<int>(
            context: context,
            animationStyle: MediaQuery.disableAnimationsOf(context)
                ? AnimationStyle.noAnimation
                : null,
            builder: (dialog) => SimpleDialog(
              title: Text(label),
              contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              children: [
                for (var i = 0; i < choices.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Builder(
                      builder: (row) => Semantics(
                        selected: i == selected,
                        child: FilledButton(
                          autofocus: i == selected,
                          style: style,
                          onFocusChange: (focused) {
                            if (focused) {
                              Scrollable.ensureVisible(row, alignment: .5);
                            }
                          },
                          onPressed: () => Navigator.pop(dialog, i),
                          child: Row(
                            children: [
                              Expanded(child: Text(choices[i])),
                              if (i == selected)
                                const Icon(Icons.check_rounded),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
          if (context.mounted && choice != null) onChanged(choice);
        },
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: Text(choices[selected], textAlign: TextAlign.end),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.expand_more_rounded),
          ],
        ),
      ),
    );
  }
}
