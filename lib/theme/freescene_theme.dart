import 'package:flutter/material.dart';

/// Graphite + Copper at night, Porcelain + Indigo in the light appearance.
abstract final class FreeSceneTheme {
  static const graphite = Color(0xff17181b);
  static const copper = Color(0xffdda66c);
  static const porcelain = Color(0xfff4f3f0);
  static const indigo = Color(0xff5263c7);

  static ButtonStyle aboutActionStyle({
    required bool dark,
    double minimumWidth = 0,
  }) {
    final background = dark ? const Color(0xff2c2e34) : Colors.white;
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      textStyle: const TextStyle(fontFamily: 'Play', fontSize: 13),
      iconSize: 16,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
    );
  }

  static ThemeData create(bool dark) {
    final colors =
        ColorScheme.fromSeed(
          seedColor: dark ? copper : indigo,
          brightness: dark ? Brightness.dark : Brightness.light,
        ).copyWith(
          primary: dark ? copper : indigo,
          onPrimary: dark ? const Color(0xff241a10) : Colors.white,
          primaryContainer: dark
              ? const Color(0xff393127)
              : const Color(0xffdce0f4),
          onPrimaryContainer: dark ? copper : const Color(0xff39499e),
          secondary: dark ? copper : indigo,
          onSecondary: dark ? const Color(0xff241a10) : Colors.white,
          secondaryContainer: dark
              ? const Color(0xff393127)
              : const Color(0xffdce0f4),
          onSecondaryContainer: dark ? copper : const Color(0xff39499e),
          tertiary: dark ? const Color(0xffd8b876) : const Color(0xff86651c),
          onTertiary: dark ? const Color(0xff241c0a) : Colors.white,
          surface: dark ? graphite : porcelain,
          onSurface: dark ? const Color(0xffeeeef0) : const Color(0xff252731),
          onSurfaceVariant: dark
              ? const Color(0xffa7a8b0)
              : const Color(0xff5d606c),
          surfaceDim: dark ? graphite : const Color(0xffdfdedb),
          surfaceBright: dark ? const Color(0xff373940) : Colors.white,
          surfaceContainerLowest: dark ? const Color(0xff121315) : Colors.white,
          surfaceContainerLow: dark
              ? const Color(0xff1c1d21)
              : const Color(0xffeeede9),
          surfaceContainer: dark
              ? const Color(0xff222429)
              : const Color(0xffeae9e5),
          surfaceContainerHigh: dark
              ? const Color(0xff27292f)
              : const Color(0xffe3e3e0),
          surfaceContainerHighest: dark
              ? const Color(0xff2c2e34)
              : const Color(0xffdddddb),
          outline: dark ? const Color(0xff82848e) : const Color(0xff787b87),
          outlineVariant: dark
              ? const Color(0xff383a42)
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
      fontFamily: 'Play',
      colorScheme: colors,
      scaffoldBackgroundColor: colors.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surfaceContainer,
        foregroundColor: colors.onSurface,
        surfaceTintColor: Colors.transparent,
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
