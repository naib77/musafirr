import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';
import 'app_palette.dart';
import 'app_palettes.dart';

/// Holds the palette the app is currently wearing, and the two ways it changes:
/// [hydrate] before the first frame, and [adopt] once `app_settings` has been
/// read.
///
/// ## Why there is a local cache at all
///
/// The admin's choice lives in Supabase, and `AppSettingsService.load()` is
/// deliberately not awaited during boot — nothing about starting the app should
/// wait on the network. So the theme genuinely is not known when the first frame
/// paints. Without a cache every launch would flash the fallback teal and then
/// snap to the configured theme, which looks like a bug even though it is only
/// latency.
///
/// So the resolved id is mirrored into `SharedPreferences` (localStorage on
/// web). Boot reads that — one local read, no network — and paints the theme the
/// admin had chosen as of last launch; the background settings load then
/// confirms or corrects it. The flash is therefore limited to a device's very
/// first launch, and to the one launch after an admin changes the theme.
///
/// ## Why users cannot change this
///
/// There is no setter taking user input, and nothing in the guest or host UI
/// calls [adopt]. The cache key holds a value the *server* chose; a user editing
/// their own localStorage could pin themselves to another compiled-in palette
/// until the next settings load overwrites it, which is a cosmetic change to
/// their own device and not worth defending against.
class ThemeController extends ValueNotifier<AppPalette> {
  ThemeController._() : super(AppPalettes.fallback);

  static final ThemeController instance = ThemeController._();

  /// Where the last known theme id is cached. Not user-scoped, unlike app mode:
  /// the theme is a property of the deployment, not of whoever is logged in, so
  /// it should survive a logout and apply to the login screen too.
  @visibleForTesting
  static const String prefsKey = 'active_theme_id';

  /// How long boot will wait on the local read. `SharedPreferences` is a
  /// platform channel on mobile, and the one thing that must not happen here is
  /// a wedged channel holding the splash screen: on timeout the app simply
  /// starts on the fallback palette and the background load corrects it.
  static const Duration _hydrateTimeout = Duration(seconds: 2);

  /// Paint the theme cached from the previous launch. Call once, before
  /// `runApp`.
  Future<void> hydrate() async {
    try {
      final prefs =
          await SharedPreferences.getInstance().timeout(_hydrateTimeout);
      final cached = prefs.getString(prefsKey);
      if (cached == null) return;

      final palette = AppPalettes.find(cached);
      if (palette == null) {
        // The cache names a palette this build does not have — an admin picked a
        // theme, then the device was downgraded, or the id was renamed (which
        // AppPalettes forbids for exactly this reason). Drop it rather than
        // re-reading it every launch.
        debugPrint('[ThemeController] cached theme "$cached" is unknown here; '
            'using ${AppPalettes.fallback.id}');
        await prefs.remove(prefsKey);
        return;
      }
      _apply(palette);
    } catch (e) {
      // Fail open on the fallback palette: a theme is not worth a failed boot.
      debugPrint('[ThemeController] hydrate failed (fail-open): $e');
    }
  }

  /// Adopt the theme named by the `active_theme` setting. Safe to call with a
  /// null or unrecognised id — both land on [AppPalettes.fallback].
  Future<void> adopt(String? themeId) async {
    if (themeId != null && AppPalettes.find(themeId) == null) {
      // Worth a log: the database and this bundle disagree about what themes
      // exist, which on web usually means a stale committed `build/web`.
      debugPrint('[ThemeController] app_settings names unknown theme '
          '"$themeId"; using ${AppPalettes.fallback.id}');
    }
    final palette = AppPalettes.resolve(themeId);
    _apply(palette);
    await _cache(palette.id);
  }

  /// Order matters: [AppColors] is read directly by screens that never touch
  /// `Theme.of(context)`, so it has to be current *before* listeners rebuild —
  /// otherwise a frame renders the new ThemeData against the old token values.
  void _apply(AppPalette palette) {
    AppColors.usePalette(palette);
    value = palette;
  }

  Future<void> _cache(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, id);
    } catch (e) {
      // A failed write costs one themed first frame next launch, nothing more.
      debugPrint('[ThemeController] could not cache theme: $e');
    }
  }

  /// Puts the controller and [AppColors] back to the fallback palette, so one
  /// test's theme does not leak into the next.
  @visibleForTesting
  void resetForTest() => _apply(AppPalettes.fallback);
}
