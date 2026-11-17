import 'package:freescene_provider_api/freescene_provider_api.dart';

/// Temporary presentation policy for providers whose site names must not be
/// shown in the interface. Keys are stable internal IDs: they never appear in
/// the UI, saved preferences, history or downloads, and are not renamed here.
const _neutralLabels = <String, String>{
  'zona': 'Torrent 1',
  'nnm': 'Torrent 2',
};

/// Providers hidden from every visible list while their implementation, IDs and
/// saved user data remain in place for a later re-enable.
const _hiddenProviders = <String>{'nnm'};

/// User-visible provider name. Falls back to the descriptor label for every
/// provider outside the temporary policy, for example the demo catalogue.
String providerDisplayLabel(SourceProvider provider) =>
    _neutralLabels[provider.name] ?? provider.label;

bool providerIsHidden(SourceProvider provider) =>
    _hiddenProviders.contains(provider.name);

List<SourceProvider> visibleProviders(Iterable<SourceProvider> providers) =>
    providers.where((provider) => !providerIsHidden(provider)).toList();

SourceProvider? _providerForStoredValue(String stored) {
  for (final provider in SourceProvider.values) {
    if (provider.name == stored ||
        provider.label == stored ||
        providerDisplayLabel(provider) == stored) {
      return provider;
    }
  }
  return null;
}

/// Resolves the provider name recorded in a history entry. Old records store
/// the site label shown at recording time; new records also store the stable
/// provider ID. Both resolve to the same neutral presentation.
String? storedProviderDisplayLabel(String? stored, {String? providerId}) {
  if (providerId != null && providerId.isNotEmpty) {
    final provider = SourceProvider(providerId);
    if (_neutralLabels.containsKey(providerId) || provider.descriptor != null) {
      return providerDisplayLabel(provider);
    }
  }
  final value = stored?.trim();
  if (value == null || value.isEmpty) return stored;
  final provider = _providerForStoredValue(value);
  return provider == null ? stored : providerDisplayLabel(provider);
}
