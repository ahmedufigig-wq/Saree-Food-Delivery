import 'package:flutter/material.dart';

/// رموز الهوية البصرية ومظهر تطبيق سريع في مكان واحد.
abstract final class SareeDesignSystem {
  static const emerald = Color(0xFF047857);
  static const deepGreen = Color(0xFF123B2F);
  static const cream = Color(0xFFFFF8E7);
  static const warmWhite = Color(0xFFFFFDF5);
  static const canary = Color(0xFFFFD60A);
  static const mutedGreen = Color(0xFF536B61);
  static const border = Color(0xFFE8E1CE);

  /// المظهر الفاتح: ألوان سريع الأصلية مع تباين واضح وخط عربي موحد.
  static ThemeData get lightTheme {
    final scheme = ColorScheme.fromSeed(
      seedColor: emerald,
      brightness: Brightness.light,
      primary: emerald,
      secondary: canary,
      surface: cream,
      onPrimary: Colors.white,
      onSurface: deepGreen,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: cream,
      fontFamily: 'SareeArabic',
      textTheme: ThemeData.light().textTheme.apply(
        fontFamily: 'SareeArabic',
        bodyColor: deepGreen,
        displayColor: deepGreen,
      ),
      iconTheme: const IconThemeData(color: emerald, size: 23),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: emerald,
        foregroundColor: cream,
        titleTextStyle: TextStyle(
          fontFamily: 'SareeArabic',
          color: cream,
          fontSize: 19,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        color: warmWhite,
        elevation: 2,
        shadowColor: Color(0x22065F46),
        margin: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        labelStyle: const TextStyle(color: mutedGreen),
        hintStyle: const TextStyle(color: Color(0xFF718579)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFFC9D8CC)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFFC9D8CC)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: emerald, width: 1.8),
        ),
        filled: true,
        fillColor: warmWhite,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: canary,
          foregroundColor: deepGreen,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(
            fontFamily: 'SareeArabic',
            fontWeight: FontWeight.w900,
            fontSize: 15,
          ),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: emerald,
        indicatorColor: canary,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontFamily: 'SareeArabic',
            color: cream,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: cream,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Color(0xFF065F46),
        contentTextStyle: TextStyle(fontFamily: 'SareeArabic', color: cream),
        behavior: SnackBarBehavior.floating,
      ),
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }

  /// مظهر داكن يتبع إعداد مظهر الجهاز تلقائياً.
  static ThemeData get darkTheme {
    const background = Color(0xFF101B17);
    const surface = Color(0xFF1B2B24);
    const foreground = Color(0xFFF5F7F3);
    final scheme = ColorScheme.fromSeed(
      seedColor: emerald,
      brightness: Brightness.dark,
      primary: const Color(0xFF48C99A),
      secondary: canary,
      surface: surface,
      onSurface: foreground,
      onPrimary: const Color(0xFF062D20),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      fontFamily: 'SareeArabic',
      textTheme: ThemeData.dark().textTheme.apply(
        fontFamily: 'SareeArabic',
        bodyColor: foreground,
        displayColor: foreground,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Color(0xFF14231D),
        foregroundColor: foreground,
        titleTextStyle: TextStyle(
          fontFamily: 'SareeArabic',
          color: foreground,
          fontSize: 19,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 1,
        margin: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF30473B)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        labelStyle: const TextStyle(color: Color(0xFFB5D5C5)),
        hintStyle: const TextStyle(color: Color(0xFF9AAEA3)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFF40584B)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFF40584B)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFF48C99A), width: 1.8),
        ),
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: canary,
          foregroundColor: deepGreen,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(
            fontFamily: 'SareeArabic',
            fontWeight: FontWeight.w900,
            fontSize: 15,
          ),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Color(0xFF14231D),
        indicatorColor: canary,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontFamily: 'SareeArabic',
            color: foreground,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Color(0xFF1D5D45),
        contentTextStyle: TextStyle(fontFamily: 'SareeArabic', color: foreground),
        behavior: SnackBarBehavior.floating,
      ),
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }
}
