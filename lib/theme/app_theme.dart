import 'package:flutter/material.dart';
import 'hsl_colors.dart';

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: HslColors.primaryBlue,
        onPrimary: Colors.white,
        secondary: HslColors.metroOrange,
        onSecondary: Colors.white,
        tertiary: HslColors.tramGreen,
        surface: HslColors.cardDark,
        onSurface: Colors.white,
        error: HslColors.safetyRed,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xFF0D1524),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0F1A2D),
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: HslColors.cardDark,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF22324C), width: 1),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF1E2B42),
        selectedColor: HslColors.primaryBlue.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: const BorderSide(color: Color(0xFF2A3D5E)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF0D1728),
        surfaceTintColor: Colors.transparent,
        indicatorColor: HslColors.primaryBlue.withValues(alpha: 0.25),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF0D1728),
        selectedItemColor: HslColors.primaryBlue,
        unselectedItemColor: Color(0xFF8899AC),
        type: BottomNavigationBarType.fixed,
        elevation: 12,
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: Color(0xFF0D1728),
        selectedIconTheme: IconThemeData(color: Colors.white),
        unselectedIconTheme: IconThemeData(color: Color(0xFF8899AC)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF16233B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF26395A)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF26395A)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: HslColors.primaryBlue, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: HslColors.primaryBlue,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: HslColors.primaryBlue,
        onPrimary: Colors.white,
        secondary: HslColors.metroOrange,
        onSecondary: Colors.white,
        tertiary: HslColors.tramGreen,
        surface: HslColors.surfaceLight,
        onSurface: HslColors.onSurfaceLight,
        surfaceContainerHighest: HslColors.surfaceContainerLight,
        outlineVariant: HslColors.borderLight,
        error: HslColors.safetyRed,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: HslColors.backgroundLight,
      canvasColor: HslColors.surfaceLight,
      cardColor: HslColors.surfaceLight,
      hintColor: const Color(0xFF423627),
      dividerTheme: const DividerThemeData(
        color: HslColors.borderLight,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: HslColors.primaryBlue,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: HslColors.surfaceLight,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: HslColors.borderLight, width: 1),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: HslColors.surfaceContainerLight,
        selectedColor: HslColors.primaryBlue.withValues(alpha: 0.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: const BorderSide(color: HslColors.borderLight),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: HslColors.surfaceLight,
        surfaceTintColor: Colors.transparent,
        indicatorColor: HslColors.primaryBlue.withValues(alpha: 0.16),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: HslColors.surfaceLight,
        selectedIconTheme: IconThemeData(color: HslColors.primaryBlue),
        unselectedIconTheme: IconThemeData(color: Color(0xFF6B6257)),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: HslColors.surfaceLight,
        selectedItemColor: HslColors.primaryBlue,
        unselectedItemColor: Color(0xFF6B6257),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: HslColors.surfaceContainerLight,
        hintStyle: const TextStyle(color: Color(0xFF423627), fontWeight: FontWeight.w500),
        labelStyle: const TextStyle(color: HslColors.onSurfaceLight, fontWeight: FontWeight.w600),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: HslColors.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: HslColors.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: HslColors.primaryBlue, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: HslColors.primaryBlue,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
