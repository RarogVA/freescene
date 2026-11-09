import 'package:flutter/material.dart';

import 'catalog_models.dart';

class CatalogFilterDialog extends StatefulWidget {
  const CatalogFilterDialog({
    required this.initial,
    required this.english,
    this.kind = CatalogKind.movies,
    super.key,
  });
  final CatalogFilter initial;
  final bool english;
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

  Widget options(
    String title,
    String? value,
    List<FilterOption> choices,
    ValueChanged<String?> change,
  ) => DropdownButtonFormField<String>(
    initialValue: choices.any((c) => c.id == value) ? value : null,
    isExpanded: true,
    decoration: InputDecoration(labelText: title),
    items: [
      DropdownMenuItem(value: null, child: Text(tr('Все', 'Any'))),
      for (final c in choices)
        DropdownMenuItem(
          value: c.id,
          child: Text(c.label(widget.english), overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: change,
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
                  if (widget.kind != CatalogKind.games)
                    options(
                      tr('Страна', 'Country'),
                      country,
                      loaded!.countries,
                      (v) => setState(() => country = v),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('filter-year'),
                  controller: year,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: tr('Год / от', 'Year / from'),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: yearTo,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: tr('До (необязательно)', 'To (optional)'),
                  ),
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
          if (widget.kind == CatalogKind.series)
            DropdownButtonFormField<bool>(
              initialValue: ended,
              decoration: InputDecoration(
                labelText: tr('Статус сериала', 'Series status'),
              ),
              items: [
                DropdownMenuItem(value: null, child: Text(tr('Любой', 'Any'))),
                DropdownMenuItem(
                  value: true,
                  child: Text(tr('Завершён', 'Completed')),
                ),
                DropdownMenuItem(
                  value: false,
                  child: Text(tr('Продолжается', 'Ongoing')),
                ),
              ],
              onChanged: (v) => setState(() => ended = v),
            ),
          DropdownButtonFormField<CatalogSort>(
            initialValue: sort,
            decoration: InputDecoration(labelText: tr('Сортировка', 'Sort')),
            items: [
              for (final v in CatalogSort.values)
                DropdownMenuItem(
                  value: v,
                  child: Text(switch (v) {
                    CatalogSort.popularity => tr('Популярность', 'Popularity'),
                    CatalogSort.newest => tr('Новые', 'Newest'),
                    CatalogSort.rating => tr('Рейтинг', 'Rating'),
                    CatalogSort.title => tr('Название', 'Title'),
                  }),
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
