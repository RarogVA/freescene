import '../domain/notifications.dart';
import '../domain/source.dart';

enum AppLanguage { ru, en }

enum AppAppearance { light, dark }

class Preferences {
  Preferences({
    this.language = AppLanguage.ru,
    this.appearance = AppAppearance.dark,
    this.scale = 100,
    this.sidebarCollapsed = false,
    Set<NotificationEvent>? notifications,
    Set<SourceProvider>? providers,
  }) : assert([100, 125, 150].contains(scale)),
       providers = Set.unmodifiable(providers ?? defaultProviders),
       notifications = Set.unmodifiable(
         notifications ?? NotificationEvent.values.toSet(),
       );

  final AppLanguage language;
  final AppAppearance appearance;
  final int scale;
  final bool sidebarCollapsed;
  final Set<NotificationEvent> notifications;
  static Set<SourceProvider> get defaultProviders => SourceProvider.values
      .where((p) => p.descriptor?.enabledByDefault == true)
      .toSet();
  static List<SourceProvider> get availableProviders => SourceProvider.values;
  final Set<SourceProvider> providers;
  bool get english => language == AppLanguage.en;

  Preferences copyWith({
    AppLanguage? language,
    AppAppearance? appearance,
    int? scale,
    bool? sidebarCollapsed,
    Set<NotificationEvent>? notifications,
    Set<SourceProvider>? providers,
  }) => Preferences(
    language: language ?? this.language,
    appearance: appearance ?? this.appearance,
    scale: scale ?? this.scale,
    sidebarCollapsed: sidebarCollapsed ?? this.sidebarCollapsed,
    notifications: notifications ?? this.notifications,
    providers: providers ?? this.providers,
  );

  Map<String, Object> toJson() => {
    'version': 2,
    'language': language.name,
    'appearance': appearance.name,
    'scale': scale,
    'sidebarCollapsed': sidebarCollapsed,
    'providers': [for (final provider in providers) provider.name],
    'notifications': {
      for (final event in NotificationEvent.values)
        event.name: notifications.contains(event),
    },
  };

  factory Preferences.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version != 1 && version != 2) {
      throw const FormatException('Unsupported settings version');
    }
    final language = AppLanguage.values.firstWhere(
      (value) => value.name == json['language'],
      orElse: () => throw const FormatException('Invalid language'),
    );
    final appearance = AppAppearance.values.firstWhere(
      (value) => value.name == json['appearance'],
      orElse: () => throw const FormatException('Invalid appearance'),
    );
    final scale = json['scale'];
    if (scale is! int || ![100, 125, 150].contains(scale)) {
      throw const FormatException('Invalid interface scale');
    }
    final saved = json['notifications'];
    final sidebarCollapsed = json['sidebarCollapsed'] ?? false;
    if (sidebarCollapsed is! bool) {
      throw const FormatException('Invalid sidebar preference');
    }
    final savedProviders = json['providers'];
    if (savedProviders != null &&
        (savedProviders is! List ||
            savedProviders.any(
              (p) =>
                  p is! String ||
                  !RegExp(r'^[a-z][a-z0-9_-]{0,63}$').hasMatch(p),
            ))) {
      throw const FormatException('Invalid provider preferences');
    }
    if (saved is! Map<String, dynamic>) {
      throw const FormatException('Invalid notification preferences');
    }
    for (final event in NotificationEvent.values) {
      if (saved.containsKey(event.name) && saved[event.name] is! bool) {
        throw const FormatException('Invalid notification switch');
      }
    }
    if (version == 1 &&
        saved.containsKey('dhtFailed') &&
        saved['dhtFailed'] is! bool) {
      throw const FormatException('Invalid legacy DHT notification switch');
    }
    // Preserve either previously enabled cause when combining the switches.
    final metadataEnabled =
        saved['metadataFailed'] != false ||
        (version == 1 && saved['dhtFailed'] != false);
    return Preferences(
      language: language,
      appearance: appearance,
      scale: scale,
      sidebarCollapsed: sidebarCollapsed,
      providers: savedProviders == null
          ? null
          : {
              for (final name in savedProviders as List)
                SourceProvider(name as String),
            },
      notifications: {
        for (final event in NotificationEvent.values)
          if (event == NotificationEvent.metadataFailed
              ? metadataEnabled
              : saved[event.name] != false)
            event,
      },
    );
  }
}
