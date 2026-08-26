import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/services/voice/voice_query_parser.dart';

void main() {
  test('sweep', () {
    const p = VoiceQueryParser();
    for (final i in [
      'dhanmondi bottris',
      'dhanmondi 32',
      'ধানমন্ডি বত্রিশ',
      'dhanmondi thirty two',
      'dhanmondi road bottris',
      'uttara sector tin',
      'uttara sector attharo',
      'mirpur dosh',
      'mirpur baro number',
      'gulshan dui',
      'banani road এগারো',
      'char fasson',
      'bottris',
      'dhanmondir dike basa khojo',
      'coxs bazar e room chai',
      'banani te room',
      'uttara 2 jon 5 hajar taka room',
      'dhakay room dekho',
      'sylhete basa ache',
    ]) {
      final q = p.parse(i);
      // ignore: avoid_print
      print(
          'S "$i" -> place=${q.placeText} guests=${q.guestCount} price=${q.maxPrice} types=${q.types.map((t) => t.name).toList()}');
    }
  });
}
