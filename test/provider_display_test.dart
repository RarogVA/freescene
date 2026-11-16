import 'package:flutter_test/flutter_test.dart';
import 'package:freescene/domain/download.dart';
import 'package:freescene/domain/provider_display.dart';
import 'package:freescene/providers/demo.dart';
import 'package:freescene/settings/preferences.dart';
import 'package:freescene_provider_api/freescene_provider_api.dart';

const zona = SourceProvider('zona');
const nnm = SourceProvider('nnm');
const rutube = SourceProvider('rutube');

void main() {
  setUp(() {
    SourceProvider.register(const [
      ProviderDescriptor(zona, 'Zona', enabledByDefault: true),
      ProviderDescriptor(nnm, 'NNM', enabledByDefault: true),
      ProviderDescriptor(rutube, 'RuTube'),
    ]);
  });
  tearDown(() => ProviderSetup.install(demoProviders));

  test('torrent providers use stable neutral names', () {
    expect(providerDisplayLabel(zona), 'Torrent 1');
    expect(providerDisplayLabel(nnm), 'Torrent 2');
    expect(providerDisplayLabel(rutube), 'RuTube');
    // Numbering comes from the ID policy, not from enabled state.
    expect(providerDisplayLabel(nnm), 'Torrent 2');
    final disabled = Preferences(providers: {zona}).providers;
    expect(disabled, {zona});
    expect(providerDisplayLabel(nnm), 'Torrent 2');
  });

  test('hidden provider is excluded from selectable lists only', () {
    expect(visibleProviders(SourceProvider.values), [zona, rutube]);
    expect(providerIsHidden(zona), isFalse);
    expect(providerIsHidden(nnm), isTrue);
    expect(Preferences.availableProviders, [zona, rutube]);
    // Saved preferences and stable IDs survive even while the provider is hidden.
    final saved = Preferences(providers: {zona, nnm, rutube});
    expect(saved.providers, {zona, nnm, rutube});
    expect(saved.toJson()['providers'], contains('nnm'));
    expect(Preferences.fromJson(saved.toJson()).providers, contains(nnm));
  });

  test('legacy stored labels resolve to the neutral presentation', () {
    expect(storedProviderDisplayLabel('Zona'), 'Torrent 1');
    expect(storedProviderDisplayLabel('NNM'), 'Torrent 2');
    expect(storedProviderDisplayLabel('RuTube'), 'RuTube');
    expect(storedProviderDisplayLabel('Zona', providerId: 'nnm'), 'Torrent 2');
    expect(storedProviderDisplayLabel('Torrent 1'), 'Torrent 1');
    expect(storedProviderDisplayLabel('Magnet'), 'Magnet');
    expect(
      storedProviderDisplayLabel('Unknown site', providerId: 'gone'),
      'Unknown site',
    );
    expect(storedProviderDisplayLabel(null), isNull);
  });

  test('download and history origins use neutral labels but keep IDs', () {
    const origin = DownloadOrigin.provider(nnm);
    expect(origin.localizedLabel(false), 'Torrent 2');
    expect(origin.localizedLabel(true), 'Torrent 2');
    expect(origin.toJson(), {'provider': 'nnm'});
    expect(DownloadOrigin.fromJson(origin.toJson()).provider, nnm);
  });
}
