import '../models/listing_purpose.dart';
import '../models/listing_type.dart';

/// A spoken search sentence after slot extraction — "ধানমন্ডির দিকে বাসা
/// খোঁজো" becomes place `Dhanmondi` + type `fullHouse`.
///
/// Deliberately NOT a [SearchFilters]: a voice query carries no coordinates.
/// Resolving [placeText] to a point or a box is the geocoder's job, and
/// letting the parser guess at coordinates would be inventing data.
class VoiceQuery {
  const VoiceQuery({
    required this.transcript,
    this.placeText,
    this.rawPlaceText,
    this.types = const [],
    this.guestCount,
    this.maxPrice,
    this.purpose,
    this.fromModel = false,
  });

  /// Exactly what the recogniser heard, kept for the "we heard …" line and
  /// for the miss log that grows the lexicon.
  final String transcript;

  /// The place to search, canonicalised to its common English spelling when
  /// the alias table knows it (ধানমন্ডি → `Dhanmondi`). Google resolves
  /// English Bangladeshi place names far more reliably than Bengali script,
  /// so translating here rather than at the geocoder is the cheaper fix.
  final String? placeText;

  /// The same leftover before aliasing and suffix-stripping. Case-suffix
  /// stripping is a heuristic; when it guesses wrong the caller can retry
  /// with this. Null when it would duplicate [placeText].
  final String? rawPlaceText;

  final List<ListingType> types;
  final int? guestCount;

  /// True when these slots came from the Gemini fallback rather than the
  /// lexicon. Read by [VoiceSearchRunner]: if the model already had a go at
  /// this sentence and its place still would not geocode, asking it the same
  /// question a second time buys nothing and costs a second call.
  final bool fromModel;

  /// A spoken ceiling — "৫ হাজার টাকার মধ্যে" → 5000.
  final double? maxPrice;

  final ListingPurpose? purpose;

  /// True when nothing at all could be pulled out of the sentence. The caller
  /// should say so rather than run an empty search that returns the whole
  /// catalogue and looks like the feature silently failed.
  bool get isEmpty =>
      (placeText == null || placeText!.isEmpty) &&
      types.isEmpty &&
      guestCount == null &&
      maxPrice == null &&
      purpose == null;

  bool get isNotEmpty => !isEmpty;

  /// Short human-readable summary of what was understood, one chip per slot.
  /// Shown before the search runs — a wrong silent search is far worse than
  /// one extra tap, and the chips teach which phrasings work.
  List<String> get chips => [
        if (placeText != null && placeText!.isNotEmpty) placeText!,
        for (final t in types) t.title,
        if (purpose != null) purpose!.label,
        if (guestCount != null) '$guestCount guests',
        if (maxPrice != null) '≤ ৳${maxPrice!.round()}',
      ];

  @override
  String toString() => 'VoiceQuery(place: $placeText, types: $types, '
      'guests: $guestCount, maxPrice: $maxPrice, purpose: $purpose)';
}
