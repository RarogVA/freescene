import 'source.dart';

enum DownloadPhase {
  queued,
  metadata,
  connecting,
  downloading,
  paused,
  seeding,
  completed,
  failed,
}

enum LocalOrigin { torrentFile, magnet }

class DownloadOrigin {
  const DownloadOrigin.provider(SourceProvider value)
    : provider = value,
      local = null;
  const DownloadOrigin.torrentFile()
    : provider = null,
      local = LocalOrigin.torrentFile;
  const DownloadOrigin.magnet() : provider = null, local = LocalOrigin.magnet;

  final SourceProvider? provider;
  final LocalOrigin? local;

  String get label => localizedLabel(false);

  String localizedLabel(bool english) =>
      provider?.label ??
      switch (local!) {
        LocalOrigin.torrentFile =>
          english ? 'Local .torrent' : 'Локальный .torrent',
        LocalOrigin.magnet => 'Magnet',
      };

  Map<String, String> toJson() => {
    if (provider != null) 'provider': provider!.name,
    if (local != null) 'local': local!.name,
  };

  factory DownloadOrigin.fromJson(Map<String, dynamic> json) {
    final provider = json['provider'];
    if (provider is String &&
        RegExp(r'^[a-z][a-z0-9_-]{0,63}$').hasMatch(provider) &&
        json['local'] == null) {
      return DownloadOrigin.provider(SourceProvider(provider));
    }
    return switch (json['local']) {
      'torrentFile' when provider == null => const DownloadOrigin.torrentFile(),
      'magnet' when provider == null => const DownloadOrigin.magnet(),
      _ => throw const FormatException('Invalid download origin'),
    };
  }
}

class DownloadSnapshot {
  const DownloadSnapshot({
    required this.id,
    required this.title,
    required this.origin,
    required this.kind,
    required this.phase,
    this.connectedCounts = const PeerCounts(),
  });

  final String id;
  final String title;
  final DownloadOrigin origin;
  final SourceKind kind;
  final DownloadPhase phase;
  final PeerCounts connectedCounts;

  bool get showsCounts => kind.isTorrent;
  PeerCounts get visibleCounts =>
      kind.isTorrent &&
          switch (phase) {
            DownloadPhase.metadata ||
            DownloadPhase.connecting ||
            DownloadPhase.downloading ||
            DownloadPhase.seeding => true,
            _ => false,
          }
      ? connectedCounts
      : const PeerCounts();
}
