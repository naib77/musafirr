import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/core/theme/app_colors.dart';
import 'package:musafir/core/theme/app_palette.dart';
import 'package:musafir/core/theme/app_palettes.dart';
import 'package:musafir/core/theme/app_theme.dart';
import 'package:musafir/core/theme/brand.dart';
import 'package:musafir/screens/splash/splash_screen.dart';
import 'package:musafir/widgets/brand_logo.dart';

/// The splash is the last link in a boot chain whose earlier links — the OS
/// launch window, `web/manifest.json`, the `index.html` splash — are static
/// files no test can reach. This screen is the only part of it Dart owns, so
/// the invariant worth pinning is that it does not drift away from them.
void main() {
  setUpAll(() => AppColors.usePalette(AppPalettes.fallback));
  tearDown(() => AppColors.usePalette(AppPalettes.fallback));

  Future<void> pump(WidgetTester tester, AppPalette palette) async {
    AppColors.usePalette(palette);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.forPalette(palette),
      home: const SplashScreen(),
    ));
    await tester.pump();
  }

  testWidgets('paints the brand rose under every palette, not the theme',
      (tester) async {
    // The regression this exists for: the background was colorScheme.primary,
    // so on the default teal palette a rose launch window handed over to a
    // teal screen. Every palette must land on the same colour as the static
    // launch surfaces, which cannot know the palette at all.
    for (final palette in AppPalettes.all) {
      await pump(tester, palette);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, Brand.rose,
          reason: 'splash follows the theme under "${palette.id}"');
    }
  });

  testWidgets('draws the mark in white, sized to match the web boot splash',
      (tester) async {
    await pump(tester, AppPalettes.fallback);

    final logo = tester.widget<BrandLogo>(find.byType(BrandLogo));
    // White, because the mark sits directly on the rose here — the artwork's
    // own rose would be invisible against it.
    expect(logo.color, Colors.white);
    // 0.86 * 98 == 0.60 * 140, the width index.html gives Icon-192. Equal
    // boxes would NOT give equal marks: the two files pad the mark
    // differently, and the handover would visibly jump.
    expect(logo.size, 98);
  });
}
