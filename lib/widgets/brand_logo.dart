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
/// ## Why it is tinted rather than shipped in colour
///
/// `assets/brand/logo.png` is a white silhouette. Passing [color] repaints it
/// through [BlendMode.srcIn], so one file works on teal, indigo, crimson and
/// near-black — see `AppPalettes`. A full-colour logo could only ever look
/// right on one theme.
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
