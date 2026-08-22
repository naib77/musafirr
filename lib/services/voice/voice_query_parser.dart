import '../../models/listing_purpose.dart';
import '../../models/listing_type.dart';
import '../../models/voice_query.dart';

/// Turns a spoken sentence into a [VoiceQuery], in Bengali script or in
/// Banglish (Bangla typed/spoken in Latin letters) — usually both at once,
/// since the recogniser returns Bengali for `bn-BD` and Latin for `en-US`
/// and people freely mix the two.
///
/// This is deliberately a lexicon + stopword stripper, not a grammar. The
/// insight that makes that enough: we do not have to *understand* the
/// sentence, only to strip everything that is definitely not a place name and
/// hand the remainder to the geocoder, which is the real parser. So
/// "ধানমন্ডির দিকে বাসা খোঁজো" only needs `দিকে`/`খোঁজো` recognised as noise
/// and `বাসা` as a type; whatever survives is the place.
///
/// Unmatched sentences are expected and are not failures — they get logged so
/// the lexicon can grow from real speech instead of guesswork.
class VoiceQueryParser {
  const VoiceQueryParser();

  VoiceQuery parse(String transcript) {
    final tokens = _tokenise(transcript);
    if (tokens.isEmpty) return VoiceQuery(transcript: transcript);

    // Consumed by a slot; index-based so multi-token slots (a number plus its
    // unit) can claim both halves and neither leaks into the place name.
    final claimed = List<bool>.filled(tokens.length, false);

    final maxPrice = _extractPrice(tokens, claimed);
    final guestCount = _extractGuests(tokens, claimed);
    final types = <ListingType>[];
    ListingPurpose? purpose;

    for (var i = 0; i < tokens.length; i++) {
      if (claimed[i]) continue;
      final t = tokens[i];

      // Case endings attach to content words too ("হাসপাতালের", "porikkhar"),
      // so every lexicon lookup gets a second try against the stem.
      final stem = _stripCaseSuffix(t);

      final type = _typeWords[t] ?? _typeWords[stem];
      if (type != null) {
        if (!types.contains(type)) types.add(type);
        claimed[i] = true;
        continue;
      }

      final p = _purposeWords[t] ?? _purposeWords[stem];
      if (p != null) {
        purpose ??= p;
        claimed[i] = true;
        continue;
      }

      if (_stopWords.contains(t) || _stopWords.contains(stem)) {
        claimed[i] = true;
      }
    }

    final leftover = [
      for (var i = 0; i < tokens.length; i++)
        if (!claimed[i]) tokens[i],
    ];

    final raw = leftover.join(' ');
    final place = _canonicalisePlace(leftover);

    return VoiceQuery(
      transcript: transcript,
      placeText: place.isEmpty ? null : place,
      // Only worth carrying when it actually differs — the caller retries
      // with it, and retrying the identical string is a wasted round trip.
      rawPlaceText: raw.isEmpty || raw == place ? null : raw,
      types: types,
      guestCount: guestCount,
      maxPrice: maxPrice,
      purpose: purpose,
    );
  }

  // ── Normalisation ─────────────────────────────────────────────────────────

  /// Lowercases, folds Bengali digits to ASCII, and splits on anything that
  /// is not a letter or a digit. The Bengali block is kept by matching on
  /// "not punctuation/space" rather than on an ASCII letter class.
  List<String> _tokenise(String input) {
    final buffer = StringBuffer();
    for (final rune in input.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      final digit = _bengaliDigits.indexOf(ch);
      if (digit >= 0) {
        buffer.write(digit);
      } else if (_isSeparator(ch)) {
        buffer.write(' ');
      } else {
        buffer.write(ch);
      }
    }
    return buffer
        .toString()
        .split(' ')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
  }

  bool _isSeparator(String ch) {
    final code = ch.codeUnitAt(0);
    // ASCII letters and digits survive; so does every non-ASCII codepoint,
    // which is what keeps Bengali script intact.
    if (code >= 0x30 && code <= 0x39) return false; // 0-9
    if (code >= 0x61 && code <= 0x7A) return false; // a-z
    if (code > 0x7F) return false;
    return true;
  }

  // ── Slots ─────────────────────────────────────────────────────────────────

  /// "৫ হাজার টাকার মধ্যে" / "5 hajar takar moddhe" / "5000 taka" → 5000.
  /// Runs before the guest pass so "5 hajar taka" cannot be misread as a
  /// number waiting for a `jon`.
  double? _extractPrice(List<String> tokens, List<bool> claimed) {
    for (var i = 0; i < tokens.length; i++) {
      if (claimed[i]) continue;

      // "8k" glues the multiplier on, so it parses as neither a number nor a
      // word and has to be matched before the numeric guard below.
      final glued = _kSuffix.firstMatch(tokens[i]);
      if (glued != null) {
        claimed[i] = true;
        return double.parse(glued.group(1)!) * 1000;
      }

      final value = _numberValue(tokens[i]);
      if (value == null) continue;

      var amount = value;
      var last = i;

      // Optional multiplier: "5 hajar" → 5000.
      if (i + 1 < tokens.length && _thousandWords.contains(tokens[i + 1])) {
        amount *= 1000;
        last = i + 1;
      }

      // A currency word is what proves this is a price and not a guest count
      // or a house number, so it is required rather than optional.
      final currencyAt = last + 1;
      if (currencyAt < tokens.length &&
          _currencyWords.contains(tokens[currencyAt])) {
        for (var k = i; k <= currencyAt; k++) {
          claimed[k] = true;
        }
        return amount;
      }
    }
    return null;
  }

  /// "২ জন" / "2 jon" / "3 people" → 2, 2, 3.
  int? _extractGuests(List<String> tokens, List<bool> claimed) {
    for (var i = 0; i < tokens.length - 1; i++) {
      if (claimed[i] || claimed[i + 1]) continue;
      final value = _numberValue(tokens[i]);
      if (value == null) continue;
      if (!_guestWords.contains(tokens[i + 1])) continue;
      claimed[i] = true;
      claimed[i + 1] = true;
      return value.round().clamp(1, 16);
    }
    return null;
  }

  double? _numberValue(String token) {
    final digits = double.tryParse(token);
    if (digits != null) return digits;
    return _numberWords[token]?.toDouble();
  }

  // ── Place ─────────────────────────────────────────────────────────────────

  /// Strips Bangla case endings and maps known areas to the English spelling
  /// Google resolves best. Anything unknown passes through cleaned but
  /// untranslated — the geocoder gets first refusal, not this table.
  String _canonicalisePlace(List<String> leftover) {
    if (leftover.isEmpty) return '';

    // The raw phrase gets first look, so two-word names ("coxs bazar") match
    // before per-word stripping can chew "bazar" down to "baza".
    final rawPhrase = leftover.join(' ');
    final rawAlias = _placeAliases[rawPhrase];
    if (rawAlias != null) return rawAlias;

    return _foldNumberWords(leftover)
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Turns spoken numbers inside a place name into digits — "dhanmondi
  /// bottris" into "Dhanmondi 32" — and resolves everything else through the
  /// alias table.
  ///
  /// A number is only converted when something precedes it, so it is
  /// modifying a place rather than being one. That guard is what keeps "char
  /// fasson" (a river island) from becoming "4 fasson", and a lone misheard
  /// "bottris" from being searched as the place "32".
  List<String> _foldNumberWords(List<String> leftover) {
    final out = <String>[];
    for (var i = 0; i < leftover.length; i++) {
      final word = leftover[i];
      final value = i == 0 ? null : _numberWords[word];
      if (value == null) {
        out.add(_resolveWord(word));
        continue;
      }

      // "thirty two" is one number said as two words; "sector 3 road 12" is
      // two numbers that must not merge. Only a tens word followed by a unit
      // combines.
      if (_compoundableTens.contains(value) && i + 1 < leftover.length) {
        final unit = _numberWords[leftover[i + 1]];
        if (unit != null && unit >= 1 && unit <= 9) {
          out.add('${value + unit}');
          i++;
          continue;
        }
      }
      out.add('$value');
    }
    return out;
  }

  /// An alias hit on the spoken form wins outright — only a word the table
  /// does not recognise gets its case ending stripped and looked up again.
  /// That ordering is what keeps "banani" from being stripped to "banan".
  ///
  /// When it does strip, EVERY ending the word could be carrying is tried and
  /// the alias table decides which one it actually was. Committing to the
  /// first match instead is what turned "sylhete" into "sylhe" — a stem no
  /// geocoder has heard of — when taking off just the "e" finds Sylhet.
  String _resolveWord(String word) {
    final direct = _placeAliases[word];
    if (direct != null) return direct;
    // Kept whole: these are the words a road number hangs off, and stripping
    // them is what turned "sector" into "secto".
    if (_addressWords.contains(word)) return word;

    String? fallback;
    for (final stem in _candidateStems(word)) {
      final alias = _placeAliases[stem];
      if (alias != null) return alias;
      // No table hit anywhere → keep the longest-ending strip, which is what
      // this did before, and let the geocoder (and the raw-form retry) decide.
      fallback ??= stem;
    }
    return fallback ?? word;
  }

  /// Bengali case markers are unambiguous, so they come off confidently.
  /// The Latin list is deliberately short — only endings that are case
  /// markers rather than part of a name. Stripping a bare trailing "i" would
  /// turn Banani into "banan", which is why vowels are left alone.
  String _stripCaseSuffix(String word) {
    final stems = _candidateStems(word);
    return stems.isEmpty ? word : stems.first;
  }

  /// Every stem [word] would have if it were carrying a case ending, longest
  /// ending first. Bengali markers are unambiguous so they come off
  /// confidently; the Latin list is short on purpose — only endings that are
  /// case markers rather than part of a name. A bare trailing "i" is never
  /// stripped, because that turns Banani into "banan".
  List<String> _candidateStems(String word) {
    final stems = <String>[];
    for (final suffix in _bengaliCaseSuffixes) {
      if (word.length > suffix.length + 1 && word.endsWith(suffix)) {
        stems.add(word.substring(0, word.length - suffix.length));
      }
    }
    for (final suffix in _latinCaseSuffixes) {
      if (word.length > suffix.length + 2 && word.endsWith(suffix)) {
        stems.add(word.substring(0, word.length - suffix.length));
      }
    }
    return stems;
  }
}

// ── Lexicons ────────────────────────────────────────────────────────────────
//
// Every entry appears in both scripts where the word exists in both. These
// lists are meant to grow from the miss log, not to be complete on day one.

const String _bengaliDigits = '০১২৩৪৫৬৭৮৯';

const Map<String, ListingType> _typeWords = {
  // Full house
  'বাসা': ListingType.fullHouse,
  'বাড়ি': ListingType.fullHouse,
  'ফ্ল্যাট': ListingType.fullHouse,
  'অ্যাপার্টমেন্ট': ListingType.fullHouse,
  'basa': ListingType.fullHouse,
  'basha': ListingType.fullHouse,
  'bari': ListingType.fullHouse,
  'barii': ListingType.fullHouse,
  'flat': ListingType.fullHouse,
  'plat': ListingType.fullHouse,
  'house': ListingType.fullHouse,
  'home': ListingType.fullHouse,
  'apartment': ListingType.fullHouse,
  // Room
  'রুম': ListingType.room,
  'ঘর': ListingType.room,
  'কামরা': ListingType.room,
  'room': ListingType.room,
  'rum': ListingType.room,
  'ghor': ListingType.room,
  'ghar': ListingType.room,
  'kamra': ListingType.room,
  // Seat
  'সিট': ListingType.seat,
  'সীট': ListingType.seat,
  'বেড': ListingType.seat,
  'seat': ListingType.seat,
  'sit': ListingType.seat,
  'bed': ListingType.seat,
};

const Map<String, ListingPurpose> _purposeWords = {
  'হাসপাতাল': ListingPurpose.medical,
  'হসপিটাল': ListingPurpose.medical,
  'ক্লিনিক': ListingPurpose.medical,
  'মেডিকেল': ListingPurpose.medical,
  'চিকিৎসা': ListingPurpose.medical,
  'hospital': ListingPurpose.medical,
  'clinic': ListingPurpose.medical,
  'medical': ListingPurpose.medical,
  'chikitsha': ListingPurpose.medical,
  'পরীক্ষা': ListingPurpose.exam,
  'পরীক্ষার': ListingPurpose.exam,
  'এক্সাম': ListingPurpose.exam,
  'porikkha': ListingPurpose.exam,
  'porikha': ListingPurpose.exam,
  'exam': ListingPurpose.exam,
  'বিশ্ববিদ্যালয়': ListingPurpose.student,
  'ভার্সিটি': ListingPurpose.student,
  'ইউনিভার্সিটি': ListingPurpose.student,
  'কলেজ': ListingPurpose.student,
  'university': ListingPurpose.student,
  'varsity': ListingPurpose.student,
  'versity': ListingPurpose.student,
  'college': ListingPurpose.student,
  'student': ListingPurpose.student,
  'অফিস': ListingPurpose.business,
  'ব্যবসা': ListingPurpose.business,
  'বিজনেস': ListingPurpose.business,
  'office': ListingPurpose.business,
  'business': ListingPurpose.business,
  'ঘুরতে': ListingPurpose.tourism,
  'বেড়াতে': ListingPurpose.tourism,
  'ভ্রমণ': ListingPurpose.tourism,
  'ট্যুর': ListingPurpose.tourism,
  'tour': ListingPurpose.tourism,
  'ghurte': ListingPurpose.tourism,
  'berate': ListingPurpose.tourism,
  'vromon': ListingPurpose.tourism,
  'travel': ListingPurpose.tourism,
};

/// Intent verbs, postpositions, pronouns and filler. Everything here is
/// "definitely not a place name".
const Set<String> _stopWords = {
  // Bengali — verbs of asking
  'খোঁজো', 'খোঁজ', 'খুঁজে', 'খুঁজছি', 'খুজি', 'দেখাও', 'দেখান',
  'দেখো', 'দেখ', 'দেখি', 'দেখতে', 'খুঁজো', 'খুজো', 'খুঁজতে', 'খুঁজব',
  'দাও', 'চাই', 'চাচ্ছি', 'লাগবে', 'দরকার', 'আছে', 'পাবো', 'পাব', 'করো',
  'করুন', 'নিয়ে', 'দিন',
  // Bengali — postpositions and location filler
  'দিকে', 'কাছে', 'কাছাকাছি', 'আশেপাশে', 'আশপাশে', 'পাশে', 'মধ্যে', 'ভিতরে',
  'এলাকা', 'এলাকায়', 'এলাকার', 'জায়গায়', 'জন্য', 'সাথে', 'থেকে',
  // Bengali — pronouns / determiners / filler
  'আমি', 'আমার', 'আমাকে', 'একটা', 'একটি', 'কিছু', 'কোনো', 'কোন', 'কি',
  'এবং', 'আর', 'প্লিজ', 'দয়া', 'ভাড়া',
  // Banglish
  'khojo', 'khoj', 'khuje', 'khujchi', 'khujci', 'dekhao', 'dekhan', 'dao',
  // The bare imperatives. "dekho"/"khujo" are how people actually speak —
  // "dhakay room dekho" — and without them the verb rides into the place name
  // and the geocoder is handed "dhakay dekho".
  'dekho', 'dekh', 'dekhi', 'dekhte', 'dekhba', 'dekhben',
  'khujo', 'khuji', 'khujte', 'khujba', 'khujben', 'khujtechi', 'khujchilam',
  'chai', 'chacchi', 'lagbe', 'dorkar', 'ache', 'pabo', 'koro', 'korun',
  'niye', 'din',
  'dike', 'kache', 'kachakachi', 'asepashe', 'ashepashe', 'pashe', 'moddhe',
  'vitore', 'elaka', 'elakay', 'elakar', 'jaygay', 'jonno', 'sathe', 'theke',
  'ami', 'amar', 'amake', 'ekta', 'ekti', 'kichu', 'kono', 'ki', 'ebong',
  'ar', 'plij', 'vara', 'bhara',
  // Case particles spoken as their own word ("chittagong e", "kushtia te").
  // Attached endings are handled by _stripCaseSuffix; these are the detached
  // forms, which tokenise separately and would otherwise land in the place.
  'e', 'te', 'er', 'ey', 'y', 'এ', 'তে', 'ের', 'য়',
  // Qualifiers that follow a purpose word rather than naming a place.
  'center', 'centre', 'kendro', 'কেন্দ্র', 'hall', 'zone',
  // English
  'find', 'show', 'search', 'searching', 'look', 'looking', 'get', 'want',
  'need', 'give', 'please', 'me', 'my', 'i', 'a', 'an', 'the', 'some', 'any',
  'near', 'nearby', 'around', 'close', 'in', 'at', 'on', 'for', 'to', 'of',
  'with', 'and', 'is', 'are', 'there', 'available', 'rent', 'stay', 'place',
};

/// Numbers as words. This runs past ten on purpose: Bangladeshi addresses ARE
/// numbers — Dhanmondi road 32, Uttara sector 18, Mirpur 14 — and people say
/// them rather than spell them out. Google does not reject "Dhanmondi
/// bottris"; it drops the word and hands back the whole neighbourhood, so a
/// gap here degrades a road-level search into an area one with nothing to
/// show for it.
const Map<String, int> _numberWords = {
  'এক': 1, 'দুই': 2, 'দুটো': 2, 'তিন': 3, 'চার': 4, 'পাঁচ': 5, 'পাচ': 5,
  'ছয়': 6, 'সাত': 7, 'আট': 8, 'নয়': 9, 'দশ': 10,
  'ek': 1, 'dui': 2, 'duto': 2, 'tin': 3, 'char': 4, 'pach': 5, 'panch': 5,
  'choy': 6, 'sat': 7, 'aat': 8, 'noy': 9, 'dosh': 10,
  'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7,
  'eight': 8, 'nine': 9, 'ten': 10,

  // 11–20
  'এগারো': 11, 'বারো': 12, 'তেরো': 13, 'চৌদ্দ': 14, 'পনেরো': 15, 'পনের': 15,
  'ষোলো': 16, 'ষোল': 16, 'সতেরো': 17, 'আঠারো': 18, 'উনিশ': 19, 'বিশ': 20,
  'egaro': 11, 'baro': 12, 'tero': 13, 'chouddo': 14, 'choddo': 14,
  'ponero': 15, 'ponro': 15, 'sholo': 16, 'sotero': 17, 'attharo': 18,
  'atharo': 18, 'unish': 19, 'unnish': 19, 'bish': 20,
  'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14, 'fifteen': 15,
  'sixteen': 16, 'seventeen': 17, 'eighteen': 18, 'nineteen': 19,
  'twenty': 20,

  // 21–32, which is as far as Dhanmondi's roads go
  'একুশ': 21, 'বাইশ': 22, 'তেইশ': 23, 'চব্বিশ': 24, 'পঁচিশ': 25, 'পচিশ': 25,
  'ছাব্বিশ': 26, 'সাতাশ': 27, 'আটাশ': 28, 'ঊনত্রিশ': 29, 'উনত্রিশ': 29,
  'ত্রিশ': 30, 'একত্রিশ': 31, 'বত্রিশ': 32,
  'ekush': 21, 'baish': 22, 'teish': 23, 'chobbish': 24, 'pochish': 25,
  'chabbish': 26, 'satash': 27, 'athash': 28, 'untrish': 29, 'trish': 30,
  'ekatrish': 31, 'bottris': 32, 'bottrish': 32, 'batris': 32,
  'battrish': 32,
  'thirty': 30,

  // 33–40, for Uttara sectors and Mirpur blocks
  'তেত্রিশ': 33, 'চৌত্রিশ': 34, 'পঁয়ত্রিশ': 35, 'ছত্রিশ': 36,
  'সাঁইত্রিশ': 37, 'আটত্রিশ': 38, 'ঊনচল্লিশ': 39, 'চল্লিশ': 40,
  'tetris': 33, 'choutris': 34, 'poitris': 35, 'chattris': 36,
  'saitris': 37, 'attris': 38, 'unchallish': 39, 'chollish': 40,
  'forty': 40,
};

/// The tens an English speaker says as two tokens ("thirty two"). Bangla does
/// not need this — বত্রিশ is one word — but without it "Dhanmondi thirty two"
/// would resolve to "Dhanmondi 30 2", which geocodes no better than the words
/// did.
const Set<int> _compoundableTens = {20, 30, 40};

/// Address vocabulary that must survive case-suffix stripping. "sector" ends
/// in the Bangla genitive -r, and taking it off left "secto" — a word no
/// geocoder resolves, silently widening "Uttara sector 3" to all of Uttara.
const Set<String> _addressWords = {
  'sector',
  'sectors',
  'road',
  'rd',
  'block',
  'lane',
  'avenue',
  'nombor',
  'number',
  'no',
  'সেক্টর',
  'রোড',
  'ব্লক',
  'নম্বর',
  'নং',
};

const Set<String> _guestWords = {
  'জন',
  'জনের',
  'জনে',
  'ব্যক্তি',
  'অতিথি',
  'jon',
  'joner',
  'jone',
  'person',
  'people',
  'guest',
  'guests',
  'pax',
};

const Set<String> _thousandWords = {'হাজার', 'hajar', 'hazar', 'thousand', 'k'};

const Set<String> _currencyWords = {
  'টাকা',
  'টাকার',
  'টাকায়',
  'taka',
  'takar',
  'tk',
  'bdt',
  'tomake',
};

final RegExp _kSuffix = RegExp(r'^(\d+)k$');

/// Bengali case endings, longest first so "ের" wins over "র". Written as
/// escapes because several of these are visually identical to their
/// decomposed forms — "\u09df" (য়) also occurs as "\u09af\u09bc", and a
/// recogniser may emit either, so both spellings are listed.
const List<String> _bengaliCaseSuffixes = [
  '\u09a4\u09c7\u0987', // তেই
  '\u09df\u09c7', // য়ে  (precomposed)
  '\u09af\u09bc\u09c7', // য়ে  (decomposed)
  '\u09a4\u09c7', // তে
  '\u09c7\u09b0', // ের
  '\u0995\u09c7', // কে
  '\u09df', // য়   (precomposed)
  '\u09af\u09bc', // য়   (decomposed)
  '\u09b0', // র
  '\u09c7', // ে
];

/// Latin case endings only — no bare vowels. "dhanmondir" → "dhanmondi",
/// while "banani" is left alone.
/// Longest first, so "sylhete" gets a shot at "te" before "e" — the table
/// then picks whichever stem it recognises. "ay"/"y" are the Banglish
/// locative ("dhakay" = ঢাকায়); "e" is the other half of the same case
/// ("mirpure", "barisale"). Bare vowels other than these are left alone.
const List<String> _latinCaseSuffixes = [
  'ter',
  'te',
  'er',
  'ay',
  'r',
  'y',
  'e',
];

/// Common Bangladeshi areas and cities mapped to the English spelling Google
/// geocodes most reliably. Both scripts point at the same canonical value, so
/// a Bengali transcript never has to be geocoded as Bengali.
const Map<String, String> _placeAliases = {
  // Dhaka areas
  'ধানমন্ডি': 'Dhanmondi', 'dhanmondi': 'Dhanmondi', 'dhanmondhi': 'Dhanmondi',
  'danmondi': 'Dhanmondi', 'dhanmandi': 'Dhanmondi',
  'গুলশান': 'Gulshan', 'gulshan': 'Gulshan', 'gulshane': 'Gulshan',
  'বনানী': 'Banani', 'banani': 'Banani',
  'উত্তরা': 'Uttara', 'uttara': 'Uttara', 'uttora': 'Uttara',
  'uttarai': 'Uttara',
  'মিরপুর': 'Mirpur', 'mirpur': 'Mirpur', 'mirpure': 'Mirpur',
  'মোহাম্মদপুর': 'Mohammadpur', 'mohammadpur': 'Mohammadpur',
  'বসুন্ধরা': 'Bashundhara', 'bashundhara': 'Bashundhara',
  'basundhara': 'Bashundhara',
  'বাড্ডা': 'Badda', 'badda': 'Badda',
  'মতিঝিল': 'Motijheel', 'motijheel': 'Motijheel', 'motijhil': 'Motijheel',
  'ফার্মগেট': 'Farmgate', 'farmgate': 'Farmgate',
  'শ্যামলী': 'Shyamoli', 'shyamoli': 'Shyamoli',
  'খিলগাঁও': 'Khilgaon', 'khilgaon': 'Khilgaon',
  'রামপুরা': 'Rampura', 'rampura': 'Rampura',
  'তেজগাঁও': 'Tejgaon', 'tejgaon': 'Tejgaon',
  'পল্টন': 'Paltan', 'paltan': 'Paltan',
  'যাত্রাবাড়ী': 'Jatrabari', 'jatrabari': 'Jatrabari',
  'সাভার': 'Savar', 'savar': 'Savar',
  'পুরান ঢাকা': 'Old Dhaka', 'puran dhaka': 'Old Dhaka',
  // Cities
  'ঢাকা': 'Dhaka', 'dhaka': 'Dhaka',
  'চট্টগ্রাম': 'Chattogram', 'chattogram': 'Chattogram',
  'chittagong': 'Chattogram', 'ctg': 'Chattogram',
  'সিলেট': 'Sylhet', 'sylhet': 'Sylhet',
  'খুলনা': 'Khulna', 'khulna': 'Khulna',
  'রাজশাহী': 'Rajshahi', 'rajshahi': 'Rajshahi',
  'বরিশাল': 'Barishal', 'barishal': 'Barishal', 'barisal': 'Barishal',
  'রংপুর': 'Rangpur', 'rangpur': 'Rangpur',
  'ময়মনসিংহ': 'Mymensingh', 'mymensingh': 'Mymensingh',
  'নারায়ণগঞ্জ': 'Narayanganj', 'narayanganj': 'Narayanganj',
  'গাজীপুর': 'Gazipur', 'gazipur': 'Gazipur',
  'কক্সবাজার': "Cox's Bazar", 'coxsbazar': "Cox's Bazar",
  'cox bazar': "Cox's Bazar", 'coxs bazar': "Cox's Bazar",
  'কুমিল্লা': 'Cumilla', 'cumilla': 'Cumilla', 'comilla': 'Cumilla',
  'যশোর': 'Jashore', 'jashore': 'Jashore', 'jessore': 'Jashore',
  'বগুড়া': 'Bogura', 'bogura': 'Bogura', 'bogra': 'Bogura',
  'সেন্ট মার্টিন': "Saint Martin's Island",
  'saint martin': "Saint Martin's Island",
  'সাজেক': 'Sajek Valley', 'sajek': 'Sajek Valley',
};
