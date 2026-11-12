import 'package:flutter/material.dart';

/// سمة "ذهبي فاخر" — داكن فقط.
class AppColors {
  static const bg = Color(0xFF0A0A0C);
  static const surface = Color(0xFF101013);
  static const card = Color(0xFF15151A);
  static const border = Color(0xFF2A2A33);
  static const text = Color(0xFFF3EEE3);
  static const muted = Color(0xFF9A948A);
  static const up = Color(0xFF10B981); // زمردي
  static const down = Color(0xFFE5484D); // ياقوتي
  static const accent = Color(0xFFD4AF37); // ذهبي
  static const gold = Color(0xFFE9C46A); // ذهبي فاتح
  static const onAccent = Color(0xFF14110A); // نص فوق الذهبي
  static const goldGrad = LinearGradient(
    colors: [Color(0xFFF1D78A), Color(0xFFD4AF37), Color(0xFFA9822A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

ThemeData buildTheme() {
  const r12 = BorderRadius.all(Radius.circular(12));
  return ThemeData(
    useMaterial3: true,
    cardColor: AppColors.card,
    dialogBackgroundColor: AppColors.surface,
    brightness: Brightness.dark,
    fontFamily: 'Cairo',
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: AppColors.onAccent,
      secondary: AppColors.gold,
      onSecondary: AppColors.onAccent,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      error: AppColors.down,
      outline: AppColors.border,
    ),
    dividerColor: AppColors.border,
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 0.6),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
          fontFamily: 'Cairo', fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.gold),
    ),
    drawerTheme: const DrawerThemeData(backgroundColor: AppColors.surface),
    bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface, surfaceTintColor: Colors.transparent),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.accent.withOpacity(0.18),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? AppColors.accent : AppColors.muted)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
          fontFamily: 'Cairo',
          fontSize: 10.5,
          height: 1.1,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? AppColors.accent : AppColors.muted)),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: AppColors.card,
      selectedColor: AppColors.accent,
      side: BorderSide(color: AppColors.border),
      shape: StadiumBorder(),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.onAccent,
          textStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700),
          shape: const RoundedRectangleBorder(borderRadius: r12)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.onAccent,
          shape: const RoundedRectangleBorder(borderRadius: r12)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.gold,
          side: const BorderSide(color: AppColors.accent),
          shape: const RoundedRectangleBorder(borderRadius: r12)),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.gold),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.onAccent : AppColors.muted),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.accent : AppColors.card),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.accent,
      thumbColor: AppColors.gold,
      inactiveTrackColor: AppColors.border,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.accent),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      border: OutlineInputBorder(borderRadius: r12, borderSide: BorderSide(color: AppColors.border)),
      enabledBorder:
          OutlineInputBorder(borderRadius: r12, borderSide: BorderSide(color: AppColors.border)),
      focusedBorder:
          OutlineInputBorder(borderRadius: r12, borderSide: BorderSide(color: AppColors.accent)),
    ),
  );
}
