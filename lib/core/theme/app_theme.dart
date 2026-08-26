import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'app_typography.dart';

/// Assembles the Musaafir [ThemeData]. Single source of truth for colors,
/// typography, component shapes, and page transitions — every screen inherits
/// this, so modernizing here lifts the whole app.
///
/// [forPalette] takes its colours as an argument rather than reading the
/// `AppColors` globals, so building a theme is a pure function of a palette:
/// swapping themes at runtime is then just calling it again with a different
/// one, and a test can inspect a palette's theme without installing it.
class AppTheme {
  AppTheme._();

  static const double _radius = 16;

  /// Builds the theme for [p]. There is deliberately no zero-argument default:
  /// the palette is an admin setting, and a convenience getter that quietly
  /// returned the fallback theme is exactly how a screen ends up painted in the
  /// wrong colours. Callers with no palette to hand want
  /// `AppTheme.forPalette(AppPalettes.fallback)` and should say so.
  static ThemeData forPalette(AppPalette p) {
    final scheme = ColorScheme.fromSeed(
      seedColor: p.brand,
      brightness: Brightness.light,
    ).copyWith(
      primary: p.brand,
      secondary: p.accent,
      tertiary: p.violet,
      surface: p.surface,
      error: p.error,
      outlineVariant: p.outline,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final textTheme = AppTypography.textTheme(base.textTheme, p);

    return base.copyWith(
      scaffoldBackgroundColor: p.scaffold,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,

      // Modern page transitions across platforms.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: p.scaffold,
        surfaceTintColor: Colors.transparent,
        foregroundColor: p.ink,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),

      cardTheme: CardThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
        ),
      ),

      // Filled buttons take p.cta, not scheme.primary. That is the seam a
      // blue-led/red-actioned palette needs: navigation and focus stay brand
      // coloured while the thing being asked for is not. A palette whose cta IS
      // its brand (oceanTeal) gets exactly the old behaviour.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.cta,
          foregroundColor: p.onCta,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle:
              textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          side: BorderSide(color: p.outline),
          textStyle: textTheme.labelLarge,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle:
              textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceMuted,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: textTheme.bodyMedium?.copyWith(color: p.inkMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.brand, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.error, width: 1.5),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: p.surfaceMuted,
        selectedColor: p.brand.withValues(alpha: 0.14),
        checkmarkColor: p.brand,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        labelStyle: textTheme.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),

      dividerTheme: DividerThemeData(
        color: p.outline,
        thickness: 1,
        space: 1,
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: p.surface,
        selectedItemColor: p.brand,
        unselectedItemColor: p.inkMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),

      // Airbnb-style compact tab bar: small single-line labels, no pill
      // indicator, tinted icon as the only selection cue.
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelSmall!.copyWith(
            fontSize: 10,
            height: 1.2,
            letterSpacing: 0,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? p.brand : p.inkMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected) ? p.brand : p.inkMuted,
          );
        }),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}
