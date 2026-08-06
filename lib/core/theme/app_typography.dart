import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Musaafir type scale, built on Plus Jakarta Sans (one family across the scale
/// for a clean, modern, geometric feel). Headings are heavier; body relaxes
/// line-height for readability.
class AppTypography {
  AppTypography._();

  static TextTheme textTheme(TextTheme base) {
    final t = GoogleFonts.plusJakartaSansTextTheme(base);
    return t.copyWith(
      displayLarge: t.displayLarge
          ?.copyWith(fontWeight: FontWeight.w800, color: AppColors.ink),
      displayMedium: t.displayMedium
          ?.copyWith(fontWeight: FontWeight.w800, color: AppColors.ink),
      displaySmall: t.displaySmall
          ?.copyWith(fontWeight: FontWeight.w800, color: AppColors.ink),
      headlineMedium: t.headlineMedium
          ?.copyWith(fontWeight: FontWeight.w800, color: AppColors.ink),
      headlineSmall: t.headlineSmall
          ?.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
      titleLarge: t.titleLarge
          ?.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
      titleMedium: t.titleMedium
          ?.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
      titleSmall: t.titleSmall
          ?.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink),
      bodyLarge: t.bodyLarge?.copyWith(color: AppColors.ink, height: 1.4),
      bodyMedium: t.bodyMedium?.copyWith(color: AppColors.ink, height: 1.4),
      bodySmall: t.bodySmall?.copyWith(color: AppColors.inkMuted, height: 1.35),
      labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      labelMedium: t.labelMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}
