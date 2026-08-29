import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_palette.dart';

/// Musaafir type scale, built on Plus Jakarta Sans (one family across the scale
/// for a clean, modern, geometric feel). Headings are heavier; body relaxes
/// line-height for readability.
///
/// The scale itself is not themeable — an admin choosing colours is not asking
/// for a different typeface — but the *ink* colours baked into it are, so the
/// palette is passed in rather than read off the `AppColors` globals. That keeps
/// [textTheme] a pure function of its arguments, which is what lets a test build
/// a theme for a palette that is not the active one.
class AppTypography {
  AppTypography._();

  static TextTheme textTheme(TextTheme base, AppPalette p) {
    final t = GoogleFonts.plusJakartaSansTextTheme(base);
    return t.copyWith(
      displayLarge:
          t.displayLarge?.copyWith(fontWeight: FontWeight.w800, color: p.ink),
      displayMedium:
          t.displayMedium?.copyWith(fontWeight: FontWeight.w800, color: p.ink),
      displaySmall:
          t.displaySmall?.copyWith(fontWeight: FontWeight.w800, color: p.ink),
      headlineMedium:
          t.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: p.ink),
      headlineSmall:
          t.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: p.ink),
      titleLarge:
          t.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: p.ink),
      titleMedium:
          t.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: p.ink),
      titleSmall:
          t.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: p.ink),
      bodyLarge: t.bodyLarge?.copyWith(color: p.ink, height: 1.4),
      bodyMedium: t.bodyMedium?.copyWith(color: p.ink, height: 1.4),
      bodySmall: t.bodySmall?.copyWith(color: p.inkMuted, height: 1.35),
      labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      labelMedium: t.labelMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}
