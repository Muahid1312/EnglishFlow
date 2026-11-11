import 'package:flutter/material.dart';

/// LexiFlow design system — modern, elegant, calm, premium educational tech.
class AppColors {
  // Primary palette: deep navy + violet
  static const Color navy = Color(0xFF1A1F36);
  static const Color navyLight = Color(0xFF252B48);
  static const Color violet = Color(0xFF6B5B95);
  static const Color violetDeep = Color(0xFF4A3F6B);
  static const Color violetSoft = Color(0xFF8B7BA8);

  // Accent: subtle teal
  static const Color teal = Color(0xFF2A9D8F);
  static const Color tealLight = Color(0xFF3DBDAE);
  static const Color tealSoft = Color(0xFFE0F2F0);

  // Surfaces — warm neutrals
  static const Color surfaceLight = Color(0xFFF8F7F4);
  static const Color surfaceCardLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF12141F);
  static const Color surfaceCardDark = Color(0xFF1E2235);

  // Text
  static const Color textPrimaryLight = Color(0xFF1A1F36);
  static const Color textSecondaryLight = Color(0xFF5C6378);
  static const Color textPrimaryDark = Color(0xFFF0EFF5);
  static const Color textSecondaryDark = Color(0xFFA8AEC0);

  // Semantic
  static const Color success = Color(0xFF2A9D8F);
  static const Color warning = Color(0xFFE9A825);
  static const Color error = Color(0xFFD64545);
  static const Color info = Color(0xFF4A90D9);

  // Borders / dividers
  static const Color borderLight = Color(0xFFE8E6E1);
  static const Color borderDark = Color(0xFF2A2F45);
}

class AppTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: AppColors.violet,
        onPrimary: Colors.white,
        primaryContainer: AppColors.violetSoft.withOpacity(0.25),
        secondary: AppColors.teal,
        onSecondary: Colors.white,
        secondaryContainer: AppColors.tealSoft,
        surface: AppColors.surfaceLight,
        onSurface: AppColors.textPrimaryLight,
        error: AppColors.error,
        onError: Colors.white,
        outline: AppColors.borderLight,
      ),
      scaffoldBackgroundColor: AppColors.surfaceLight,
      fontFamily: 'Roboto',
    );

    return base.copyWith(
      textTheme: _textTheme(base.textTheme, AppColors.textPrimaryLight,
          AppColors.textSecondaryLight),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: AppColors.surfaceLight,
        foregroundColor: AppColors.textPrimaryLight,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimaryLight,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardTheme(
        elevation: 0,
        color: AppColors.surfaceCardLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.borderLight, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.violet,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.2),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.violet,
          side: const BorderSide(color: AppColors.violet, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.teal,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceCardLight,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.violet, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondaryLight),
        hintStyle:
            TextStyle(color: AppColors.textSecondaryLight.withOpacity(0.7)),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surfaceCardLight,
        selectedItemColor: AppColors.violet,
        unselectedItemColor: AppColors.textSecondaryLight,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        selectedLabelStyle:
            TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 12),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surfaceCardLight,
        indicatorColor: AppColors.violet.withOpacity(0.12),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.violet);
          }
          return const TextStyle(
              fontSize: 12, color: AppColors.textSecondaryLight);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.violet, size: 24);
          }
          return const IconThemeData(
              color: AppColors.textSecondaryLight, size: 24);
        }),
      ),
      dividerTheme: const DividerThemeData(
          color: AppColors.borderLight, thickness: 1, space: 1),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.violet,
        linearTrackColor: AppColors.borderLight,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dialogTheme: DialogTheme(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: AppColors.surfaceCardLight,
      ),
    );
  }

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: AppColors.violetSoft,
        onPrimary: AppColors.navy,
        primaryContainer: AppColors.violetDeep,
        secondary: AppColors.tealLight,
        onSecondary: AppColors.navy,
        secondaryContainer: AppColors.teal.withOpacity(0.25),
        surface: AppColors.surfaceDark,
        onSurface: AppColors.textPrimaryDark,
        error: AppColors.error,
        onError: Colors.white,
        outline: AppColors.borderDark,
      ),
      scaffoldBackgroundColor: AppColors.surfaceDark,
      fontFamily: 'Roboto',
    );

    return base.copyWith(
      textTheme: _textTheme(base.textTheme, AppColors.textPrimaryDark,
          AppColors.textSecondaryDark),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: AppColors.surfaceDark,
        foregroundColor: AppColors.textPrimaryDark,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimaryDark,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardTheme(
        elevation: 0,
        color: AppColors.surfaceCardDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.borderDark, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.violetSoft,
          foregroundColor: AppColors.navy,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.2),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.violetSoft,
          side: const BorderSide(color: AppColors.violetSoft, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.teal,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceCardDark,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.borderDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.violetSoft, width: 1.5),
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondaryDark),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surfaceCardDark,
        selectedItemColor: AppColors.violetSoft,
        unselectedItemColor: AppColors.textSecondaryDark,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surfaceCardDark,
        indicatorColor: AppColors.violetSoft.withOpacity(0.18),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.violetSoft);
          }
          return const TextStyle(
              fontSize: 12, color: AppColors.textSecondaryDark);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.violetSoft, size: 24);
          }
          return const IconThemeData(
              color: AppColors.textSecondaryDark, size: 24);
        }),
      ),
      dividerTheme: const DividerThemeData(
          color: AppColors.borderDark, thickness: 1, space: 1),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.violetSoft,
        linearTrackColor: AppColors.borderDark,
      ),
      dialogTheme: DialogTheme(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: AppColors.surfaceCardDark,
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base, Color primary, Color secondary) {
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(
          color: primary, fontWeight: FontWeight.w700, letterSpacing: -1),
      displayMedium: base.displayMedium?.copyWith(
          color: primary, fontWeight: FontWeight.w700, letterSpacing: -0.5),
      headlineLarge: base.headlineLarge?.copyWith(
          color: primary, fontWeight: FontWeight.w700, letterSpacing: -0.5),
      headlineMedium: base.headlineMedium?.copyWith(
          color: primary, fontWeight: FontWeight.w600, letterSpacing: -0.3),
      headlineSmall: base.headlineSmall
          ?.copyWith(color: primary, fontWeight: FontWeight.w600),
      titleLarge: base.titleLarge?.copyWith(
          color: primary, fontWeight: FontWeight.w600, letterSpacing: -0.2),
      titleMedium: base.titleMedium
          ?.copyWith(color: primary, fontWeight: FontWeight.w600),
      titleSmall: base.titleSmall
          ?.copyWith(color: primary, fontWeight: FontWeight.w600),
      bodyLarge: base.bodyLarge?.copyWith(color: primary, height: 1.5),
      bodyMedium: base.bodyMedium?.copyWith(color: primary, height: 1.45),
      bodySmall: base.bodySmall?.copyWith(color: secondary, height: 1.4),
      labelLarge: base.labelLarge
          ?.copyWith(color: primary, fontWeight: FontWeight.w600),
      labelMedium: base.labelMedium?.copyWith(color: secondary),
      labelSmall: base.labelSmall?.copyWith(color: secondary),
    );
  }
}
