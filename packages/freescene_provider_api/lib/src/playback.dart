import 'catalog_models.dart';
import 'source.dart';

class PlaybackRequest {
  const PlaybackRequest({
    required this.url,
    required this.provider,
    required this.kind,
    this.mimeType,
    this.referrer,
    this.webPlayer,
    this.episodes = const [],
  });
  final Uri url;
  final String provider;
  final SourceKind kind;
  final String? mimeType;
  final Uri? referrer;
  final int? webPlayer;
  final List<CatalogWebEpisode> episodes;
}

class TrailerMedia {
  const TrailerMedia(this.url, {this.referrer, this.webProvider});
  final Uri url;
  final Uri? referrer;
  final String? webProvider;
}

abstract class TrailerResolver {
  Future<TrailerMedia> resolve(CatalogTrailer trailer);
  void close();
}
