class FilterOption {
  FilterOption(Map<String, dynamic> json)
    : id = '${json['id']}',
      ru = json['ru'] as String,
      en = json['en'] as String,
      ids = ((json['ids'] ?? [json['id']]) as List).map((v) => '$v').toList();
  final String id, ru, en;
  final List<String> ids;
  String label(bool english) => english ? en : ru;
}

class CatalogDictionaries {
  CatalogDictionaries(Map<String, dynamic> json)
    : genres = (json['genres'] as List).map((j) => FilterOption(j)).toList(),
      gameGenres = (json['gameGenres'] as List)
          .map((j) => FilterOption(j))
          .toList(),
      countries = (json['countries'] as List)
          .map((j) => FilterOption(j))
          .toList();
  final List<FilterOption> genres, gameGenres, countries;
  String? translateLabels(String? labels, List<FilterOption> options) {
    if (labels == null) return null;
    final translations = {for (final o in options) o.ru.toLowerCase(): o.en};
    final result = <String>[];
    for (final part in labels.split(RegExp(r'[,;/]'))) {
      final label = part.trim();
      if (label.isNotEmpty) {
        result.add(translations[label.toLowerCase()] ?? label);
      }
    }
    return result.isEmpty ? null : result.join(', ');
  }

  static Future<CatalogDictionaries> Function() loader = () async =>
      CatalogDictionaries({'genres': [], 'gameGenres': [], 'countries': []});
  static Future<CatalogDictionaries> load() => loader();
}
