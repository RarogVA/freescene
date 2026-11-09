enum NotificationEvent {
  downloadCompleted,
  downloadFailed,
  noPeers,
  metadataFailed;

  static NotificationEvent? fromNative(String name) => switch (name) {
    'dhtFailed' || 'metadataFailed' => metadataFailed,
    _ => values.where((event) => event.name == name).firstOrNull,
  };
}

extension NotificationEventLabel on NotificationEvent {
  String label(bool english) => switch (this) {
    NotificationEvent.downloadCompleted =>
      english ? 'Download completed' : 'Завершение загрузки',
    NotificationEvent.downloadFailed =>
      english ? 'Download failed' : 'Ошибка загрузки',
    NotificationEvent.noPeers => english ? 'No peers' : 'Нет пиров',
    NotificationEvent.metadataFailed =>
      english
          ? 'Video download metadata error'
          : 'Ошибка метаданных при загрузке видео',
  };
}

/// One gate per native download/player task. Re-arm after recovery or retry.
/// The engine classifies confirmed errors after timeouts; zero counts alone
/// are deliberately not treated as an error here.
class NotificationGate {
  final Set<NotificationEvent> _delivered = {};

  bool shouldNotify(NotificationEvent event, Set<NotificationEvent> enabled) {
    if (_delivered.contains(event)) return false;
    final specialized = {
      NotificationEvent.noPeers,
      NotificationEvent.metadataFailed,
    };
    if (event == NotificationEvent.downloadFailed &&
        _delivered.any(specialized.contains)) {
      return false;
    }
    if (specialized.contains(event) &&
        _delivered.contains(NotificationEvent.downloadFailed)) {
      return false;
    }
    // A muted event still consumes this episode: enabling the switch should
    // not retroactively announce an old error.
    _delivered.add(event);
    return enabled.contains(event);
  }

  void recoveredOrRetried() => _delivered.clear();
}
