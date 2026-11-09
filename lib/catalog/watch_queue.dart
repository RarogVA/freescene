import 'catalog_models.dart';
import 'favorites.dart';

/// Public catalogue metadata, with the same validated atomic format as favorites.
/// Account/session data and games are excluded by the shared implementation.
class QueueStore extends FavoritesStore {
  QueueStore(super.directory);

  @override
  String get storageFileName => 'queue.json';
}

class QueueController extends FavoritesController {
  QueueController({super.store});

  /// Earlier additions stay first; removing and adding again moves to the end.
  @override
  List<CatalogTitle> get titles => List.unmodifiable(super.titles.reversed);
}
