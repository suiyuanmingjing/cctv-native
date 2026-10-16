import 'package:flutter/material.dart';

import 'tv_colors.dart';

abstract final class TvTheme {
  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: TvColors.red,
      brightness: Brightness.dark,
    ).copyWith(
      primary: TvColors.red,
      onPrimary: Colors.white,
      surface: TvColors.surface,
      onSurface: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: TvColors.bg,
      splashFactory: InkSparkle.splashFactory,
      iconTheme: const IconThemeData(color: Colors.white),
      dividerColor: TvColors.white12,
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: TvColors.red,
        linearTrackColor: TvColors.white24,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: TvColors.red,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 15),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}
