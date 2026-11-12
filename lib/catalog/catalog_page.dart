import 'dart:async';

import 'package:flutter/material.dart';

import 'catalog_controller.dart';
import 'catalog_models.dart';
import 'catalog_tile.dart';
import 'favorite_button.dart';
import 'queue_button.dart';
import 'favorites.dart';
import 'source_seasons.dart' as seasons;
import 'cached_poster.dart';
import 'source_metadata.dart';
import 'watched.dart';
import 'truncated_text.dart';
import 'source_filter.dart';
import 'source_format.dart';
export 'source_format.dart' show catalogBytes, sourceEpisodeDisplay;
import '../domain/availability.dart';

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
    this.onUseSource,
    this.onToggleFavorites,
    this.onToggleQueue,
    this.onTrailer,
    this.compactSourceActions = false,
    super.key,
  });
  final CatalogController controller;
  final bool english, compactSourceActions;
  final Widget? kindSwitch;
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
      final details = _details(context, controller.selected!);
      return Column(
        children: [
          _detailsToolbar(controller.selected!),
          Expanded(child: details),
        ],
      );
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

  Widget _toolbar({
    required String id,
    required Widget leading,
    required Widget compactLeading,
    required Widget trailing,
    double compactLeadingWidth = 40,
    double minimumLeadingWidth = 160,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
    child: LayoutBuilder(
      builder: (context, constraints) {
        if (kindSwitch == null) {
          return SizedBox(
            key: ValueKey(id),
            height: 48,
            child: Row(
              children: [
                Expanded(
                  child: constraints.maxWidth < minimumLeadingWidth + 56
                      ? compactLeading
                      : leading,
                ),
                trailing,
              ],
            ),
          );
        }
        final switchWidth = (constraints.maxWidth / 2)
            .clamp(360.0, 520.0)
            .clamp(
              0.0,
              (constraints.maxWidth - minimumLeadingWidth * 2 - 24).clamp(
                0.0,
                double.infinity,
              ),
            );
        if (switchWidth < 360) {
          final gap = constraints.maxWidth < 400 ? 8.0 : 12.0;
          return Row(
            key: ValueKey(id),
            children: [
              SizedBox(
                width: compactLeadingWidth,
                height: 48,
                child: compactLeading,
              ),
              SizedBox(width: gap),
              Expanded(child: Align(child: kindSwitch)),
              SizedBox(width: gap),
              trailing,
            ],
          );
        }
        return Row(
          key: ValueKey(id),
          children: [
            Expanded(child: leading),
            const SizedBox(width: 12),
            SizedBox(width: switchWidth, child: kindSwitch),
            const SizedBox(width: 12),
            Expanded(
              child: Align(alignment: Alignment.centerRight, child: trailing),
            ),
          ],
        );
      },
    ),
  );

  Widget _detailsToolbar(CatalogTitle title) {
    final back = controller.queueOnly
        ? tr('К очереди', 'Back to queue')
        : controller.favoritesOnly
        ? tr('К избранному', 'Back to favorites')
        : tr('К каталогу', 'Back to catalogue');
    return _toolbar(
      id: 'catalog-details-toolbar',
      leading: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('catalog-back'),
          onPressed: controller.back,
          icon: const Icon(Icons.arrow_back),
          label: Text(back, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
      compactLeading: IconButton(
        key: const ValueKey('catalog-back'),
        onPressed: controller.back,
        tooltip: back,
        icon: const Icon(Icons.arrow_back),
      ),
      trailing: SizedBox(
        width: 104,
        height: 48,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (controller.queue case final queue?
                when FavoritesController.eligible(title))
              QueueButton(
                key: ValueKey('queue-detail-${title.kind.name}-${title.id}'),
                title: title,
                queue: queue,
                english: english,
              ),
            if (controller.favorites case final favorites?
                when FavoritesController.eligible(title)) ...[
              const SizedBox(width: 8),
              FavoriteButton(
                key: ValueKey('favorite-detail-${title.kind.name}-${title.id}'),
                title: title,
                favorites: favorites,
                english: english,
              ),
            ],
          ],
        ),
      ),
    );
  }

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

  Widget _collectionButton(
    BuildContext context, {
    required bool queue,
    required bool compact,
  }) {
    final selected = queue ? controller.queueOnly : controller.favoritesOnly;
    final label = queue ? tr('Очередь', 'Queue') : tr('Избранное', 'Favorites');
    final colors = Theme.of(context).colorScheme;
    final icon = Icon(
      queue
          ? Icons.playlist_play
          : selected
          ? Icons.favorite
          : Icons.favorite_border,
    );
    final callback = queue ? _toggleQueue : _toggleFavorites;
    final key = ValueKey(queue ? 'catalog-queue' : 'catalog-favorites');
    return Semantics(
      toggled: selected,
      child: compact
          ? IconButton.outlined(
              key: key,
              onPressed: callback,
              tooltip: label,
              style: IconButton.styleFrom(
                backgroundColor: selected ? colors.primaryContainer : null,
                foregroundColor: selected ? colors.onPrimaryContainer : null,
              ),
              icon: icon,
            )
          : OutlinedButton.icon(
              key: key,
              onPressed: callback,
              style: OutlinedButton.styleFrom(
                backgroundColor: selected ? colors.primaryContainer : null,
                foregroundColor: selected ? colors.onPrimaryContainer : null,
              ),
              icon: icon,
              label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
    );
  }

  Widget _listingToolbar(BuildContext context) {
    final collection = controller.queueOnly
        ? controller.queue
        : controller.favorites;
    return _toolbar(
      id: 'catalog-listing-toolbar',
      minimumLeadingWidth: 285,
      compactLeadingWidth: 104,
      leading: Row(
        children: [
          Flexible(
            child: _collectionButton(context, queue: false, compact: false),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: _collectionButton(context, queue: true, compact: false),
          ),
        ],
      ),
      compactLeading: Row(
        children: [
          _collectionButton(context, queue: false, compact: true),
          const SizedBox(width: 8),
          _collectionButton(context, queue: true, compact: true),
        ],
      ),
      trailing: SizedBox(
        width: 40,
        height: 48,
        child: IconButton(
          key: const ValueKey('catalog-refresh'),
          tooltip: controller.queueOnly
              ? tr('Обновить очередь', 'Refresh queue')
              : controller.favoritesOnly
              ? tr('Обновить избранное', 'Refresh favorites')
              : tr('Обновить каталог', 'Refresh catalogue'),
          onPressed: () => controller.localCollectionOnly
              ? collection?.restore()
              : controller.browse(),
          icon: const Icon(Icons.refresh),
        ),
      ),
    );
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
                          mainAxisExtent: 330,
                          crossAxisSpacing: 20,
                          mainAxisSpacing: 20,
                        ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final item = controller.items[index];
                      return CatalogTile(
                        key: ValueKey('title-${item.id}'),
                        onTap: () => controller.open(item),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  CatalogPoster(title: item),
                                  if (controller.queue case final queue?
                                      when FavoritesController.eligible(item))
                                    Positioned(
                                      top: 8,
                                      left: 8,
                                      child: QueueButton(
                                        key: ValueKey(
                                          'queue-tile-${item.kind.name}-${item.id}',
                                        ),
                                        title: item,
                                        queue: queue,
                                        english: english,
                                        overPoster: true,
                                      ),
                                    ),
                                  if (controller.favorites case final favorites?
                                      when FavoritesController.eligible(item))
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: FavoriteButton(
                                        key: ValueKey(
                                          'favorite-tile-${item.kind.name}-${item.id}',
                                        ),
                                        title: item,
                                        favorites: favorites,
                                        english: english,
                                        overPoster: true,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title(english),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  TitleMetadata(title: item, english: english),
                                ],
                              ),
                            ),
                          ],
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
      ],
    );
  }

  Widget _details(BuildContext context, CatalogTitle title) => SourceTable(
    title: title,
    compactActions: compactSourceActions,
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
        if (controller.providerStates.isEmpty)
          Text(
            tr(
              'Включите провайдеров в настройках, чтобы искать источники.',
              'Enable providers in Settings to search for sources.',
            ),
          ),
        for (final entry in controller.providerStates.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.key.label} · ${tr('Показано', 'Loaded')}: ${entry.value.items.length} / ${entry.value.total}',
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
                  TextButton(
                    onPressed: () => controller.loadMoreSources(entry.key),
                    child: Text('${tr('Ещё', 'More')} ${entry.key.label}'),
                  ),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _titleDescription(
    BuildContext context,
    CatalogTitle title,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final description = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.title(english),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            [
              if (title.year != null) '${title.year}',
              if (title.rating != null) '★ ${title.rating!.toStringAsFixed(1)}',
              if (title.genres != null) title.genres!,
            ].join(' · '),
          ),
          if (title.country != null) Text(title.country!),
          const SizedBox(height: 16),
          if (controller.detailsLoading) const LinearProgressIndicator(),
          if (controller.detailsError != null)
            _error(controller.detailsError!, () => controller.open(title)),
          if (title.synopsis(english).isNotEmpty)
            SelectableText(_plainText(title.synopsis(english)))
          else if (!controller.detailsLoading &&
              controller.detailsError == null)
            Text(tr('Описание отсутствует', 'No description available')),
          if (title.kind != CatalogKind.games && title.trailer != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: OutlinedButton.icon(
                key: const ValueKey('catalog-trailer'),
                onPressed: onTrailer == null ? null : () => onTrailer!(title),
                icon: const Icon(Icons.movie_outlined),
                label: Text(tr('Трейлер', 'Trailer')),
              ),
            ),
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
        width: 180,
        height: 265,
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
    this.footer,
    this.compactActions = false,
    super.key,
  });
  final Widget? introduction, footer;
  final CatalogTitle? title;
  final List<CatalogSource> sources;
  final List<SourceProvider>? providers;
  final bool english, game, series, compactActions;
  final Future<void> Function(CatalogSource, bool)? onUseSource;
  @override
  State<SourceTable> createState() => _SourceTableState();
}

class _SourceTableState extends State<SourceTable> {
  final sourceSearch = TextEditingController();
  int? season, episode;
  final hiddenProviders = <SourceProvider>{};
  Set<SourceProvider> get providers =>
      widget.providers?.toSet() ??
      widget.sources.map((source) => source.row.provider).toSet();
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

  int? sortColumn;
  bool ascending = false;
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
    final colors = Theme.of(context).colorScheme;
    final style = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      foregroundColor: colors.onSurface,
      side: BorderSide(color: colors.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    );
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
          : Icon(watch ? Icons.play_arrow : Icons.download_outlined, size: 20);
      final actionKey = ValueKey('source-${watch ? 'watch' : 'download'}-$key');
      if (widget.compactActions) {
        return Tooltip(
          message: label,
          child: OutlinedButton(
            key: actionKey,
            style: style.copyWith(
              fixedSize: const WidgetStatePropertyAll(Size.square(32)),
              padding: const WidgetStatePropertyAll(EdgeInsets.zero),
              shape: const WidgetStatePropertyAll(CircleBorder()),
            ),
            onPressed: enabled ? () => _use(source, watch) : null,
            child: Semantics(label: label, child: icon),
          ),
        );
      }
      return OutlinedButton.icon(
        key: actionKey,
        style: style,
        onPressed: enabled ? () => _use(source, watch) : null,
        icon: icon,
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
    }

    if (widget.compactActions) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!widget.game) ...[action(true), const SizedBox(width: 6)],
          action(false),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.game) ...[action(true), const SizedBox(height: 4)],
        action(false),
      ],
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
    if (sortColumn != null) {
      sources.sort((a, b) {
        if (sortColumn == 2) {
          final c = a.row.provider.label.compareTo(b.row.provider.label);
          return ascending ? c : -c;
        }
        if (sortColumn == 6) {
          final x = sourceSeason(a), y = sourceSeason(b);
          if (x == null) return y == null ? 0 : 1;
          if (y == null) return -1;
          final c = x == y
              ? sourceEpisode(a).compareTo(sourceEpisode(b))
              : x.compareTo(y);
          return ascending ? c : -c;
        }
        num? value(CatalogSource s) => switch (sortColumn) {
          1 => sourceHeight(s),
          3 => s.row.sizeBytes,
          4 => s.row.durationSeconds,
          5 =>
            s.row.isTorrent
                ? TorrentAvailability(s.row.visibleCounts).score
                : null,
          _ => null,
        };
        final x = value(a), y = value(b);
        if (x == null) return y == null ? 0 : 1;
        if (y == null) return -1;
        final compared = ascending ? x.compareTo(y) : y.compareTo(x);
        return compared != 0
            ? compared
            : widget.sources.indexOf(a).compareTo(widget.sources.indexOf(b));
      });
    }
    void sort(int column, bool asc) => setState(() {
      final startsAscending = column == 2 || column == 6;
      if (sortColumn != column) {
        sortColumn = column;
        ascending = startsAscending;
      } else if (ascending == startsAscending) {
        ascending = !startsAscending;
      } else {
        sortColumn = null;
        ascending = false;
      }
    });
    return _buildSourceScroll(context, sources, sort);
  }

  Widget _buildSourceScroll(
    BuildContext context,
    List<CatalogSource> sources,
    void Function(int, bool) sort,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final inset = widget.introduction == null ? 0.0 : 24.0;
      final width = constraints.maxWidth - inset * 2;
      final filters = <({double width, Widget child})>[
        (
          width: 240,
          child: TextField(
            key: const ValueKey('source-search'),
            controller: sourceSearch,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: tr('Поиск по найденному', 'Search these sources'),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              prefixIcon: const Icon(Icons.search, size: 18),
              prefixIconConstraints: const BoxConstraints(minWidth: 36),
              suffixIcon: sourceSearch.text.isEmpty
                  ? null
                  : IconButton(
                      key: const ValueKey('source-search-clear'),
                      tooltip: tr(
                        'Очистить поиск по источникам',
                        'Clear source search',
                      ),
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(sourceSearch.clear),
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ),
        if (widget.series)
          (
            width: 136,
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
        if (widget.series)
          (
            width: 136,
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
        (
          width: 40,
          child: IconButton.filledTonal(
            key: const ValueKey('source-reset'),
            tooltip: tr('Сбросить фильтры', 'Reset filters'),
            onPressed: () => setState(() {
              sourceSearch.clear();
              season = episode = null;
              hiddenProviders.clear();
            }),
            icon: const Icon(Icons.filter_alt_off_outlined, size: 20),
          ),
        ),
      ];
      final background = Theme.of(context).scaffoldBackgroundColor;
      final tableColor = Theme.of(context).colorScheme.surfaceContainerLow;
      final header = ColoredBox(
        color: background,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Column(
              key: const ValueKey('source-filters'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  key: const ValueKey('source-primary-filters'),
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    for (final filter in filters)
                      SizedBox(
                        width: filter.width.clamp(0, width),
                        height: 40,
                        child: filter.child,
                      ),
                  ],
                ),
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
                            key: ValueKey('source-provider-${provider.name}'),
                            label: Text(provider.label),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            labelPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                            ),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            selected: !hiddenProviders.contains(provider),
                            tooltip: hiddenProviders.contains(provider)
                                ? '${tr('Показать', 'Show')} ${provider.label}'
                                : '${tr('Скрыть', 'Hide')} ${provider.label}',
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
                  '${tr('Строк', 'Rows')}: ${sources.length} / ${widget.sources.length}',
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (widget.series)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => sort(6, !ascending),
                  icon: Icon(
                    sortColumn == 6 && ascending
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                    size: 14,
                  ),
                  label: Text(tr('Сезон / серия', 'Season / episode')),
                ),
              ),
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
              maxLines: 2,
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
        return Container(
          key: ValueKey('source-${source.row.provider.name}-${source.row.id}'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: tableColor,
            border: Border(bottom: Divider.createBorderSide(context)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: widget.compactActions
                    ? (widget.game ? 32 : 70)
                    : widget.game
                    ? 176
                    : 124,
                child: _actions(source),
              ),
              const SizedBox(width: 12),
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
                IconButton(
                  key: ValueKey('source-watched-$key'),
                  tooltip: tr('Просмотрено', 'Watched'),
                  isSelected:
                      title != null &&
                      watched?.sourceWatched(title, source) == true,
                  selectedIcon: Icon(
                    Icons.visibility_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  icon: const Icon(Icons.visibility_outlined),
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
