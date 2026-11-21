import 'package:flutter/material.dart';

import '../theme/freescene_theme.dart';

class RemoteFocusStyle extends ThemeExtension<RemoteFocusStyle> {
  const RemoteFocusStyle({required this.outlineOnly});
  final bool outlineOnly;
  @override
  RemoteFocusStyle copyWith({bool? outlineOnly}) =>
      RemoteFocusStyle(outlineOnly: outlineOnly ?? this.outlineOnly);
  @override
  RemoteFocusStyle lerp(RemoteFocusStyle? other, double t) =>
      t < .5 ? this : other ?? this;
}

ThemeData androidTheme({required bool dark, required bool tv}) {
  var theme = FreeSceneTheme.create(dark);
  if (tv) {
    final colors = dark
        ? theme.colorScheme.copyWith(
            surface: const Color(0xff1b1b1d),
            surfaceContainerLowest: const Color(0xff171719),
            surfaceContainerLow: const Color(0xff232325),
            surfaceContainer: const Color(0xff2c2c2f),
            surfaceContainerHigh: const Color(0xff303033),
            surfaceContainerHighest: const Color(0xff37373b),
            onSurfaceVariant: const Color(0xffbdbdc5),
            primary: const Color(0xffbdb3ff),
            onPrimary: const Color(0xff241d46),
            primaryContainer: const Color(0xff403951),
            onPrimaryContainer: const Color(0xffe0d9ff),
            secondaryContainer: const Color(0xff414145),
            onSecondaryContainer: const Color(0xfff3f3f6),
            outlineVariant: const Color(0xff4a4a50),
          )
        : theme.colorScheme.copyWith(
            surface: const Color(0xfff4f4f6),
            surfaceContainerLow: const Color(0xffededf0),
            surfaceContainer: Colors.white,
            surfaceContainerHigh: const Color(0xffe8e8ed),
            surfaceContainerHighest: const Color(0xffdedee5),
            primary: const Color(0xff6755b6),
            primaryContainer: const Color(0xffe8e1fa),
            onPrimaryContainer: const Color(0xff443181),
            secondaryContainer: const Color(0xffdedee5),
            onSecondaryContainer: const Color(0xff303038),
          );
    theme = theme.copyWith(
      colorScheme: colors,
      scaffoldBackgroundColor: colors.surface,
      textTheme: theme.textTheme
          .apply(fontFamily: 'Roboto')
          .copyWith(
            bodyMedium: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'Roboto',
              fontSize: 15,
            ),
            labelLarge: theme.textTheme.labelLarge?.copyWith(
              fontFamily: 'Roboto',
              fontSize: 14,
            ),
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
    );
  }
  // Dialogs and text-entry actions need the same obvious remote focus as tiles.
  final focusStyle = ButtonStyle(
    overlayColor: WidgetStateProperty.resolveWith(
      (states) =>
          tv &&
              states.contains(WidgetState.focused) &&
              !states.contains(WidgetState.disabled)
          ? Colors.transparent
          : null,
    ),
    side: WidgetStateProperty.resolveWith(
      (states) =>
          tv &&
              states.contains(WidgetState.focused) &&
              !states.contains(WidgetState.disabled)
          ? BorderSide(color: theme.colorScheme.primary, width: 3)
          : null,
    ),
    animationDuration: tv ? Duration.zero : kThemeChangeDuration,
  );
  final aboutStyle = FreeSceneTheme.aboutActionStyle(dark: dark);
  final tvAction = FilledButton.styleFrom(
    backgroundColor: theme.colorScheme.surfaceContainerHigh,
    foregroundColor: theme.colorScheme.onSurface,
    minimumSize: const Size(48, 48),
    shape: const StadiumBorder(),
    textStyle: theme.textTheme.labelLarge,
  ).merge(focusStyle);
  return theme.copyWith(
    extensions: [
      ...theme.extensions.values,
      RemoteFocusStyle(outlineOnly: tv),
    ],
    textButtonTheme: TextButtonThemeData(
      style: tv
          ? tvAction
          : theme.textButtonTheme.style?.merge(focusStyle) ?? focusStyle,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: tv
          ? tvAction
          : aboutStyle.copyWith(
              minimumSize: const WidgetStatePropertyAll(Size(48, 44)),
              overlayColor: focusStyle.overlayColor,
              side: focusStyle.side,
              animationDuration: tv ? Duration.zero : kThemeChangeDuration,
            ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: tv
          ? tvAction
          : theme.outlinedButtonTheme.style?.merge(focusStyle) ?? focusStyle,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: theme.iconButtonTheme.style?.merge(focusStyle) ?? focusStyle,
    ),
  );
}
