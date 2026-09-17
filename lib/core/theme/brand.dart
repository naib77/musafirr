import 'package:flutter/material.dart';

/// The Musaafir brand colour, fixed and deliberately outside the palette system.
///
/// Everything in `AppPalette` is data an admin can swap through the
/// `active_theme` setting. This is not: it is the colour of the logo artwork in
/// `assets/brand/`, and the same value is compiled into the places the OS and
/// the browser paint *before any Dart runs* and therefore before a palette
/// could possibly be known:
///
/// - `android/.../values/colors.xml` — the pre-12 launch window
/// - `android/.../values-v31/styles.xml` — the Android 12+ SplashScreen
/// - `ios/.../LaunchScreen.storyboard` — the iOS launch screen
/// - `web/manifest.json` — the PWA install splash
/// - `web/index.html` — the boot splash that paints before the engine loads
/// - `tool/gen_brand_assets.py` — which draws the artwork itself
///
/// Those seven cannot follow the theme, so the boot sequence is brand rose on
/// every platform and the app proper wears whichever palette the admin chose.
/// Handing the splash `colorScheme.primary` instead — which is what it used to
/// do — meant the very first thing a user saw was teal while the logo, the
/// launcher icon and the install splash were all rose.
///
/// If this value changes, all seven change with it. There is no way to make
/// that automatic, so it is written down here instead.
class Brand {
  const Brand._();

  /// `#C35063`, measured from the solid interior of the supplied artwork.
  static const Color rose = Color(0xFFC35063);

  /// The far end of the gradient the search button wears: [rose] taken about
  /// 15% darker, so the button has depth without leaving the brand. Both ends
  /// carry white text and are held to 4.5:1 in `brand_test.dart`.
  ///
  /// The button is brand rose rather than the palette's `brand` on purpose.
  /// It is the one call to action on the page and has to read the same under
  /// every palette — under `coral_ink` the palette brand is #222222 and the
  /// button vanished into a black disc that looked like every other icon.
  static const Color roseDeep = Color(0xFFA63C4F);
}
