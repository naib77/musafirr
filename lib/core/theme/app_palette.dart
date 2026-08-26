import 'package:flutter/material.dart';

/// One complete set of colour values for the app — a "theme" in the sense the
/// admin portal means it.
///
/// Musaafir's colours used to be `static const` on `AppColors`, which made the
/// palette a compile-time fact: changing it meant a Dart edit, a rebuild, and a
/// redeploy of the committed web bundle. The palette is now data, selected by
/// the `active_theme` row in `app_settings`, so switching the app's colours is
/// an admin action rather than a release.
///
/// Only colours live here. Type scale, radii, spacing and component shapes stay
/// compiled in: they are layout decisions that a colour swap must not be able to
/// disturb, and an admin picking "the red one" is not asking for different
/// button geometry.
///
/// ## Why the hue-named slots
///
/// [coral], [amber], [violet], [blue], [green], [pink] and [indigo] are named
/// after hues rather than roles, which is not how you would design this from
/// scratch. They are kept because ~40 call sites already reach for them by name,
/// and mechanically renaming those would mean guessing at each one whether
/// `amber` meant "a rating star" or "a caution". Read them as *slots*: a palette
/// may put any colour in its `amber` slot, and a theme that wants orange stars
/// where another wants rose does so by filling the slot differently. New code
/// should prefer the role tokens ([brand], [accent], [cta], [success], …).
@immutable
class AppPalette {
  const AppPalette({
    required this.id,
    required this.label,
    required this.brand,
    required this.brandDark,
    required this.brandLight,
    required this.accent,
    required this.cta,
    required this.onCta,
    required this.coral,
    required this.amber,
    required this.violet,
    required this.blue,
    required this.green,
    required this.pink,
    required this.indigo,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.scaffold,
    required this.surface,
    required this.surfaceMuted,
    required this.ink,
    required this.inkMuted,
    required this.outline,
    required this.brandGradient,
    required this.sunsetGradient,
    required this.seat,
    required this.room,
    required this.fullHouse,
    required this.accentCycle,
  });

  // ---- Identity ----

  /// Stable slug stored in `app_settings.active_theme`. Never change one of
  /// these: it is the value already sitting in the live database and cached on
  /// every user's device, and a rename silently demotes them to the fallback.
  final String id;

  /// Human-readable name, for the admin portal's picker.
  final String label;

  // ---- Brand: the structural colour ----
  // Navigation, icons, links, focus rings, selected states. The colour the app
  // wears when it is not asking for anything.

  final Color brand;
  final Color brandDark;
  final Color brandLight;

  // ---- Accent & call-to-action ----

  /// The secondary brand colour (`ColorScheme.secondary`).
  final Color accent;

  /// What fills a primary button. Deliberately separate from both [brand] and
  /// [accent]: a theme decides for itself whether its structural colour or its
  /// accent is the one that says "Book". Pointing this at [accent] is what makes
  /// a blue-led theme with red buttons possible without recolouring navigation.
  final Color cta;

  /// Label/icon colour on top of [cta]. A field rather than an assumption of
  /// white, because a light [cta] would need dark text.
  final Color onCta;

  // ---- Hue slots (see the class comment) ----

  final Color coral;
  final Color amber;
  final Color violet;
  final Color blue;
  final Color green;
  final Color pink;
  final Color indigo;

  // ---- Semantic ----
  // These stay themeable rather than fixed, because a palette has to be able to
  // keep them clear of its own brand colours — a red-accented theme whose error
  // colour is the same red has no way to say "this went wrong".

  final Color success;
  final Color warning;
  final Color error;
  final Color info;

  // ---- Surfaces ----

  final Color scaffold;
  final Color surface;
  final Color surfaceMuted;

  // ---- Neutrals / text ----

  final Color ink;
  final Color inkMuted;
  final Color outline;

  // ---- Gradients ----

  final LinearGradient brandGradient;
  final LinearGradient sunsetGradient;

  // ---- Category accents (listing type) ----
  // Kept mutually distinguishable within a palette: these three appear side by
  // side on the same screen, so they carry meaning only if they read apart.

  final Color seat;
  final Color room;
  final Color fullHouse;

  /// Vivid, stable accents for an arbitrary index (list items, chips, badges).
  /// Order is load-bearing — it is indexed by position, so inserting a colour
  /// in the middle reshuffles every list that uses it.
  final List<Color> accentCycle;

  /// A stable accent for [i], wrapping around [accentCycle].
  Color accentForIndex(int i) => accentCycle[i % accentCycle.length];

  @override
  String toString() => 'AppPalette($id)';
}
