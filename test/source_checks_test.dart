import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:freescene/catalog/source_checks.dart';
import 'package:freescene/catalog/catalog_models.dart';

CatalogSource source(String id) => CatalogSource(
  row: SourceRow(
    id: id,
    provider: const SourceProvider('test'),
    title: id,
    watch: SourceKind.magnet,
    download: DownloadKind.magnet,
  ),
);
Future<void> tick() => Future<void>.delayed(Duration.zero);
void main() {
  setUp(() => sourceCheckResults.value = {});
  test('same torrent must be checked again after episode changes', () async {
    var calls = 0;
    final second = Completer<SourceCheckState>();
    final controller = SourceChecks(
      probe: (_) async {
        calls++;
        return calls == 1 ? SourceCheckState.data : await second.future;
      },
      cancelProbe: () async {},
    );
    controller.select('episode1', [source('pack')]);
    await tick();
    expect(recentSourceCheck('test:pack')?.state, SourceCheckState.data);
    controller.select('episode4', [source('pack')]);
    await tick();
    expect(calls, 2);
    expect(recentSourceCheck('test:pack')?.state, SourceCheckState.checking);
    second.complete(SourceCheckState.timeout);
    await tick();
    expect(recentSourceCheck('test:pack')?.state, SourceCheckState.timeout);
    controller.dispose();
  });
  test('only three automatic probes, one at a time, cache and retry', () async {
    var calls = 0, active = 0, maximum = 0;
    final controller = SourceChecks(
      probe: (_) async {
        calls++;
        active++;
        if (active > maximum) maximum = active;
        await tick();
        active--;
        return SourceCheckState.data;
      },
      cancelProbe: () async {},
    );
    final sources = List.generate(6, (i) => source('$i'));
    controller.select('title', sources);
    for (var i = 0; i < 10; i++) {
      await tick();
    }
    expect(calls, 3);
    expect(maximum, 1);
    controller.select('title', sources);
    await tick();
    expect(calls, 3);
    controller.retry(sources.first);
    await tick();
    await tick();
    expect(calls, 4);
    controller.dispose();
  });
  test('cancelled probe cannot publish success for old title', () async {
    final result = Completer<SourceCheckState>();
    final controller = SourceChecks(
      probe: (_) => result.future,
      cancelProbe: () async {},
    );
    controller.select('old', [source('one')]);
    await tick();
    controller.select(null, []);
    result.complete(SourceCheckState.data);
    await tick();
    expect(recentSourceCheck('test:one'), isNull);
    controller.dispose();
  });
  test('timeout is not reported as available and cache expires', () async {
    final controller = SourceChecks(
      probe: (_) async => SourceCheckState.timeout,
      cancelProbe: () async {},
    );
    controller.select('title', [source('one')]);
    await tick();
    expect(recentSourceCheck('test:one')?.state, SourceCheckState.timeout);
    expect(
      recentSourceCheck(
        'test:one',
        now: DateTime.now().add(const Duration(minutes: 6)),
      ),
      isNull,
    );
    controller.dispose();
  });
  test('source resolution timeout remains indeterminate', () async {
    final controller = SourceChecks(
      probe: (_) async => throw TimeoutException('resolving'),
      cancelProbe: () async {},
    );
    controller.select('title', [source('slow')]);
    await tick();
    expect(recentSourceCheck('test:slow')?.state, SourceCheckState.timeout);
    controller.dispose();
  });
}
