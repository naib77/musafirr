/// What a hotel says about itself beyond what every stay says (migration 150).
///
/// All three are nullable in the database and optional here, the same
/// contract as `TurfDetails`: a hotel that states nothing is legal, but a
/// non-hotel row that states any of them is refused outright by
/// `listings_hotel_fields_only_on_hotel` (23514) -- which is why
/// `scopeFieldsToType` clears this whenever the type is not hotel.
class HotelDetails {
  const HotelDetails({this.starRating, this.frontDesk24h, this.idRequired});

  /// 1-5, self-declared. Nothing verifies it; the listing page says "3-star"
  /// on the host's word, the way every OTA in the market does.
  final int? starRating;

  /// Someone at reception around the clock -- the answer to "can I arrive at
  /// 2am", which is the question a day-use guest off a night bus asks.
  final bool? frontDesk24h;

  /// NID/passport asked at check-in.
  final bool? idRequired;

  bool get isEmpty =>
      starRating == null && frontDesk24h == null && idRequired == null;

  /// `clear*` because a `null` argument already means "unchanged" -- the same
  /// shape as `TurfDetails.copyWith`, so a host can take an answer back.
  HotelDetails copyWith({
    int? starRating,
    bool? frontDesk24h,
    bool? idRequired,
    bool clearStarRating = false,
    bool clearFrontDesk24h = false,
    bool clearIdRequired = false,
  }) {
    return HotelDetails(
      starRating: clearStarRating ? null : (starRating ?? this.starRating),
      frontDesk24h:
          clearFrontDesk24h ? null : (frontDesk24h ?? this.frontDesk24h),
      idRequired: clearIdRequired ? null : (idRequired ?? this.idRequired),
    );
  }

  /// Star ratings outside 1-5 are read as unstated rather than trusted: the
  /// constraint forbids them, so one arriving means a row older or stranger
  /// than this build, and printing "7-star" would be worse than nothing.
  static HotelDetails fromJson(Map<String, dynamic> json) {
    final stars = (json['hotel_star_rating'] as num?)?.toInt();
    return HotelDetails(
      starRating: stars != null && stars >= 1 && stars <= 5 ? stars : null,
      frontDesk24h: json['hotel_front_desk_24h'] as bool?,
      idRequired: json['hotel_id_required'] as bool?,
    );
  }

  /// Always all three keys, nulls included: a host switching a listing away
  /// from hotel must clear them in the same write or the row is refused.
  Map<String, dynamic> toJson() => {
        'hotel_star_rating': starRating,
        'hotel_front_desk_24h': frontDesk24h,
        'hotel_id_required': idRequired,
      };
}

/// The Room Matrix facts (150) -- size, bathroom, toilet. Unlike
/// [HotelDetails] these describe ANY stay (a room in a flat has a squat or a
/// sitting toilet too), so the database carries no type guard on them and
/// `scopeFieldsToType` clears them only for a turf.
class RoomFacts {
  const RoomFacts({this.sizeSqft, this.bathroom, this.toilet});

  /// Floor area of ONE unit. 1-20000 in the database.
  final int? sizeSqft;
  final BathroomKind? bathroom;
  final ToiletKind? toilet;

  bool get isEmpty => sizeSqft == null && bathroom == null && toilet == null;

  RoomFacts copyWith({
    int? sizeSqft,
    BathroomKind? bathroom,
    ToiletKind? toilet,
    bool clearSizeSqft = false,
    bool clearBathroom = false,
    bool clearToilet = false,
  }) {
    return RoomFacts(
      sizeSqft: clearSizeSqft ? null : (sizeSqft ?? this.sizeSqft),
      bathroom: clearBathroom ? null : (bathroom ?? this.bathroom),
      toilet: clearToilet ? null : (toilet ?? this.toilet),
    );
  }

  static RoomFacts fromJson(Map<String, dynamic> json) {
    final size = (json['size_sqft'] as num?)?.toInt();
    return RoomFacts(
      sizeSqft: size != null && size >= 1 && size <= maxSizeSqft ? size : null,
      bathroom: _byName(BathroomKind.values, json['bathroom_kind']),
      toilet: _byName(ToiletKind.values, json['toilet_kind']),
    );
  }

  Map<String, dynamic> toJson() => {
        'size_sqft': sizeSqft,
        'bathroom_kind': bathroom?.name,
        'toilet_kind': toilet?.name,
      };

  /// `listings_size_sqft_valid`'s upper bound.
  static const int maxSizeSqft = 20000;

  /// Parses the host's size field. Blank is "not stated"; anything that is
  /// not a whole number in range is null too, and [sizeError] is what tells
  /// the host so -- the save must never send a value the constraint refuses.
  static int? parseSize(String text) {
    final n = int.tryParse(text.trim());
    return n != null && n >= 1 && n <= maxSizeSqft ? n : null;
  }

  static String? sizeError(String text) {
    final t = text.trim();
    if (t.isEmpty || parseSize(t) != null) return null;
    return 'Enter the size as a whole number of square feet, 1 to '
        '$maxSizeSqft.';
  }
}

enum BathroomKind { attached, common }

extension BathroomKindX on BathroomKind {
  String get label => switch (this) {
        BathroomKind.attached => 'Attached',
        BathroomKind.common => 'Shared',
      };
}

/// `indian` is the wire value because it is what Bangladeshi listings call a
/// squat toilet; the label says what it is for anyone who does not know that.
enum ToiletKind { commode, indian }

extension ToiletKindX on ToiletKind {
  String get label => switch (this) {
        ToiletKind.commode => 'Commode',
        ToiletKind.indian => 'Squat (Indian)',
      };
}

/// Unknown wire values read as unstated, never as a throw -- a build older
/// than a future constraint change must keep rendering the listing.
T? _byName<T extends Enum>(List<T> values, Object? wire) {
  if (wire is! String) return null;
  for (final v in values) {
    if (v.name == wire) return v;
  }
  return null;
}
