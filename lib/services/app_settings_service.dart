import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  /// Whether a host must upload a proof-of-address document before adding a
  /// listing.
  bool get requireListingAddressProof => _requireListingAddressProof;

  /// Fetch settings from Supabase. Safe to call multiple times.
  Future<void> load() async {
    try {
      final rows = await _client.from('app_settings').select('key, value');
      for (final row in (rows as List)) {
        final key = row['key'] as String?;
        final value = row['value']?.toString().toLowerCase().trim();
        switch (key) {
          case 'require_listing_address_proof':
            _requireListingAddressProof = value == 'true';
            break;
        }
      }
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
}
