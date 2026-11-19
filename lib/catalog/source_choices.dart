import 'dart:convert';

import 'catalog_models.dart';
import 'source_checks.dart';
import 'source_seasons.dart';

enum SourceQuality {
  uhd8k('8K'),
  uhd('4K'),
  qhd('1440p'),
  fullHd('1080p'),
  hd('720p'),
  sd('SD'),
  inPlayer(''),
  unknown('');

  const SourceQuality(this.caption);
  final String caption;
  String label(bool english) => switch (this) {
    inPlayer => english ? 'In player' : 'В плеере',
    unknown => english ? 'Not specified' : 'Не указано',
    _ => caption,
  };
}

SourceQuality sourceQuality(CatalogSource source) {
  if (source.row.provider.descriptor?.qualityInPlayer == true) {
    return SourceQuality.inPlayer;
  }
  SourceQuality? parse(String value) {
    final text = value.toLowerCase();
    final dimensions = RegExp(r'(\d{3,4})\s*[xх×]\s*(\d{3,4})')
        .firstMatch(text);
    if (dimensions != null) {
      final width = int.parse(dimensions[1]!);
      final height = int.parse(dimensions[2]!);
      if (width >= 7680 || height >= 4320) return SourceQuality.uhd8k;
      if (width >= 3840 || height >= 2160) return SourceQuality.uhd;
      if (width >= 2560 || height >= 1440) return SourceQuality.qhd;
      if (width >= 1920 || height >= 1080) return SourceQuality.fullHd;
      if (width >= 1280 || height >= 720) return SourceQuality.hd;
      return SourceQuality.sd;
    }
    if (RegExp(r'(^|[^a-z0-9])(8k|4320p?)([^a-z0-9]|$)').hasMatch(text)) {
      return SourceQuality.uhd8k;
    }
    if (RegExp(r'(^|[^a-z0-9])(4k|uhd|2160p?)([^a-z0-9]|$)').hasMatch(text)) {
      return SourceQuality.uhd;
    }
    if (RegExp(r'(^|[^0-9])1440[pi]?([^0-9]|$)').hasMatch(text)) {
      return SourceQuality.qhd;
    }
    if (RegExp(r'(^|[^0-9])1080[pi]?([^0-9]|$)|full\s*hd|\bfhd\b')
        .hasMatch(text)) {
      return SourceQuality.fullHd;
    }
    if (RegExp(r'(^|[^0-9])720[pi]?([^0-9]|$)').hasMatch(text)) {
      return SourceQuality.hd;
    }
    if (RegExp(r'(^|[^0-9])(480|576)[pi]?([^0-9]|$)|\bsd\b').hasMatch(text)) {
      return SourceQuality.sd;
    }
    return null;
  }

  return parse(source.row.quality ?? '') ??
      parse(source.row.title) ??
      SourceQuality.unknown;
}

SourceQuality? automaticQuality(Iterable<SourceQuality> available) {
  final values = available.toSet();
  // Prefer a common TV resolution, without claiming codec/device compatibility.
  for (final quality in [
    SourceQuality.fullHd,
    SourceQuality.hd,
    SourceQuality.sd,
    SourceQuality.qhd,
    SourceQuality.uhd,
    SourceQuality.uhd8k,
    SourceQuality.inPlayer,
    SourceQuality.unknown,
  ]) {
    if (values.contains(quality)) return quality;
  }
  return null;
}

String _normalize(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(RegExp(r'\s+'), ' ');
bool sourceHasMultipleVoices(String? value) {
  if (value == null) return false;
  return RegExp(
            r'(?:перевод|озвучка|audio|translation)\s*\d+',
            caseSensitive: false,
          ).allMatches(value).length >
          1 ||
      RegExp(r'[;|\n]|\s[/+]\s').hasMatch(value);
}

String? _namedVoice(String? value) {
  if (value == null || value.trim().isEmpty || sourceHasMultipleVoices(value)) {
    return null;
  }
  final normalized = _normalize(value);
  final words = normalized
      .split(RegExp(r'[^a-zа-я0-9]+'))
      .where((word) => word.isNotEmpty);
  const generic = {
    'дубляж',
    'дублированный',
    'полное',
    'дублирование',
    'профессиональный',
    'любительский',
    'многоголосый',
    'двухголосый',
    'одноголосый',
    'закадровый',
    'авторский',
    'перевод',
    'озвучка',
    'русский',
    'русская',
    'рус',
    'russian',
    'rus',
    'ru',
    'eng',
    'en',
    'english',
    'английский',
    'оригинал',
    'original',
    'субтитры',
    'субтитрами',
    'с',
    'sub',
    'subs',
    'dub',
    'dubbing',
    'mvo',
    'dvo',
    'avo',
    'vo',
    'd',
    'p',
    'l',
    'ac3',
    'aac',
    'dts',
    'eac3',
    'itunes',
    'netflix',
    'не',
    'указана',
    'неизвестно',
    'unknown',
  };
  if (words.every(
    (word) =>
        generic.contains(word) ||
        RegExp(
          r'^(дубл|профессиональн|любительск|многоголос|двухголос|одноголос|закадров|авторск|перевод|озвуч|русск|английск|субтитр|оригинал|неизвестн)',
        ).hasMatch(word) ||
        int.tryParse(word) != null,
  )) {
    return null;
  }
  return normalized.replaceAll(
    RegExp(r'^lost[ .-]?film(?:\.tv)?$'),
    'lostfilm',
  );
}

class SourceVoiceChoice {
  SourceVoiceChoice(this.key, this.audio, this.sources);
  final String key;
  final String? audio;
  final List<CatalogSource> sources;
  String label(bool english) => sourceHasMultipleVoices(audio)
      ? (english
            ? 'Multiple voices · choose in player'
            : 'Несколько озвучек · выбор в плеере')
      : audio?.trim().isNotEmpty == true
      ? audio!.trim()
      : english
      ? 'Voice not specified'
      : 'Озвучка не указана';
  List<CatalogSource> ranked() {
    int score(CatalogSource source) {
      if (!source.canWatch) return 5;
      return switch (recentSourceCheck(sourceCheckKey(source))?.state) {
        SourceCheckState.data => 0,
        SourceCheckState.checking => 1,
        null => 2,
        SourceCheckState.timeout => 3,
        SourceCheckState.unavailable => 4,
      };
    }

    final ordered = sources.indexed.toList()
      ..sort((a, b) {
        final state = score(a.$2).compareTo(score(b.$2));
        if (state != 0) return state;
        final seeds = (b.$2.row.catalogueCounts.seeds ?? -1).compareTo(
          a.$2.row.catalogueCounts.seeds ?? -1,
        );
        return seeds != 0 ? seeds : a.$1.compareTo(b.$1);
      });
    return ordered.map((entry) => entry.$2).toList();
  }
}

List<SourceVoiceChoice> sourceVoiceChoices(
  List<CatalogSource> sources, {
  required bool series,
}) {
  final groups = <String, SourceVoiceChoice>{};
  for (final source in sources) {
    final voice = _namedVoice(source.audio);
    final seasons = sourceSeasons(source);
    // Unknown translations and unknown series coverage cannot be assumed equal.
    final separate =
        voice == null ||
        (series &&
            (seasons.isEmpty ||
                seasons.any(
                  (season) => sourceEpisodes(source, season: season).isEmpty,
                )));
    final key = jsonEncode([
      sourceQuality(source).name,
      if (separate) sourceCheckKey(source) else voice,
      if (series)
        [
          for (final season in seasons)
            [season, sourceEpisodes(source, season: season)],
        ],
    ]);
    (groups[key] ??= SourceVoiceChoice(
      key,
      source.audio,
      [],
    )).sources.add(source);
  }
  return groups.values.toList();
}
