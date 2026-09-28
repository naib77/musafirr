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

      // Selection colours live in [chipThemeFor] — see the note there.
      chipTheme: chipThemeFor(p, labelStyle: textTheme.labelLarge),

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

  // Selection is a solid brand fill, not a tint of one.
  //
  // It used to be `brand.withValues(alpha: 0.14)` over a `surfaceMuted`
  // base, which is invisible under the live palette: `coral_ink`'s brand is
  // #222222, so the tint flattens to #E0E0E0 against a #EBEBEB unselected
  // chip — 1.11:1, and `side: BorderSide.none` left no second cue. Seven of
  // the nine selectable chips in the app take their colours from here and
  // nowhere else, so all seven read as permanently unselected: the search
  // type row (All / Seat / Room / Full House), both amenity pickers, the
  // purpose selector, the report categories and the payout chooser.
  //
  // A tint cannot be rescued by raising the alpha, either: the whole point
  // of the brand in this palette is that it is nearly black, so any alpha
  // low enough to read as a tint lands within a few values of the grey it
  // sits on. Filling with the brand outright is also what
  // `identity_verification_screen` already did by hand.
  //
  // The label and checkmark then flip to `surface`, and that pairing is
  // safe in every palette *by construction*: `app_palettes_test` already
  // holds every `brand` to 4.5:1 against its own `surface`, and contrast is
  // symmetric — so brand-legible-on-surface is exactly surface-legible-on-
  // brand. A new palette cannot pass that test and fail this.
  ///
  /// Extracted from [forPalette] so this can be asserted on directly: building
  /// the whole [ThemeData] pulls the text theme through GoogleFonts, which in a
  /// test wants a font asset that is not there. A palette's chip colours are a
  /// pure function of the palette, and testing them should not need a font.
  static ChipThemeData chipThemeFor(AppPalette p, {TextStyle? labelStyle}) {
    return ChipThemeData(
      backgroundColor: p.surfaceMuted,
      selectedColor: p.brand,
      checkmarkColor: p.surface,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      // RawChip resolves the label's *colour* against widget states but not the
      // rest of the TextStyle (`chip.dart` calls `resolveAs<Color?>` on
      // `effectiveLabelStyle.color` alone), so a WidgetStateColor is the one
      // hook a theme has for restyling a selected label — a WidgetStateTextStyle
      // here would be read as a plain style. Call sites that pass their own
      // `labelStyle` keep it, because `merge` only overrides non-null fields: a
      // size or weight of their own survives, and so does this colour, as long
      // as they do not set one themselves.
      labelStyle: (labelStyle ?? const TextStyle()).copyWith(
        color: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected) ? p.surface : p.ink,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    );
  }
}
