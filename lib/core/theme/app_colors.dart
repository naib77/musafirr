import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'app_palettes.dart';

/// Centralized color tokens for the Musaafir design system.
///
/// These used to be `static const` values. They are now **getters over the
/// active [AppPalette]**, because which colours the app wears is chosen by an
/// admin (the `active_theme` row in `app_settings`) rather than fixed at compile
/// time. Call sites did not have to change: `AppColors.brand` still reads as a
/// plain colour token, it just answers with the current theme's blue or teal.
///
/// The cost of that is `const`: a getter cannot appear in a const expression, so
/// the handful of `const BoxDecoration(color: AppColors.brand)` sites had to drop
/// the keyword. That is the whole reason this file is getters rather than a
/// `ThemeExtension` the call sites read through `Theme.of(context)` — the
/// extension is the more orthodox Flutter answer, but it would have meant
/// rewriting 298 references across 27 files and threading a BuildContext into
/// places that currently need none.
///
/// Light theme only, as before.
///
/// ## Mutating this
///
/// [usePalette] is the only writer, and [ThemeController] is the only thing that
/// should call it: the palette and the [ThemeData] built from it have to change
/// together, or screens reading these getters would disagree with the widgets
/// reading `Theme.of(context)`.
class AppColors {
  AppColors._();

  static AppPalette _palette = AppPalettes.fallback;

  /// The palette currently in force.
  static AppPalette get palette => _palette;

  /// Swap the active palette. Callers are responsible for rebuilding the widget
  /// tree afterwards — this changes what the getters answer, nothing more.
  static void usePalette(AppPalette palette) => _palette = palette;

  // ---- Brand ----
  static Color get brand => _palette.brand;
  static Color get brandDark => _palette.brandDark;
  static Color get brandLight => _palette.brandLight;

  // ---- Accent / call-to-action ----
  static Color get accent => _palette.accent;
  static Color get cta => _palette.cta;
  static Color get onCta => _palette.onCta;

  // ---- Accents (multi-accent system) ----
  static Color get coral => _palette.coral;
  static Color get amber => _palette.amber;
  static Color get violet => _palette.violet;
  static Color get blue => _palette.blue;
  static Color get green => _palette.green;
  static Color get pink => _palette.pink;
  static Color get indigo => _palette.indigo;

  // ---- Semantic ----
  static Color get success => _palette.success;
  static Color get warning => _palette.warning;
  static Color get error => _palette.error;
  static Color get info => _palette.info;

  // ---- Surfaces ----
  static Color get scaffold => _palette.scaffold;
  static Color get surface => _palette.surface;
  static Color get surfaceMuted => _palette.surfaceMuted;

  // ---- Neutrals / text ----
  static Color get ink => _palette.ink;
  static Color get inkMuted => _palette.inkMuted;
  static Color get outline => _palette.outline;

  // ---- Gradients ----
  static LinearGradient get brandGradient => _palette.brandGradient;
  static LinearGradient get sunsetGradient => _palette.sunsetGradient;

  // ---- Category accents (listing type) ----
  static Color get seat => _palette.seat;
  static Color get room => _palette.room;
  static Color get fullHouse => _palette.fullHouse;

  /// A vivid, stable accent for an arbitrary index (list items, chips, badges).
  static List<Color> get accentCycle => _palette.accentCycle;

  static Color accentForIndex(int i) => _palette.accentForIndex(i);
}
