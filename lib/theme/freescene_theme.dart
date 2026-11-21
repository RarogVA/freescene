import 'package:flutter/material.dart';

/// Graphite surfaces and lavender accents shared by all three platforms.
abstract final class FreeSceneTheme {
  static const graphite = Color(0xff1b1b1d);
  static const lavender = Color(0xffbdb3ff);
  static const porcelain = Color(0xfff4f4f6);
  static const indigo = Color(0xff6755b6);

  static ButtonStyle aboutActionStyle({
    required bool dark,
    double minimumWidth = 0,
  }) {
    final background = dark ? const Color(0xff303033) : Colors.white;
    final foreground = dark ? const Color(0xffeeeef0) : const Color(0xff252731);
    return FilledButton.styleFrom(
      backgroundColor: background,
      foregroundColor: foreground,
      disabledBackgroundColor: background.withValues(alpha: 0.55),
      disabledForegroundColor: foreground.withValues(alpha: 0.38),
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      minimumSize: Size(minimumWidth, 32),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: const StadiumBorder(),
      textStyle: const TextStyle(fontSize: 13),
      iconSize: 16,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
    );
  }

  static ThemeData create(bool dark) {
    final colors =
        ColorScheme.fromSeed(
          seedColor: dark ? lavender : indigo,
          brightness: dark ? Brightness.dark : Brightness.light,
        ).copyWith(
          primary: dark ? lavender : indigo,
          onPrimary: dark ? const Color(0xff241d46) : Colors.white,
          primaryContainer: dark
              ? const Color(0xff403951)
              : const Color(0xffe8e1fa),
          onPrimaryContainer: dark ? lavender : const Color(0xff443181),
          secondary: dark ? lavender : indigo,
          onSecondary: dark ? const Color(0xff241d46) : Colors.white,
          secondaryContainer: dark
              ? const Color(0xff414145)
              : const Color(0xffdedee5),
          onSecondaryContainer: dark
              ? const Color(0xfff3f3f6)
              : const Color(0xff303038),
          tertiary: dark ? const Color(0xffd8b876) : const Color(0xff86651c),
          onTertiary: dark ? const Color(0xff241c0a) : Colors.white,
          surface: dark ? graphite : porcelain,
          onSurface: dark ? const Color(0xffeeeef0) : const Color(0xff252731),
          onSurfaceVariant: dark
              ? const Color(0xffbdbdc5)
              : const Color(0xff5d606c),
          surfaceDim: dark ? graphite : const Color(0xffdfdedb),
          surfaceBright: dark ? const Color(0xff373940) : Colors.white,
          surfaceContainerLowest: dark ? const Color(0xff171719) : Colors.white,
          surfaceContainerLow: dark
              ? const Color(0xff232325)
              : const Color(0xffededf0),
          surfaceContainer: dark
              ? const Color(0xff2c2c2f)
              : const Color(0xffffffff),
          surfaceContainerHigh: dark
              ? const Color(0xff303033)
              : const Color(0xffe8e8ed),
          surfaceContainerHighest: dark
              ? const Color(0xff303033)
              : const Color(0xffdedee5),
          outline: dark ? const Color(0xff82848e) : const Color(0xff787b87),
          outlineVariant: dark
              ? const Color(0xff4a4a50)
              : const Color(0xffd4d4d8),
          error: dark ? const Color(0xffef9088) : const Color(0xffb74236),
          onError: dark ? const Color(0xff3a1210) : Colors.white,
          errorContainer: dark
              ? const Color(0xff4d2927)
              : const Color(0xfff6dedb),
          onErrorContainer: dark
              ? const Color(0xffffdad6)
              : const Color(0xff6d2019),
          surfaceTint: Colors.transparent,
        );
    return ThemeData(
      useMaterial3: true,

      colorScheme: colors,
      scaffoldBackgroundColor: colors.surface,
      filledButtonTheme: FilledButtonThemeData(
        style: aboutActionStyle(dark: dark),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: colors.surfaceContainerLow,
          foregroundColor: colors.onSurface,
          side: BorderSide(color: colors.outlineVariant),
          shape: const StadiumBorder(),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surfaceContainer,
        foregroundColor: colors.onSurface,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.primary, width: 3),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      cardTheme: CardThemeData(
        color: colors.surfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: colors.outlineVariant.withValues(alpha: .5)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        selectedColor: colors.onPrimaryContainer,
        selectedTileColor: colors.primaryContainer,
      ),
    );
  }
}

/// A compact filled action matching the native About window.
/// Apply the style directly so local button themes cannot turn actions into links.
class FreeSceneActionButton extends StatelessWidget {
  const FreeSceneActionButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.minimumWidth = 0,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double minimumWidth;

  @override
  Widget build(BuildContext context) {
    final style = FreeSceneTheme.aboutActionStyle(
      dark: Theme.of(context).brightness == Brightness.dark,
      minimumWidth: minimumWidth,
    );
    if (icon case final icon?) {
      return FilledButton.icon(
        onPressed: onPressed,
        style: style,
        icon: Icon(icon),
        label: Text(label),
      );
    }
    return FilledButton(onPressed: onPressed, style: style, child: Text(label));
  }
}
