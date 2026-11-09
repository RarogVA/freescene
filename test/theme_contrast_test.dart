import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freescene/android/android_theme.dart';
import 'package:freescene/theme/freescene_theme.dart';

double contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
}

void main() {
  for (final dark in [true, false]) {
    test('${dark ? 'dark' : 'light'} text stays readable on every surface', () {
      final colors = FreeSceneTheme.create(dark).colorScheme;
      for (final surface in [
        colors.surface,
        colors.surfaceContainerLowest,
        colors.surfaceContainerLow,
        colors.surfaceContainer,
        colors.surfaceContainerHigh,
        colors.surfaceContainerHighest,
      ]) {
        expect(contrast(colors.onSurface, surface), greaterThanOrEqualTo(4.5));
        expect(
          contrast(colors.onSurfaceVariant, surface),
          greaterThanOrEqualTo(4.5),
        );
      }
      for (final (foreground, background) in [
        (colors.onPrimary, colors.primary),
        (colors.onPrimaryContainer, colors.primaryContainer),
        (colors.onSecondaryContainer, colors.secondaryContainer),
        (colors.onError, colors.error),
        (colors.onErrorContainer, colors.errorContainer),
      ]) {
        expect(contrast(foreground, background), greaterThanOrEqualTo(4.5));
      }
    });
    test('${dark ? 'dark' : 'light'} TV focus contrasts with selection', () {
      final theme = androidTheme(dark: dark, tv: true);
      final colors = theme.colorScheme;
      expect(contrast(colors.primary, colors.surfaceContainer), greaterThan(3));
      final border = theme.filledButtonTheme.style!.side!.resolve({
        WidgetState.focused,
      })!;
      expect(
        contrast(border.color, colors.surfaceContainerHighest),
        greaterThan(3),
      );
      expect(border.width, 3);
    });
  }
}
