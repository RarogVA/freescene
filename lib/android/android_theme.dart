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
  final theme = FreeSceneTheme.create(dark);
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
  return theme.copyWith(
    extensions: [
      ...theme.extensions.values,
      RemoteFocusStyle(outlineOnly: tv),
    ],
    textButtonTheme: TextButtonThemeData(
      style: theme.textButtonTheme.style?.merge(focusStyle) ?? focusStyle,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: aboutStyle.copyWith(
        minimumSize: const WidgetStatePropertyAll(Size(48, 44)),
        overlayColor: focusStyle.overlayColor,
        side: focusStyle.side,
        animationDuration: tv ? Duration.zero : kThemeChangeDuration,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: theme.outlinedButtonTheme.style?.merge(focusStyle) ?? focusStyle,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: theme.iconButtonTheme.style?.merge(focusStyle) ?? focusStyle,
    ),
  );
}
