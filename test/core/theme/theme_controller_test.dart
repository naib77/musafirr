import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:musafir/core/theme/app_colors.dart';
import 'package:musafir/core/theme/app_palette.dart';
import 'package:musafir/core/theme/app_theme.dart';
import 'package:musafir/core/theme/app_palettes.dart';
import 'package:musafir/core/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The theme is admin-chosen and arrives over the network, so the interesting
/// behaviour is all in the cache: what the app paints before the answer lands,
/// and what happens when the cached answer no longer makes sense.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  final controller = ThemeController.instance;

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(controller.resetForTest);

  Future<String?> cached() async => (await SharedPreferences.getInstance())
      .getString(ThemeController.prefsKey);

  group('hydrate', () {
    test('paints the fallback when nothing is cached', () async {
      await controller.hydrate();
      expect(controller.value, AppPalettes.fallback);
    });

    test('paints the theme cached by the previous launch', () async {
      SharedPreferences.setMockInitialValues(
        {ThemeController.prefsKey: 'indigo_crimson'},
      );

      await controller.hydrate();

      expect(controller.value, AppPalettes.indigoCrimson);
      // The whole point: the token getters screens read must be current too,
      // not just the ThemeData.
      expect(AppColors.brand, AppPalettes.indigoCrimson.brand);
    });

    test('discards a cached theme this build does not have', () async {
      // A downgraded device, or a renamed id. Keeping the value would mean
      // re-reading and re-rejecting it on every launch forever.
      SharedPreferences.setMockInitialValues(
        {ThemeController.prefsKey: 'midnight_gold'},
      );

      await controller.hydrate();

      expect(controller.value, AppPalettes.fallback);
      expect(await cached(), isNull);
    });
  });

  group('adopt', () {
    test('applies the admin choice and caches it for the next launch',
        () async {
      await controller.adopt('indigo_crimson');

      expect(controller.value, AppPalettes.indigoCrimson);
      expect(AppColors.brand, AppPalettes.indigoCrimson.brand);
      expect(await cached(), 'indigo_crimson');
    });

    test('an unset setting is the default theme, not a no-op', () async {
      await controller.adopt('indigo_crimson');
      await controller.adopt(null);

      expect(controller.value, AppPalettes.fallback);
      // Cached too, so removing the setting takes effect on the very next
      // launch rather than leaving the old theme painted at boot forever.
      expect(await cached(), AppPalettes.fallback.id);
    });

    test('an unknown theme falls back rather than throwing', () async {
      await controller.adopt('midnight_gold');

      expect(controller.value, AppPalettes.fallback);
      expect(await cached(), AppPalettes.fallback.id);
    });

    test('accepts the casing and padding a hand-edited row may carry',
        () async {
      await controller.adopt('  Indigo_Crimson  ');
      expect(controller.value, AppPalettes.indigoCrimson);
      // Cached in canonical form, so the next hydrate does no normalising.
      expect(await cached(), 'indigo_crimson');
    });

    test('notifies listeners so MaterialApp rebuilds', () async {
      final seen = <String>[];
      void listener() => seen.add(controller.value.id);
      controller.addListener(listener);
      addTearDown(() => controller.removeListener(listener));

      await controller.adopt('indigo_crimson');
      // ValueNotifier suppresses a set to an identical value, and that is
      // wanted here: confirming the theme already in force must not rebuild the
      // entire app for nothing.
      await controller.adopt('indigo_crimson');

      expect(seen, ['indigo_crimson']);
    });
  });

  group('a live swap', () {
    testWidgets('repaints ThemeData and AppColors together', (tester) async {
      // Two ways a swap can render an inconsistent frame, both guarded here:
      // ThemeController sets AppColors before notifying, so a rebuild never
      // renders new ThemeData against stale token values; and MaterialApp's
      // theme crossfade is disabled, so it never renders a half-lerped theme
      // beside already-swapped tokens. Screens read both — most reach for AppColors.brand
      // directly, some for Theme.of(context) — and a frame where the two
      // disagree is a frame with two different brand colours on it.
      //
      // This mirrors app.dart's wiring: ValueListenableBuilder over the
      // controller, MaterialApp rebuilt from AppTheme.forPalette. MusafirApp
      // itself cannot boot in a test (it builds Supabase singletons in
      // initState — see widget_test.dart), so the wiring is reproduced rather
      // than driven.
      final observed = <List<Color>>[];

      await tester.pumpWidget(
        ValueListenableBuilder<AppPalette>(
          valueListenable: controller,
          builder: (context, palette, _) => MaterialApp(
            theme: AppTheme.forPalette(palette),
            // The line under test as much as the ordering is: without it
            // MaterialApp lerps to the new theme over 200ms, and the frames
            // during that lerp show Theme.of(context) part-way to the new brand
            // colour while AppColors has already snapped to it. This assertion
            // fails if app.dart ever loses it.
            themeAnimationDuration: Duration.zero,
            home: Builder(
              builder: (context) {
                observed.add([
                  Theme.of(context).colorScheme.primary,
                  AppColors.brand,
                ]);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      await controller.adopt('indigo_crimson');
      await tester.pump();

      expect(observed, isNotEmpty);
      for (final frame in observed) {
        expect(frame[0], frame[1],
            reason: 'a frame rendered ThemeData and AppColors out of step');
      }
      // And the swap actually took effect, rather than every frame agreeing on
      // the old palette.
      expect(observed.last.first, AppPalettes.indigoCrimson.brand);
    });
  });
}
