import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../catalog/catalog_controller.dart';
import '../catalog/catalog_models.dart';
import '../catalog/source_seasons.dart';
import '../catalog/catalog_filter_dialog.dart';
import '../catalog/cached_poster.dart';
import '../catalog/favorites.dart';
import '../catalog/poster_cache.dart';
import '../catalog/watch_queue.dart';
import '../settings/preferences.dart';
import '../settings/settings_store.dart';
import 'android_runtime.dart';

import 'package:freescene_provider_api/freescene_provider_api.dart';

import 'android_torrents.dart';
import 'android_downloads.dart';
import 'android_search_dialog.dart';
import 'android_voice_dialog.dart';
import 'android_theme.dart';
import 'android_updates.dart';
import 'remote_focus.dart';
import 'source_card.dart';

class AndroidBootstrap extends StatefulWidget {
  const AndroidBootstrap({super.key});
  @override
  State<AndroidBootstrap> createState() => _AndroidBootstrapState();
}

class _AndroidBootstrapState extends State<AndroidBootstrap> {
  late Future<_AndroidSession> session = _AndroidSession.open();
  @override
  Widget build(BuildContext context) => FutureBuilder<_AndroidSession>(
    future: session,
    builder: (context, snapshot) {
      final value = snapshot.data;
      if (value != null) {
        return AndroidApp(
          runtime: value.runtime,
          initialPreferences: value.preferences,
          savePreferences: value.store.save,
          repository: value.repository,
          favorites: value.favorites,
          queue: value.queue,
          posterCache: value.cache,
        );
      }
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: snapshot.hasError
                ? FilledButton(
                    onPressed: () =>
                        setState(() => session = _AndroidSession.open()),
                    child: const Text('Не удалось открыть профиль. Повторить'),
                  )
                : const CircularProgressIndicator(),
          ),
        ),
      );
    },
  );
}

class _AndroidSession {
  _AndroidSession(
    this.runtime,
    this.store,
    this.preferences,
    this.favorites,
    this.queue,
    this.cache,
  );
  final AndroidRuntime runtime;
  final SettingsStore store;
  final Preferences preferences;
  final FavoritesController favorites;
  final QueueController queue;
  final PosterDiskCache cache;
  final repository = ProviderSetup.current.createCatalog(android: true);
  static Future<_AndroidSession> open() async {
    final runtime = await AndroidRuntime.load();
    final budget = AndroidBudget.forDevice(runtime);
    PaintingBinding.instance.imageCache.maximumSizeBytes =
        budget.imageMemoryBytes;
    PaintingBinding.instance.imageCache.maximumSize = budget.lite ? 64 : 160;
    final store = SettingsStore(runtime.profile);
    final preferences = await store.load();
    final favorites = FavoritesController(
      store: FavoritesStore(runtime.profile),
    );
    final queue = QueueController(store: QueueStore(runtime.profile));
    await Future.wait([favorites.restore(), queue.restore()]);
    return _AndroidSession(
      runtime,
      store,
      preferences,
      favorites,
      queue,
      PosterDiskCache(
        Directory('${runtime.cache.path}/posters'),
        maxBytes: budget.diskCacheBytes,
        maxEntries: budget.lite ? 200 : 500,
        maxConcurrent: budget.concurrentPosters,
      ),
    );
  }
}

class _BackIntent extends Intent {
  const _BackIntent();
}

/// Separate compact/mobile and remote-first TV shell over shared catalogue data.
/// A lazy grid keeps remote navigation reachable without retaining every poster.
class AndroidApp extends StatefulWidget {
  const AndroidApp({
    required this.runtime,
    required this.initialPreferences,
    required this.savePreferences,
    required this.repository,
    this.favorites,
    this.queue,
    this.posterCache,
    this.play,
    this.voice,
    this.exit,
    this.trailerFactory,
    super.key,
  });
  final AndroidRuntime runtime;
  final Preferences initialPreferences;
  final Future<void> Function(Preferences) savePreferences;
  final CatalogRepository repository;
  final FavoritesController? favorites;
  final QueueController? queue;
  final PosterDiskCache? posterCache;
  final Future<void> Function(CatalogSource)? play;
  final Future<String?> Function()? voice;
  final VoidCallback? exit;
  final TrailerResolver Function()? trailerFactory;
  @override
  State<AndroidApp> createState() => _AndroidAppState();
}

class _AndroidAppState extends State<AndroidApp> with WidgetsBindingObserver {
  final navigator = GlobalKey<NavigatorState>();
  late final remote = RemoteFocus(enabled: widget.runtime.tv);
  late final traversal = RemoteTraversalPolicy(
    remote,
    horizontalGroups: const [
      ['filter', 'search', 'voice', 'clear-search'],
      ['favorites', 'queue', 'kind-movies', 'kind-series', 'refresh'],
      [
        'detail-back',
        'source-search',
        'source-clear',
        'source-season',
        'source-episode',
        'kind-movies',
        'kind-series',
        'favorite-title',
        'queue-title',
      ],
    ],
    verticalGroups: widget.runtime.tv
        ? const [
            ['home', 'settings', 'about-brand'],
          ]
        : const [],
  );
  late final favorites = widget.favorites ?? FavoritesController();
  late final queue = widget.queue ?? QueueController();
  late final catalog = CatalogController(
    widget.repository,
    favorites: favorites,
    queue: queue,
  );
  late Preferences preferences = widget.initialPreferences;
  late final budget = AndroidBudget.forDevice(widget.runtime);
  String screen = 'catalog';
  String? returnTile;
  int sourceLimit = 8;
  final hiddenSourceProviders = <SourceProvider>{};
  String sourceQuery = '';
  int? sourceSeason, sourceEpisode;
  bool get tvDetails => widget.runtime.tv && catalog.selected != null;
  bool modal = false, playing = false, backBusy = false;
  int playbackEpoch = 0;
  TrailerResolver? trailerClient;
  final gridScroll = ScrollController();
  final sourcesScroll = ScrollController();
  bool sourceLoadScheduled = false;
  String? updateOffer;
  String tr(String ru, String en) => preferences.english ? en : ru;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.repository.configureProviders(
      preferences.providers.intersection(SourceProvider.values.toSet()),
    );
    catalog.addListener(_changed);
    gridScroll.addListener(loadNearEnd);
    sourcesScroll.addListener(scheduleSourceLoad);
    unawaited(catalog.browse());
    remote.restore('home');
    unawaited(checkStartupUpdate());
  }

  Future<void> checkStartupUpdate() async {
    try {
      final result = await AndroidUpdates().check();
      if (!mounted || result['available'] != true) return;
      updateOffer = result['version'] as String?;
      offerUpdate();
    } catch (_) {
      /* Startup checks are silent when offline or unauthenticated. */
    }
  }

  void offerUpdate() {
    if (!mounted ||
        modal ||
        playing ||
        updateOffer == null ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final version = updateOffer;
    updateOffer = null;
    unawaited(
      dialog<void>(
        AndroidAboutDialog(
          version: widget.runtime.version,
          english: preferences.english,
          tv: widget.runtime.tv,
          offeredVersion: version,
        ),
      ),
    );
  }

  Future<void> about() => dialog<void>(
    AndroidAboutDialog(
      version: widget.runtime.version,
      english: preferences.english,
      tv: widget.runtime.tv,
    ),
  );

  Future<void> filters() async {
    final result = await dialog<CatalogFilter>(
      CatalogFilterDialog(
        initial: catalog.filter,
        english: preferences.english,
        kind: catalog.kind,
      ),
    );
    if (result != null && mounted) {
      await catalog.browse(filter: result);
      remote.restore('filter');
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !modal && !playing) remote.repair();
      loadNearEnd();
      loadSourcesNearEnd();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !modal) {
      remote.restore(remote.last);
      offerUpdate();
    }
    if (state == AppLifecycleState.paused && budget.lite) {
      PaintingBinding.instance.imageCache.clear();
    }
  }

  @override
  void dispose() {
    ++playbackEpoch;
    trailerClient?.close();
    WidgetsBinding.instance.removeObserver(this);
    catalog.removeListener(_changed);
    catalog.dispose();
    favorites.dispose();
    queue.dispose();
    widget.posterCache?.close();
    remote.dispose();
    gridScroll.dispose();
    sourcesScroll.dispose();
    super.dispose();
  }

  Widget button(
    String id,
    String label,
    VoidCallback? action, {
    IconData? icon,
    bool selected = false,
  }) => RemoteButton(
    key: ValueKey(id),
    id: id,
    focus: remote,
    onPressed: action,
    selected: selected,
    child: icon == null
        ? Text(label, textAlign: TextAlign.center)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
  );

  Future<void> browse({
    CatalogKind? kind,
    bool? saved,
    bool? queued,
    String? search,
  }) async {
    cancelPlayback();
    setState(() {
      screen = 'catalog';
    });
    remote.restore(kind == null ? remote.last : 'kind-${kind.name}');
    await catalog.browse(
      kind: kind,
      favoritesOnly: saved,
      queueOnly: queued,
      search: search,
      filter: const CatalogFilter(),
    );
    if (mounted && gridScroll.hasClients) gridScroll.jumpTo(0);
  }

  void home() {
    cancelPlayback();
    setState(() {
      screen = 'catalog';
    });
    remote.restore('home');
    unawaited(catalog.resetToHome());
  }

  void open(CatalogTitle title) {
    returnTile = 'title-${title.kind.name}-${title.id}';
    sourceLimit = 8;
    hiddenSourceProviders.clear();
    sourceQuery = '';
    sourceSeason = sourceEpisode = null;
    unawaited(catalog.open(title));
    remote.restore('detail-back');
  }

  Future<T?> dialog<T>(Widget child, {String? restore}) async {
    final target = restore ?? remote.last;
    modal = true;
    try {
      return await showDialog<T>(
        context: navigator.currentContext!,
        builder: (_) => child,
      );
    } finally {
      modal = false;
      if (mounted) remote.restore(target);
    }
  }

  Future<void> back() async {
    if (backBusy || modal) return;
    cancelPlayback();
    if (catalog.selected != null) {
      catalog.back();
      remote.restore(returnTile);
      return;
    }
    if (screen != 'catalog') {
      final from = screen;
      setState(() => screen = 'catalog');
      remote.restore(from);
      return;
    }
    if (catalog.localCollectionOnly ||
        catalog.search.isNotEmpty ||
        catalog.kind != CatalogKind.movies) {
      home();
      return;
    }
    backBusy = true;
    final exit = await dialog<bool>(
      Builder(
        builder: (context) => AlertDialog(
          title: Text(tr('Закрыть FreeScene?', 'Close FreeScene?')),
          actions: [
            TextButton(
              autofocus: widget.runtime.tv,
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Остаться', 'Stay')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('Закрыть', 'Close')),
            ),
          ],
        ),
      ),
    );
    backBusy = false;
    if (mounted && exit == true) {
      if (widget.exit != null) {
        widget.exit!();
      } else {
        await SystemNavigator.pop();
      }
    }
  }

  Future<void> search({bool voice = false}) async {
    if (modal) return;
    cancelPlayback();
    if (voice && widget.runtime.tv) {
      final result = await dialog<String>(
        AndroidVoiceDialog(english: preferences.english, listen: widget.voice),
        restore: 'voice',
      );
      if (!mounted) return;
      if (result != null && result.trim().isNotEmpty) {
        await browse(search: result.trim());
        if (mounted) remote.restore('search');
      }
      return;
    }
    String? initialError;
    if (voice) {
      modal = true;
      String? result;
      try {
        result =
            await (widget.voice?.call() ??
                AndroidRuntime.channel.invokeMethod<String>('voiceSearch', {
                  'language': preferences.english ? 'en-US' : 'ru-RU',
                }));
      } catch (error) {
        initialError =
            error is PlatformException && error.code == 'voice_permission'
            ? tr(
                'Разрешите доступ к микрофону для голосового поиска. Пока можно ввести запрос вручную.',
                'Allow microphone access for voice search, or type your search.',
              )
            : tr(
                'Голосовой ввод недоступен. Введите запрос вручную.',
                'Voice input unavailable. Type your search.',
              );
      } finally {
        modal = false;
      }
      if (!mounted) return;
      if (initialError == null) {
        if (result != null && result.trim().isNotEmpty) {
          await browse(search: result.trim());
          if (mounted) remote.restore('search');
        } else {
          remote.restore('voice');
        }
        return;
      }
    }
    final query = await dialog<String>(
      AndroidSearchDialog(
        initial: catalog.search,
        english: preferences.english,
        voice: widget.voice,
        initialError: initialError,
        allowVoice: !widget.runtime.tv,
      ),
      restore: 'search',
    );
    if (mounted && query != null) {
      await browse(search: query);
      if (mounted) remote.restore('search');
    }
  }

  Future<void> save(Preferences value) async {
    setState(() => preferences = value);
    try {
      await widget.savePreferences(value);
    } catch (_) {
      if (mounted) {
        await message(
          tr('Не удалось сохранить настройки.', 'Could not save preferences.'),
        );
      }
    }
  }

  Future<void> message(String text) => dialog<void>(
    Builder(
      builder: (context) => AlertDialog(
        scrollable: true,
        content: Text(text),
        actions: [
          FilledButton(
            autofocus: widget.runtime.tv,
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Закрыть', 'Close')),
          ),
        ],
      ),
    ),
  );
  Future<void> toggle(
    FavoritesController collection,
    CatalogTitle title,
    String id,
  ) async {
    try {
      await collection.toggle(title);
    } catch (_) {
      if (mounted) {
        await message(
          tr('Не удалось сохранить список.', 'Could not save the list.'),
        );
      }
    }
    if (mounted) remote.restore(id, fallback: 'detail-back');
  }

  Future<void> downloadSource(CatalogSource source) async {
    if (playing) return;
    final epoch = ++playbackEpoch;
    setState(() => playing = true);
    try {
      final resolved = await widget.repository.resolve(source);
      if (!mounted || epoch != playbackEpoch) return;
      await const AndroidTorrents().add(resolved);
      if (mounted) {
        ScaffoldMessenger.of(navigator.currentContext!).showSnackBar(
          SnackBar(
            content: Text(tr('Добавлено в загрузки', 'Added to downloads')),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        await message(
          tr('Не удалось добавить загрузку', 'Could not add download'),
        );
      }
    } finally {
      if (mounted && epoch == playbackEpoch) setState(() => playing = false);
    }
  }

  Future<void> play(CatalogSource source) async {
    if (playing) return;
    final epoch = ++playbackEpoch;
    final target = remote.last;
    setState(() => playing = true);
    try {
      if (widget.play != null) {
        await widget.play!(source);
      } else {
        final resolved = await widget.repository.resolve(source);
        if (!mounted || epoch != playbackEpoch) return;
        final title =
            catalog.selected?.title(preferences.english) ?? source.row.title;
        if (resolved.row.isTorrent) {
          if (widget.runtime.tv) {
            await const AndroidTorrents().open(resolved, title: title);
          } else {
            final id = await const AndroidTorrents().add(resolved);
            if (!mounted || epoch != playbackEpoch) return;
            await const AndroidTorrents().play(id, title: title);
          }
          return;
        }
        final playback = await widget.repository.playback(
          resolved,
          lowRam: widget.runtime.lowRam,
        );
        if (!mounted || epoch != playbackEpoch) return;
        if (playback.kind == SourceKind.embed) {
          await AndroidRuntime.channel.invokeMethod<void>('playWeb', {
            'provider': playback.provider,
            'title': title,
            'url': playback.url.toString(),
            'webPlayer': playback.webPlayer ?? 0,
            'episodes': playback.episodes.map((e) => e.toJson()).toList(),
          });
          return;
        }
        final url = playback.url;
        if (!mounted || epoch != playbackEpoch) return;
        if (url.scheme != 'https' || url.userInfo.isNotEmpty) {
          throw const FormatException('Invalid media URL');
        }
        await AndroidRuntime.channel.invokeMethod<void>('play', {
          'url': url.toString(),
          'title': title,
          'playbackId':
              'source:${resolved.row.provider.name}:${resolved.row.id}',
          'mimeType': playback.mimeType,
          'referrer': playback.referrer?.toString(),
        });
      }
    } catch (_) {
      if (mounted && epoch == playbackEpoch) {
        setState(() => playing = false);
        await message(
          tr(
            'Источник недоступен в Android-плеере. Выберите другой источник.',
            'Source unavailable in the Android player. Choose another source.',
          ),
        );
      }
    } finally {
      if (mounted && epoch == playbackEpoch) {
        setState(() => playing = false);
        remote.restore(target, fallback: 'detail-back');
      }
    }
  }

  Future<void> watchTrailer(CatalogTitle title) async {
    final trailer = title.trailer;
    if (playing || trailer == null) return;
    final epoch = ++playbackEpoch;
    final client =
        widget.trailerFactory?.call() ??
        ProviderSetup.current.createTrailerResolver(
          'FreeScene/${widget.runtime.version} Android',
        );
    trailerClient = client;
    setState(() => playing = true);
    try {
      final media = await client.resolve(trailer);
      if (!mounted || epoch != playbackEpoch) return;
      if (media.webProvider != null) {
        await AndroidRuntime.channel.invokeMethod<void>('playWeb', {
          'provider': media.webProvider,
          'title':
              '${tr('Трейлер', 'Trailer')} · ${title.title(preferences.english)}',
          'url': media.url.toString(),
        });
        return;
      }
      await AndroidRuntime.channel.invokeMethod<void>('play', {
        'url': media.url.toString(),
        'referrer': media.referrer?.toString(),
        'title':
            '${tr('Трейлер', 'Trailer')} · ${title.title(preferences.english)}',
      });
    } catch (_) {
      if (mounted && epoch == playbackEpoch) {
        await message(
          tr(
            'Не удалось открыть трейлер. Повторите попытку.',
            'Could not open the trailer. Retry.',
          ),
        );
      }
    } finally {
      client.close();
      if (identical(trailerClient, client)) trailerClient = null;
      if (mounted && epoch == playbackEpoch) {
        setState(() => playing = false);
        remote.restore('trailer', fallback: 'detail-back');
      }
    }
  }

  void cancelPlayback() {
    ++playbackEpoch;
    widget.repository.cancelPlayback();
    trailerClient?.close();
    trailerClient = null;
    if (playing && mounted) setState(() => playing = false);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navigator,
    debugShowCheckedModeBanner: false,
    title: 'FreeScene',
    theme: androidTheme(
      dark: preferences.appearance == AppAppearance.dark,
      tv: widget.runtime.tv,
    ),
    locale: Locale(preferences.language.name),
    supportedLocales: const [Locale('ru'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    // Single-line dialog inputs must let the remote leave vertically. Keep
    // left/right available for moving the caret and adjusting sliders.
    builder: (context, child) => !widget.runtime.tv
        ? child!
        : Shortcuts(
            shortcuts: const {
              SingleActivator(
                LogicalKeyboardKey.arrowUp,
              ): DirectionalFocusIntent(
                TraversalDirection.up,
                ignoreTextFields: false,
              ),
              SingleActivator(
                LogicalKeyboardKey.arrowDown,
              ): DirectionalFocusIntent(
                TraversalDirection.down,
                ignoreTextFields: false,
              ),
              SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
            },
            child: FocusTraversalGroup(
              policy: RemoteDialogTraversalPolicy(),
              child: child!,
            ),
          ),
    home: Builder(
      builder: (context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(back());
        },
        child: Shortcuts(
          shortcuts: {
            if (widget.runtime.tv) ...{
              const SingleActivator(LogicalKeyboardKey.select):
                  const ActivateIntent(),
              const SingleActivator(LogicalKeyboardKey.gameButtonA):
                  const ActivateIntent(),
            },
            const SingleActivator(LogicalKeyboardKey.escape):
                const _BackIntent(),
            const SingleActivator(LogicalKeyboardKey.goBack):
                const _BackIntent(),
          },
          child: Actions(
            actions: {
              _BackIntent: CallbackAction<_BackIntent>(
                onInvoke: (_) {
                  unawaited(back());
                  return null;
                },
              ),
            },
            child: Scaffold(
              body: SafeArea(
                top: !widget.runtime.tv,
                bottom: !widget.runtime.tv,
                left: !widget.runtime.tv,
                right: !widget.runtime.tv,
                child: FocusTraversalGroup(
                  policy: widget.runtime.tv
                      ? traversal
                      : ReadingOrderTraversalPolicy(),
                  child: Row(
                    children: [
                      if (widget.runtime.tv) ...[
                        _rail(),
                        const VerticalDivider(width: 1),
                      ],
                      Expanded(
                        child: Column(
                          children: [
                            if (screen == 'catalog') _toolbar(),
                            Expanded(
                              child: screen == 'settings'
                                  ? _settings()
                                  : screen == 'downloads'
                                  ? AndroidDownloads(
                                      focus: remote,
                                      back: () => unawaited(back()),
                                      english: preferences.english,
                                    )
                                  : catalog.selected == null
                                  ? _catalog()
                                  : _details(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  void downloads() {
    cancelPlayback();
    catalog.back();
    setState(() => screen = 'downloads');
    remote.restore('downloads-back');
  }

  void settings() {
    cancelPlayback();
    catalog.back();
    setState(() => screen = 'settings');
    remote.restore('settings-back');
  }

  Widget _rail() {
    Widget item(
      String id,
      IconData icon,
      String label,
      VoidCallback action, {
      bool selected = false,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RemoteButton(
        id: id,
        focus: remote,
        onPressed: action,
        flat: true,
        selected: selected,
        radius: 24,
        alignment: Alignment.center,
        child: Tooltip(message: label, child: Icon(icon)),
      ),
    );
    return SizedBox(
      key: const ValueKey('android-tv-sidebar'),
      width: 76,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            item('home', Icons.home_outlined, tr('Домой', 'Home'), home),
            const Spacer(),
            item(
              'settings',
              Icons.settings_outlined,
              tr('Настройки', 'Settings'),
              settings,
              selected: screen == 'settings',
            ),
            item(
              'about-brand',
              Icons.info_outline,
              'FreeScene',
              () => unawaited(about()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbar() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
    child: Column(
      children: [
        if (!tvDetails)
          Row(
            children: [
              RemoteButton(
                id: 'filter',
                focus: remote,
                onPressed: () => unawaited(filters()),
                radius: 28,
                flat: true,
                selected: catalog.filter.active,
                child: Icon(
                  Icons.filter_alt_outlined,
                  color: catalog.filter.active
                      ? Theme.of(navigator.currentContext!).colorScheme.error
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: RemoteButton(
                  id: 'search',
                  focus: remote,
                  radius: 28,
                  alignment: Alignment.centerLeft,
                  onPressed: () => unawaited(search()),
                  child: Row(
                    children: [
                      const Icon(Icons.search),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          catalog.search.isEmpty
                              ? tr('Поиск', 'Search')
                              : catalog.search,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              RemoteButton(
                id: 'voice',
                focus: remote,
                radius: 28,
                flat: true,
                onPressed: () => unawaited(search(voice: true)),
                child: Tooltip(
                  message: tr('Голосовой поиск', 'Voice search'),
                  child: const Icon(Icons.mic),
                ),
              ),
              if (!widget.runtime.tv)
                SizedBox.square(
                  dimension: 48,
                  child: RemoteButton(
                    id: catalog.selected == null ? 'refresh' : 'detail-back',
                    focus: remote,
                    flat: true,
                    radius: 24,
                    padding: EdgeInsets.zero,
                    onPressed: () =>
                        unawaited(catalog.selected == null ? browse() : back()),
                    child: Tooltip(
                      message: catalog.selected == null
                          ? tr('Обновить', 'Refresh')
                          : tr('К каталогу', 'Back to catalogue'),
                      child: Icon(
                        catalog.selected == null
                            ? Icons.refresh
                            : Icons.arrow_back,
                      ),
                    ),
                  ),
                ),
              if (catalog.search.isNotEmpty)
                SizedBox.square(
                  dimension: 48,
                  child: RemoteButton(
                    id: 'clear-search',
                    focus: remote,
                    radius: 24,
                    padding: EdgeInsets.zero,
                    onPressed: () => unawaited(browse(search: '')),
                    child: Tooltip(
                      message: tr('Очистить поиск', 'Clear search'),
                      child: const Icon(Icons.close),
                    ),
                  ),
                ),
            ],
          ),
        if (!tvDetails) const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, bounds) {
            final compact = bounds.maxWidth < (tvDetails ? 1250 : 1050);
            final switcher = tvDetails
                ? SizedBox(
                    width: bounds.maxWidth < 600
                        ? bounds.maxWidth
                        : math.min(
                            catalog.selected?.kind == CatalogKind.series
                                ? 760
                                : 420,
                            bounds.maxWidth - 248,
                          ),
                    child: _sourceToolbar(),
                  )
                : Container(
                    key: const ValueKey('android-kind-switch'),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final kind in [
                          CatalogKind.movies,
                          CatalogKind.series,
                        ])
                          SizedBox(
                            width: compact
                                ? math.min(150, (bounds.maxWidth - 8) / 2)
                                : 160,
                            child: RemoteButton(
                              id: 'kind-${kind.name}',
                              segment: true,
                              focus: remote,
                              flat: true,
                              radius: 26,
                              selected: catalog.kind == kind,
                              selectedBackground: widget.runtime.tv
                                  ? const Color(0xffbdbdbd)
                                  : null,
                              selectedForeground: widget.runtime.tv
                                  ? const Color(0xff252731)
                                  : null,
                              onPressed: () => unawaited(browse(kind: kind)),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    kind == CatalogKind.movies
                                        ? Icons.movie_outlined
                                        : Icons.tv,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    kind == CatalogKind.movies
                                        ? tr('Фильмы', 'Films')
                                        : tr('Сериалы', 'Series'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
            final title = catalog.selected;
            final detail = title != null;
            Widget action(
              String id,
              IconData icon,
              String label,
              VoidCallback onPressed, {
              bool selected = false,
            }) => SizedBox(
              width: widget.runtime.tv ? null : 48,
              height: widget.runtime.tv ? null : 48,
              child: RemoteButton(
                id: id,
                focus: remote,
                radius: widget.runtime.tv ? 20 : 24,
                padding: widget.runtime.tv
                    ? const EdgeInsets.all(12)
                    : EdgeInsets.zero,
                selected: selected,
                onPressed: onPressed,
                child: Tooltip(
                  message: label,
                  child: compact || !widget.runtime.tv
                      ? Icon(icon)
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon),
                            const SizedBox(width: 8),
                            Text(label),
                          ],
                        ),
                ),
              ),
            );
            final collections = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                action(
                  detail ? 'favorite-title' : 'favorites',
                  Icons.favorite_border,
                  detail
                      ? tr('В избранное', 'Save')
                      : tr('Избранное', 'Favorites'),
                  () => unawaited(
                    detail
                        ? toggle(favorites, title, 'favorite-title')
                        : browse(saved: !catalog.favoritesOnly, queued: false),
                  ),
                  selected: detail
                      ? favorites.contains(title)
                      : catalog.favoritesOnly,
                ),
                const SizedBox(width: 6),
                action(
                  detail ? 'queue-title' : 'queue',
                  Icons.playlist_play,
                  detail ? tr('В очередь', 'Queue') : tr('Очередь', 'Queue'),
                  () => unawaited(
                    detail
                        ? toggle(queue, title, 'queue-title')
                        : browse(queued: !catalog.queueOnly, saved: false),
                  ),
                  selected: detail ? queue.contains(title) : catalog.queueOnly,
                ),
              ],
            );
            final left = detail
                ? action(
                    'detail-back',
                    Icons.arrow_back,
                    tr('К каталогу', 'Back to catalogue'),
                    () => unawaited(back()),
                  )
                : collections;
            final right = detail
                ? collections
                : RemoteButton(
                    id: 'refresh',
                    focus: remote,
                    flat: true,
                    radius: 24,
                    onPressed: () => unawaited(browse()),
                    child: Tooltip(
                      message: tr('Обновить', 'Refresh'),
                      child: const Icon(Icons.refresh),
                    ),
                  );
            if (!widget.runtime.tv) {
              return Column(
                children: [
                  switcher,
                  const SizedBox(height: 6),
                  Row(
                    key: const ValueKey('android-mobile-navigation'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      action(
                        'home',
                        Icons.home_outlined,
                        tr('Домой', 'Home'),
                        home,
                      ),
                      const SizedBox(width: 6),
                      action(
                        'downloads',
                        Icons.download_outlined,
                        tr('Загрузки', 'Downloads'),
                        downloads,
                      ),
                      const SizedBox(width: 6),
                      action(
                        'settings',
                        Icons.settings_outlined,
                        tr('Настройки', 'Settings'),
                        settings,
                      ),
                      const SizedBox(width: 6),
                      collections,
                    ],
                  ),
                ],
              );
            }
            return bounds.maxWidth < 600
                ? Column(
                    children: [
                      switcher,
                      const SizedBox(height: 6),
                      Row(children: [left, const Spacer(), right]),
                    ],
                  )
                : Row(
                    key: const ValueKey('android-catalog-toolbar'),
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: left,
                        ),
                      ),
                      switcher,
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: right,
                        ),
                      ),
                    ],
                  );
          },
        ),
      ],
    ),
  );

  void loadNearEnd() {
    if (!mounted ||
        screen != 'catalog' ||
        catalog.selected != null ||
        !gridScroll.hasClients ||
        !gridScroll.position.hasContentDimensions ||
        catalog.error != null ||
        catalog.loading ||
        catalog.loadingMore ||
        !catalog.hasMore) {
      return;
    }
    if (gridScroll.position.extentAfter < 300) unawaited(catalog.loadMore());
  }

  Widget _catalog() => Column(
    children: [
      if (catalog.loading || catalog.loadingMore)
        LinearProgressIndicator(value: budget.lite ? 0.5 : null),
      if (catalog.error != null)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            tr(
              'Не удалось загрузить каталог. Нажмите «Обновить», чтобы повторить.',
              'Could not load catalogue. Use Refresh to retry.',
            ),
          ),
        ),
      Expanded(
        child: catalog.items.isEmpty
            ? Center(
                child: Text(
                  catalog.loading
                      ? tr('Загрузка…', 'Loading…')
                      : catalog.localCollectionOnly
                      ? tr('Список пуст', 'Your list is empty')
                      : tr('Ничего не найдено', 'Nothing found'),
                ),
              )
            : LayoutBuilder(
                builder: (context, bounds) {
                  final columns = widget.runtime.tv
                      ? 6
                      : math.max(2, (bounds.maxWidth / 180).floor());
                  final height =
                      ((bounds.maxWidth - 24 - (columns - 1) * 10) / columns) *
                      1.85;
                  return GridView.builder(
                    key: PageStorageKey('android-grid-${catalog.kind.name}'),
                    controller: gridScroll,
                    padding: const EdgeInsets.all(12),
                    scrollCacheExtent: ScrollCacheExtent.pixels(height * 2),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      mainAxisExtent: height,
                    ),
                    itemCount: catalog.items.length,
                    itemBuilder: (context, i) => _poster(catalog.items[i]),
                  );
                },
              ),
      ),
    ],
  );

  Widget _poster(CatalogTitle title) => RemoteButton(
    key: ValueKey('title-${title.kind.name}-${title.id}'),
    id: 'title-${title.kind.name}-${title.id}',
    focus: remote,
    onPressed: () => open(title),
    tile: true,
    padding: EdgeInsets.zero,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                title.poster == null
                    ? const Center(child: Icon(Icons.movie_outlined, size: 44))
                    : CachedPoster(
                        uri: title.poster!,
                        fallback: title.posterFallback,
                        cache: widget.posterCache,
                        decodeWidth: budget.posterWidth,
                        placeholder: const Icon(Icons.movie_outlined),
                      ),
                if (favorites.contains(title))
                  const Positioned(
                    right: 8,
                    top: 8,
                    child: Icon(Icons.favorite, color: Colors.white),
                  ),
                if (queue.contains(title))
                  const Positioned(
                    left: 8,
                    top: 8,
                    child: Icon(Icons.playlist_play, color: Colors.white),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 82,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Tooltip(
                      message: title.title(preferences.english),
                      child: Text(
                        title.title(preferences.english),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  Text(
                    [
                      if (title.year != null) '${title.year}',
                      if (title.rating != null)
                        '★ ${title.rating!.toStringAsFixed(1)}',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> searchSources() async {
    final selected = catalog.selected;
    final query = await dialog<String>(
      AndroidSearchDialog(
        initial: sourceQuery,
        english: preferences.english,
        allowVoice: false,
        label: tr('Поиск по найденному', 'Search results'),
      ),
      restore: 'source-search',
    );
    if (!mounted ||
        query == null ||
        catalog.selected?.id != selected?.id ||
        catalog.selected?.kind != selected?.kind) {
      return;
    }
    setState(() {
      sourceQuery = query.trim();
      sourceLimit = 8;
    });
    resetSourceScroll();
  }

  Future<void> chooseSourceNumber({required bool season}) async {
    final title = catalog.selected;
    final values = season
        ? availableSourceSeasons(catalog.sources)
        : availableSourceEpisodes(catalog.sources, season: sourceSeason);
    final selected = season ? sourceSeason : sourceEpisode;
    final label = season ? tr('Сезон', 'Season') : tr('Серия', 'Episode');
    final choice = await dialog<int>(
      Builder(
        builder: (context) => AlertDialog(
          title: Text(label),
          content: SizedBox(
            width: 360,
            height: math.min(320, MediaQuery.sizeOf(context).height * .5),
            child: ListView.builder(
              itemCount: values.length + 1,
              itemBuilder: (context, index) {
                final value = index == 0 ? null : values[index - 1];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: FilledButton(
                    key: ValueKey('source-number-${value ?? 'all'}'),
                    autofocus: widget.runtime.tv && index == 0,
                    onPressed: () => Navigator.pop(context, value ?? -1),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 28,
                          child: value == selected
                              ? const Icon(Icons.check)
                              : null,
                        ),
                        Expanded(
                          child: Text(
                            value == null
                                ? (season
                                      ? tr('Все сезоны', 'All seasons')
                                      : tr('Все серии', 'All episodes'))
                                : '$label $value',
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('Закрыть', 'Close')),
            ),
          ],
        ),
      ),
      restore: season ? 'source-season' : 'source-episode',
    );
    if (!mounted ||
        choice == null ||
        catalog.selected?.id != title?.id ||
        catalog.selected?.kind != title?.kind) {
      return;
    }
    setState(() {
      if (season) {
        sourceSeason = choice < 0 ? null : choice;
        sourceEpisode = null;
      } else {
        sourceEpisode = choice < 0 ? null : choice;
      }
      sourceLimit = 8;
    });
    resetSourceScroll();
  }

  Widget _sourceToolbar() => LayoutBuilder(
    builder: (context, bounds) {
      final series = catalog.selected?.kind == CatalogKind.series;
      Widget number(bool season) {
        final value = season ? sourceSeason : sourceEpisode;
        final name = season ? tr('Сезон', 'Season') : tr('Серия', 'Episode');
        return SizedBox(
          width: bounds.maxWidth < 480 ? 92 : 112,
          child: RemoteButton(
            id: season ? 'source-season' : 'source-episode',
            focus: remote,
            radius: 28,
            selected: value != null,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            onPressed: () => unawaited(chooseSourceNumber(season: season)),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$name${value == null ? '' : ' $value'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 20),
              ],
            ),
          ),
        );
      }

      return Row(
        children: [
          Expanded(
            child: RemoteButton(
              id: 'source-search',
              focus: remote,
              radius: 28,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              onPressed: () => unawaited(searchSources()),
              child: Row(
                children: [
                  const Icon(Icons.search),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      sourceQuery.isEmpty
                          ? tr('Поиск по найденному', 'Search results')
                          : sourceQuery,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (sourceQuery.isNotEmpty) ...[
            const SizedBox(width: 6),
            RemoteButton(
              id: 'source-clear',
              focus: remote,
              radius: 28,
              padding: const EdgeInsets.all(10),
              onPressed: () {
                setState(() {
                  sourceQuery = '';
                  sourceLimit = 8;
                });
                resetSourceScroll();
                remote.restore('source-search');
              },
              child: const Icon(Icons.close),
            ),
          ],
          if (series) ...[
            const SizedBox(width: 6),
            number(true),
            const SizedBox(width: 6),
            number(false),
          ],
        ],
      );
    },
  );

  List<CatalogSource> get filteredSources {
    String normalize(String value) => value.toLowerCase().replaceAll('ё', 'е');
    final words = normalize(sourceQuery)
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty);
    return catalog.sources.where((source) {
      final text = normalize(
        [
          source.row.title,
          source.row.provider.label,
          source.row.quality,
          source.audio,
          source.channel,
        ].whereType<String>().join(' '),
      );
      return !hiddenSourceProviders.contains(source.row.provider) &&
          words.every(text.contains) &&
          (sourceSeason == null ||
              sourceMatchesSeason(source, sourceSeason!)) &&
          (sourceEpisode == null ||
              sourceEpisodes(
                source,
                season: sourceSeason,
              ).contains(sourceEpisode));
    }).toList();
  }

  void resetSourceScroll() {
    if (sourcesScroll.hasClients) sourcesScroll.jumpTo(0);
    WidgetsBinding.instance.addPostFrameCallback((_) => loadSourcesNearEnd());
  }

  void scheduleSourceLoad() {
    if (sourceLoadScheduled || !mounted) return;
    sourceLoadScheduled = true;
    // Scroll correction can fire during layout, before newly added rows have
    // updated the extent. Read the final extent to avoid fetching too early.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      sourceLoadScheduled = false;
      _loadSourcesNearEnd();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void loadSourcesNearEnd() => scheduleSourceLoad();

  void _loadSourcesNearEnd() {
    if (!mounted ||
        screen != 'catalog' ||
        catalog.selected == null ||
        modal ||
        playing ||
        !sourcesScroll.hasClients ||
        !sourcesScroll.position.hasContentDimensions ||
        sourcesScroll.position.extentAfter > 450) {
      return;
    }
    if (sourceLimit < filteredSources.length) {
      setState(() => sourceLimit += 8);
      WidgetsBinding.instance.addPostFrameCallback((_) => loadSourcesNearEnd());
      return;
    }
    for (final entry in catalog.providerStates.entries.toList()) {
      if (!hiddenSourceProviders.contains(entry.key) &&
          entry.value.hasMore &&
          !entry.value.loading &&
          entry.value.error == null) {
        unawaited(catalog.loadMoreSources(entry.key));
      }
    }
  }

  Widget _details() {
    final title = catalog.selected!;
    final visible = filteredSources.take(sourceLimit).toList();
    return Column(
      children: [
        if (catalog.sourcesLoading || catalog.detailsLoading || playing)
          LinearProgressIndicator(value: budget.lite ? 0.5 : null),
        if (!widget.runtime.tv)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: _sourceToolbar(),
          ),
        Expanded(
          child: SingleChildScrollView(
            key: ValueKey('sources-${title.kind.name}-${title.id}'),
            controller: sourcesScroll,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, bounds) {
                    final description = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title.title(preferences.english),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          [
                            if (title.year != null) '${title.year}',
                            if (title.rating != null)
                              '★ ${title.rating!.toStringAsFixed(1)}',
                            if (title.genres != null) title.genres!,
                          ].join(' · '),
                        ),
                        const SizedBox(height: 16),
                        Text(title.synopsis(preferences.english)),
                        if (title.trailer != null) ...[
                          const SizedBox(height: 12),
                          button(
                            'trailer',
                            tr('Трейлер', 'Trailer'),
                            () => unawaited(watchTrailer(title)),
                            icon: Icons.movie_outlined,
                          ),
                        ],
                      ],
                    );
                    if (title.poster == null || bounds.maxWidth < 480) {
                      return description;
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 150,
                          height: 225,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: CachedPoster(
                              uri: title.poster!,
                              fallback: title.posterFallback,
                              cache: widget.posterCache,
                              decodeWidth: budget.posterWidth,
                              placeholder: const Icon(Icons.movie_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(child: description),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final provider in catalog.providerStates.keys)
                      button(
                        'source-provider-${provider.name}',
                        provider.label,
                        () {
                          setState(() {
                            if (!hiddenSourceProviders.add(provider)) {
                              hiddenSourceProviders.remove(provider);
                            }
                            sourceLimit = 8;
                          });
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => loadSourcesNearEnd(),
                          );
                        },
                        selected: !hiddenSourceProviders.contains(provider),
                        icon: hiddenSourceProviders.contains(provider)
                            ? Icons.check_box_outline_blank
                            : Icons.check_box,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (visible.isEmpty && !catalog.sourcesLoading)
                  Text(
                    tr(
                      sourceQuery.isEmpty
                          ? 'Доступных источников пока нет. Можно повторить поиск или вернуться.'
                          : 'По запросу ничего не найдено.',
                      sourceQuery.isEmpty
                          ? 'No sources yet. Retry or go back.'
                          : 'No matching results.',
                    ),
                  ),
                for (final source in visible)
                  Padding(
                    key: ValueKey(
                      'source-row-${source.row.provider.name}-${source.row.id}',
                    ),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AndroidSourceCard(
                      source: source,
                      posterCache: widget.posterCache,
                      previewDecodeWidth: budget.posterWidth,
                      focus: remote,
                      english: preferences.english,
                      series: title.kind == CatalogKind.series,
                      onDownload: !widget.runtime.tv && source.row.isTorrent
                          ? () => unawaited(downloadSource(source))
                          : null,
                      onPlay: source.canWatch
                          ? () => unawaited(play(source))
                          : null,
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in catalog.providerStates.entries)
                      if (!hiddenSourceProviders.contains(entry.key) &&
                          entry.value.error != null)
                        button(
                          'more-${entry.key.name}',
                          '${tr('Повторить', 'Retry')} · ${entry.key.label}',
                          () async {
                            await catalog.loadMoreSources(entry.key);
                            if (mounted &&
                                catalog.selected?.id == title.id &&
                                remote.last == 'more-${entry.key.name}') {
                              final source = visible.lastOrNull;
                              remote.restore(
                                source == null
                                    ? 'source-provider-${entry.key.name}'
                                    : 'source-${source.row.provider.name}-${source.row.id}',
                                fallback: 'detail-back',
                              );
                            }
                          },
                        ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _settings() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            button(
              'settings-back',
              tr('Назад', 'Back'),
              () => unawaited(back()),
              icon: Icons.arrow_back,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                tr('Настройки', 'Settings'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('Интерфейс', 'Interface'),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          button(
                            'language',
                            preferences.english ? 'Русский' : 'English',
                            () => unawaited(
                              save(
                                preferences.copyWith(
                                  language: preferences.english
                                      ? AppLanguage.ru
                                      : AppLanguage.en,
                                ),
                              ),
                            ),
                          ),
                          button(
                            'appearance',
                            tr('Сменить тему', 'Change theme'),
                            () => unawaited(
                              save(
                                preferences.copyWith(
                                  appearance:
                                      preferences.appearance ==
                                          AppAppearance.dark
                                      ? AppAppearance.light
                                      : AppAppearance.dark,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('Провайдеры', 'Providers'),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final provider in SourceProvider.values.toSet())
                            button(
                              'provider-${provider.name}',
                              provider.label,
                              () async {
                                final enabled = preferences.providers
                                    .intersection(
                                      SourceProvider.values.toSet(),
                                    );
                                if (!enabled.remove(provider)) {
                                  enabled.add(provider);
                                }
                                await save(
                                  preferences.copyWith(providers: enabled),
                                );
                                await catalog.configureProviders(enabled);
                              },
                              selected: preferences.providers.contains(
                                provider,
                              ),
                              icon: preferences.providers.contains(provider)
                                  ? Icons.check_box
                                  : Icons.check_box_outline_blank,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: button(
                  'about',
                  tr('О приложении', 'About'),
                  () => unawaited(about()),
                  icon: Icons.info_outline,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}
