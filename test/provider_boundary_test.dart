import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freescene_provider_api/freescene_provider_api.dart';
import 'package:freescene/providers/demo.dart';
import 'package:freescene/settings/preferences.dart';
import 'package:freescene/domain/download.dart';
import 'package:freescene/catalog/favorites.dart';
import 'package:freescene/catalog/watch_queue.dart';
import 'package:freescene/android/android_app.dart';
import 'package:freescene/android/android_runtime.dart';
import 'package:freescene/android/remote_focus.dart';

void main() {
  setUp(() => ProviderSetup.install(demoProviders));
  test(
    'disabled or absent provider IDs survive settings and download origins',
    () {
      final original = Preferences(
        providers: {const SourceProvider('absent_adapter')},
      );
      final restored = Preferences.fromJson(original.toJson());
      expect(restored.toJson()['providers'], ['absent_adapter']);
      final origin = DownloadOrigin.fromJson({'provider': 'absent_adapter'});
      expect(origin.toJson(), {'provider': 'absent_adapter'});
      expect(origin.label, 'absent_adapter');
      for (final invalid in ['../outside', '', 'bad/id']) {
        expect(
          () => Preferences.fromJson(
            original.toJson()..['providers'] = [invalid],
          ),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'saved cards and opaque trailers survive without their adapter',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'freescene-profile-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      const title = CatalogTitle(
        id: 'existing:123',
        kind: CatalogKind.movies,
        name: 'Saved movie',
        trailer: CatalogTrailer('absent_adapter', 'video-123'),
      );
      for (final store in [FavoritesStore(directory), QueueStore(directory)]) {
        await store.save([title]);
        final restored = (await store.load()).single;
        expect(restored.id, title.id);
        expect(restored.trailer?.toJson(), title.trailer!.toJson());
      }
    },
  );
  test('demo catalogue works offline and honors disabled provider', () async {
    final catalog = DemoCatalog();
    expect((await catalog.list(CatalogKind.movies)).items, hasLength(12));
    expect(
      (await catalog.list(
        CatalogKind.movies,
        search: 'Demo 2',
      )).items.single.id,
      'demo:movies:2',
    );
    catalog.configureProviders({});
    expect((await catalog.list(CatalogKind.movies)).items, isEmpty);
  });
  testWidgets('phone opens settings and title on first tap without TV focus', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      AndroidRuntime.channel,
      (_) async => {'available': false},
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        AndroidRuntime.channel,
        null,
      ),
    );
    await tester.pumpWidget(
      AndroidApp(
        runtime: AndroidRuntime(
          profile: Directory.systemTemp,
          cache: Directory.systemTemp,
          tv: false,
          lowRam: false,
          version: '1.3.4',
        ),
        initialPreferences: Preferences(),
        savePreferences: (_) async {},
        repository: DemoCatalog(),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> tap(String id) async {
      final target = find.byKey(ValueKey('remote-$id'));
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, isNot(isA<RemoteFocusNode>()));
    }

    await tap('settings');
    expect(find.byKey(const ValueKey('remote-settings-back')), findsOneWidget);
    await tap('settings-back');
    await tap('title-movies-demo:movies:1');
    expect(find.byKey(const ValueKey('remote-detail-back')), findsOneWidget);
    await tap('detail-back');
    await tester.pumpWidget(const SizedBox());
  });
}
