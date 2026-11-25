import '../widgets/app_icons.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import 'catalog_controller.dart';
import 'catalog_models.dart';
import 'catalog_tile.dart';
import 'title_context_menu.dart';
import 'favorite_button.dart';
import 'queue_button.dart';
import 'favorites.dart';
import 'source_seasons.dart' as seasons;
import 'cached_poster.dart';
import '../widgets/catalog_style.dart';
import '../navigation/catalog_section_swipe.dart';
import '../widgets/desktop_controls.dart';
import '../domain/provider_display.dart';
import 'source_metadata.dart';
import 'watched.dart';
import 'truncated_text.dart';
import 'source_format.dart';
export 'source_format.dart' show catalogBytes, sourceEpisodeDisplay;
import '../widgets/source_action_overlay.dart';

String catalogError(Object error, bool english) => error is ProviderError
    ? error.label(english)
    : english
    ? 'Could not complete the request. Retry.'
    : 'Не удалось выполнить запрос. Повторите попытку.';

class CatalogPageView extends StatelessWidget {
  const CatalogPageView({
    required this.controller,
    required this.english,
    this.kindSwitch,
    this.onKindChanged,
    this.searchControls,
    this.onUseSource,
    this.onToggleFavorites,
    this.onToggleQueue,
    this.onTrailer,
    super.key,
  });
  final CatalogController controller;
  final bool english;
  final Widget? kindSwitch;
  final ValueChanged<CatalogKind>? onKindChanged;
  final Widget Function(Widget refresh)? searchControls;
  final Future<void> Function(CatalogSource, bool watch)? onUseSource;
  final VoidCallback? onToggleFavorites;
  final VoidCallback? onToggleQueue;
  final Future<void> Function(CatalogTitle)? onTrailer;
  String tr(String ru, String en) => english ? en : ru;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (controller.selected == null) return _listing(context);
      return _details(context, controller.selected!);
    },
  );
  Widget _error(Object error, VoidCallback retry) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        Expanded(child: Text(catalogError(error, english))),
        TextButton.icon(
          onPressed: retry,
          icon: const Icon(Icons.refresh),
          label: Text(tr('Повторить', 'Retry')),
        ),
      ],
    ),
  );
  String _emptyListingMessage() {
    if (!controller.localCollectionOnly) {
      return tr('Ничего не найдено', 'No results');
    }
    if (controller.kind == CatalogKind.games) {
      return controller.queueOnly
          ? tr(
              'В очередь можно добавлять только фильмы и сериалы',
              'Games cannot be added to the queue',
            )
          : tr(
              'В избранное можно добавлять только фильмы и сериалы',
              'Games cannot be added to favorites',
            );
    }
    if (controller.search.isNotEmpty) {
      return controller.queueOnly
          ? tr(
              'В очереди ничего не найдено',
              'No queued titles match your search',
            )
          : tr(
              'В избранном ничего не найдено',
              'No favorites match your search',
            );
    }
    return controller.queueOnly
        ? tr(
            'Здесь появятся фильмы и сериалы, добавленные в очередь',
            'Films and series you add to the queue will appear here',
          )
        : tr(
            'Здесь появятся отмеченные сердечком фильмы и сериалы',
            'Films and series you mark with a heart will appear here',
          );
  }

  Widget _detailsToolbar(Widget search) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
    child: Row(
      key: const ValueKey('catalog-details-toolbar'),
      children: [
        SizedBox(
          width: 132,
          child: Align(
            alignment: Alignment.centerLeft,
            child: DesktopActionButton(
              key: const ValueKey('catalog-back'),
              icon: Icons.arrow_back_rounded,
              label: tr('Назад', 'Back'),
              onPressed: controller.back,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: search),
      ],
    ),
  );

  Widget _titleActions(CatalogTitle title) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Wrap(
      key: const ValueKey('catalog-title-actions'),
      spacing: 16,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (title.kind != CatalogKind.games && title.trailer != null)
          DesktopActionButton(
            key: const ValueKey('catalog-trailer'),
            onPressed: onTrailer == null ? null : () => onTrailer!(title),
            icon: Icons.movie_outlined,
            label: tr('Трейлер', 'Trailer'),
          ),
        if (controller.favorites case final favorites?
            when FavoritesController.eligible(title))
          FavoriteButton(
            key: ValueKey('favorite-detail-${title.kind.name}-${title.id}'),
            title: title,
            favorites: favorites,
            english: english,
          ),
        if (controller.queue case final queue?
            when FavoritesController.eligible(title))
          QueueButton(
            key: ValueKey('queue-detail-${title.kind.name}-${title.id}'),
            title: title,
            queue: queue,
            english: english,
          ),
      ],
    ),
  );

  void _toggleFavorites() {
    if (onToggleFavorites case final callback?) {
      callback();
    } else {
      unawaited(
        controller.browse(
          favoritesOnly: !controller.favoritesOnly,
          queueOnly: false,
        ),
      );
    }
  }

  void _toggleQueue() {
    if (onToggleQueue case final callback?) {
      callback();
    } else {
      unawaited(
        controller.browse(
          favoritesOnly: false,
          queueOnly: !controller.queueOnly,
        ),
      );
    }
  }

  Widget _collectionButton({required bool queue}) {
    final selected = queue ? controller.queueOnly : controller.favoritesOnly;
    return DesktopActionButton(
      key: ValueKey(queue ? 'catalog-queue' : 'catalog-favorites'),
      icon: queue ? Icons.playlist_play_rounded : Icons.favorite_border_rounded,
      label: queue ? tr('Очередь', 'Queue') : tr('Избранное', 'Favorites'),
      selected: selected,
      onPressed: queue ? _toggleQueue : _toggleFavorites,
    );
  }

  Widget _listingToolbar(BuildContext context) {
    final collection = controller.queueOnly
        ? controller.queue
        : controller.favorites;
    final refresh = DesktopSearchAction(
      key: const ValueKey('catalog-refresh'),
      icon: Icons.refresh_rounded,
      label: tr('Обновить', 'Refresh'),
      onPressed: () => controller.localCollectionOnly
          ? collection?.restore()
          : controller.browse(),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: LayoutBuilder(
        builder: (context, bounds) {
          final narrow = bounds.maxWidth < 900;
          // Reserve the segment width: captions grow right without moving it.
          final switchWidth = narrow
              ? (bounds.maxWidth - 320).clamp(130.0, 360.0)
              : (bounds.maxWidth * .42).clamp(300.0, 520.0);
          final collectionWidth =
              ((bounds.maxWidth - switchWidth - (narrow ? 16 : 288)) / 2).clamp(
                44.0,
                170.0,
              );
          final navigation = <Widget>[
            if (kindSwitch != null) ...[
              SizedBox(width: switchWidth, child: kindSwitch),
              const SizedBox(width: 8),
            ],
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: collectionWidth),
              child: _collectionButton(queue: false),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: collectionWidth),
              child: _collectionButton(queue: true),
            ),
          ];
          final search =
              searchControls?.call(refresh) ??
              Align(alignment: Alignment.centerRight, child: refresh);
          return narrow
              ? Column(
                  key: const ValueKey('catalog-listing-toolbar'),
                  children: [
                    Row(children: navigation),
                    const SizedBox(height: 8),
                    SizedBox(height: 44, child: search),
                  ],
                )
              : Row(
                  key: const ValueKey('catalog-listing-toolbar'),
                  children: [
                    ...navigation,
                    const SizedBox(width: 12),
                    Expanded(child: search),
                  ],
                );
        },
      ),
    );
  }

  Future<void> _titleMenu(BuildContext context, CatalogTitle title) async {
    final favorites = controller.favorites, queue = controller.queue;
    final watched = WatchedScope.of(context);
    final eligible = FavoritesController.eligible(title);
    final result = await showDialog<String>(
      context: context,
      animationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (_) => TitleContextMenu(
        title: title,
        english: english,
        favorite: eligible ? favorites?.contains(title) : null,
        queued: eligible ? queue?.contains(title) : null,
        watched: eligible ? watched?.titleWatched(title) : null,
        favoriteEnabled:
            favorites != null &&
            favorites.ready &&
            !favorites.loading &&
            !favorites.saving,
        queueEnabled:
            queue != null && queue.ready && !queue.loading && !queue.saving,
      ),
    );
    if (!context.mounted) return;
    try {
      switch (result) {
        case 'watch':
          await controller.open(title);
        case 'favorite':
          await favorites!.toggle(title);
        case 'queue':
          await queue!.toggle(title);
        case 'watched':
          await watched!.markTitle(title);
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(catalogError(error, english))));
      }
    }
  }

  Widget _listing(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _listingToolbar(context),
        if (controller.loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: CatalogSectionSwipe(
              key: const ValueKey('catalog-section-swipe'),
              value: controller.kind,
              kinds: CatalogKind.values,
              onChanged: onKindChanged,
              child: _AutoPagedCatalogue(
                controller: controller,
                key: ValueKey(
                  'catalog-${controller.favoritesOnly}-${controller.queueOnly}-${controller.kind}-${controller.search}-${controller.filter.hashCode}',
                ),
                slivers: [
                  if (controller.localCollectionOnly &&
                      (controller.queueOnly
                                  ? controller.queue
                                  : controller.favorites)
                              ?.error !=
                          null)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      sliver: SliverToBoxAdapter(
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                tr(
                                  controller.queueOnly
                                      ? 'Не удалось прочитать очередь. Повторите попытку.'
                                      : 'Не удалось прочитать избранное. Повторите попытку.',
                                  controller.queueOnly
                                      ? 'Could not read the queue. Try again.'
                                      : 'Could not read favorites. Try again.',
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed:
                                  (controller.queueOnly
                                          ? controller.queue
                                          : controller.favorites)
                                      ?.restore,
                              child: Text(tr('Повторить', 'Retry')),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (controller.error != null)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      sliver: SliverToBoxAdapter(
                        child: _error(
                          controller.error!,
                          () => controller.items.isEmpty
                              ? controller.browse()
                              : controller.loadMore(),
                        ),
                      ),
                    ),
                  if (controller.items.isEmpty &&
                      controller.error == null &&
                      (!controller.localCollectionOnly ||
                          (controller.queueOnly
                                      ? controller.queue
                                      : controller.favorites)
                                  ?.error ==
                              null))
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: Text(_emptyListingMessage())),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 220,
                            mainAxisExtent: 298,
                            crossAxisSpacing: 20,
                            mainAxisSpacing: 20,
                          ),
                      delegate: SliverChildBuilderDelegate((_, index) {
                        final item = controller.items[index];
                        return CatalogTile(
                          key: ValueKey('title-${item.id}'),
                          onTap: () => controller.open(item),
                          onContextMenu: () => _titleMenu(context, item),
                          child: PosterCardContent(
                            title: item,
                            english: english,
                            favorite:
                                controller.favorites?.contains(item) ?? false,
                            queued: controller.queue?.contains(item) ?? false,
                          ),
                        );
                      }, childCount: controller.items.length),
                    ),
                  ),
                  if (controller.loadingMore)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _details(BuildContext context, CatalogTitle title) {
    final visibleProviderStates = [
      for (final entry in controller.providerStates.entries)
        if (!providerIsHidden(entry.key)) entry,
    ];
    return SourceTable(
      toolbarBuilder: _detailsToolbar,
      title: title,
      key: ValueKey('${title.kind}-${title.id}'),
      sources: controller.sources,
      providers: controller.providerStates.keys.toList(),
      english: english,
      game: title.kind == CatalogKind.games,
      series: title.kind == CatalogKind.series,
      onUseSource: onUseSource,
      introduction: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        child: _titleDescription(context, title),
      ),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (visibleProviderStates.isEmpty)
            Text(
              tr(
                'Включите провайдеров в настройках, чтобы искать источники.',
                'Enable providers in Settings to search for sources.',
              ),
            ),
          for (final entry in visibleProviderStates)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${providerDisplayLabel(entry.key)} · ${tr('Показано', 'Loaded')}: ${entry.value.items.length} / ${entry.value.total}',
                  ),
                  if (entry.value.loading) const LinearProgressIndicator(),
                  if (entry.value.error != null)
                    _error(
                      entry.value.error!,
                      () => controller.loadMoreSources(entry.key),
                    ),
                  if (!entry.value.loading &&
                      entry.value.error == null &&
                      entry.value.items.isEmpty)
                    Text(tr('Ничего не найдено', 'No sources found')),
                  if (entry.value.hasMore &&
                      !entry.value.loading &&
                      entry.value.error == null)
                    DesktopActionButton(
                      icon: Icons.expand_more_rounded,
                      label:
                          '${tr('Ещё', 'More')} ${providerDisplayLabel(entry.key)}',
                      onPressed: () => controller.loadMoreSources(entry.key),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _titleDescription(
    BuildContext context,
    CatalogTitle title,
  ) => Container(
    key: const ValueKey('desktop-detail-card'),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(28),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Theme.of(context).colorScheme.surfaceContainerHigh,
          Theme.of(context).colorScheme.surfaceContainerLow,
        ],
      ),
      border: Border.all(
        color: Theme.of(context).colorScheme.outlineVariant
            .withValues(alpha: .5),
      ),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final description = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.kind == CatalogKind.series
                  ? tr('СЕРИАЛ', 'SERIES')
                  : title.kind == CatalogKind.games
                  ? tr('ИГРА', 'GAME')
                  : tr('ФИЛЬМ', 'FILM'),
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 2,
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title.title(english),
              style: const TextStyle(
                fontSize: 30,
                height: 1.15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              [
                if (title.year != null) '${title.year}',
                if (title.rating != null)
                  '★ ${title.rating!.toStringAsFixed(1)}',
                ?title.genreLabel(english),
              ].join('   ·   '),
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
            if (title.countryLabel(english) case final country?) Text(country),
            const SizedBox(height: 16),
            if (controller.detailsLoading) const LinearProgressIndicator(),
            if (controller.detailsError != null)
              _error(controller.detailsError!, () => controller.open(title)),
            if (title.synopsis(english).isNotEmpty)
              SelectableText(_plainText(title.synopsis(english)))
            else if (!controller.detailsLoading &&
                controller.detailsError == null)
              Text(
                tr('Описание отсутствует', 'No English description available'),
              ),
            if (FavoritesController.eligible(title)) _titleActions(title),
            if (title.kind == CatalogKind.games)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  tr(
                    'В каталоге показаны игры с раздачами для macOS. Совместимость с Apple Silicon проверяйте в описании раздачи.',
                    'These games have macOS sources. Check the release notes for Apple Silicon compatibility.',
                  ),
                ),
              ),
          ],
        );
        final poster = SizedBox(
          width: 136,
          height: 204,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: CatalogPoster(title: title),
          ),
        );
        return constraints.maxWidth < 600
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [poster, const SizedBox(height: 20), description],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  poster,
                  const SizedBox(width: 24),
                  Expanded(child: description),
                ],
              );
      },
    ),
  );
}

/// Checks remaining scroll extent after layout as well as user scrolls. This
/// also fills a large viewport and retries only after an explicit error retry.
class _AutoPagedCatalogue extends StatefulWidget {
  const _AutoPagedCatalogue({
    required this.controller,
    required this.slivers,
    super.key,
  });
  final CatalogController controller;
  final List<Widget> slivers;
  @override
  State<_AutoPagedCatalogue> createState() => _AutoPagedCatalogueState();
}

class _AutoPagedCatalogueState extends State<_AutoPagedCatalogue> {
  final scroll = ScrollController();
  bool scheduled = false;
  @override
  void initState() {
    super.initState();
    scroll.addListener(_check);
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void _check() {
    final c = widget.controller;
    if (mounted &&
        scroll.hasClients &&
        scroll.position.hasContentDimensions &&
        c.selected == null &&
        !c.loading &&
        !c.loadingMore &&
        c.error == null &&
        c.hasMore &&
        scroll.position.extentAfter < 600) {
      unawaited(c.loadMore());
    }
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          _schedule();
          return false;
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            _schedule();
            return CustomScrollView(
              controller: scroll,
              slivers: widget.slivers,
            );
          },
        ),
      );
  void _schedule() {
    if (scheduled) return;
    scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduled = false;
      if (mounted) _check();
    });
  }
}

String _plainText(String value) => value
    .replaceAll(RegExp(r'<[^>]*>'), ' ')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&quot;', '"')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .trim();

class CatalogPoster extends StatelessWidget {
  const CatalogPoster({required this.title, super.key});
  final CatalogTitle title;
  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Center(
        child: Icon(
          title.kind == CatalogKind.games
              ? Icons.sports_esports_outlined
              : Icons.local_movies_outlined,
          size: 48,
        ),
      ),
    );
    return title.poster == null
        ? placeholder
        : CachedPoster(
            uri: title.poster!,
            fallback: title.posterFallback,
            placeholder: placeholder,
          );
  }
}

class SourceTable extends StatefulWidget {
  const SourceTable({
    required this.sources,
    required this.english,
    required this.game,
    required this.series,
    this.providers,
    this.title,
    this.onUseSource,
    this.introduction,
    this.toolbarBuilder,
    this.footer,
    super.key,
  });
  final Widget? introduction, footer;
  final Widget Function(Widget search)? toolbarBuilder;
  final CatalogTitle? title;
  final List<CatalogSource> sources;
  final List<SourceProvider>? providers;
  final bool english, game, series;
  final Future<void> Function(CatalogSource, bool)? onUseSource;
  @override
  State<SourceTable> createState() => _SourceTableState();
}

class _SourceTableState extends State<SourceTable> {
  final sourceSearch = TextEditingController();
  int? season, episode;
  final hiddenProviders = <SourceProvider>{};
  Set<SourceProvider> get providers => visibleProviders(
    widget.providers ?? widget.sources.map((source) => source.row.provider),
  ).toSet();
  @override
  void didUpdateWidget(SourceTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    hiddenProviders.retainAll(providers);
    if (season != null &&
        !seasons.availableSourceSeasons(widget.sources).contains(season)) {
      season = null;
      episode = null;
    }
    if (episode != null &&
        !seasons
            .availableSourceEpisodes(widget.sources, season: season)
            .contains(episode)) {
      episode = null;
    }
  }

  @override
  void dispose() {
    sourceSearch.dispose();
    super.dispose();
  }

  String? busy;
  bool? busyWatch;
  final failures = <String, String>{};
  String tr(String ru, String en) => widget.english ? en : ru;
  Future<void> _use(CatalogSource source, bool watch) async {
    final key = '${source.row.provider.name}/${source.row.id}';
    setState(() {
      busy = key;
      busyWatch = watch;
      failures.remove(key);
    });
    try {
      await widget.onUseSource!(source, watch);
    } catch (e) {
      if (mounted) {
        setState(() => failures[key] = catalogError(e, widget.english));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(catalogError(e, widget.english))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = null;
          busyWatch = null;
        });
      }
    }
  }

  Widget _actions(CatalogSource source) {
    final key = '${source.row.provider.name}/${source.row.id}';
    Widget action(bool watch) {
      final label = watch
          ? tr('Смотреть', 'Watch')
          : widget.game
          ? tr('Скачать для macOS', 'Download for macOS')
          : tr('Скачать', 'Download');
      final enabled =
          busy == null &&
          (watch ? source.canWatch : source.row.canDownload) &&
          (source.uri != null || source.topic != null) &&
          widget.onUseSource != null;
      final icon = busy == key && busyWatch == watch
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(watch ? Icons.play_arrow : AppIcons.download, size: 20);
      final actionKey = ValueKey('source-${watch ? 'watch' : 'download'}-$key');
      return DesktopActionButton(
        key: actionKey,
        size: 40,
        onPressed: enabled ? () => _use(source, watch) : null,
        icon: watch ? Icons.play_arrow_rounded : AppIcons.download,
        glyph: icon,
        label: label,
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!widget.game) ...[
            Flexible(child: action(true)),
            const SizedBox(width: 6),
          ],
          Flexible(child: action(false)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String normalized(String text) => text
        .toLowerCase()
        .replaceAll('ё', 'е')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final query = normalized(sourceSearch.text);
    final sources = widget.sources
        .where(
          (source) =>
              !providerIsHidden(source.row.provider) &&
              !hiddenProviders.contains(source.row.provider) &&
              normalized(source.row.title).contains(query) &&
              (!widget.series ||
                  season == null ||
                  seasons.sourceMatchesSeason(source, season!)) &&
              (!widget.series ||
                  episode == null ||
                  seasons
                      .sourceEpisodes(source, season: season)
                      .contains(episode)),
        )
        .toList();
    final scroll = _buildSourceScroll(context, sources);
    if (widget.toolbarBuilder case final toolbar?) {
      return Column(
        children: [
          toolbar(_searchField()),
          Expanded(child: scroll),
        ],
      );
    }
    return scroll;
  }

  Widget _searchField({double width = 480, bool inline = false}) =>
      DesktopSearchField(
        key: const ValueKey('source-search-pill'),
        expandedWidth: width,
        alignment: inline
            ? AlignmentDirectional.centerStart
            : AlignmentDirectional.centerEnd,
        shrinkWrap: inline,
        fieldKey: const ValueKey('source-search'),
        clearKey: const ValueKey('source-search-clear'),
        controller: sourceSearch,
        label: tr('Поиск по найденному', 'Search these sources'),
        clearLabel: tr('Очистить поиск по источникам', 'Clear source search'),
        onChanged: (_) => setState(() {}),
      );

  Widget _buildSourceScroll(
    BuildContext context,
    List<CatalogSource> sources,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final inset = widget.introduction == null ? 0.0 : 24.0;
      final width = constraints.maxWidth - inset * 2;
      final filters = <({double? width, Widget child})>[
        if (widget.series)
          (
            width: 190,
            child: DesktopPicker(
              icon: Icons.video_library_outlined,
              child: DropdownButton<int>(
                key: const ValueKey('source-season'),
                value: season,
                isExpanded: true,
                hint: Text(
                  tr('Любой сезон', 'Any season'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(tr('Любой сезон', 'Any season')),
                  ),
                  for (final value in seasons.availableSourceSeasons(
                    widget.sources,
                  ))
                    DropdownMenuItem(
                      value: value,
                      child: Text(
                        value == 0
                            ? tr('Спецвыпуски', 'Specials')
                            : '${tr('Сезон', 'Season')} $value',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() {
                  season = value;
                  episode = null;
                }),
              ),
            ),
          ),
        if (widget.series)
          (
            width: 190,
            child: DesktopPicker(
              icon: Icons.playlist_play_rounded,
              child: DropdownButton<int>(
                key: const ValueKey('source-episode'),
                value: episode,
                isExpanded: true,
                hint: Text(tr('Любая серия', 'Any episode')),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(tr('Любая серия', 'Any episode')),
                  ),
                  for (final value in seasons.availableSourceEpisodes(
                    widget.sources,
                    season: season,
                  ))
                    DropdownMenuItem(
                      value: value,
                      child: Text(
                        '${tr('Серия', 'Episode')} $value',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => episode = value),
              ),
            ),
          ),
      ];
      final background = Theme.of(context).scaffoldBackgroundColor;
      final tableColor = Theme.of(context).colorScheme.surfaceContainer;
      final header = ColoredBox(
        color: background,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Column(
              key: const ValueKey('source-filters'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.toolbarBuilder == null)
                  _searchField(width: width.clamp(44, 360), inline: true),
                if (providers.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    key: const ValueKey('source-providers'),
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final provider in providers)
                        SizedBox(
                          height: 40,
                          child: FilterChip(
                            showCheckmark: false,
                            selectedColor: Theme.of(context)
                                .colorScheme
                                .primaryContainer,
                            labelStyle: TextStyle(
                              color: !hiddenProviders.contains(provider)
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurface,
                            ),
                            shape: const StadiumBorder(),
                            key: ValueKey('source-provider-${provider.name}'),
                            label: Text(providerDisplayLabel(provider)),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            labelPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                            ),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            selected: !hiddenProviders.contains(provider),
                            tooltip: hiddenProviders.contains(provider)
                                ? '${tr('Показать', 'Show')} ${providerDisplayLabel(provider)}'
                                : '${tr('Скрыть', 'Hide')} ${providerDisplayLabel(provider)}',
                            onSelected: (selected) => setState(() {
                              if (selected) {
                                hiddenProviders.remove(provider);
                              } else {
                                hiddenProviders.add(provider);
                              }
                            }),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 24,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${tr('Найдено', 'Results')}: ${sources.length} / ${widget.sources.length}',
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (widget.series)
              Wrap(
                key: const ValueKey('source-primary-filters'),
                spacing: 12,
                runSpacing: 8,
                children: [
                  for (final filter in filters)
                    SizedBox(
                      width: filter.width?.clamp(0, width),
                      height: 44,
                      child: filter.child,
                    ),
                ],
              ),
            const SizedBox(height: 12),
          ],
        ),
      );
      Widget sourceRow(CatalogSource source) {
        final key = '${source.row.provider.name}/${source.row.id}';
        final watched = WatchedScope.of(context);
        final title = widget.title;
        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TruncatedText(
              source.row.title,
              maxLines: 1,
              style: const TextStyle(fontWeight: FontWeight.bold),
              key: ValueKey('source-name-$key'),
            ),
            for (final text in [source.audio, source.channel])
              if (text != null && text.isNotEmpty)
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            if (source.restriction != null || failures.containsKey(key))
              Text(
                source.restriction != null
                    ? ProviderFailure(
                        source.row.provider,
                        source.restriction!,
                      ).label(widget.english)
                    : failures[key]!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        );
        final metadata = SourceMetadata(
          source: source,
          english: widget.english,
          singleLine: true,
          scrollable: false,
        );
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SourceActionOverlay(
            key: ValueKey('source-actions-$key'),
            busy: busy == key,
            actions: _actions(source),
            child: Container(
              key: ValueKey(
                'source-${source.row.provider.name}-${source.row.id}',
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              constraints: const BoxConstraints(minHeight: 54),
              decoration: BoxDecoration(
                color: tableColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) => Row(
                        children: [
                          Expanded(child: details),
                          const SizedBox(width: 12),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: box.maxWidth * .48,
                            ),
                            child: metadata,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.series)
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: SizedBox(
                        width: width >= 600 ? 100 : 58,
                        child: TruncatedText(sourceEpisodeDisplay(source)),
                      ),
                    ),
                  if (!widget.game) ...[
                    const SizedBox(width: 8),
                    DesktopActionButton(
                      key: ValueKey('source-watched-$key'),
                      size: 40,
                      revealLabel: false,
                      label: tr('Просмотрено', 'Watched'),
                      selected:
                          title != null &&
                          watched?.sourceWatched(title, source) == true,
                      icon: Icons.visibility_outlined,
                      onPressed: title == null || watched == null
                          ? null
                          : () async {
                              try {
                                await watched.toggle(title, source);
                              } catch (_) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        tr(
                                          'Не удалось сохранить отметку',
                                          'Could not save watched status',
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }

      return Padding(
        padding: EdgeInsets.symmetric(horizontal: inset),
        child: CustomScrollView(
          key: const ValueKey('catalog-details-list'),
          shrinkWrap: !constraints.hasBoundedHeight,
          physics: constraints.hasBoundedHeight
              ? null
              : const NeverScrollableScrollPhysics(),
          slivers: [
            if (widget.introduction != null)
              SliverToBoxAdapter(child: widget.introduction),
            if (widget.sources.isNotEmpty) ...[
              PinnedHeaderSliver(child: header),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => sourceRow(sources[index]),
                  childCount: sources.length,
                ),
              ),
            ],
            if (widget.footer != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                  child: widget.footer,
                ),
              ),
          ],
        ),
      );
    },
  );
}
