/// How large an area a proximity search covers, configured by an admin.
///
/// These numbers used to be compiled into the app: the expanding tiers
/// `[1000, 3000, 5000, 10000]` in the repository and a 15 km landmark ring in
/// the Explore search sheet. They are now rows in `app_settings`, so tuning the
/// search area is a text edit in the admin portal rather than a release.
///
/// That moves the values from something a compiler checked to something a human
/// types, so parsing here is deliberately forgiving: a malformed setting must
/// degrade to a working search, never to zero rings (which would make Explore
/// return nothing at all for every "near me" query). Junk entries are dropped,
/// out-of-band values are clamped rather than discarded, and an input with
/// nothing usable in it falls back to [defaults].
class SearchAreaSettings {
  const SearchAreaSettings({
    required this.radiusTiersMeters,
    required this.landmarkRadiusMeters,
  });

  /// Expanding rings for a bare-point search ("near me", or a place that
  /// geocoded without an extent). The server takes the SMALLEST tier that
  /// contains a match, so this list must be ascending.
  final List<int> radiusTiersMeters;

  /// The single fixed ring drawn around a purpose landmark (hospital, exam
  /// centre). Not expanding — a landmark search is "everything around here".
  final int landmarkRadiusMeters;

  /// Below this a ring is too small to contain anything on a city street grid;
  /// above it the "area" stops being an area. Values outside the band are
  /// clamped into it, so a fat-fingered zero still yields a usable search.
  static const int minRadiusMeters = 100;
  static const int maxRadiusMeters = 200000;

  /// Each tier is a separate distance test server-side, and a guest cannot
  /// meaningfully tell six rings apart. Beyond this the extra tiers cost query
  /// time and buy nothing.
  static const int maxTiers = 6;

  /// What the app shipped with, and what every unusable setting falls back to.
  static const SearchAreaSettings defaults = SearchAreaSettings(
    radiusTiersMeters: [1000, 3000, 5000, 10000],
    landmarkRadiusMeters: 15000,
  );

  /// Builds settings from the raw `app_settings` text values. Either argument
  /// may be null (key absent) or malformed; both cases yield [defaults] for
  /// that field alone — one bad value never takes the other down with it.
  static SearchAreaSettings fromRaw({String? tiers, String? landmarkRadius}) {
    return SearchAreaSettings(
      radiusTiersMeters: _parseTiers(tiers),
      landmarkRadiusMeters:
          _parseRadius(landmarkRadius) ?? defaults.landmarkRadiusMeters,
    );
  }

  static List<int> _parseTiers(String? raw) {
    if (raw == null) return defaults.radiusTiersMeters;

    final parsed = <int>{};
    for (final part in raw.split(',')) {
      final metres = _parseRadius(part);
      if (metres != null) parsed.add(metres);
    }
    if (parsed.isEmpty) return defaults.radiusTiersMeters;

    final tiers = parsed.toList()..sort();
    if (tiers.length <= maxTiers) return tiers;

    // Over the cap: keep the narrowest rings and ALWAYS the widest. Trimming
    // from the end instead would shrink the searchable area, the opposite of
    // what an admin who typed many tiers was asking for.
    return [...tiers.take(maxTiers - 1), tiers.last];
  }

  /// A single radius in metres, or null when the text holds no usable number.
  /// Never throws: this runs over admin-typed text during startup settings
  /// load, where an exception would abandon the whole load and silently reset
  /// every other setting to its default too.
  static int? _parseRadius(String? raw) {
    if (raw == null) return null;
    final metres = int.tryParse(raw.trim());
    if (metres == null || metres <= 0) return null;
    return metres.clamp(minRadiusMeters, maxRadiusMeters);
  }
}
