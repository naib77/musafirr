import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/listing_purpose.dart';
import 'package:musafir/models/listing_type.dart';
import 'package:musafir/services/voice/remote_voice_parser.dart';

/// A stand-in for the `voice-parse` edge function. Nothing here touches a
/// network — the tests drive the responses, including the ugly ones.
RemoteVoiceParser _parserReturning(
  Map<String, dynamic>? body, {
  Duration delay = Duration.zero,
  Object? throws,
  Duration timeout = const Duration(seconds: 4),
}) {
  return RemoteVoiceParser(
    timeout: timeout,
    invoke: (_) async {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (throws != null) throw throws;
      return body;
    },
  );
}

void main() {
  group('what the model gives back', () {
    test('fills the slots the lexicon could not', () async {
      final q = await _parserReturning({
        'parsed': true,
        'place': 'Dhanmondi 32',
        'types': ['fullHouse'],
        'guests': 3,
        'max_price': 8000,
        'purpose': 'medical',
      }).parse('dhanmondi bottris e basa lagbe');

      expect(q, isNotNull);
      expect(q!.placeText, 'Dhanmondi 32');
      expect(q.types, [ListingType.fullHouse]);
      expect(q.guestCount, 3);
      expect(q.maxPrice, 8000);
      expect(q.purpose, ListingPurpose.medical);
    });

    test('keeps the spoken form so the geocoder gets a second look', () async {
      const spoken = 'dhanmondi bottris';
      final q = await _parserReturning({
        'parsed': true,
        'place': 'Dhanmondi 32',
        'types': <String>[],
      }).parse(spoken);

      expect(q!.transcript, spoken);
      expect(q.rawPlaceText, spoken,
          reason: "the model's spelling is a guess too");
    });

    test('drops values outside the app enums instead of passing them on',
        () async {
      // A hallucinated type or purpose must never reach SearchFilters.
      final q = await _parserReturning({
        'parsed': true,
        'place': 'Uttara',
        'types': ['penthouse', 'room'],
        'purpose': 'honeymoon',
      }).parse('uttara');

      expect(q!.types, [ListingType.room]);
      expect(q.purpose, isNull);
    });
  });

  group('failures must never reach the user', () {
    test('a declared miss is a miss', () async {
      expect(await _parserReturning({'parsed': false}).parse('mmm'), isNull);
    });

    test('a "parsed" response that filled nothing is also a miss', () async {
      final q = await _parserReturning({
        'parsed': true,
        'place': null,
        'types': <String>[],
      }).parse('mmm');
      expect(q, isNull,
          reason: 'an empty query would search the whole catalogue');
    });

    test('a network error returns null rather than throwing', () async {
      final p = _parserReturning(null, throws: Exception('offline'));
      expect(await p.parse('dhanmondi'), isNull);
    });

    test('malformed JSON returns null rather than throwing', () async {
      final p = RemoteVoiceParser(
          invoke: (_) async => {'parsed': true, 'types': 'not-a-list'});
      expect(await p.parse('dhanmondi'), isNull);
    });

    test('a slow model is abandoned, not waited on', () async {
      // The lexicon has already produced an answer by this point. Waiting on
      // a model having a bad day is worse than shipping the lesser result.
      final p = _parserReturning(
        {'parsed': true, 'place': 'Dhanmondi', 'types': <String>[]},
        delay: const Duration(seconds: 3),
        timeout: const Duration(milliseconds: 80),
      );
      final started = DateTime.now();
      expect(await p.parse('dhanmondi'), isNull);
      expect(DateTime.now().difference(started),
          lessThan(const Duration(seconds: 1)));
    });

    test('an empty transcript never leaves the device', () async {
      var called = false;
      final p = RemoteVoiceParser(invoke: (_) async {
        called = true;
        return null;
      });
      expect(await p.parse('   '), isNull);
      expect(called, isFalse, reason: 'no point paying for silence');
    });
  });
}
