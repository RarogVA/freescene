import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freescene/catalog/catalog_kind_switch.dart';
import 'package:freescene/catalog/catalog_models.dart';
import 'package:freescene/theme/freescene_theme.dart';

void main() {
  testWidgets('all segment surfaces align with the selected thumb', (
    tester,
  ) async {
    final theme = FreeSceneTheme.create(true);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Center(
            child: CatalogKindSwitch(
              value: CatalogKind.games,
              onChanged: (_) {},
              english: false,
            ),
          ),
        ),
      ),
    );
    final thumb = find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).color ==
              theme.colorScheme.primary,
    );
    final selected = tester.getRect(thumb);
    for (final kind in CatalogKind.values) {
      final button = find.byKey(ValueKey('catalog-kind-${kind.name}'));
      final surface = tester.getRect(
        find.descendant(of: button, matching: find.byType(Material)),
      );
      expect(surface.top, closeTo(selected.top, 0.01));
      expect(surface.bottom, closeTo(selected.bottom, 0.01));
      expect(surface.width, closeTo(selected.width, 0.01));
    }
  }, variant: TargetPlatformVariant({TargetPlatform.macOS}));
}
