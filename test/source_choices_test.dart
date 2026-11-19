import 'package:flutter_test/flutter_test.dart';
import 'package:freescene/catalog/catalog_models.dart';
import 'package:freescene/catalog/source_choices.dart';
import 'package:freescene/catalog/source_checks.dart';

CatalogSource candidate(
  String id, {
  String? audio = 'LostFilm',
  String? quality = '1080p',
  String name = 'Movie',
  int seeds = 5,
  List<String> episodes = const [],
  String? restriction,
}) => CatalogSource(
  row: SourceRow(
    id: id,
    provider: const SourceProvider('test'),
    title: name,
    watch: SourceKind.magnet,
    download: DownloadKind.magnet,
    quality: quality,
    catalogueCounts: PeerCounts(seeds: seeds),
  ),
  audio: audio,
  episodes: episodes,
  restriction: restriction,
);
void main() {
  setUp(() => sourceCheckResults.value = {});
  test('quality preserves cropped widescreen and does not label unknown or 8K as 4K', () {
    expect(
      sourceQuality(candidate('a', quality: '1920x800')),
      SourceQuality.fullHd,
    );
    expect(
      sourceQuality(candidate('a', quality: '3840×1600')),
      SourceQuality.uhd,
    );
    expect(sourceQuality(candidate('a', quality: '8K')), SourceQuality.uhd8k);
    expect(
      sourceQuality(candidate('a', quality: null, name: 'Movie.720p.mkv')),
      SourceQuality.hd,
    );
    expect(sourceQuality(candidate('a', quality: null)), SourceQuality.unknown);
    expect(
      automaticQuality([SourceQuality.uhd, SourceQuality.fullHd]),
      SourceQuality.fullHd,
    );
  });
  test(
    'named voices group while generic dubs and unknown voices remain distinct',
    () {
      final groups = sourceVoiceChoices([
        candidate('a', audio: 'LostFilm'),
        candidate('b', audio: ' lostfilm '),
        candidate('c', audio: 'Дубляж'),
        candidate('d', audio: 'Дубляж'),
        candidate('e', audio: 'Профессиональное дублирование'),
        candidate('f', audio: 'Профессиональное дублирование'),
        candidate('g', audio: null),
        candidate('h', audio: null),
        candidate('i', quality: '720p'),
        candidate('j', audio: 'NewStudio'),
      ], series: false);
      expect(groups, hasLength(9));
      expect(groups.first.sources.map((s) => s.row.id), ['a', 'b']);
    },
  );
  test('different episodes and incomplete coverage cannot silently share a voice row', () {
    final groups = sourceVoiceChoices([
      candidate('a', episodes: ['S01E01']),
      candidate('b', episodes: ['S01E02']),
      candidate('c', episodes: ['S01E01']),
      candidate('d', name: 'Movie S01'),
      candidate('e', name: 'Movie S01'),
    ], series: true);
    expect(groups, hasLength(4));
    expect(groups.first.sources.map((s) => s.row.id), ['a', 'c']);
  });
  test('actual received data outranks catalogue counts but restricted sources never win', () {
    final groups = sourceVoiceChoices([
      candidate('many-seeds', seeds: 10000),
      candidate('verified', seeds: 0),
      candidate('restricted', seeds: 100000, restriction: 'Unavailable'),
    ], series: false);
    sourceCheckResults.value = {
      for (final id in ['verified', 'restricted'])
        'test:$id': SourceCheck(SourceCheckState.data, DateTime.now()),
      'test:many-seeds': SourceCheck(SourceCheckState.timeout, DateTime.now()),
    };
    expect(groups.single.ranked().map((s) => s.row.id), [
      'verified',
      'many-seeds',
      'restricted',
    ]);
  });
  test(
    'composite voice descriptions stay separate and advertise player selection',
    () {
      final sources = [
        candidate('a', audio: 'Перевод 1: LostFilm Перевод 2: AlexFilm'),
        candidate('b', audio: 'Перевод 1: LostFilm Перевод 2: AlexFilm'),
        candidate('c', audio: 'LostFilm / AlexFilm'),
      ];
      final groups = sourceVoiceChoices(sources, series: false);
      expect(groups, hasLength(3));
      expect(
        groups.every((group) => group.label(false).contains('выбор в плеере')),
        isTrue,
      );
      expect(sourceHasMultipleVoices('LostFilm (AC3 5.1)'), isFalse);
    },
  );
}
