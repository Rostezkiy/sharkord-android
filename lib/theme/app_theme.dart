import 'package:flutter/material.dart';

/// one dark palette for the whole app, kept in a single place so no widget ever
/// invents its own shade of grey.
abstract final class AppColors {
  static const background = Color(0xFF0A0B0F);
  static const surface = Color(0xFF101218);
  static const surfaceHigh = Color(0xFF161922);
  static const surfaceHigher = Color(0xFF1C202B);
  static const border = Color(0xFF232835);
  static const borderStrong = Color(0xFF2E3444);

  static const text = Color(0xFFE9EBF0);
  static const textMuted = Color(0xFF98A0B3);
  static const textFaint = Color(0xFF656D80);

  static const accent = Color(0xFF6C63FF);
  static const accentSoft = Color(0x2E6C63FF);
  static const accentText = Color(0xFFB9B4FF);

  static const online = Color(0xFF3FB950);
  static const idle = Color(0xFFD29922);
  static const danger = Color(0xFFF85149);
  static const warning = Color(0xFFE3B341);
}

abstract final class AppRadius {
  static const small = BorderRadius.all(Radius.circular(8));
  static const medium = BorderRadius.all(Radius.circular(12));
  static const large = BorderRadius.all(Radius.circular(16));
}

ThemeData buildAppTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.accent,
        brightness: Brightness.dark,
      ).copyWith(
        surface: AppColors.surface,
        primary: AppColors.accent,
        onPrimary: Colors.white,
        error: AppColors.danger,
        outline: AppColors.border,
      );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    splashFactory: NoSplash.splashFactory,
    visualDensity: VisualDensity.standard,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.accent,
      selectionColor: AppColors.accentSoft,
      selectionHandleColor: AppColors.accent,
    ),
    scrollbarTheme: const ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll<Color>(AppColors.borderStrong),
      thickness: WidgetStatePropertyAll<double>(6),
      radius: Radius.circular(3),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.surfaceHigher,
        borderRadius: AppRadius.small,
        border: Border.all(color: AppColors.border),
      ),
      textStyle: const TextStyle(color: AppColors.text, fontSize: 12),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.surfaceHigher,
        disabledForegroundColor: AppColors.textFaint,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.medium),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textMuted,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceHigh,
      hintStyle: const TextStyle(color: AppColors.textFaint, fontSize: 14),
      labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: _inputBorder(AppColors.border),
      enabledBorder: _inputBorder(AppColors.border),
      focusedBorder: _inputBorder(AppColors.accent),
      errorBorder: _inputBorder(AppColors.danger),
      focusedErrorBorder: _inputBorder(AppColors.danger),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surfaceHigher,
      contentTextStyle: const TextStyle(color: AppColors.text, fontSize: 13),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.medium),
    ),
  );
}

OutlineInputBorder _inputBorder(Color color) => OutlineInputBorder(
  borderRadius: AppRadius.medium,
  borderSide: BorderSide(color: color),
);
