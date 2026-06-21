import 'package:flutter/material.dart';

/// Centralized color tokens for the Musafir design system.
///
/// Brand stays teal; accents lean colorful and modern (multi-accent system).
/// Light theme only for now — values are grouped so a dark variant can be
/// layered on later without touching call sites.
class AppColors {
  AppColors._();

  // ---- Brand ----
  static const Color brand = Color(0xFF0B7285); // teal
  static const Color brandDark = Color(0xFF075460);
  static const Color brandLight = Color(0xFF0E9AA7);

  // ---- Accents (multi-accent system) ----
  static const Color coral = Color(0xFFFF6B6B);
  static const Color amber = Color(0xFFF59E0B);
  static const Color violet = Color(0xFF7C3AED);
  static const Color blue = Color(0xFF2563EB);
  static const Color green = Color(0xFF10B981);
  static const Color pink = Color(0xFFEC4899);
  static const Color indigo = Color(0xFF4F46E5);

  // ---- Semantic ----
  static const Color success = Color(0xFF059669);
  static const Color warning = Color(0xFFD97706);
  static const Color error = Color(0xFFDC2626);
  static const Color info = Color(0xFF2563EB);

  // ---- Surfaces ----
  static const Color scaffold = Color(0xFFF6F8F7);
  static const Color surface = Colors.white;
  static const Color surfaceMuted = Color(0xFFEDF1F1);

  // ---- Neutrals / text ----
  static const Color ink = Color(0xFF0E1F23); // near-black with a teal tint
  static const Color inkMuted = Color(0xFF5B6B70);
  static const Color outline = Color(0xFFE2E8E9);

  // ---- Gradients ----
  static const LinearGradient brandGradient = LinearGradient(
    colors: [brand, brandLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient sunsetGradient = LinearGradient(
    colors: [coral, amber],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ---- Category accents (listing type) ----
  static const Color seat = blue;
  static const Color room = violet;
  static const Color fullHouse = brand;

  /// A vivid, stable accent for an arbitrary index (list items, chips, badges).
  static const List<Color> accentCycle = [
    coral,
    amber,
    violet,
    blue,
    green,
    pink,
    indigo,
  ];

  static Color accentForIndex(int i) => accentCycle[i % accentCycle.length];
}
