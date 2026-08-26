import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:musafir/core/theme/app_colors.dart';
import 'package:musafir/core/theme/app_palette.dart';
import 'package:musafir/core/theme/app_palettes.dart';
import 'package:musafir/core/theme/app_theme.dart';

/// WCAG 2.1 contrast ratio between two opaque colours.
///
/// Flutter's own `computeLuminance()` implements the relative-luminance formula,
/// so this is only the ratio on top of it — worth having rather than eyeballing
/// hex values, because "is this red readable on this grey" is not a judgement a
/// reviewer can make reliably and it is the exact thing that breaks when someone
/// adds a palette.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// AA for normal-size text (WCAG 1.4.3).
const double kMinTextContrast = 4.5;

/// WCAG 1.4.11: icons and other graphical objects need less than text does,
/// because a glyph is a shape as well as a colour.
const double kMinGraphicalContrast = 3.0;

/// Tokens that carry text or a thin border, held to [kMinTextContrast].
Map<String, Color> textTokens(AppPalette p) => {
      'brand': p.brand,
      'brandDark': p.brandDark,
      'success': p.success,
      'warning': p.warning,
      'error': p.error,
      'info': p.info,
      'ink': p.ink,
      'inkMuted': p.inkMuted,
    };

/// Tokens only ever used as an icon tint or a fill, held to
/// [kMinGraphicalContrast].
///
/// `accent` sits here rather than with the text tokens on the strength of a
/// check, not an assumption: in this app it reaches the screen only as the
/// favourite heart's colour and a sidebar shortcut's glyph, and
/// `colorScheme.secondary` — the one place Material could turn it into text — is
/// never read. A palette that starts drawing labels in `accent` has to move it
/// back up here.
///
/// A palette whose `cta` is its `accent` still gets the stricter check, via the
/// separate button-label assertion below.
Map<String, Color> graphicalTokens(AppPalette p) => {
      'accent': p.accent,
    };

void main() {
  // AppTheme builds its text theme through GoogleFonts, which wants an asset
  // bundle; and a test must never reach the network for a font file.
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  tearDown(() {
    // AppColors is process-global; don't leak one test's palette into the next.
    AppColors.usePalette(AppPalettes.fallback);
  });

  group('registry', () {
    test('slug list is pinned', () {
      // These ids are stored in `app_settings.active_theme` and cached on every
      // user's device, and migration 105's validator hardcodes the same list.
      // Changing this expectation means changing the database too — that is the
      // point of pinning it.
      expect(
        AppPalettes.all.map((p) => p.id).toList(),
        ['ocean_teal', 'indigo_crimson', 'crimson_ember', 'coral_ink'],
      );
    });

    test('ids are unique, slug-shaped, and labelled', () {
      final ids = AppPalettes.all.map((p) => p.id).toList();
      expect(ids.toSet(), hasLength(ids.length), reason: 'duplicate theme id');
      for (final p in AppPalettes.all) {
        expect(p.id, matches(RegExp(r'^[a-z][a-z0-9_]*$')),
            reason: '${p.id} is not a lowercase slug');
        expect(p.label.trim(), isNotEmpty, reason: '${p.id} has no label');
      }
    });

    test('the fallback is a registered palette', () {
      expect(AppPalettes.all, contains(AppPalettes.fallback));
    });
  });

  group('find / resolve', () {
    test('finds a palette by its exact id', () {
      expect(AppPalettes.find('indigo_crimson'), AppPalettes.indigoCrimson);
      expect(AppPalettes.find('ocean_teal'), AppPalettes.oceanTeal);
    });

    test('tolerates the casing and padding a hand-typed setting arrives with',
        () {
      for (final raw in [
        '  indigo_crimson',
        'INDIGO_CRIMSON',
        ' Indigo_Crimson '
      ]) {
        expect(AppPalettes.find(raw), AppPalettes.indigoCrimson, reason: raw);
      }
    });

    test('reports an unknown or absent id as null, not as the default', () {
      // The distinction is what lets ThemeController log "the database names a
      // theme this bundle does not have" instead of silently doing nothing.
      expect(AppPalettes.find(null), isNull);
      expect(AppPalettes.find(''), isNull);
      expect(AppPalettes.find('   '), isNull);
      expect(AppPalettes.find('midnight_gold'), isNull);
    });

    test('resolve falls back rather than throwing', () {
      expect(AppPalettes.resolve(null), AppPalettes.fallback);
      expect(AppPalettes.resolve('midnight_gold'), AppPalettes.fallback);
      expect(AppPalettes.resolve('indigo_crimson'), AppPalettes.indigoCrimson);
    });
  });

  group('oceanTeal pins the teal identity', () {
    // The palette refactor touched 27 files, and this group is the guard that
    // the default theme's appearance is a decision rather than a side effect:
    // every value is pinned, so a change to what users see fails here instead
    // of shipping.
    //
    // Most of these are the original `static const`s that AppColors held before
    // the theme system existed. FIVE are deliberately not, and are marked
    // below: accent/coral, success, warning, and the brand gradient were all
    // under their WCAG minimum and were corrected. brandLight keeps its
    // original value — it is decorative-only now that the gradient no longer
    // reaches it.
    const p = AppPalettes.oceanTeal;

    test('brand, accents and semantics', () {
      expect(p.brand, const Color(0xFF0B7285));
      expect(p.brandDark, const Color(0xFF075460));
      expect(p.brandLight, const Color(0xFF0E9AA7));
      // CHANGED from #FF6B6B (2.8:1) — see the palette's comment.
      expect(p.coral, const Color(0xFFF04F4F));
      expect(p.amber, const Color(0xFFF59E0B));
      expect(p.violet, const Color(0xFF7C3AED));
      expect(p.blue, const Color(0xFF2563EB));
      expect(p.green, const Color(0xFF10B981));
      expect(p.pink, const Color(0xFFEC4899));
      expect(p.indigo, const Color(0xFF4F46E5));
      // CHANGED from #059669 (3.8:1) and #D97706 (3.2:1); both carry text.
      expect(p.success, const Color(0xFF047857));
      expect(p.warning, const Color(0xFFB45309));
      expect(p.error, const Color(0xFFDC2626));
      expect(p.info, const Color(0xFF2563EB));
    });

    test('surfaces and neutrals', () {
      expect(p.scaffold, const Color(0xFFF6F8F7));
      expect(p.surface, const Color(0xFFFFFFFF));
      expect(p.surfaceMuted, const Color(0xFFEDF1F1));
      expect(p.ink, const Color(0xFF0E1F23));
      expect(p.inkMuted, const Color(0xFF5B6B70));
      expect(p.outline, const Color(0xFFE2E8E9));
    });

    test('gradients, category accents and the accent cycle', () {
      // CHANGED: was [brand, brandLight]. The light end was 3.4:1 under the
      // white text this gradient carries, so it now runs dark→brand instead of
      // brand→light. Asserted as an explicit pair rather than [p.brandDark,
      // p.brand] so that redefining brandDark cannot quietly move the gradient.
      expect(p.brandGradient.colors,
          [const Color(0xFF075460), const Color(0xFF0B7285)]);
      expect(p.sunsetGradient.colors, [p.coral, p.amber]);
      expect(p.seat, p.blue);
      expect(p.room, p.violet);
      expect(p.fullHouse, p.brand);
      expect(p.accentCycle, [
        p.coral,
        p.amber,
        p.violet,
        p.blue,
        p.green,
        p.pink,
        p.indigo,
      ]);
    });

    test('its buttons are brand coloured, as they always were', () {
      // oceanTeal.cta == brand is what makes introducing the separate cta token
      // a no-op for the live theme.
      expect(p.cta, p.brand);
    });
  });

  group('indigoCrimson mixes red and blue without losing either', () {
    const p = AppPalettes.indigoCrimson;

    test('blue is structural and red is the call to action', () {
      // The whole design of the palette in one assertion: navigation-coloured
      // blue, action-coloured red, and they are genuinely different colours.
      expect(p.cta, p.accent);
      expect(p.cta, isNot(p.brand));
      expect(contrast(p.brand, p.accent), greaterThan(1.2),
          reason: 'brand and cta must be tellable apart');
    });

    test('the brand gradient is the red/blue mix, bridged through violet', () {
      expect(p.brandGradient.colors, [p.brand, p.violet, p.accent]);
    });

    test('error stays distinguishable from the red call to action', () {
      // A red-accented theme's real hazard: "wrong" and "press me" looking the
      // same. They are separated by lightness, not just hue.
      expect(p.error, isNot(p.accent));
      expect(contrast(p.error, p.accent), greaterThan(1.15));
    });

    test('the blue hue slot does not collapse into the brand blue', () {
      // Measured as hue distance, not contrast: the two are deliberately close
      // in lightness, and a contrast ratio would call them identical while they
      // read as a clear sky-vs-indigo pair on screen.
      final delta =
          (HSLColor.fromColor(p.blue).hue - HSLColor.fromColor(p.brand).hue)
              .abs();
      expect(delta, greaterThan(15),
          reason: 'blue and brand are only ${delta.toStringAsFixed(1)}° apart');
    });
  });

  group('crimsonEmber leads with a reds gradient', () {
    const p = AppPalettes.crimsonEmber;

    test('the gradient is a red ramp, and the brand is drawn from it', () {
      expect(p.brandGradient.colors, [p.brandDark, p.brand, p.brandLight]);
      // A "reds gradient" means no stop leaves the family. Hues within 40° of
      // each other, all in the red/rose arc rather than wandering into orange
      // or violet the way a two-hue gradient would.
      final hues =
          p.brandGradient.colors.map((c) => HSLColor.fromColor(c).hue).toList();
      for (final h in hues) {
        expect(h, inInclusiveRange(330, 360),
            reason: 'gradient stop at ${h.toStringAsFixed(0)}° is not a red');
      }
      // And it actually ramps — three stops of the same colour is not a
      // gradient.
      final lums =
          p.brandGradient.colors.map((c) => c.computeLuminance()).toList();
      expect(lums[0], lessThan(lums[1]));
      expect(lums[1], lessThan(lums[2]));
    });

    test('red leads: it carries both navigation and the ask', () {
      expect(p.cta, p.brand);
      expect(HSLColor.fromColor(p.brand).hue, inInclusiveRange(330, 360));
    });

    test('error is separated from the brand by lightness, not hue', () {
      // The invariant this palette is designed around. Hue is spent on the
      // brand, so "wrong" has to be told apart some other way — and by a wider
      // margin than indigoCrimson needs, since there red is only the CTA.
      final separation = contrast(p.error, p.brand);
      expect(separation, greaterThan(1.35),
          reason: 'error and brand are only '
              '${separation.toStringAsFixed(2)} apart');
      expect(
        separation,
        greaterThan(contrast(
            AppPalettes.indigoCrimson.error, AppPalettes.indigoCrimson.cta)),
        reason: 'a red-branded theme must separate error at least as well as '
            'the blue-led one does',
      );
    });

    test('info does not read as the brand', () {
      // "For your information" and "this is our brand" must not be the same
      // colour, which rules out red here.
      expect(HSLColor.fromColor(p.info).hue, isNot(inInclusiveRange(330, 360)));
    });
  });

  group('coralInk keeps its one red for the ask', () {
    const p = AppPalettes.coralInk;

    test('structure is ink, not coral', () {
      // The actual mechanism behind the Airbnb look: a single high-chroma colour
      // spent only on primary actions, everything else near-neutral. If brand
      // ever becomes the red, the restraint — and the resemblance — is gone.
      expect(p.brand, const Color(0xFF222222));
      expect(p.cta, isNot(p.brand));
      expect(contrast(p.brand, p.surface), greaterThan(12),
          reason: 'brand should be near-black');
    });

    test('Rausch survives where it is legible, and only there', () {
      // Rausch #FF385C is 3.5:1 on white: fine for the favourite heart, not for
      // a button label. So it lives in the graphical tokens while the CTA takes
      // Airbnb's own deeper pressed red.
      expect(p.accent, const Color(0xFFFF385C));
      expect(p.coral, const Color(0xFFFF385C));
      expect(p.cta, const Color(0xFFE00B41));
      expect(contrast(p.accent, p.surface), lessThan(kMinTextContrast));
      expect(contrast(p.accent, p.surface),
          greaterThanOrEqualTo(kMinGraphicalContrast));
    });

    test('error is separated from the CTA by warmth, not lightness', () {
      // Airbnb's own answer, and it works here only because nothing structural
      // is red — so a red error competes with the CTA alone, not the whole UI.
      final hue = HSLColor.fromColor(p.error).hue;
      final ctaHue = HSLColor.fromColor(p.cta).hue;
      expect(p.error, const Color(0xFFC13515));
      // CTA sits at 345°, error at 11° — the wrap-around distance is what
      // matters, not the arithmetic difference.
      final delta = ((hue - ctaHue + 540) % 360 - 180).abs();
      expect(delta, greaterThan(20),
          reason: 'error and cta are only ${delta.toStringAsFixed(0)}° apart');
    });
  });

  group('accessibility', () {
    // No exemptions. Both palettes meet these thresholds outright — ocean_teal
    // did not when the theme system was introduced, and the four values that
    // fell short (accent, success, warning, and the brand gradient's light end)
    // were corrected rather than annotated.
    for (final p in AppPalettes.all) {
      test('${p.id}: text tokens are legible on surface and scaffold', () {
        textTokens(p).forEach((name, color) {
          for (final bg
              in {'surface': p.surface, 'scaffold': p.scaffold}.entries) {
            expect(
              contrast(color, bg.value),
              greaterThanOrEqualTo(kMinTextContrast),
              reason: '${p.id}.$name on ${bg.key} is '
                  '${contrast(color, bg.value).toStringAsFixed(2)}:1',
            );
          }
        });
      });

      test('${p.id}: graphical tokens clear the icon threshold', () {
        graphicalTokens(p).forEach((name, color) {
          for (final bg
              in {'surface': p.surface, 'scaffold': p.scaffold}.entries) {
            expect(
              contrast(color, bg.value),
              greaterThanOrEqualTo(kMinGraphicalContrast),
              reason: '${p.id}.$name on ${bg.key} is '
                  '${contrast(color, bg.value).toStringAsFixed(2)}:1',
            );
          }
        });
      });

      test('${p.id}: a primary button label is legible on its fill', () {
        expect(
            contrast(p.onCta, p.cta), greaterThanOrEqualTo(kMinTextContrast));
      });

      test('${p.id}: white text is legible across the whole brand gradient',
          () {
        // Gradients carry white headings, and a two-stop check would miss a
        // pale midpoint — so every declared stop is checked. This also covers
        // the gradient's other job: listing_detail_screen paints text with it as
        // a shader, where the same stops sit against the page instead.
        for (final stop in p.brandGradient.colors) {
          expect(contrast(Colors.white, stop),
              greaterThanOrEqualTo(kMinTextContrast),
              reason: '${p.id}: white on gradient stop $stop');
        }
      });

      test('${p.id}: the three listing types read apart', () {
        // seat/room/fullHouse appear side by side as chips, so they only carry
        // meaning if they are mutually distinguishable.
        final pairs = [
          ['seat', p.seat, 'room', p.room],
          ['room', p.room, 'fullHouse', p.fullHouse],
          ['seat', p.seat, 'fullHouse', p.fullHouse],
        ];
        for (final pair in pairs) {
          expect(pair[1], isNot(pair[3]),
              reason: '${p.id}: ${pair[0]} and ${pair[2]} are the same colour');
        }
      });
    }
  });

  group('accentForIndex', () {
    test('wraps around the cycle', () {
      const p = AppPalettes.indigoCrimson;
      final n = p.accentCycle.length;
      expect(p.accentForIndex(0), p.accentCycle[0]);
      expect(p.accentForIndex(n), p.accentCycle[0]);
      expect(p.accentForIndex(n + 2), p.accentCycle[2]);
      expect(p.accentForIndex(n * 100 + 1), p.accentCycle[1]);
    });

    test('every palette offers a non-empty cycle', () {
      for (final p in AppPalettes.all) {
        expect(p.accentCycle, isNotEmpty, reason: p.id);
      }
    });
  });

  group('AppColors facade', () {
    test('answers from whichever palette is active', () {
      AppColors.usePalette(AppPalettes.oceanTeal);
      expect(AppColors.brand, AppPalettes.oceanTeal.brand);
      expect(AppColors.palette, AppPalettes.oceanTeal);

      AppColors.usePalette(AppPalettes.indigoCrimson);
      expect(AppColors.brand, AppPalettes.indigoCrimson.brand);
      expect(AppColors.cta, AppPalettes.indigoCrimson.cta);
      expect(AppColors.brandGradient.colors,
          AppPalettes.indigoCrimson.brandGradient.colors);
      expect(AppColors.accentForIndex(1),
          AppPalettes.indigoCrimson.accentCycle[1]);
    });
  });

  group('AppTheme.forPalette', () {
    testWidgets('is a pure function of the palette, not of the active one',
        (tester) async {
      AppColors.usePalette(AppPalettes.oceanTeal);
      final theme = AppTheme.forPalette(AppPalettes.indigoCrimson);
      expect(theme.colorScheme.primary, AppPalettes.indigoCrimson.brand);
      expect(theme.scaffoldBackgroundColor, AppPalettes.indigoCrimson.scaffold);
    });

    testWidgets('wires the palette into the scheme it is asked for',
        (tester) async {
      for (final p in AppPalettes.all) {
        final theme = AppTheme.forPalette(p);
        expect(theme.colorScheme.primary, p.brand, reason: p.id);
        expect(theme.colorScheme.secondary, p.accent, reason: p.id);
        expect(theme.colorScheme.error, p.error, reason: p.id);
        expect(theme.scaffoldBackgroundColor, p.scaffold, reason: p.id);
      }
    });

    testWidgets('fills primary buttons from cta, not from the brand',
        (tester) async {
      // The seam that lets a blue-led palette have red buttons. Asserted through
      // the resolved style, because that is what a FilledButton actually reads.
      final theme = AppTheme.forPalette(AppPalettes.indigoCrimson);
      final style = theme.filledButtonTheme.style!;
      const pressed = <WidgetState>{};
      expect(style.backgroundColor?.resolve(pressed),
          AppPalettes.indigoCrimson.cta);
      expect(style.foregroundColor?.resolve(pressed),
          AppPalettes.indigoCrimson.onCta);
    });

    testWidgets('leaves geometry alone across palettes — colours only',
        (tester) async {
      // An admin picking a theme must not be able to change layout.
      final a = AppTheme.forPalette(AppPalettes.oceanTeal);
      final b = AppTheme.forPalette(AppPalettes.indigoCrimson);
      expect(b.navigationBarTheme.height, a.navigationBarTheme.height);
      expect(b.cardTheme.shape, a.cardTheme.shape);
      expect(b.inputDecorationTheme.contentPadding,
          a.inputDecorationTheme.contentPadding);
      expect(
          b.textTheme.titleLarge?.fontSize, a.textTheme.titleLarge?.fontSize);
    });
  });
}
