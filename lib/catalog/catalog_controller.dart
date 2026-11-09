import 'package:flutter/foundation.dart';

import 'catalog_models.dart';
import 'favorites.dart';
import 'watch_queue.dart';

class ProviderSources {
  List<CatalogSource> items = [];
  int total = 0, next = 0;
  bool loading = false, hasMore = false;
  Object? error;
}

class CatalogController extends ChangeNotifier {
  CatalogController(this.repository, {this.favorites, this.queue}) {
    favorites?.addListener(_favoritesChanged);
    queue?.addListener(_queueChanged);
  }
  final CatalogRepository repository;
  final FavoritesController? favorites;
  final QueueController? queue;
  bool favoritesOnly = false, queueOnly = false;
  bool get localCollectionOnly => favoritesOnly || queueOnly;
  FavoritesController? get _collection => queueOnly ? queue : favorites;
  CatalogKind kind = CatalogKind.movies;
  CatalogFilter filter = const CatalogFilter();
  String search = '';
  List<CatalogTitle> items = [];
  int total = 0, _next = 0;
  bool loading = true, loadingMore = false, hasMore = false;
  Object? error;
  CatalogTitle? selected;
  List<CatalogSource> sources = [];
  final providerStates = <SourceProvider, ProviderSources>{};
  int get sourceTotal =>
      providerStates.values.fold(0, (sum, p) => sum + p.total);
  bool get sourcesLoading => providerStates.values.any((p) => p.loading);
  Object? get sourcesError =>
      providerStates.values.map((s) => s.error).whereType<Object>().firstOrNull;
  bool get moreSources => providerStates.values.any((p) => p.hasMore);
  bool detailsLoading = false;
  Object? detailsError;
  int _generation = 0, _detailsGeneration = 0;
  bool _disposed = false;
  Future<void> configureProviders(Set<SourceProvider> enabled) async {
    repository.configureProviders(enabled);
    if (selected case final title?) {
      await open(title);
    } else {
      ++_detailsGeneration;
      repository.cancelSources();
      sources = [];
      providerStates.clear();
      _changed();
    }
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _collectionListing() {
    String normalized(String value) => value.toLowerCase().replaceAll('ё', 'е');
    final query = normalized(search);
    items = (_collection?.titles ?? <CatalogTitle>[])
        .where(
          (title) =>
              title.kind == kind &&
              normalized(
                '${title.name} ${title.englishName ?? ''} ${title.year ?? ''}',
              ).contains(query),
        )
        .toList();
    total = items.length;
    hasMore = false;
    loading = _collection?.loading ?? false;
    loadingMore = false;
    error = null;
  }

  void _favoritesChanged() {
    if (_disposed) return;
    if (favoritesOnly) _collectionListing();
    _changed();
  }

  void _queueChanged() {
    if (_disposed) return;
    if (queueOnly) _collectionListing();
    _changed();
  }

  Future<void> browse({
    CatalogKind? kind,
    String? search,
    CatalogFilter? filter,
    bool? favoritesOnly,
    bool? queueOnly,
  }) async {
    final nextKind = kind ?? this.kind;
    this.filter =
        filter ?? (nextKind == this.kind ? this.filter : const CatalogFilter());
    this.kind = nextKind;
    this.search = search ?? this.search;
    if (queueOnly == true) {
      this.queueOnly = true;
      this.favoritesOnly = false;
    } else if (favoritesOnly == true) {
      this.favoritesOnly = true;
      this.queueOnly = false;
    } else {
      this.favoritesOnly = favoritesOnly ?? this.favoritesOnly;
      this.queueOnly = queueOnly ?? this.queueOnly;
    }
    selected = null;
    ++_detailsGeneration;
    repository.cancelSources();
    final generation = ++_generation;
    loading = true;
    loadingMore = false;
    error = null;
    items = [];
    total = 0;
    _next = 0;
    hasMore = false;
    _changed();
    try {
      if (localCollectionOnly) {
        _collectionListing();
        return;
      }
      final page = await repository.list(
        this.kind,
        search: this.search,
        filter: this.filter,
      );
      if (_disposed || generation != _generation) return;
      items = page.items;
      total = page.total;
      _next = page.next;
      hasMore = page.hasMore;
    } catch (e) {
      if (!_disposed && generation == _generation) error = e;
    } finally {
      if (!_disposed && generation == _generation) {
        loading = localCollectionOnly ? _collection?.loading ?? false : false;
        _changed();
      }
    }
  }

  void resetFilters() {
    filter = const CatalogFilter();
    _changed();
  }

  Future<void> resetToHome() {
    sources = [];
    providerStates.clear();
    detailsLoading = false;
    detailsError = null;
    return browse(
      kind: CatalogKind.movies,
      search: '',
      filter: const CatalogFilter(),
      favoritesOnly: false,
      queueOnly: false,
    );
  }

  Future<void> loadMore() async {
    if (_disposed ||
        localCollectionOnly ||
        loading ||
        loadingMore ||
        !hasMore) {
      return;
    }
    final generation = _generation;
    loadingMore = true;
    error = null;
    _changed();
    try {
      final page = await repository.list(
        kind,
        search: search,
        filter: filter,
        start: _next,
      );
      if (_disposed || generation != _generation) return;
      final existing = items.map((t) => t.id).toSet();
      items = [...items, ...page.items.where((t) => existing.add(t.id))];
      total = page.total;
      _next = page.next;
      hasMore = page.hasMore;
    } catch (e) {
      if (!_disposed && generation == _generation) error = e;
    } finally {
      if (!_disposed && generation == _generation) {
        loadingMore = false;
        _changed();
      }
    }
  }

  Future<void> open(CatalogTitle title) async {
    final generation = ++_detailsGeneration;
    repository.cancelSources();
    selected = title;
    sources = [];
    providerStates.clear();
    detailsLoading = true;
    detailsError = null;
    for (final provider in repository.providers(title)) {
      providerStates[provider] = ProviderSources()..loading = true;
    }
    _changed();
    await Future.wait([
      (() async {
        try {
          final detail = await repository.details(title);
          if (!_disposed && generation == _detailsGeneration) selected = detail;
        } catch (e) {
          if (!_disposed && generation == _detailsGeneration) detailsError = e;
        } finally {
          if (!_disposed && generation == _detailsGeneration) {
            detailsLoading = false;
            _changed();
          }
        }
      })(),
      for (final provider in providerStates.keys.toList())
        _loadSources(title, provider, generation, 0),
    ]);
  }

  Future<void> _loadSources(
    CatalogTitle title,
    SourceProvider provider,
    int generation,
    int start,
  ) async {
    final state = providerStates[provider]!;
    try {
      final page = await repository.providerSources(
        title,
        provider,
        start: start,
      );
      if (_disposed || generation != _detailsGeneration) return;
      final existing = sources
          .map((s) => '${s.row.provider.name}/${s.row.id}')
          .toSet();
      final added = page.items
          .where((s) => existing.add('${s.row.provider.name}/${s.row.id}'))
          .toList();
      state.items.addAll(added);
      sources = [...sources, ...added];
      state.total = page.total;
      state.next = page.next;
      // Stop a provider repeating an entire page despite advancing its cursor.
      // Empty filtered pages can still advance to subsequent relevant results.
      state.hasMore = page.hasMore && (page.items.isEmpty || added.isNotEmpty);
    } catch (e) {
      if (!_disposed && generation == _detailsGeneration) state.error = e;
    } finally {
      if (!_disposed && generation == _detailsGeneration) {
        state.loading = false;
        _changed();
      }
    }
  }

  Future<void> loadMoreSources([SourceProvider? provider]) async {
    provider ??= providerStates.keys.firstOrNull;
    final state = providerStates[provider];
    if (_disposed ||
        selected == null ||
        provider == null ||
        state == null ||
        state.loading ||
        (!state.hasMore && state.error == null)) {
      return;
    }
    state.loading = true;
    state.error = null;
    _changed();
    await _loadSources(selected!, provider, _detailsGeneration, state.next);
  }

  void back() {
    selected = null;
    ++_detailsGeneration;
    repository.cancelSources();
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    ++_detailsGeneration;
    favorites?.removeListener(_favoritesChanged);
    queue?.removeListener(_queueChanged);
    repository.close();
    super.dispose();
  }
}
