import 'package:flutter/material.dart';
import '../models/lily_appearance.dart';

abstract final class LilyTheme {
  static const lavender = Color(0xFF7760BA);
  static const sky = Color(0xFFDCEFFC);
  static const cream = Color(0xFFFFFBF4);
  static const peach = Color(0xFFFFD9C6);
  static const _kidsText = Color(0xFF352C4A);

  static ThemeData forAppearance(LilyAppearance appearance) =>
      appearance == LilyAppearance.gaming ? gaming : light;

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(seedColor: lavender).copyWith(
      primary: lavender,
      secondary: const Color(0xFF487D9E),
      secondaryContainer: sky,
      tertiaryContainer: peach,
      surface: cream,
      onSurface: _kidsText,
    );
    return _build(scheme, const Color(0xFFF3EFFB), Colors.white,
        const Color(0xFFDAD0ED), const Color(0xFFE6DDF8));
  }

  static ThemeData get gaming {
    final scheme = ColorScheme.fromSeed(
            seedColor: const Color(0xFF54DBD4), brightness: Brightness.dark)
        .copyWith(
      primary: const Color(0xFF75E9DD),
      onPrimary: const Color(0xFF073A36),
      secondaryContainer: const Color(0xFF253C54),
      onSecondaryContainer: const Color(0xFFD6E8FF),
      tertiaryContainer: const Color(0xFF43315D),
      onTertiaryContainer: const Color(0xFFF2E2FF),
      surface: const Color(0xFF172338),
      onSurface: const Color(0xFFF2F6FF),
      onSurfaceVariant: const Color(0xFFC4D0E2),
    );
    return _build(scheme, const Color(0xFF0E1728), const Color(0xFF1F2D45),
        const Color(0xFF647994), scheme.secondaryContainer);
  }

  static ThemeData _build(ColorScheme scheme, Color background, Color input,
      Color inputBorder, Color indicator) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: scheme.brightness,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
          backgroundColor: scheme.surface,
          centerTitle: false,
          foregroundColor: scheme.onSurface,
          elevation: 0),
      cardTheme: CardThemeData(
          color: scheme.surface,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
      inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: input,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: inputBorder))),
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
      navigationBarTheme: NavigationBarThemeData(
          backgroundColor: scheme.surface, indicatorColor: indicator),
      snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    );
  }
}
