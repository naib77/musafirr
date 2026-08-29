import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// The Musaafir mark.
///
/// One widget for every place the brand symbol appears, because before this
/// there were three places and they did not agree: the splash and the sidebar
/// drew `Icons.travel_explore_rounded` while the login screen drew
/// `Icons.home_work_rounded`. A logo that changes between screens is not a logo.
///
/// ## Why the mark is an image and the wordmark is not
///
/// "Musaafir" stays live [Text] at every call site, so it inherits the active
/// theme's ink colour for free and stays selectable, searchable and translatable.
/// Only the symbol is a raster, because that is the part a designer needs to
/// draw. Baking the wordmark into the PNG would freeze its colour against four
/// admin-selectable palettes and cost the app its text.
///
/// ## Why it ships in the brand colour and is not tinted per theme
///
/// `assets/brand/logo.png` is the mark in the brand rose `#C35063`, and every
/// call site leaves [color] null. A logo is not a UI accent: repainting it teal
/// or indigo because an admin selected that palette would swap the brand out
/// for the theme, which is the opposite of what a logo is for. The launcher
/// icon, the PWA manifest and the Android launch window are all fixed to the
/// same rose for the same reason.
///
/// [color] still exists, and repaints the mark through [BlendMode.srcIn] for a
/// caller that puts it on a surface the rose cannot survive — a saturated
/// brand-coloured header, say. Nothing needs that today.
///
/// Falls back to a Material glyph if the asset is missing or unreadable, so a
/// half-finished branding change degrades to the app's previous appearance
/// rather than to a broken-image box on the splash screen.
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.size = 64,
    this.color,
    this.assetPath = defaultAssetPath,
  });

  /// Width and height in logical pixels. The mark is square.
  final double size;

  /// Repaints the silhouette in this colour. Null renders the asset as
  /// authored — correct only on top of a brand-coloured surface, where white is
  /// what you want.
  final Color? color;

  /// The asset the mark is drawn from. Overridable so a test can point at a
  /// path that does not exist and assert the fallback actually renders — an
  /// untested fallback is a fallback you find out about on the splash screen.
  final String assetPath;

  /// Declared in pubspec.yaml.
  static const String defaultAssetPath = 'assets/brand/logo.png';

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      color: color,
      colorBlendMode: color == null ? null : BlendMode.srcIn,
      // The brand name is rendered as text beside the mark at every call site,
      // so announcing this as an image would only repeat it.
      excludeFromSemantics: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stack) => _fallback(),
    );
  }

  /// What the app looked like before the logo existed. Deliberately the same
  /// glyph the splash and sidebar already used, so the fallback is a return to
  /// the previous design rather than a third variant.
  Widget _fallback() => Icon(
        Icons.travel_explore_rounded,
        size: size,
        color: color ?? AppColors.brand,
      );
}
