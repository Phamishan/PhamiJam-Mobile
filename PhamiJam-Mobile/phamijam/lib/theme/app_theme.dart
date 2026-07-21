import 'package:flutter/material.dart';

const Color kBrandGold = Color(0xFFDBA43A);

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: kBrandGold,
          brightness: Brightness.light,
        ).copyWith(
          primary: const Color(0xFF1C1B1A),
          onPrimary: Colors.white,
          surface: kBrandGold,
          onSurface: Colors.white,
          onSurfaceVariant: const Color(0xFFFCEFD1),
          surfaceContainerLowest: const Color(0xFFE6B850),
          surfaceContainerLow: const Color(0xFFDDAC45),
          surfaceContainer: const Color(0xFFCC9730),
          surfaceContainerHigh: const Color(0xFFBC8A26),
          surfaceContainerHighest: const Color(0xFFAD7E1D),
        );

    return ThemeData(colorScheme: colorScheme, fontFamily: 'Lexend');
  }

  static ThemeData get dark {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: kBrandGold,
      brightness: Brightness.dark,
    ).copyWith(primary: kBrandGold);

    return ThemeData(colorScheme: colorScheme, fontFamily: 'Lexend');
  }
}
