import 'catalog_models.dart';
import 'source.dart';
import 'catalog_dictionaries.dart';
import 'stream_client.dart';
import 'playback.dart';

class ProviderSetup {
  const ProviderSetup({
    required this.descriptors,
    required this.createCatalog,
    required this.createTrailerResolver,
    required this.loadDictionaries,
    this.createStreamClient,
    this.downloadProvider,
    this.downloadDirectory,
    this.trailerValidators = const {},
  });
  final List<ProviderDescriptor> descriptors;
  final CatalogRepository Function({required bool android}) createCatalog;
  final TrailerResolver Function(String userAgent) createTrailerResolver;
  final Future<CatalogDictionaries> Function() loadDictionaries;
  final StreamClient Function()? createStreamClient;
  final SourceProvider? downloadProvider;
  final String? downloadDirectory;
  final Map<String, bool Function(String)> trailerValidators;
  static ProviderSetup? _current;
  static ProviderSetup get current =>
      _current ?? (throw StateError('Provider setup is not installed'));
  static void install(ProviderSetup setup) {
    _current = setup;
    SourceProvider.register(setup.descriptors);
    CatalogTrailer.validators = setup.trailerValidators;
    CatalogDictionaries.loader = setup.loadDictionaries;
  }
}
