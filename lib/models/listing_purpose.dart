import 'package:flutter/material.dart';

/// What a listing is good for — a dimension separate from [ListingType] (which
/// is the unit: seat/room/full house). A listing can serve several purposes.
///
/// Stored in `listings.purpose_tags text[]` using [wireName]. The guest-facing
/// "stay near a hospital / exam center" search uses [landmarkType] to suggest
/// the relevant landmarks for a chosen purpose.
enum ListingPurpose { general, medical, exam, tourism, business, student }

extension ListingPurposeX on ListingPurpose {
  /// DB/wire value (matches the enum name and the seeded landmark logic).
  String get wireName => name;

  String get label => switch (this) {
        ListingPurpose.general => 'General',
        ListingPurpose.medical => 'Medical',
        ListingPurpose.exam => 'Exam',
        ListingPurpose.tourism => 'Tourism',
        ListingPurpose.business => 'Business',
        ListingPurpose.student => 'Student',
      };

  /// Short guest-facing hint used on purpose chips/cards.
  String get tagline => switch (this) {
        ListingPurpose.general => 'Any stay',
        ListingPurpose.medical => 'Near hospitals',
        ListingPurpose.exam => 'Near exam centers',
        ListingPurpose.tourism => 'Near attractions',
        ListingPurpose.business => 'Near business hubs',
        ListingPurpose.student => 'Near universities',
      };

  IconData get icon => switch (this) {
        ListingPurpose.general => Icons.home_rounded,
        ListingPurpose.medical => Icons.local_hospital_rounded,
        ListingPurpose.exam => Icons.school_rounded,
        ListingPurpose.tourism => Icons.beach_access_rounded,
        ListingPurpose.business => Icons.business_center_rounded,
        ListingPurpose.student => Icons.menu_book_rounded,
      };

  /// The landmark `type` to suggest when a guest picks this purpose, or null
  /// when the purpose has no associated landmark (general → no distance step).
  String? get landmarkType => switch (this) {
        ListingPurpose.general => null,
        ListingPurpose.medical => 'hospital',
        ListingPurpose.exam => 'exam_center',
        ListingPurpose.tourism => 'tourist_spot',
        ListingPurpose.business => 'business_hub',
        ListingPurpose.student => 'university',
      };
}

/// Parses a wire string (from `purpose_tags`) into a [ListingPurpose], or null
/// if it's unknown (forward-compatible with tags added server-side later).
ListingPurpose? listingPurposeFromWire(String? value) {
  if (value == null) return null;
  for (final p in ListingPurpose.values) {
    if (p.wireName == value) return p;
  }
  return null;
}

/// Parses a `purpose_tags` array (dynamic list from JSON) into purposes,
/// dropping any unknown values.
List<ListingPurpose> listingPurposesFromWire(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .map((e) => listingPurposeFromWire(e as String?))
      .whereType<ListingPurpose>()
      .toList();
}
