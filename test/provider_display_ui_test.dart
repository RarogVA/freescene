import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freescene/catalog/catalog_models.dart';
import 'package:freescene/catalog/catalog_page.dart';
import 'package:freescene/catalog/source_metadata.dart';
import 'package:freescene/domain/provider_display.dart';
import 'package:freescene/providers/demo.dart';
import 'package:freescene/theme/freescene_theme.dart';
import 'package:freescene_provider_api/freescene_provider_api.dart';

const zona = SourceProvider('zona');
const nnm = SourceProvider('nnm');

CatalogSource source(SourceProvider provider) => CatalogSource(
  row: SourceRow(
    id: 'release',
    provider: provider,
    title: 'Release',
    watch: SourceKind.embed,
    download: DownloadKind.unavailable,
  ),
  uri: Uri.parse('https://example.test/video'),
);

void main() {
  testWidgets('source table hides NNM and labels Zona neutrally', (
    tester,
  ) async {
    SourceProvider.register(const [
      ProviderDescriptor(zona, 'Zona'),
      ProviderDescriptor(nnm, 'NNM'),
    ]);
    addTearDown(() => ProviderSetup.install(demoProviders));
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: FreeSceneTheme.create(true),
        home: Scaffold(
          body: SourceTable(
            sources: [source(zona), source(nnm)],
            providers: [zona, nnm],
            english: true,
            game: false,
            series: false,
            onUseSource: (_, _) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('source-provider-zona')), findsOneWidget);
    expect(find.byKey(const ValueKey('source-provider-nnm')), findsNothing);
    expect(find.text('Torrent 1'), findsWidgets);
    expect(find.text('Torrent 2'), findsNothing);
    expect(find.text('Zona'), findsNothing);
    expect(find.byKey(const ValueKey('source-zona-release')), findsOneWidget);
    expect(find.byKey(const ValueKey('source-nnm-release')), findsNothing);
  });

  testWidgets('source metadata never exposes a real torrent name', (
    tester,
  ) async {
    SourceProvider.register(const [
      ProviderDescriptor(zona, 'Zona'),
      ProviderDescriptor(nnm, 'NNM'),
    ]);
    addTearDown(() => ProviderSetup.install(demoProviders));
    await tester.pumpWidget(
      MaterialApp(
        theme: FreeSceneTheme.create(false),
        home: Scaffold(
          body: SourceMetadata(
            source: source(zona),
            english: false,
            singleLine: true,
          ),
        ),
      ),
    );
    expect(providerDisplayLabel(zona), 'Torrent 1');
    expect(find.text('Torrent 1'), findsOneWidget);
    expect(find.text('Zona'), findsNothing);
  });
}
