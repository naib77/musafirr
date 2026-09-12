import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'booking/booking_accept_window.dart';
import '../models/payout_method.dart';
import '../models/search_area_settings.dart';
import '../models/support_links.dart';
import 'update/app_update_decision.dart';

/// Reads admin-configurable, app-wide flags from the Supabase `app_settings`
/// table (key/value). Loaded once at startup and cached.
///
/// Fails **open**: if the table can't be read (offline, not migrated yet), the
/// flags fall back to their safe defaults so a config hiccup never locks users
/// out of core flows.
class AppSettingsService {
  AppSettingsService._();
  static final AppSettingsService instance = AppSettingsService._();

  SupabaseClient get _client => Supabase.instance.client;

  bool _loaded = false;

  // Default false: don't gate listing creation unless the setting is present
  // and explicitly enabled.
  bool _requireListingAddressProof = false;

  // Default false: only offer "hand cash" at the pay step if the admin has
  // explicitly enabled it (and the row is missing/unreadable → hide it, the
  // safe default for a payment option).
  bool _cashPaymentEnabled = false;

  // How wide a proximity search reaches. Defaults are the values the app used
  // to hardcode, so an unreadable/unmigrated settings table searches exactly
  // as before.
  SearchAreaSettings _searchArea = SearchAreaSettings.defaults;

  // Which palette the app wears. A theme id rather than an AppPalette so this
  // service stays free of any dependency on the theme layer — it reads settings,
  // it does not decide what colours mean. ThemeController resolves the id.
  // Null means "not configured", which the resolver reads as the default theme.
  String? _activeThemeId;

  // Where Profile → Support sends people. Defaults to the compiled-in URLs, so
  // an unreadable or unmigrated settings table still opens a working link
  // instead of a dead menu item.
  SupportLinks _supportLinks = SupportLinks.defaults;

  // How long a host has to answer a booking request. The scheduled job
  // expire_stale_bookings() is what actually enforces it; this copy only feeds
  // the countdown the guest watches, so an unreadable table showing the old
  // 24-hour default is a cosmetic drift, never a wrong cancellation.
  Duration _bookingAcceptWindow = kDefaultBookingAcceptWindow;

  // The oldest Android build still allowed to talk to this database. Zero —
  // the default, and what an unreadable table means — forces nobody. Unlike
  // every other flag here, the fail-open direction is not merely convenient:
  // this is the only setting that can take the app away from a user, so a
  // config hiccup has to mean "don't".
  int _androidMinVersionCode = kNoForcedUpdate;

  // Which payout channels a user may add. Defaults to all of them: unlike a
  // payment option, an unreadable settings table here must not silently stop
  // hosts registering somewhere to be paid — and nothing is at risk, because
  // add_payout_method() re-checks the real list server-side and refuses a
  // channel that is genuinely disabled.
  List<PayoutChannel> _payoutChannels = PayoutChannel.values;

  /// Whether a host must upload a proof-of-address document before adding a
  /// listing.
  bool get requireListingAddressProof => _requireListingAddressProof;

  /// Whether guests may choose to pay in "hand cash" (paid directly to the
  /// host) instead of online. Toggled by an admin in the admin portal.
  bool get cashPaymentEnabled => _cashPaymentEnabled;

  /// Radius tiers and the landmark ring for proximity search, configured by an
  /// admin. Prefer [ensureSearchArea] on the search path — [load] is kicked off
  /// unawaited at startup, so a very early search could otherwise read the
  /// defaults instead of the configured values.
  SearchAreaSettings get searchArea => _searchArea;

  /// The `active_theme` slug an admin selected, or null when the row is absent.
  /// Resolved to a palette by `ThemeController` — an id this build does not know
  /// falls back to the default theme rather than failing.
  String? get activeThemeId => _activeThemeId;

  /// The help / terms / privacy destinations an admin configured, each falling
  /// back to its compiled-in default. Prefer [ensureSupportLinks] where the
  /// value is read on a path that could run before [load] has finished.
  SupportLinks get supportLinks => _supportLinks;

  /// How long a host has to accept a booking request before the server
  /// rejects it. Prefer [ensureBookingAcceptWindow] where this is read on a
  /// path that could run before [load] has finished.
  Duration get bookingAcceptWindow => _bookingAcceptWindow;

  /// The oldest Android versionCode still supported. Builds below it are
  /// pushed through Play's blocking updater at launch; [kNoForcedUpdate] (the
  /// default) forces nobody. Only ever consulted on Android — see
  /// `AppUpdateService`, which also checks that Play actually HAS a newer
  /// build before acting on this number.
  int get androidMinVersionCode => _androidMinVersionCode;

  /// Payout channels currently on offer, in the order the enum declares them
  /// rather than the order an admin happened to type — so the add-a-method
  /// screen doesn't reshuffle itself when the setting is edited.
  List<PayoutChannel> get payoutChannels => _payoutChannels;

  /// Fetch settings from Supabase. Safe to call multiple times.
  Future<void> load() async {
    try {
      final rows = await _client.from('app_settings').select('key, value');
      String? radiusTiers;
      String? landmarkRadius;
      String? helpUrl;
      String? termsUrl;
      String? privacyUrl;
      for (final row in (rows as List)) {
        final key = row['key'] as String?;
        // Two readings of the same cell. Every flag and id here is
        // case-insensitive, so `value` is lowercased once for all of them —
        // but a URL is not: paths and mailto addresses are case-sensitive in
        // practice, and lowercasing one silently breaks the link. Those keys
        // read `raw` instead.
        final raw = row['value']?.toString().trim();
        final value = raw?.toLowerCase();
        switch (key) {
          case 'require_listing_address_proof':
            _requireListingAddressProof = value == 'true';
            break;
          case 'cash_payment_enabled':
            _cashPaymentEnabled = value == 'true';
            break;
          case 'active_theme':
            // Stored lowercase-trimmed already by the shared normalisation
            // above, which is exactly the slug form AppPalettes.find expects.
            _activeThemeId = (value == null || value.isEmpty) ? null : value;
            break;
          case 'search_radius_tiers_m':
            radiusTiers = value;
            break;
          case 'search_landmark_radius_m':
            landmarkRadius = value;
            break;
          case 'support_help_url':
            helpUrl = raw;
            break;
          case 'terms_url':
            termsUrl = raw;
            break;
          case 'privacy_url':
            privacyUrl = raw;
            break;
          case 'booking_accept_window_hours':
            // Parsed here rather than stashed for the block below because it
            // stands alone — one cell, one value, no cross-key sanitising.
            _bookingAcceptWindow = bookingAcceptWindowFromRaw(value);
            break;
          case 'android_min_version_code':
            _androidMinVersionCode = minSupportedVersionCodeFromRaw(value);
            break;
          case 'payout_channels_enabled':
            final parsed = (value ?? '')
                .split(',')
                .map((t) => payoutChannelFromWire(t.trim()))
                .whereType<PayoutChannel>()
                .toSet();
            // An empty or entirely unparseable list keeps the default. The
            // admin portal cannot save one (migration 100 validates the key on
            // write), so reaching here means the value predates that guard or
            // names channels this build is too old to know about — in both
            // cases offering everything beats offering nothing.
            if (parsed.isNotEmpty) {
              _payoutChannels = PayoutChannel.values
                  .where(parsed.contains)
                  .toList(growable: false);
            }
            break;
        }
      }
      // Parsed together, and only from keys that were actually present: a null
      // here means "not configured" and keeps that field's default, while a
      // present-but-malformed value is sanitised by SearchAreaSettings.
      _searchArea = SearchAreaSettings.fromRaw(
        tiers: radiusTiers,
        landmarkRadius: landmarkRadius,
      );
      // Same rule: an absent key keeps that link's compiled default, and a
      // present-but-unopenable value is rejected by SupportLinks rather than
      // shipped to launchUrl.
      _supportLinks = SupportLinks.fromRaw(
        help: helpUrl,
        terms: termsUrl,
        privacy: privacyUrl,
      );
      _loaded = true;
    } catch (e) {
      debugPrint('[AppSettingsService] load failed (fail-open): $e');
    }
  }

  /// Returns the flag, loading settings first if they haven't been fetched yet.
  Future<bool> ensureRequireListingAddressProof() async {
    if (!_loaded) await load();
    return _requireListingAddressProof;
  }

  /// Returns the offered payout channels, loading settings first if needed.
  Future<List<PayoutChannel>> ensurePayoutChannels() async {
    if (!_loaded) await load();
    return _payoutChannels;
  }

  /// Returns the search-area config, loading settings first if needed.
  Future<SearchAreaSettings> ensureSearchArea() async {
    if (!_loaded) await load();
    return _searchArea;
  }

  /// Returns the support/legal destinations, loading settings first if needed.
  Future<SupportLinks> ensureSupportLinks() async {
    if (!_loaded) await load();
    return _supportLinks;
  }

  /// Returns the host-response window, loading settings first if needed.
  Future<Duration> ensureBookingAcceptWindow() async {
    if (!_loaded) await load();
    return _bookingAcceptWindow;
  }

  /// Returns the forced-update floor, loading settings first if needed. The
  /// update check runs in `initState`, well before the background [load] can
  /// have finished, so this one is always read through `ensure`.
  Future<int> ensureAndroidMinVersionCode() async {
    if (!_loaded) await load();
    return _androidMinVersionCode;
  }
}
