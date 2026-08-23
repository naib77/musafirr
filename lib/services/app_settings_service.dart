import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/payout_method.dart';
import '../models/search_area_settings.dart';

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
      for (final row in (rows as List)) {
        final key = row['key'] as String?;
        final value = row['value']?.toString().toLowerCase().trim();
        switch (key) {
          case 'require_listing_address_proof':
            _requireListingAddressProof = value == 'true';
            break;
          case 'cash_payment_enabled':
            _cashPaymentEnabled = value == 'true';
            break;
          case 'search_radius_tiers_m':
            radiusTiers = value;
            break;
          case 'search_landmark_radius_m':
            landmarkRadius = value;
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
}
