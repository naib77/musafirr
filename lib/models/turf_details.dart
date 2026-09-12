import 'package:flutter/material.dart' show IconData, Icons;

/// What a turf listing describes beyond the fields every listing has
/// (migration 121).
///
/// Three nullable strings, and the vocabularies are fixed by check constraints
/// in the database rather than only here — `listings` is written through
/// PostgREST by the owner, so the host form is not the only writer and "the
/// picker only offers five sports" is not enforcement. These enums are the
/// display and input side of that same vocabulary; the wire values must match
/// the constraint exactly or the insert is refused with 23514.
///
/// Every field is null for every non-turf listing, and 121 enforces that too:
/// a room carrying a `turf_sport` would render as a football pitch.
class TurfDetails {
  const TurfDetails({this.sport, this.format, this.surface});

  final TurfSport? sport;
  final TurfFormat? format;
  final TurfSurface? surface;

  bool get isEmpty => sport == null && format == null && surface == null;

  /// `clear*` flags rather than "null means unchanged", for the same reason
  /// [PartyLimits] needs them: null is a *meaning* here — the host taking a
  /// statement back off — and a host must be able to do that.
  TurfDetails copyWith({
    TurfSport? sport,
    TurfFormat? format,
    TurfSurface? surface,
    bool clearSport = false,
    bool clearFormat = false,
    bool clearSurface = false,
  }) {
    return TurfDetails(
      sport: clearSport ? null : (sport ?? this.sport),
      format: clearFormat ? null : (format ?? this.format),
      surface: clearSurface ? null : (surface ?? this.surface),
    );
  }
}

/// Wire values are the enum `name` and must match
/// `listings_turf_sport_valid` (121).
enum TurfSport { football, cricket, badminton, basketball, volleyball, multi }

extension TurfSportX on TurfSport {
  String get label => switch (this) {
        TurfSport.football => 'Football',
        TurfSport.cricket => 'Cricket',
        TurfSport.badminton => 'Badminton',
        TurfSport.basketball => 'Basketball',
        TurfSport.volleyball => 'Volleyball',
        TurfSport.multi => 'Multi-sport',
      };

  IconData get icon => switch (this) {
        TurfSport.football => Icons.sports_soccer,
        TurfSport.cricket => Icons.sports_cricket,
        TurfSport.badminton => Icons.sports_tennis,
        TurfSport.basketball => Icons.sports_basketball,
        TurfSport.volleyball => Icons.sports_volleyball,
        TurfSport.multi => Icons.sports,
      };
}

/// Side size. The wire value carries the hyphens because the check constraint
/// in 121 spells them that way ('5-a-side'), so these cannot use `name`.
enum TurfFormat { five, six, seven, nine, eleven, other }

extension TurfFormatX on TurfFormat {
  String get wireName => switch (this) {
        TurfFormat.five => '5-a-side',
        TurfFormat.six => '6-a-side',
        TurfFormat.seven => '7-a-side',
        TurfFormat.nine => '9-a-side',
        TurfFormat.eleven => '11-a-side',
        TurfFormat.other => 'other',
      };

  String get label => switch (this) {
        TurfFormat.other => 'Other',
        _ => wireName,
      };
}

/// Wire values are the enum `name` and must match
/// `listings_turf_surface_valid` (121).
enum TurfSurface { artificial, natural, concrete, wooden, clay }

extension TurfSurfaceX on TurfSurface {
  String get label => switch (this) {
        TurfSurface.artificial => 'Artificial grass',
        TurfSurface.natural => 'Natural grass',
        TurfSurface.concrete => 'Concrete',
        TurfSurface.wooden => 'Wooden',
        TurfSurface.clay => 'Clay',
      };
}

/// Parses a wire value back to its enum, tolerating an unknown string by
/// answering null — a database that has grown a sixth sport must not crash a
/// build that predates it, the same fail-soft rule `_listingTypeFromString`
/// follows.
TurfSport? turfSportFromWire(String? v) {
  if (v == null) return null;
  for (final s in TurfSport.values) {
    if (s.name == v) return s;
  }
  return null;
}

TurfFormat? turfFormatFromWire(String? v) {
  if (v == null) return null;
  for (final f in TurfFormat.values) {
    if (f.wireName == v) return f;
  }
  return null;
}

TurfSurface? turfSurfaceFromWire(String? v) {
  if (v == null) return null;
  for (final s in TurfSurface.values) {
    if (s.name == v) return s;
  }
  return null;
}
