import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/listing_purpose.dart';
import 'package:musafir/models/listing_type.dart';
import 'package:musafir/services/voice/voice_query_parser.dart';

void main() {
  const parser = VoiceQueryParser();

  group('the sentence the feature was built for', () {
    test('parses it in Bengali script', () {
      final q = parser.parse('ধানমন্ডির দিকে বাসা খোঁজো');
      expect(q.placeText, 'Dhanmondi');
      expect(q.types, [ListingType.fullHouse]);
    });

    test('parses it in Banglish', () {
      final q = parser.parse('dhanmondir dike basa khojo');
      expect(q.placeText, 'Dhanmondi');
      expect(q.types, [ListingType.fullHouse]);
    });

    test('parses it in English', () {
      final q = parser.parse('find a house near Dhanmondi');
      expect(q.placeText, 'Dhanmondi');
      expect(q.types, [ListingType.fullHouse]);
    });
  });

  group('place extraction', () {
    test('strips Bengali case endings', () {
      expect(parser.parse('উত্তরায় রুম').placeText, 'Uttara');
      expect(parser.parse('মিরপুরে সিট').placeText, 'Mirpur');
      expect(parser.parse('গুলশানের বাসা').placeText, 'Gulshan');
    });

    test('strips the Banglish possessive -r', () {
      expect(parser.parse('gulshanr basa').placeText, 'Gulshan');
    });

    test('leaves bare vowels alone so Banani survives', () {
      // The bug this guards: a blanket trailing-vowel strip turns "banani"
      // into "banan", which geocodes to nothing.
      expect(parser.parse('banani te room').placeText, 'Banani');
    });

    test('canonicalises spelling variants to one English name', () {
      for (final spoken in ['dhanmondhi', 'danmondi', 'ধানমন্ডি']) {
        expect(parser.parse('$spoken basa').placeText, 'Dhanmondi',
            reason: 'failed for "$spoken"');
      }
      expect(parser.parse('chittagong e basa').placeText, 'Chattogram');
    });

    test('matches multi-word names as a phrase', () {
      expect(parser.parse('coxs bazar e room chai').placeText, "Cox's Bazar");
    });

    test('passes unknown places through instead of dropping them', () {
      final q = parser.parse('kushtia te basa');
      expect(q.placeText, 'kushtia');
    });

    test('keeps the pre-canonical form when it differs', () {
      final q = parser.parse('dhanmondir basa');
      expect(q.placeText, 'Dhanmondi');
      expect(q.rawPlaceText, 'dhanmondir');
    });

    test('carries no raw fallback when nothing was rewritten', () {
      expect(parser.parse('kushtia basa').rawPlaceText, isNull);
    });
  });

  group('listing type', () {
    test('maps each type in both scripts', () {
      expect(parser.parse('বাসা').types, [ListingType.fullHouse]);
      expect(parser.parse('basa').types, [ListingType.fullHouse]);
      expect(parser.parse('রুম').types, [ListingType.room]);
      expect(parser.parse('rum').types, [ListingType.room]);
      expect(parser.parse('সিট').types, [ListingType.seat]);
      expect(parser.parse('seat').types, [ListingType.seat]);
    });

    test('does not repeat a type said twice', () {
      expect(parser.parse('basa bari dhaka').types, [ListingType.fullHouse]);
    });
  });

  group('guests', () {
    test('reads digits and Bengali digits', () {
      expect(parser.parse('uttara 2 jon room').guestCount, 2);
      expect(parser.parse('উত্তরা ৩ জন রুম').guestCount, 3);
    });

    test('reads spelled-out numbers', () {
      expect(parser.parse('dhaka dui jon basa').guestCount, 2);
      expect(parser.parse('dhaka three people room').guestCount, 3);
    });

    test('does not treat a bare number as a guest count', () {
      expect(parser.parse('mirpur 10 basa').guestCount, isNull);
    });
  });

  group('price', () {
    test('reads a thousands multiplier', () {
      expect(parser.parse('mirpur 5 hajar takar moddhe room').maxPrice, 5000);
      expect(parser.parse('মিরপুর ৫ হাজার টাকা রুম').maxPrice, 5000);
    });

    test('reads a plain amount with a currency word', () {
      expect(parser.parse('dhaka 3000 taka basa').maxPrice, 3000);
    });

    test('reads the glued k suffix', () {
      expect(parser.parse('banani 8k room').maxPrice, 8000);
    });

    test('requires a currency word so house numbers are not prices', () {
      expect(parser.parse('road 5 dhanmondi basa').maxPrice, isNull);
    });

    test('does not eat the guest count', () {
      final q = parser.parse('uttara 2 jon 5 hajar taka room');
      expect(q.guestCount, 2);
      expect(q.maxPrice, 5000);
      expect(q.placeText, 'Uttara');
    });
  });

  group('purpose', () {
    test('maps purposes in both scripts', () {
      expect(parser.parse('hospital er kache room').purpose,
          ListingPurpose.medical);
      expect(
          parser.parse('হাসপাতালের কাছে রুম').purpose, ListingPurpose.medical);
      expect(parser.parse('exam center er kache seat').purpose,
          ListingPurpose.exam);
      expect(parser.parse('university er pashe seat').purpose,
          ListingPurpose.student);
    });
  });

  group('empty and junk input', () {
    test('reports empty for an unparseable sentence', () {
      expect(parser.parse('').isEmpty, isTrue);
      expect(parser.parse('   ').isEmpty, isTrue);
      // Pure filler — every token is a stopword, so nothing is left.
      expect(parser.parse('ami chai please').isEmpty, isTrue);
    });

    test('is not empty when only a type was heard', () {
      final q = parser.parse('basa khojo');
      expect(q.isEmpty, isFalse);
      expect(q.placeText, isNull);
      expect(q.types, [ListingType.fullHouse]);
    });

    test('ignores punctuation', () {
      expect(parser.parse('ধানমন্ডি, বাসা!').placeText, 'Dhanmondi');
    });

    test('keeps the raw transcript for the miss log', () {
      const spoken = 'kichu ekta bolo';
      expect(parser.parse(spoken).transcript, spoken);
    });
  });

  group('case endings the table has to see through', () {
    // The reported bug: "dhakay room dekho" searched for the whole sentence
    // because "dhakay" carried an unlisted locative and "dekho" was not a
    // known verb, so both fell through into the place name.
    test('"dhakay room dekho" searches Dhaka, not the sentence', () {
      final q = parser.parse('dhakay room dekho');
      expect(q.placeText, 'Dhaka');
      expect(q.types, [ListingType.room]);
    });

    test('the bare imperatives are noise in both scripts', () {
      expect(parser.parse('ঢাকায় রুম দেখো').placeText, 'Dhaka');
      expect(parser.parse('gulshane seat khujo').placeText, 'Gulshan');
      // A verb on its own leaves nothing to search for.
      expect(parser.parse('dekho').placeText, isNull);
    });

    // Each of these used to emit a mangled stem because the first ending that
    // matched won, whether or not the table recognised what was left.
    test('the ending the table recognises wins, not the first that matches',
        () {
      expect(parser.parse('sylhete basa ache').placeText, 'Sylhet');
      expect(parser.parse('chittagonge room lagbe').placeText, 'Chattogram');
      expect(parser.parse('barisale room').placeText, 'Barishal');
      expect(parser.parse('motijheele room').placeText, 'Motijheel');
    });

    test('the Banglish locative -y/-ay comes off', () {
      expect(parser.parse('khulnay room').placeText, 'Khulna');
      expect(parser.parse('bashundharay room').placeText, 'Bashundhara');
    });

    test('the spoken form is still kept for the geocoder retry', () {
      // The canonical name is a heuristic; the runner falls back to what was
      // actually said when the geocoder does not recognise it.
      expect(parser.parse('dhakay room').rawPlaceText, 'dhakay');
    });
  });

  group('numbers spoken as words inside a place name', () {
    // Dhanmondi 32, Uttara sector 7, Mirpur 10 — Bangladeshi addresses ARE
    // numbers, and people say them as words. Google does not error on
    // "Dhanmondi bottris"; it quietly drops the word and returns the whole
    // 2 km neighbourhood, so a road-level search silently becomes an area
    // search. Nothing surfaces as a failure, which is why this has to be
    // caught here.
    test('a spoken number searches the same as a dialled one', () {
      expect(parser.parse('dhanmondi bottris').placeText,
          parser.parse('dhanmondi 32').placeText);
      expect(parser.parse('dhanmondi bottris').placeText, 'Dhanmondi 32');
    });

    test('works in Bengali script and Bengali digits alike', () {
      expect(parser.parse('ধানমন্ডি বত্রিশ').placeText, 'Dhanmondi 32');
      expect(parser.parse('ধানমন্ডি ৩২').placeText, 'Dhanmondi 32');
    });

    test('covers the small numbers too, not just the reported one', () {
      expect(parser.parse('mirpur dosh').placeText, 'Mirpur 10');
      expect(parser.parse('uttara sector tin').placeText, 'Uttara sector 3');
    });

    test('address vocabulary survives suffix stripping', () {
      // "sector" ends in the Bangla genitive -r, and stripping it left
      // "secto" — a word no geocoder resolves.
      expect(parser.parse('uttara sector tin').placeText, contains('sector'));
      expect(parser.parse('dhanmondi road bottris').placeText,
          'Dhanmondi road 32');
    });

    test('a number in a place is not mistaken for guests or a budget', () {
      final q = parser.parse('dhanmondi bottris');
      expect(q.guestCount, isNull);
      expect(q.maxPrice, isNull);
    });

    test('guest and price counting still wins where it should', () {
      expect(parser.parse('uttara dui jon room').guestCount, 2);
      expect(parser.parse('uttara bish jon').guestCount, 16,
          reason: 'clamped, but still read as a guest count');
      expect(parser.parse('dhanmondi 5 hajar taka').maxPrice, 5000);
    });

    test('a bare number word alone is left as spoken', () {
      // Nothing to attach it to — converting it would invent a place called
      // "32" out of a word that was probably misheard.
      expect(parser.parse('bottris').placeText, 'bottris');
    });
  });

  group('chips', () {
    test('summarise every filled slot', () {
      final q = parser.parse('uttara 2 jon 5 hajar taka room');
      expect(q.chips, containsAll(['Uttara', 'Room', '2 guests']));
    });

    test('are empty for an empty query', () {
      expect(parser.parse('').chips, isEmpty);
    });
  });
}
