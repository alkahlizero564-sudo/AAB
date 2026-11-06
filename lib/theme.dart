import 'package:flutter/material.dart';

class AppColors {
  static const bg = Color(0xFF0B1220);
  static const surface = Color(0xFF111B2E);
  static const card = Color(0xFF16233A);
  static const border = Color(0xFF223152);
  static const text = Color(0xFFE8EEF8);
  static const muted = Color(0xFF8CA0BF);
  static const up = Color(0xFF16C784);
  static const down = Color(0xFFEA3943);
  static const accent = Color(0xFF4C8DFF);
  static const gold = Color(0xFFF5A623);
}

ThemeData buildTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      secondary: AppColors.gold,
      surface: AppColors.surface,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.text,
      elevation: 0,
      centerTitle: true,
    ),
    drawerTheme: const DrawerThemeData(backgroundColor: AppColors.surface),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.accent.withOpacity(0.25),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 11, color: AppColors.text),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
    ),
  );
}
