/// An opaque persistent provider ID. Unknown IDs survive profile round trips.
class SourceProvider {
  const SourceProvider(this.name);
  final String name;
  static final Map<SourceProvider, ProviderDescriptor> _registered = {};
  static List<SourceProvider> get values =>
      _registered.keys.toList(growable: false);
  static void register(Iterable<ProviderDescriptor> descriptors) {
    _registered
      ..clear()
      ..addEntries(descriptors.map((d) => MapEntry(d.id, d)));
  }

  ProviderDescriptor? get descriptor => _registered[this];
  String get label => descriptor?.label ?? name;
  @override
  bool operator ==(Object other) =>
      other is SourceProvider && other.name == name;
  @override
  int get hashCode => name.hashCode;
}

class ProviderDescriptor {
  const ProviderDescriptor(
    this.id,
    this.label, {
    this.enabledByDefault = false,
    this.qualityInPlayer = false,
    this.showThumbnail = false,
    this.gameCatalog = false,
    this.torrentTracker = false,
    this.descriptionRu,
    this.descriptionEn,
  });
  final SourceProvider id;
  final String label;
  final bool enabledByDefault,
      qualityInPlayer,
      showThumbnail,
      gameCatalog,
      torrentTracker;
  final String? descriptionRu, descriptionEn;
}

enum SourceKind { torrent, magnet, direct, embed }

extension SourceKindTorrent on SourceKind {
  bool get isTorrent => this == SourceKind.torrent || this == SourceKind.magnet;
}

enum DownloadKind { torrent, magnet, file, external, unavailable }

/// Unknown counts stay null. Catalogue counts never become live connections.
class PeerCounts {
  const PeerCounts({this.seeds, this.peers})
    : assert(seeds == null || seeds >= 0),
      assert(peers == null || peers >= 0);

  final int? seeds;
  final int? peers;

  String get seedsLabel => seeds?.toString() ?? '—';
  String get peersLabel => peers?.toString() ?? '—';
}

/// A calendar day from provider metadata (ISO dates may include a timestamp).
DateTime? catalogDay(Object? value) {
  if (value is! String) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:$|[ T])').firstMatch(value);
  if (match == null) return null;
  final year = int.parse(match[1]!),
      month = int.parse(match[2]!),
      day = int.parse(match[3]!);
  final date = DateTime.utc(year, month, day);
  return year >= 1888 && date.month == month && date.day == day ? date : null;
}

class SourceRow {
  const SourceRow({
    required this.id,
    required this.provider,
    required this.title,
    required this.watch,
    required this.download,
    this.quality,
    this.sizeBytes,
    this.durationSeconds,
    this.releaseYear,
    this.releaseDate,
    this.publishedDate,
    this.season,
    this.episode,
    this.catalogueCounts = const PeerCounts(),
  });

  final String id;
  final SourceProvider provider;
  final String title;
  final SourceKind watch;
  final DownloadKind download;
  final String? quality;
  final int? sizeBytes;
  final int? durationSeconds, releaseYear;
  final DateTime? releaseDate, publishedDate;
  final int? season;
  final int? episode;
  final PeerCounts catalogueCounts;

  bool get isTorrent =>
      watch.isTorrent ||
      download == DownloadKind.torrent ||
      download == DownloadKind.magnet;
  bool get canDownload => download != DownloadKind.unavailable;
  PeerCounts get visibleCounts =>
      isTorrent ? catalogueCounts : const PeerCounts();
}
