import 'package:flutter/material.dart';

abstract final class LilyTheme {
  static const lavender = Color(0xFF7760BA);
  static const sky = Color(0xFFDCEFFC);
  static const cream = Color(0xFFFFFBF4);
  static const peach = Color(0xFFFFD9C6);

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(seedColor: lavender).copyWith(
      primary: lavender,
      secondary: const Color(0xFF487D9E),
      secondaryContainer: sky,
      tertiaryContainer: peach,
      surface: cream,
      onSurface: const Color(0xFF352C4A),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF3EFFB),
      appBarTheme: const AppBarTheme(
          backgroundColor: cream,
          centerTitle: false,
          foregroundColor: Color(0xFF352C4A),
          elevation: 0),
      cardTheme: CardThemeData(
          color: cream,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
      inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0xFFDAD0ED)))),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              minimumSize: const Size(48, 48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)))),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)))),
      navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: cream, indicatorColor: Color(0xFFE6DDF8)),
      snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    );
  }
}
