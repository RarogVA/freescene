/// Explicit season/episode markings only; a release range is not a file list.
class SeriesCoverage {
  SeriesCoverage._(this._spans);
  final List<_Span> _spans;

  Set<int> get seasons => {
    for (final span in _spans)
      for (var i = span.season; i <= span.lastSeason; i++) i,
  };
  int get firstSeason => _spans.first.season;
  int? get firstEpisode => _spans.first.episode;
  int? get singleEpisode {
    if (_spans.any(
      (s) => s.cross || s.episode == null || s.episode != s.lastEpisode,
    )) {
      return null;
    }
    final episodes = _spans.map((s) => s.episode!).toSet();
    return episodes.length == 1 ? episodes.single : null;
  }

  /// Known episode numbers for a selected season. Cross-season spans only
  /// enumerate their explicit endpoints; unknown intermediate totals are not invented.
  Set<int> episodesForSeason([int? season]) => {
    for (final span in _spans)
      if (season == null ||
          (season >= span.season && season <= span.lastSeason))
        if (span.episode != null && span.lastEpisode != null)
          if (span.cross && span.season != span.lastSeason) ...{
            if (season == null || season == span.season) span.episode!,
            if (season == null || season == span.lastSeason) span.lastEpisode!,
          } else
            for (var i = span.episode!; i <= span.lastEpisode!; i++) i,
  };

  String get label => _spans.map((span) => span.label).join(', ');

  static SeriesCoverage? parse(String title) {
    final parsed = _parse(title);
    return parsed.invalid || parsed.spans.isEmpty
        ? null
        : SeriesCoverage._(List.unmodifiable(parsed.spans));
  }

  /// Also supports episode-only labels, including "4 серия" and "выпуск 4".
  /// Ranges and conflicting episode numbers never become a single episode.
  static int? episodeNumber(String title) {
    final parsed = _parse(title);
    if (parsed.invalid ||
        parsed.episodes.isEmpty ||
        parsed.episodes.any((e) => e.first != e.last)) {
      return null;
    }
    final values = parsed.episodes.map((e) => e.first).toSet();
    return values.length == 1 ? values.single : null;
  }
}

const _seasonWord = r'(?:seasons?|сезон(?:ы|ов|а|е|у|ом)?)';
const _episodeWord =
    r'(?:episodes?|сер(?:ия|ии|ий|ию|ией)|эпизод(?:ы|ов|а)?|выпуск(?:и|ов|а)?)';
const _ordinal = r'(?:-?(?:ой|ый|ий|й|ая|я|ое|е|го)|st|nd|rd|th)?';
const _atom = '[0-9]{1,6}$_ordinal';
const _range = '$_atom(?:\\s*-\\s*$_atom)?';
const _numberList = '$_range(?:(?:\\s*,\\s*|\\s*(?:and|и|&|\\+)\\s*)$_range)*';
final _letter = RegExp(r'\p{L}', unicode: true);
final _digit = RegExp(r'[0-9]');
final _numericRuns = RegExp(r'[0-9]+');
final _wordMarker = RegExp(
  '(?<![\\p{L}])(?:$_seasonWord|$_episodeWord)(?![\\p{L}])',
  caseSensitive: false,
  unicode: true,
);
final _ordinalNumber = RegExp(
  '[0-9](?:-?(?:ой|ый|ий|й|ая|я|ое|е|го)|st|nd|rd|th)',
  caseSensitive: false,
);
final _numberRange = RegExp(
  '([0-9]+)$_ordinal(?:\\s*-\\s*([0-9]+)$_ordinal)?',
  caseSensitive: false,
);
final _nounAtStart = RegExp(
  '^(?:$_seasonWord|$_episodeWord)(?![\\p{L}])',
  caseSensitive: false,
  unicode: true,
);
final _nounAtEnd = RegExp(
  '(?<![\\p{L}])(?:$_seasonWord|$_episodeWord)\$',
  caseSensitive: false,
  unicode: true,
);
final _numberContinuationAtEnd = RegExp(
  '[0-9]$_ordinal\\s*(?:[-,]|and|и|&|\\+)\\s*\$',
  caseSensitive: false,
);

class _Range {
  const _Range(this.first, this.last);
  final int first, last;
  bool valid(int maximum, {bool season = false}) =>
      first >= 0 &&
      last >= first &&
      last <= maximum &&
      (!season || last - first <= 99);
}

class _Parsed {
  _Parsed(this.spans, this.episodes, {this.invalid = false});
  final List<_Span> spans;
  final List<_Range> episodes;
  final bool invalid;
}

class _Unit {
  _Unit(
    this.start,
    this.end,
    this.nounStart,
    this.season,
    this.prefix,
    this.ordinal,
    this.ranges,
  );
  final int start, end, nounStart;
  final bool season, prefix, ordinal;
  final List<_Range> ranges;
  bool get valid =>
      ranges.isNotEmpty &&
      ranges.every((r) => r.valid(season ? 999 : 9999, season: season));
}

class _Plan {
  const _Plan(this.units);
  final List<_Unit> units;
  bool betterThan(_Plan other) {
    if (units.length != other.units.length) {
      return units.length > other.units.length;
    }
    final ordinals = units.where((u) => u.ordinal).length,
        oldOrdinals = other.units.where((u) => u.ordinal).length;
    if (ordinals != oldOrdinals) {
      return ordinals > oldOrdinals;
    }
    final prefixes = units.where((u) => u.prefix).length,
        oldPrefixes = other.units.where((u) => u.prefix).length;
    if (prefixes != oldPrefixes) {
      return prefixes > oldPrefixes;
    }
    return units.fold<int>(0, (n, u) => n + u.end - u.start) >
        other.units.fold<int>(0, (n, u) => n + u.end - u.start);
  }
}

List<_Range> _ranges(String value) {
  final result = <_Range>[];
  for (final match in _numberRange.allMatches(value)) {
    final first = int.tryParse(match[1]!),
        last = int.tryParse(match[2] ?? match[1]!);
    if (first == null || last == null) {
      return [];
    }
    result.add(_Range(first, last));
  }
  return result;
}

_Parsed _parse(String title) {
  if (title.length > 4096) {
    return _Parsed([], []);
  }
  final text = title.replaceAll(RegExp('[–—−‑]'), '-');
  final spans = <_Span>[], episodes = <_Range>[];
  final compact = RegExp(
    r'(?<![\p{L}\p{N}])S([0-9]+)(?:[ ._]*E([0-9]+))?(?:\s*-\s*(?:S([0-9]+)(?:[ ._]*E([0-9]+))?|E([0-9]+)|([0-9]+)))?(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  ).allMatches(text).toList();
  if (compact.isNotEmpty) {
    for (final match in compact) {
      final season = int.tryParse(match[1]!);
      final episode = int.tryParse(match[2] ?? '');
      final lastSeason = int.tryParse(
        match[3] ?? (episode == null ? match[6] : null) ?? match[1]!,
      );
      final cross = match[3] != null && match[2] != null;
      final lastEpisode = int.tryParse(
        match[4] ??
            match[5] ??
            (episode != null ? match[6] : null) ??
            match[2] ??
            '',
      );
      if (season == null ||
          lastSeason == null ||
          !_Range(season, lastSeason).valid(999, season: true)) {
        return _Parsed([], [], invalid: true);
      }
      if (cross &&
          lastSeason == season &&
          episode != null &&
          lastEpisode != null &&
          lastEpisode < episode) {
        return _Parsed([], [], invalid: true);
      }
      final validEpisodes =
          episode != null &&
          lastEpisode != null &&
          episode <= 9999 &&
          lastEpisode <= 9999 &&
          (cross || lastEpisode >= episode);
      spans.add(
        _Span(
          season,
          lastSeason,
          validEpisodes ? episode : null,
          validEpisodes ? lastEpisode : null,
          cross: cross,
        ),
      );
      if (validEpisodes) {
        // A cross-season interval describes endpoints, not one repeated episode.
        episodes.add(_Range(episode, cross ? -1 : lastEpisode));
      }
    }
    return _finish(spans, episodes);
  }

  // Reject pathological numeric lists before suffix matching or constructing
  // list alternatives. Compact S/E labels above remain cheap and independent.
  if (!_wordMarker.hasMatch(text) ||
      _numericRuns.allMatches(text).take(129).length > 128) {
    return _Parsed([], []);
  }

  final candidates = <_Unit>[];
  for (final season in [true, false]) {
    final noun = season ? _seasonWord : _episodeWord;
    for (final prefix in [true, false]) {
      final pattern = prefix
          ? '(?<![\\p{L}])(?<noun>$noun)(?![\\p{L}])[\\s._:]*?(?<numbers>$_numberList)(?![0-9]|\\s*(?:[-,]|and|и|&|\\+)\\s*[0-9])'
          : '(?<![0-9])(?<numbers>$_numberList)[\\s._:]*(?<noun>$noun)(?![\\p{L}])';
      for (final match in RegExp(
        pattern,
        caseSensitive: false,
        unicode: true,
      ).allMatches(text)) {
        final numbers = match.namedGroup('numbers')!;
        final nounStart = prefix
            ? match.start
            : match.end - match.namedGroup('noun')!.length;
        final numberStart = prefix ? match.end - numbers.length : match.start;
        // A list can end at the next noun: "Season 2 and 4 episodes".
        // Offer its prefixes/suffixes so both nouns can claim their own number.
        for (final range in _numberRange.allMatches(numbers)) {
          final start = prefix ? match.start : numberStart + range.start;
          final end = prefix ? numberStart + range.end : match.end;
          if (prefix &&
              range.end == numbers.length &&
              end < text.length &&
              _letter.hasMatch(text[end]) &&
              !_nounAtStart.hasMatch(text.substring(end))) {
            continue;
          }
          if (!prefix && range.start == 0 && start > 0) {
            final previous = text[start - 1];
            if (_digit.hasMatch(previous) ||
                _numberContinuationAtEnd.hasMatch(text.substring(0, start)) ||
                (_letter.hasMatch(previous) &&
                    !_nounAtEnd.hasMatch(text.substring(0, start)))) {
              continue;
            }
          }
          final chosen = prefix
              ? numbers.substring(0, range.end)
              : numbers.substring(range.start);
          candidates.add(
            _Unit(
              start,
              end,
              nounStart,
              season,
              prefix,
              _ordinalNumber.hasMatch(chosen),
              _ranges(chosen),
            ),
          );
        }
      }
    }
  }
  final valid = candidates.where((u) => u.valid).toList()
    ..sort(
      (a, b) =>
          a.end != b.end ? a.end.compareTo(b.end) : a.start.compareTo(b.start),
    );
  final plans = <_Plan>[const _Plan([])];
  for (var i = 0; i < valid.length; i++) {
    var previous = i - 1;
    while (previous >= 0 && valid[previous].end > valid[i].start) {
      previous--;
    }
    final included = _Plan([...plans[previous + 1].units, valid[i]]);
    plans.add(included.betterThan(plans.last) ? included : plans.last);
  }
  final selected = plans.last.units.toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  // Invalid intervals must not reappear as a valid partial list or endpoint.
  if (candidates.any(
    (u) =>
        !u.valid &&
        u.ranges.any((r) => r.first != r.last) &&
        (!selected.any((s) => s.nounStart == u.nounStart) ||
            selected.any(
              (s) => s.nounStart == u.nounStart && s.prefix == u.prefix,
            )),
  )) {
    return _Parsed([], [], invalid: true);
  }
  final seasons = selected.where((u) => u.season).toList();
  final episodeUnits = selected.where((u) => !u.season).toList();
  final associated = <_Unit, List<_Range>>{
    for (final unit in seasons) unit: [],
  };
  for (final unit in episodeUnits) {
    episodes.addAll(unit.ranges);
    if (seasons.isEmpty) {
      continue;
    }
    int distance(_Unit season) => unit.end <= season.start
        ? season.start - unit.end
        : unit.start - season.end;
    final nearest = seasons.reduce((a, b) {
      final difference = distance(a).compareTo(distance(b));
      if (difference != 0) {
        return difference < 0 ? a : b;
      }
      return a.end <= unit.start ? a : b;
    });
    associated[nearest]!.addAll(unit.ranges);
  }
  for (final unit in seasons) {
    for (final season in unit.ranges) {
      final found = associated[unit]!;
      if (found.isEmpty) {
        spans.add(_Span(season.first, season.last, null, null));
      }
      for (final episode in found) {
        spans.add(
          _Span(season.first, season.last, episode.first, episode.last),
        );
      }
    }
  }
  return _finish(spans, episodes);
}

_Parsed _finish(List<_Span> spans, List<_Range> episodes) {
  final unique = <String, _Span>{for (final span in spans) span.label: span}
      .values
      .toList();
  unique.sort(
    (a, b) => a.season != b.season
        ? a.season.compareTo(b.season)
        : (a.episode ?? 0).compareTo(b.episode ?? 0),
  );
  return _Parsed(unique, episodes);
}

class _Span {
  const _Span(
    this.season,
    this.lastSeason,
    this.episode,
    this.lastEpisode, {
    this.cross = false,
  });
  final int season, lastSeason;
  final int? episode, lastEpisode;
  final bool cross;
  static String mark(String prefix, int value) =>
      '$prefix${value.toString().padLeft(2, '0')}';
  String get label {
    if (cross && episode != null && lastEpisode != null) {
      return '${mark('S', season)}${mark('E', episode!)}–${mark('S', lastSeason)}${mark('E', lastEpisode!)}';
    }
    return '${mark('S', season)}${lastSeason == season ? '' : '–${mark('S', lastSeason)}'}'
        '${episode == null ? '' : '${lastSeason == season ? '' : ' · '}${mark('E', episode!)}${lastEpisode == episode ? '' : '–${mark('E', lastEpisode!)}'}'}';
  }
}
