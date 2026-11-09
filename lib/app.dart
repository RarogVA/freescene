import 'package:freescene_provider_api/freescene_provider_api.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'navigation/back_swipe_guard.dart';
import 'domain/notifications.dart';
import 'settings/preferences.dart';
import 'torrent/native_torrent.dart';
import 'torrent/downloads_page.dart';
import 'settings/settings_store.dart';
import 'settings/license_document.dart';
import 'theme/freescene_theme.dart';
import 'catalog/catalog_models.dart';
import 'catalog/catalog_controller.dart';
import 'catalog/catalog_page.dart';
import 'catalog/catalog_kind_switch.dart';
import 'catalog/favorites.dart';
import 'catalog/watch_queue.dart';
import 'catalog/catalog_filter_dialog.dart';
import 'catalog/source_import.dart';
import 'downloads/video_quality_dialog.dart';
import 'android/android_app.dart';

void runFreeScene({required ProviderSetup providers}) {
  ProviderSetup.install(providers);
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'FreeScene',
    ], await rootBundle.loadString('assets/branding/LICENSE.txt'));
    for (final entry in {
      ...{
        'libtorrent': 'libtorrent-LICENSE.txt',
        'try_signal': 'try_signal-LICENSE.txt',
        'Boost': 'Boost-LICENSE.txt',
        'OpenSSL': 'OpenSSL-LICENSE.txt',
        'nlohmann/json': 'nlohmann-json-LICENSE.txt',
      },
      if (!Platform.isAndroid) ...{
        'libVLC': 'libVLC-LGPL-2.1.txt',
        'VLC / FFmpeg / contrib': 'VLC-THIRD-PARTY-NOTICES.txt',
      },
      'Play': 'Play-OFL.txt',
      if (Platform.isAndroid) 'AndroidX Media3': 'AndroidX-Media3-LICENSE.txt',
      if (Platform.isAndroid) ...{
        'FFmpeg audio': 'ANDROID-AUDIO-NOTICES.txt',
        'FFmpeg LGPL 2.1': 'libVLC-LGPL-2.1.txt',
      },
    }.entries) {
      yield LicenseEntryWithLineBreaks([
        entry.key,
      ], await rootBundle.loadString('licenses/${entry.value}'));
    }
  });
  runApp(
    Platform.isAndroid
        ? const AndroidBootstrap()
        : FreeSceneBootstrap(store: SettingsStore.application()),
  );
}

class FreeSceneBootstrap extends StatefulWidget {
  const FreeSceneBootstrap({required this.store, super.key});
  final SettingsStore store;
  @override
  State<FreeSceneBootstrap> createState() => _FreeSceneBootstrapState();
}

class _FreeSceneBootstrapState extends State<FreeSceneBootstrap> {
  late Future<Preferences> _loading = widget.store.load();
  late final _favorites = FavoritesController(
    store: FavoritesStore(widget.store.directory),
  )..restore();
  late final _queue = QueueController(store: QueueStore(widget.store.directory))
    ..restore();
  late final _catalogRepository = ProviderSetup.current.createCatalog(
    android: false,
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<Preferences>(
    future: _loading,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return FreeSceneApp(
          initialPreferences: snapshot.requireData,
          savePreferences: widget.store.save,
          nativeService: const NativeTorrentService(),
          catalogRepository: _catalogRepository,
          favorites: _favorites,
          queue: _queue,
        );
      }
      return MaterialApp(
        title: 'FreeScene',
        home: Scaffold(
          body: Center(
            child: snapshot.hasError
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Не удалось прочитать настройки FreeScene'),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () =>
                            setState(() => _loading = widget.store.load()),
                        child: const Text('Повторить'),
                      ),
                    ],
                  )
                : const CircularProgressIndicator(),
          ),
        ),
      );
    },
  );
}

enum _Page { movies, series, games, downloads, settings }

class FreeSceneApp extends StatefulWidget {
  const FreeSceneApp({
    required this.initialPreferences,
    required this.savePreferences,
    this.nativeService,
    this.catalogRepository,
    this.favorites,
    this.queue,
    super.key,
  });
  final Preferences initialPreferences;
  final Future<void> Function(Preferences) savePreferences;
  final NativeTorrentService? nativeService;
  final CatalogRepository? catalogRepository;
  final FavoritesController? favorites;
  final QueueController? queue;

  @override
  State<FreeSceneApp> createState() => _FreeSceneAppState();
}

class _FreeSceneAppState extends State<FreeSceneApp> {
  late Preferences _preferences = widget.initialPreferences;
  _Page _page = _Page.movies;
  _Page _lastCatalogPage = _Page.movies;
  bool _showFavorites = false, _showQueue = false;
  late final _favorites = widget.favorites ?? FavoritesController();
  late final _queue = widget.queue ?? QueueController();
  bool get _sidebarCollapsed => _preferences.sidebarCollapsed;
  int _catalogViewGeneration = 0;
  TorrentController? _torrents;
  CatalogController? _catalog;
  final _search = TextEditingController();
  String _catalogSearch = '', _favoriteSearch = '', _queueSearch = '';
  final _navigator = GlobalKey<NavigatorState>();
  Timer? _searchDebounce;
  @override
  void initState() {
    super.initState();
    if (widget.nativeService != null) {
      NativeTorrentService.channel.setMethodCallHandler((call) async {
        if (call.method == 'canOfferStartupUpdate') {
          return mounted && !(_navigator.currentState?.canPop() ?? true);
        } else if (call.method == 'navigateBack') {
          return _navigateBack(call.arguments);
        } else if (call.method == 'applicationWillTerminate') {
          _torrents?.stopForShutdown();
          _searchDebounce?.cancel();
        } else if (call.method == 'openLicenses') {
          final notices = await collectLicenseNotices();
          if (mounted) {
            await widget.nativeService!.call('showLicenses', {'text': notices});
          }
        }
      });
      unawaited(
        widget.nativeService!
            .call('configureUI', {
              'english': _preferences.english,
              'dark': _preferences.appearance == AppAppearance.dark,
            })
            .catchError((_) => null),
      );
      _torrents = TorrentController(
        widget.nativeService!,
        () => _preferences.notifications,
        english: () => _preferences.english,
        chooseVideo: _chooseVideo,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        try {
          await widget.nativeService!.call('requestAppPermissionsIfNeeded');
        } catch (_) {
          /* Native status will report unavailable access. */
        }
        if (mounted) _torrents?.start();
      });
    }
    if (widget.catalogRepository != null) {
      widget.catalogRepository!.configureProviders(_preferences.providers);
      _catalog = CatalogController(
        widget.catalogRepository!,
        favorites: _favorites,
        queue: _queue,
      )..browse();
    }
  }

  @override
  void dispose() {
    if (widget.nativeService != null) {
      NativeTorrentService.channel.setMethodCallHandler(null);
    }
    _torrents?.dispose();
    _catalog?.dispose();
    _favorites.dispose();
    _queue.dispose();
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  final _messenger = GlobalKey<ScaffoldMessengerState>();

  String text(String ru, String en) => _preferences.english ? en : ru;

  Widget _catalogSwitch() => CatalogKindSwitch(
    key: const ValueKey('catalog-kind-switch'),
    value: switch (_lastCatalogPage) {
      _Page.series => CatalogKind.series,
      _Page.games => CatalogKind.games,
      _ => CatalogKind.movies,
    },
    english: _preferences.english,
    onChanged: (kind) => _selectPage(switch (kind) {
      CatalogKind.movies => _Page.movies,
      CatalogKind.series => _Page.series,
      CatalogKind.games => _Page.games,
    }),
  );

  CatalogKind? get _catalogKind => switch (_page) {
    _Page.movies => CatalogKind.movies,
    _Page.series => CatalogKind.series,
    _Page.games => CatalogKind.games,
    _ => null,
  };
  void _selectPage(_Page value, {bool? favoritesOnly, bool? queueOnly}) {
    _searchDebounce?.cancel();
    var nextFavorites = favoritesOnly ?? _showFavorites;
    var nextQueue = queueOnly ?? _showQueue;
    if (favoritesOnly == true) nextQueue = false;
    if (queueOnly == true) nextFavorites = false;
    final changedMode =
        nextFavorites != _showFavorites || nextQueue != _showQueue;
    final changedSection = value != _page || changedMode;
    if (changedSection) _catalog?.resetFilters();
    if (changedMode) {
      if (_showQueue) {
        _queueSearch = _search.text;
      } else if (_showFavorites) {
        _favoriteSearch = _search.text;
      } else {
        _catalogSearch = _search.text;
      }
      _search.text = nextQueue
          ? _queueSearch
          : nextFavorites
          ? _favoriteSearch
          : _catalogSearch;
    }
    setState(() {
      _page = value;
      _showFavorites = nextFavorites;
      _showQueue = nextQueue;
      if (_catalogKind != null) _lastCatalogPage = value;
    });
    if (_catalogKind != null && _catalog != null) {
      if (!changedSection &&
          _catalog!.kind == _catalogKind &&
          _catalog!.search == _search.text.trim() &&
          _catalog!.favoritesOnly == _showFavorites &&
          _catalog!.queueOnly == _showQueue) {
        _catalog!.back();
      } else {
        unawaited(
          _catalog!.browse(
            kind: _catalogKind,
            search: _search.text.trim(),
            favoritesOnly: _showFavorites,
            queueOnly: _showQueue,
          ),
        );
      }
    }
  }

  void _toggleFavoritesView() {
    _selectPage(
      _lastCatalogPage,
      favoritesOnly: !(_catalogKind != null && _showFavorites),
      queueOnly: false,
    );
  }

  void _toggleQueueView() {
    _selectPage(
      _lastCatalogPage,
      favoritesOnly: false,
      queueOnly: !(_catalogKind != null && _showQueue),
    );
  }

  bool _navigateBack(dynamic arguments) {
    if (!mounted || _navigator.currentState?.canPop() == true) return false;
    var editing =
        FocusManager.instance.primaryFocus?.context?.widget is EditableText;
    FocusManager.instance.primaryFocus?.context?.visitAncestorElements((
      element,
    ) {
      if (element.widget is EditableText) {
        editing = true;
        return false;
      }
      return true;
    });
    if (editing) return false;
    if (arguments is! Map || arguments['x'] is! num || arguments['y'] is! num) {
      return false;
    }
    final point = Offset(
      (arguments['x'] as num).toDouble(),
      (arguments['y'] as num).toDouble(),
    );
    if (!point.dx.isFinite ||
        !point.dy.isFinite ||
        BackSwipeGuard.blocks(point)) {
      return false;
    }
    if (_catalogKind != null && _catalog?.selected != null) {
      _catalog!.back();
      return true;
    }
    if (_page == _Page.settings || _page == _Page.downloads) {
      _selectPage(_lastCatalogPage);
      return true;
    }
    if (_catalogKind != null && (_showFavorites || _showQueue)) {
      _selectPage(_lastCatalogPage, favoritesOnly: false, queueOnly: false);
      return true;
    }
    return false;
  }

  void _goHome() {
    _searchDebounce?.cancel();
    _navigator.currentState?.popUntil((route) => route.isFirst);
    _search.clear();
    _catalogSearch = '';
    _favoriteSearch = '';
    _queueSearch = '';
    setState(() {
      _page = _Page.movies;
      _lastCatalogPage = _Page.movies;
      _showFavorites = false;
      _showQueue = false;
      ++_catalogViewGeneration;
    });
    unawaited(_catalog?.resetToHome());
  }

  void _searchChanged(String value, {bool immediate = false}) {
    _searchDebounce?.cancel();
    if (_catalog == null || _catalogKind == null) return;
    if (immediate) {
      unawaited(_catalog!.browse(search: value.trim()));
    } else {
      _searchDebounce = Timer(
        const Duration(milliseconds: 350),
        () => _catalog?.browse(search: value.trim()),
      );
    }
  }

  Widget _catalogFilterButton() {
    Widget button(BuildContext context) {
      final enabled =
          _catalog != null &&
          _catalogKind != null &&
          !_showFavorites &&
          !_showQueue;
      final active = enabled && _catalog!.filter.active;
      final colors = Theme.of(context).colorScheme;
      return Semantics(
        toggled: active,
        child: IconButton.filledTonal(
          key: const ValueKey('catalog-filter'),
          tooltip: text('Фильтр', 'Filter'),
          isSelected: active,
          style: active
              ? IconButton.styleFrom(
                  backgroundColor: colors.errorContainer,
                  foregroundColor: colors.onErrorContainer,
                )
              : null,
          onPressed: enabled ? _filterCatalog : null,
          icon: const Icon(Icons.filter_alt_outlined),
        ),
      );
    }

    return _catalog == null
        ? Builder(builder: button)
        : ListenableBuilder(
            listenable: _catalog!,
            builder: (context, _) => button(context),
          );
  }

  Future<void> _filterCatalog() async {
    final filter = await showDialog<CatalogFilter>(
      context: _navigator.currentContext!,
      builder: (context) => CatalogFilterDialog(
        initial: _catalog!.filter,
        english: _preferences.english,
        kind: _catalog!.kind,
      ),
    );
    if (mounted && filter != null) await _catalog!.browse(filter: filter);
  }

  Future<TorrentFile?> _chooseVideo(TorrentTask task) async {
    final index = await widget.nativeService!.call('choosePlayerVideo', {
      'id': task.id,
    });
    if (!mounted || index is! int) return null;
    return task.videos.where((file) => file.index == index).firstOrNull;
  }

  Future<void> _useCatalogSource(CatalogSource source, bool watch) async {
    final resolved = await _catalog!.repository.resolve(source);
    if (!watch &&
        resolved.row.provider == ProviderSetup.current.downloadProvider) {
      final qualities = await _torrents!.videoQualities(resolved.row.id);
      if (!mounted) return;
      final quality = await chooseStreamQuality(
        _navigator.currentContext!,
        qualities,
        _preferences.english,
      );
      if (!mounted || quality == null) return;
      await _torrents!.downloadVideo(
        resolved.row.id,
        resolved.row.title,
        quality,
      );
      if (mounted) _downloadAdded();
      return;
    }
    if (!resolved.row.isTorrent) {
      if (!watch || !resolved.canWatch || resolved.uri == null) {
        throw const FormatException('Playback source is unavailable');
      }
      await _torrents!.watchProvider(
        url: resolved.uri.toString(),
        title: resolved.row.title,
        provider: resolved.row.provider.name,
        kind: resolved.row.watch.name,
        webPlayer: resolved.webPlayer,
        webEpisodes: resolved.webEpisodes.map((e) => e.toJson()).toList(),
      );
      return;
    }
    final id = await importCatalogSource(_torrents!, resolved);
    if (!mounted) return;
    if (watch) {
      await _torrents!.watch(id);
    } else {
      _downloadAdded();
    }
  }

  void _downloadAdded() {
    _messenger.currentState?.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        persist: false,
        content: Text(text('Добавлено в загрузки', 'Added to downloads')),
        action: SnackBarAction(
          label: text('Загрузки', 'Downloads'),
          onPressed: () => _selectPage(_Page.downloads),
        ),
      ),
    );
  }

  Future<void> _showTrailer(CatalogTitle title) async {
    final trailer = title.trailer;
    if (trailer == null || title.kind == CatalogKind.games) return;
    try {
      await widget.nativeService!.call('showTrailer', {
        ...trailer.toJson(),
        'title': title.title(_preferences.english),
      });
    } catch (error) {
      if (!mounted ||
          (error is PlatformException && error.code == 'cancelled')) {
        return;
      }
      _messenger.currentState?.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Text(
            text(
              'Не удалось открыть трейлер. Повторите попытку.',
              'Could not open the trailer. Try again.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _update(Preferences value) async {
    final changedProviders = !setEquals(
      _preferences.providers,
      value.providers,
    );
    final changedUI =
        _preferences.language != value.language ||
        _preferences.appearance != value.appearance;
    setState(() => _preferences = value);
    if (changedProviders && _catalog != null) {
      unawaited(_catalog!.configureProviders(value.providers));
    }
    if (changedUI && widget.nativeService != null) {
      unawaited(
        widget.nativeService!
            .call('configureUI', {
              'english': value.english,
              'dark': value.appearance == AppAppearance.dark,
            })
            .catchError((_) => null),
      );
    }
    try {
      await widget.savePreferences(value);
    } catch (_) {
      if (!mounted) return;
      _messenger.currentState?.showSnackBar(
        SnackBar(
          content: Text(
            text('Не удалось сохранить настройки', 'Could not save settings'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = _preferences.appearance == AppAppearance.dark;
    return MaterialApp(
      title: 'FreeScene',
      navigatorKey: _navigator,
      scaffoldMessengerKey: _messenger,
      debugShowCheckedModeBanner: false,
      locale: Locale(_preferences.language.name),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: FreeSceneTheme.create(dark),
      builder: (context, child) => LayoutBuilder(
        builder: (context, constraints) {
          final factor = _preferences.scale / 100;
          final size = Size(
            constraints.maxWidth / factor,
            constraints.maxHeight / factor,
          );
          return FittedBox(
            fit: BoxFit.fill,
            child: SizedBox.fromSize(
              size: size,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(size: size),
                child: child!,
              ),
            ),
          );
        },
      ),
      home: Scaffold(
        body: Row(
          children: [
            AnimatedContainer(
              key: const ValueKey('sidebar'),
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeInOutCubic,
              width: _sidebarCollapsed ? 76 : 200,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 180;
                  final dense = constraints.maxHeight < 600;
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          children: [
                            const SizedBox(height: 24),
                            _sidebarButton(
                              context,
                              key: const ValueKey('sidebar-home'),
                              compact: compact,
                              dense: dense,
                              label: text('Домой', 'Home'),
                              leading: const Icon(Icons.home_outlined),
                              onTap: _goHome,
                            ),
                            const Spacer(),
                            for (final entry in [
                              (
                                _Page.downloads,
                                Icons.download_outlined,
                                text('Загрузки', 'Downloads'),
                              ),
                              (
                                _Page.settings,
                                Icons.settings_outlined,
                                text('Настройки', 'Settings'),
                              ),
                            ])
                              _sidebarButton(
                                context,
                                key: ValueKey('sidebar-${entry.$1.name}'),
                                compact: compact,
                                dense: dense,
                                label: entry.$3,
                                leading: Icon(entry.$2),
                                selected: _page == entry.$1,
                                onTap: () => _selectPage(entry.$1),
                              ),
                            _sidebarButton(
                              context,
                              key: const ValueKey('sidebar-toggle'),
                              compact: compact,
                              dense: dense,
                              label: _sidebarCollapsed
                                  ? text('Развернуть', 'Expand')
                                  : text('Свернуть', 'Collapse'),
                              leading: Icon(
                                _sidebarCollapsed
                                    ? Icons.keyboard_double_arrow_right
                                    : Icons.keyboard_double_arrow_left,
                              ),
                              onTap: () => _update(
                                _preferences.copyWith(
                                  sidebarCollapsed: !_sidebarCollapsed,
                                ),
                              ),
                            ),
                            _sidebarButton(
                              context,
                              key: const ValueKey('about-branding'),
                              compact: compact,
                              dense: dense,
                              label: 'FreeScene',
                              onTap: _showAbout,
                              leading: Image.asset(
                                'assets/branding/app-icon.png',
                                width: 30,
                                height: 30,
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        _catalogFilterButton(),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _search,
                            builder: (context, value, _) => TextField(
                              key: const ValueKey('catalog-search'),
                              controller: _search,
                              enabled: _catalog != null && _catalogKind != null,
                              onChanged: _searchChanged,
                              onSubmitted: (value) =>
                                  _searchChanged(value, immediate: true),
                              decoration: InputDecoration(
                                hintText: text('Поиск', 'Search'),
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: value.text.isEmpty
                                    ? null
                                    : IconButton(
                                        key: const ValueKey(
                                          'catalog-search-clear',
                                        ),
                                        tooltip: text(
                                          'Очистить поиск',
                                          'Clear search',
                                        ),
                                        onPressed: () {
                                          _search.clear();
                                          _searchChanged('', immediate: true);
                                        },
                                        icon: const Icon(Icons.close),
                                      ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                isDense: true,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_catalogKind != null && _catalog == null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                      child: Align(
                        alignment: Alignment.center,
                        child: _catalogSwitch(),
                      ),
                    ),
                  Expanded(
                    child: _page == _Page.settings
                        ? _settings()
                        : _page == _Page.downloads && _torrents != null
                        ? DownloadsPage(
                            controller: _torrents!,
                            english: _preferences.english,
                            onBack: () => _selectPage(_lastCatalogPage),
                          )
                        : _catalog != null && _catalogKind != null
                        ? CatalogPageView(
                            key: ValueKey(
                              'catalog-view-$_catalogViewGeneration',
                            ),
                            onToggleFavorites: _toggleFavoritesView,
                            onToggleQueue: _toggleQueueView,
                            onTrailer: widget.nativeService == null
                                ? null
                                : _showTrailer,
                            controller: _catalog!,
                            english: _preferences.english,
                            kindSwitch: _catalogSwitch(),
                            onUseSource: _torrents == null
                                ? null
                                : _useCatalogSource,
                          )
                        : _emptyPage(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyPage() {
    final (title, subtitle, icon) = switch (_page) {
      _Page.movies => (
        text('Фильмы', 'Films'),
        text('Пока нет фильмов', 'No films yet'),
        Icons.local_movies_outlined,
      ),
      _Page.series => (
        text('Сериалы', 'Series'),
        text('Пока нет сериалов', 'No series yet'),
        Icons.tv_outlined,
      ),
      _Page.games => (
        text('Игры', 'Games'),
        text('Пока нет игр', 'No games yet'),
        Icons.sports_esports_outlined,
      ),
      _ => (
        text('Загрузки', 'Downloads'),
        text('Загрузок пока нет', 'No downloads yet'),
        Icons.download_outlined,
      ),
    };
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_catalogKind == null)
            Text(
              title,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
            ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 52),
                  const SizedBox(height: 20),
                  Text(subtitle),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebarButton(
    BuildContext context, {
    Key? key,
    required bool compact,
    required String label,
    required Widget leading,
    required VoidCallback? onTap,
    bool dense = false,
    bool selected = false,
  }) => Tooltip(
    message: label,
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: dense ? 2 : 4),
      child: compact
          ? IconButton.filledTonal(
              key: key,
              onPressed: onTap,
              icon: leading,
              style: IconButton.styleFrom(
                backgroundColor: selected
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Colors.transparent,
                minimumSize: Size(52, dense ? 40 : 48),
              ),
            )
          : ListTile(
              key: key,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              selected: selected,
              enabled: onTap != null,
              minTileHeight: dense ? 40 : null,
              selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
              leading: leading,
              title: Text(label, maxLines: 1, overflow: TextOverflow.clip),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              minLeadingWidth: 24,
              onTap: onTap,
            ),
    ),
  );

  Future<void> _showAbout() async {
    if (widget.nativeService != null) {
      await widget.nativeService!.call('showAbout');
    }
  }

  Widget _settings() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: Row(
          key: const ValueKey('settings-header'),
          children: [
            IconButton(
              key: const ValueKey('settings-back'),
              tooltip: text('Назад к каталогу', 'Back to catalogue'),
              onPressed: () => _selectPage(_lastCatalogPage),
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text('Настройки', 'Settings'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
      Expanded(child: _settingsContent()),
    ],
  );

  Widget _settingsContent() => ListView(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth >= 896
              ? (constraints.maxWidth - 16) / 2
              : constraints.maxWidth;
          final cards = <Widget>[
            Card(
              key: const ValueKey('settings-interface'),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text('Интерфейс', 'Appearance'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _settingControl(
                      text('Язык', 'Language'),
                      SegmentedButton<AppLanguage>(
                        segments: const [
                          ButtonSegment(
                            value: AppLanguage.ru,
                            label: Text('Русский'),
                          ),
                          ButtonSegment(
                            value: AppLanguage.en,
                            label: Text('English'),
                          ),
                        ],
                        selected: {_preferences.language},
                        onSelectionChanged: (value) => _update(
                          _preferences.copyWith(language: value.single),
                        ),
                      ),
                    ),
                    _settingControl(
                      text('Тема', 'Theme'),
                      SegmentedButton<AppAppearance>(
                        segments: [
                          ButtonSegment(
                            value: AppAppearance.light,
                            label: Text(text('Светлая', 'Light')),
                          ),
                          ButtonSegment(
                            value: AppAppearance.dark,
                            label: Text(text('Тёмная', 'Dark')),
                          ),
                        ],
                        selected: {_preferences.appearance},
                        onSelectionChanged: (value) => _update(
                          _preferences.copyWith(appearance: value.single),
                        ),
                      ),
                    ),
                    _settingControl(
                      text('Масштаб', 'Scale'),
                      SegmentedButton<int>(
                        segments: [
                          for (final value in [100, 125, 150])
                            ButtonSegment(
                              value: value,
                              label: Text('$value %'),
                            ),
                        ],
                        selected: {_preferences.scale},
                        onSelectionChanged: (value) =>
                            _update(_preferences.copyWith(scale: value.single)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Card(
              key: const ValueKey('settings-notifications'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              text('Уведомления', 'Notifications'),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    for (final event in NotificationEvent.values)
                      SwitchListTile(
                        key: ValueKey(event),
                        title: Text(event.label(_preferences.english)),
                        value: _preferences.notifications.contains(event),
                        onChanged: (enabled) {
                          final changed = {..._preferences.notifications};
                          enabled ? changed.add(event) : changed.remove(event);
                          _update(
                            _preferences.copyWith(notifications: changed),
                          );
                        },
                      ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        text(
                          'Системные баннеры со звуком',
                          'System banners with sound',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_torrents != null) ...[
              DownloadLimitsCard(
                key: const ValueKey('settings-download-limits'),
                controller: _torrents!,
                english: _preferences.english,
              ),
            ],
            Card(
              key: const ValueKey('settings-providers'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        text('Провайдеры', 'Providers'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        text(
                          'Источники для поиска и отображения в карточках. ',
                          'Sources to search and display in title details. ',
                        ),
                      ),
                    ),
                    for (final provider in Preferences.availableProviders)
                      CheckboxListTile(
                        key: ValueKey('provider-${provider.name}'),
                        title: Text(provider.label),
                        subtitle: provider.descriptor?.descriptionRu != null
                            ? Text(
                                text(
                                  provider.descriptor!.descriptionRu!,
                                  provider.descriptor!.descriptionEn ??
                                      provider.descriptor!.descriptionRu!,
                                ),
                              )
                            : null,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _preferences.providers.contains(provider),
                        onChanged: (enabled) {
                          final changed = {..._preferences.providers};
                          enabled == true
                              ? changed.add(provider)
                              : changed.remove(provider);
                          _update(_preferences.copyWith(providers: changed));
                        },
                      ),
                  ],
                ),
              ),
            ),
          ];
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final card in cards) SizedBox(width: width, child: card),
            ],
          );
        },
      ),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: widget.nativeService == null
              ? null
              : () => widget.nativeService!.call('requestAppPermissions'),
          icon: const Icon(Icons.admin_panel_settings_outlined),
          style: _aboutActionStyle(),
          label: Text(
            text('Перезапросить разрешения', 'Request permissions again'),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: _showAbout,
          style: _aboutActionStyle(),
          icon: const Icon(Icons.info_outline),
          label: Text(text('О приложении', 'About')),
        ),
      ),
    ],
  );

  ButtonStyle _aboutActionStyle() => FreeSceneTheme.aboutActionStyle(
    dark: _preferences.appearance == AppAppearance.dark,
    minimumWidth: 300,
  );

  Widget _settingControl(String label, Widget control) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 20,
      runSpacing: 8,
      children: [
        SizedBox(width: 100, child: Text(label)),
        control,
      ],
    ),
  );
}
