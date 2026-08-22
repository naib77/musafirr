import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/listing_purpose.dart';
import '../../models/listing_type.dart';
import '../../models/voice_query.dart';

/// The tail of voice parsing, handled by Gemini behind the `voice-parse` edge
/// function.
///
/// This exists because a lexicon only knows the words someone typed into it.
/// [VoiceQueryParser] stays the fast path — instant, offline, free, and right
/// for almost everything people say — and this is called ONLY when it comes up
/// empty, or when the place it found does not geocode. So the common query
/// never pays the latency and never costs anything.
///
/// Three properties matter more than accuracy here:
///
/// * **It cannot break a search.** Every failure — offline, timeout, 500, junk
///   JSON — returns null, and the caller carries on with the lexicon's answer.
/// * **It is bounded in time.** A voice interaction cannot wait on a model
///   that is having a bad day, so the call is abandoned at [timeout] and the
///   user gets the lexicon result instead of a spinner.
/// * **It never locates anything.** The model returns a place *string*, which
///   still goes through the same geocoder a typed search uses. A model that
///   emitted coordinates would be a model that could confidently send someone
///   to the wrong city.
class RemoteVoiceParser {
  const RemoteVoiceParser({
    this.timeout = const Duration(seconds: 4),
    Future<Map<String, dynamic>?> Function(String transcript)? invoke,
  }) : _invoke = invoke;

  /// How long a spoken search will wait on the model before giving up on it.
  /// Four seconds is already at the edge of what feels broken; past that the
  /// lexicon's answer, even if poorer, is the better product.
  final Duration timeout;

  /// Injected so tests can exercise every failure path without a network.
  final Future<Map<String, dynamic>?> Function(String transcript)? _invoke;

  Future<VoiceQuery?> parse(String transcript) async {
    final text = transcript.trim();
    if (text.isEmpty) return null;

    try {
      final body = await (_invoke ?? _callFunction)(text).timeout(timeout);
      if (body == null || body['parsed'] != true) return null;

      final query = _toQuery(text, body);
      // A "parsed" response that filled nothing is a miss, not a result.
      return query.isEmpty ? null : query;
    } catch (e) {
      // Deliberately swallowed, including TimeoutException: the lexicon has
      // already produced something, and a search the user is watching must not
      // fail because a fallback did.
      debugPrint('[RemoteVoiceParser] skipped: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _callFunction(String transcript) async {
    final res = await Supabase.instance.client.functions.invoke(
      'voice-parse',
      body: {'transcript': transcript},
    );
    final data = res.data;
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  VoiceQuery _toQuery(String transcript, Map<String, dynamic> body) {
    final place = (body['place'] as String?)?.trim();

    final types = <ListingType>[];
    for (final raw in (body['types'] as List? ?? const [])) {
      final match = ListingType.values.where((t) => t.name == raw);
      if (match.isNotEmpty && !types.contains(match.first)) {
        types.add(match.first);
      }
    }

    ListingPurpose? purpose;
    final rawPurpose = body['purpose'] as String?;
    if (rawPurpose != null) {
      final match =
          ListingPurpose.values.where((p) => p.wireName == rawPurpose);
      if (match.isNotEmpty) purpose = match.first;
    }

    return VoiceQuery(
      transcript: transcript,
      placeText: place == null || place.isEmpty ? null : place,
      // The spoken form is kept as the retry, exactly as with the lexicon: the
      // model's spelling is a guess too, and the geocoder gets a second look.
      rawPlaceText: place == null || place == transcript ? null : transcript,
      types: types,
      guestCount: (body['guests'] as num?)?.toInt(),
      maxPrice: (body['max_price'] as num?)?.toDouble(),
      purpose: purpose,
      fromModel: true,
    );
  }
}
