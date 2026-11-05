import 'package:flutter/material.dart';

class DeskColors {
  static const bg = Color(0xFF1A1612);
  static const raised = Color(0xFF241F1A);
  static const line = Color(0xFF3A332C);
  static const paper = Color(0xFFF3EFE4);
  static const ink = Color(0xFF1C1814);
  static const muted = Color(0xFFA3988C);
  static const amber = Color(0xFFE09A45);
  static const amberDeep = Color(0xFFB8742A);
}

ThemeData buildDeskTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: DeskColors.bg,
    colorScheme: const ColorScheme.dark(
      surface: DeskColors.bg,
      primary: DeskColors.amber,
      onPrimary: DeskColors.ink,
      secondary: DeskColors.amberDeep,
      onSurface: DeskColors.paper,
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: DeskColors.paper,
      displayColor: DeskColors.paper,
    ),
    splashFactory: NoSplash.splashFactory,
  );
}
