import 'package:flutter/material.dart';

import 'app_palette.dart';

/// Every palette this build can render, and the lookup from the stored
/// `active_theme` slug to one of them.
///
/// The app can only wear a palette it was compiled with, so this list — not the
/// database — is the real limit on what an admin can select. Migration 105
/// validates the setting against the same slugs so the portal cannot save a
/// theme the app would silently ignore; **adding a palette here means adding its
/// id to `fn_validate_setting_active_theme` too**, and
/// `test/core/theme/app_palettes_test.dart` pins the slug list so the two
/// drifting apart shows up as a failing test rather than a theme that never
/// appears.
class AppPalettes {
  AppPalettes._();

  /// The original teal identity, reproduced value-for-value from the
  /// `static const`s this system replaced. Applying the theme system therefore
  /// changes nothing on screen until an admin actually picks something else —
  /// which is the only way to tell a refactor of 27 files from a redesign.
  static const AppPalette oceanTeal = AppPalette(
    id: 'ocean_teal',
    label: 'Ocean Teal',
    brand: Color(0xFF0B7285),
    brandDark: Color(0xFF075460),
    brandLight: Color(0xFF0E9AA7),
    // Teal leads and teal acts: this palette's buttons have always been brand
    // coloured, with coral only as ColorScheme.secondary.
    //
    // Coral was #FF6B6B, which is 2.8:1 on white. In this app the colour is only
    // ever an icon tint — the favourite heart, and a sidebar shortcut's glyph —
    // and `colorScheme.secondary` is never read, so the bar is WCAG 1.4.11's
    // 3:1 for graphical objects rather than 4.5:1 for text. Darkened just past
    // that (3.5:1 on white, 3.3:1 on the scaffold) instead of all the way to
    // 4.5:1, which would have meant a brick red and cost the colour its coral
    // identity.
    accent: Color(0xFFF04F4F),
    cta: Color(0xFF0B7285),
    onCta: Colors.white,
    coral: Color(0xFFF04F4F),
    amber: Color(0xFFF59E0B),
    violet: Color(0xFF7C3AED),
    blue: Color(0xFF2563EB),
    green: Color(0xFF10B981),
    pink: Color(0xFFEC4899),
    indigo: Color(0xFF4F46E5),
    // Both were a step lighter (#059669 at 3.8:1, #D97706 at 3.2:1) and both are
    // used as text and icon colours throughout — "Verified", "Available",
    // earnings figures — so they are held to 4.5:1. One step down the same
    // ramps: emerald-700 and amber-700, so they read as the same colours, only
    // legible.
    success: Color(0xFF047857), // 5.5:1
    warning: Color(0xFFB45309), // 5.0:1
    error: Color(0xFFDC2626),
    info: Color(0xFF2563EB),
    scaffold: Color(0xFFF6F8F7),
    surface: Colors.white,
    surfaceMuted: Color(0xFFEDF1F1),
    ink: Color(0xFF0E1F23), // near-black with a teal tint
    inkMuted: Color(0xFF5B6B70),
    outline: Color(0xFFE2E8E9),
    // Was brand → brandLight (#0B7285 → #0E9AA7). The light end was 3.4:1 under
    // the white headings this gradient carries, and it is also used as a text
    // shader (listing_detail_screen.dart), where it sat on white at the same
    // ratio. Rather than darkening brandLight — which is still an honest "light
    // teal" for its one decorative tint — the gradient now runs brandDark →
    // brand, keeping a comparable luminance sweep while both ends clear 4.5:1
    // (8.6:1 and 5.6:1). Deeper than before, and legible in both directions.
    brandGradient: LinearGradient(
      colors: [Color(0xFF075460), Color(0xFF0B7285)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    sunsetGradient: LinearGradient(
      colors: [Color(0xFFF04F4F), Color(0xFFF59E0B)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    seat: Color(0xFF2563EB),
    room: Color(0xFF7C3AED),
    fullHouse: Color(0xFF0B7285),
    accentCycle: [
      Color(0xFFF04F4F),
      Color(0xFFF59E0B),
      Color(0xFF7C3AED),
      Color(0xFF2563EB),
      Color(0xFF10B981),
      Color(0xFFEC4899),
      Color(0xFF4F46E5),
    ],
  );

  /// Red and blue, mixed — blue structural, red for action.
  ///
  /// The split is deliberate and is what makes the mix work rather than fight:
  ///
  /// * **Blue carries the app.** Navigation, the selected tab, icons, links and
  ///   focus rings are indigo-blue. It is the colour a marketplace wants for the
  ///   parts of the UI that are simply *there*, and it stays out of the way.
  /// * **Red carries the ask.** [cta] points at [accent], so every primary
  ///   button — Book, Pay, Confirm — is rose red, and it is the only thing on a
  ///   screen wearing that colour.
  /// * **[brandGradient] is the actual mix**, blue → violet → rose. Violet is
  ///   the bridge hue; a straight two-stop blue-to-red passes through the same
  ///   place but muddily, so the midpoint is named instead of stumbled into.
  ///
  /// Red as the *accent* rather than the brand also keeps [error] usable. A
  /// red-branded theme has to push its error colour somewhere strange to stay
  /// distinguishable; here error is Material's #B3261E, a brick red two shades
  /// darker than the rose CTA and in a different hue family. The two never share
  /// a context anyway (one is a filled button, the other borders a field beside a
  /// message), and error states always carry text and an icon, so colour is
  /// never the only signal.
  static const AppPalette indigoCrimson = AppPalette(
    id: 'indigo_crimson',
    label: 'Indigo Crimson',
    brand: Color(0xFF1D4ED8), // 6.7:1 on white
    brandDark: Color(0xFF1B3AA0),
    brandLight: Color(0xFF3B82F6),
    // 5.3:1 on white and 5.0:1 on the scaffold. The brighter #E11D48 reads
    // better in isolation but drops to 4.4:1 against the page background, which
    // a price or a badge label sitting on the scaffold would fail.
    accent: Color(0xFFD31843),
    cta: Color(0xFFD31843),
    onCta: Colors.white,
    coral: Color(0xFFFB7185), // rose-400: the soft end of the accent family
    amber:
        Color(0xFFF59E0B), // unchanged — rating stars stay gold in every theme
    violet: Color(0xFF7C3AED), // the hue the gradient turns through
    // A deep sky rather than another blue-600: the `blue` slot has to stay
    // visibly apart from `brand`, which is itself blue in this palette.
    blue: Color(0xFF0369A1),
    green: Color(0xFF10B981),
    pink: Color(0xFFEC4899),
    indigo: Color(0xFF4F46E5),
    success: Color(0xFF047857), // 5.5:1 — darker than oceanTeal's, and legible
    warning: Color(0xFFB45309), // 5.0:1
    error: Color(0xFFB3261E), // 6.5:1, and clear of the rose CTA
    info: Color(0xFF1D4ED8),
    scaffold: Color(0xFFF6F8FC), // near-white, cooled toward the brand
    surface: Colors.white,
    surfaceMuted: Color(0xFFEDF0F9),
    ink: Color(0xFF111634), // navy-black, 18:1
    inkMuted: Color(0xFF5A6284), // 6.0:1
    outline: Color(0xFFE1E6F2),
    brandGradient: LinearGradient(
      colors: [Color(0xFF1D4ED8), Color(0xFF7C3AED), Color(0xFFD31843)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    sunsetGradient: LinearGradient(
      colors: [Color(0xFFD31843), Color(0xFFF59E0B)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    // Three listing types, three hues far enough apart to be told apart at chip
    // size: sky, indigo, rose.
    seat: Color(0xFF0369A1),
    room: Color(0xFF4F46E5),
    fullHouse: Color(0xFFD31843),
    accentCycle: [
      Color(0xFFD31843),
      Color(0xFF1D4ED8),
      Color(0xFF7C3AED),
      Color(0xFFB45309),
      Color(0xFF4F46E5),
      Color(0xFFEC4899),
      Color(0xFF0369A1),
    ],
  );

  /// Reds, all the way down — the brand gradient is a red ramp and it leads.
  ///
  /// Where [indigoCrimson] keeps red for the ask and lets blue carry the app,
  /// this palette hands red both jobs: navigation, icons, focus rings and the
  /// primary buttons are all crimson, and [brandGradient] runs wine → crimson →
  /// rose rather than crossing into another hue. [cta] points at [brand], as
  /// oceanTeal's does, because a red-led theme has no reason to ask in a
  /// different colour than it speaks in.
  ///
  /// ## The problem a red brand creates, and the answer
  ///
  /// Red is the colour of "wrong". Spend it on the brand and [error] has nowhere
  /// obvious to go: it cannot move hue without ceasing to read as an error, and
  /// staying red risks a rejected field looking merely branded. Hue is spoken
  /// for, so the separation is made in **lightness** — error is a deep oxblood
  /// at 9.2:1 against a crimson brand at 6.3:1, which puts 1.47 between them.
  /// For comparison, [indigoCrimson] separates its error from its red CTA by
  /// only 1.24, so this is the wider gap of the two, not a compromise.
  ///
  /// It is also never the only signal: an error state carries an icon and a
  /// message, and the app's rejected-field border sits beside both.
  ///
  /// The three stops of the gradient are all dark enough for white text (9.4,
  /// 6.3 and 4.7), which is what stops a red ramp from being the one gradient
  /// you cannot put a heading on.
  static const AppPalette crimsonEmber = AppPalette(
    id: 'crimson_ember',
    label: 'Crimson Ember',
    brand: Color(0xFFBE123C), // 6.3:1 — the gradient's middle stop
    brandDark: Color(0xFF8A1538), // 9.4:1 — its dark end
    brandLight: Color(0xFFE11D48), // 4.7:1 — its bright end
    // Bright rose: the same family as the brand, a step up in energy. Clears the
    // text bar as well as the graphical one, so it is safe anywhere.
    accent: Color(0xFFE11D48),
    cta: Color(0xFFBE123C),
    onCta: Colors.white,
    coral: Color(0xFFF04F4F),
    amber: Color(0xFFF59E0B), // rating stars stay gold in every theme
    violet: Color(0xFF7C3AED),
    blue: Color(0xFF0369A1),
    green: Color(0xFF10B981),
    pink: Color(0xFFEC4899),
    indigo: Color(0xFF4F46E5),
    success: Color(0xFF047857), // 5.5:1
    warning: Color(0xFFB45309), // 5.0:1 — amber, 43° of hue clear of the brand
    error: Color(0xFF8E1616), // 9.2:1 — see the class comment
    // Info must not be red in a theme this red, or "for your information" and
    // "this is our brand" become the same sentence.
    info: Color(0xFF1D4ED8),
    scaffold: Color(0xFFFCF7F8), // near-white, warmed toward the brand
    surface: Colors.white,
    surfaceMuted: Color(0xFFF5EDEF),
    ink: Color(0xFF1F1013), // near-black with a red tint, 18:1
    inkMuted: Color(0xFF6B565A), // 6.8:1
    outline: Color(0xFFEFE2E5),
    brandGradient: LinearGradient(
      colors: [Color(0xFF8A1538), Color(0xFFBE123C), Color(0xFFE11D48)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    sunsetGradient: LinearGradient(
      colors: [Color(0xFFBE123C), Color(0xFFF59E0B)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    // Sky, violet, crimson: three clearly separate hues, because these three sit
    // next to each other as chips on the same screen.
    seat: Color(0xFF0369A1),
    room: Color(0xFF7C3AED),
    fullHouse: Color(0xFFBE123C),
    // Led by the brand, then deliberately away from red — a list of seven reds
    // would defeat the point of an accent cycle.
    accentCycle: [
      Color(0xFFBE123C),
      Color(0xFF0369A1),
      Color(0xFFB45309),
      Color(0xFF7C3AED),
      Color(0xFF047857),
      Color(0xFFEC4899),
      Color(0xFF4F46E5),
    ],
  );

  /// The Airbnb look: near-black everything, one coral-red reserved for the ask.
  ///
  /// Modelled on Airbnb's live product palette rather than the 2014 Design
  /// Language System deck that most colour databases still reproduce — both are
  /// real, from different eras. Current: Rausch #FF385C (the DLS one was
  /// #FF5A5F), Babu #00A699, Arches #FC642D, ink #222222, Foggy #767676, soft
  /// surface #F7F7F7.
  ///
  /// ## What actually makes it look like Airbnb
  ///
  /// Not the red — the *restraint*. Airbnb spends a single high-chroma colour on
  /// primary actions only and leaves everything else near-neutral, which is why
  /// the red always means "this is the thing to press". So here [brand] is ink,
  /// not coral: navigation, icons, links and focus rings all go near-black, and
  /// [cta] carries the one red. That is the opposite arrangement to
  /// [crimsonEmber], which hands red both jobs.
  ///
  /// It also means this palette gets the error problem for free — with a black
  /// brand, a red error competes with nothing structural.
  ///
  /// ## Three deliberate departures from Airbnb's own hex
  ///
  /// Airbnb's palette does not meet WCAG AA, and this app's does. Measured:
  ///
  /// * **[cta] is #E00B41, not Rausch #FF385C.** White text on Rausch is
  ///   3.5:1 — under AA for normal text, and their Reserve button is normal
  ///   text. #E00B41 is Airbnb's *own* pressed-state red and reaches 4.9:1, so
  ///   the button is their colour, one state deeper. Rausch survives untouched
  ///   as [accent] and [coral], where it tints the favourite heart — an icon, so
  ///   the bar there is 3:1 and Rausch clears it.
  /// * **[inkMuted] is #6A6A6A, not Foggy #767676.** Foggy is 4.54:1 on white
  ///   but only 4.24:1 on the #F7F7F7 page, and secondary text is where it is
  ///   used. One notch darker clears both.
  /// * **The gradient's first stop is #DA1A47, not #E61E4D.** Airbnb's search
  ///   button starts at #E61E4D, which lands on 4.51:1 under white text —
  ///   passing by 0.01, close enough to the line that a rounding difference
  ///   decides it. #DA1A47 is the same colour with an actual margin.
  ///
  /// Babu and Arches are likewise too light to set text in (3.0:1 and 3.0:1), so
  /// [success] and [warning] use the darker members of those families.
  ///
  /// One thing this is not: [brandGradient] is Airbnb's search-button gradient,
  /// which they use sparingly — a wordmark and one button. This app paints
  /// section headers with it, so it appears far more here than it would there.
  static const AppPalette coralInk = AppPalette(
    id: 'coral_ink',
    label: 'Coral Ink',
    brand: Color(0xFF222222), // Airbnb's ink — 15.9:1
    brandDark: Color(0xFF000000),
    brandLight: Color(0xFF484848), // Hof, the classic DLS grey
    accent: Color(0xFFFF385C), // Rausch, current — 3.5:1, icons only
    cta: Color(0xFFE00B41), // their pressed red, 4.9:1 — see above
    onCta: Colors.white,
    coral: Color(0xFFFF385C), // Rausch again: the favourite heart
    amber: Color(0xFFF59E0B), // rating stars stay gold in every theme
    violet: Color(0xFF7C3AED),
    blue: Color(0xFF0B6E99),
    green: Color(0xFF008489), // Babu, one step down so it clears 3:1
    pink: Color(0xFFEC4899),
    indigo: Color(0xFF4F46E5),
    success: Color(0xFF007A87), // deep Babu — 5.1:1
    warning: Color(0xFFA8420F), // deep Arches — 6.1:1
    // Airbnb's own error red, and it is 34° of hue off the CTA: they separate
    // "wrong" from "press me" by warmth rather than by lightness. Nothing
    // structural is red here, so that is enough.
    error: Color(0xFFC13515),
    info: Color(0xFF0B6E99), // 5.7:1
    // Airbnb's pages are white and their panels are #F7F7F7. That is inverted
    // here: this app's cards are white with no border and no elevation, so a
    // white page would make them vanish. #F7F7F7 is still their grey, just
    // carrying the page instead of the panel.
    scaffold: Color(0xFFF7F7F7),
    surface: Colors.white,
    surfaceMuted: Color(0xFFEBEBEB),
    ink: Color(0xFF222222),
    inkMuted: Color(0xFF6A6A6A), // 5.4:1 — see above re: Foggy
    outline: Color(0xFFDDDDDD), // their border grey
    // Their search-button gradient: a hue sweep (346° → 340° → 332°), red into
    // magenta, rather than a light-to-dark ramp. White text clears AA on all
    // three stops.
    brandGradient: LinearGradient(
      colors: [Color(0xFFDA1A47), Color(0xFFE31C5F), Color(0xFFD70466)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    sunsetGradient: LinearGradient(
      colors: [Color(0xFFFF385C), Color(0xFFFC642D)], // Rausch → Arches
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    // Babu, Arches and Rausch — the three colours Airbnb itself uses to tell
    // categories apart, and far enough apart to work as chips.
    seat: Color(0xFF007A87),
    room: Color(0xFFA8420F),
    fullHouse: Color(0xFFE00B41),
    accentCycle: [
      Color(0xFFE00B41),
      Color(0xFF007A87),
      Color(0xFFA8420F),
      Color(0xFF0B6E99),
      Color(0xFF7C3AED),
      Color(0xFFEC4899),
      Color(0xFF4F46E5),
    ],
  );

  /// Every selectable palette, in the order the admin portal should offer them.
  static const List<AppPalette> all = [
    oceanTeal,
    indigoCrimson,
    crimsonEmber,
    coralInk,
  ];

  /// What the app wears when the setting is absent, unreadable, or names a
  /// palette this build does not have. The original identity, so falling back is
  /// never a surprise.
  static const AppPalette fallback = oceanTeal;

  /// The palette for [id], or null if no palette has that slug.
  ///
  /// Returns null rather than the fallback so callers can tell "the admin picked
  /// the default" apart from "the admin picked something this build has never
  /// heard of" — the second is worth a log line, because it means the database
  /// and the deployed bundle disagree.
  static AppPalette? find(String? id) {
    final slug = id?.trim().toLowerCase();
    if (slug == null || slug.isEmpty) return null;
    for (final palette in all) {
      if (palette.id == slug) return palette;
    }
    return null;
  }

  /// The palette for [id], falling back to [fallback]. This is the whole of the
  /// setting-to-colours decision, kept pure and away from the I/O in
  /// `ThemeController` so it can be tested directly.
  static AppPalette resolve(String? id) => find(id) ?? fallback;
}
