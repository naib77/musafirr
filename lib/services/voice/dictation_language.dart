import 'package:shared_preferences/shared_preferences.dart';

import 'speech_service.dart';

/// The stored form of a dictation language.
///
/// Deliberately short codes rather than `VoiceLanguage.name`: the enum is
/// Dart's to rename, but this string is already on users' devices, and a
/// rename would silently reset everyone to Auto rather than failing loudly.
String encodeVoiceLanguage(VoiceLanguage language) => switch (language) {
      VoiceLanguage.bangla => 'bn',
      VoiceLanguage.english => 'en',
      VoiceLanguage.auto => 'auto',
    };

/// Reads back [encodeVoiceLanguage]. Anything unrecognised — absent, corrupt,
/// or written by a newer build — resolves to Auto, which is the behaviour
/// someone who has never chosen would expect.
VoiceLanguage decodeVoiceLanguage(String? stored) => switch (stored) {
      'bn' => VoiceLanguage.bangla,
      'en' => VoiceLanguage.english,
      _ => VoiceLanguage.auto,
    };

/// Remembers which language the mic should listen for.
///
/// Kept per DEVICE, not per user account, unlike host/guest mode: the language
/// someone speaks belongs to the person holding the phone, and on a shared
/// device a new login is far likelier to speak the same language as the last
/// one than to want Auto again.
///
/// Every failure is swallowed to a default. A composer must never be blocked
/// from taking dictation because a preference could not be read.
class DictationLanguageStore {
  static final DictationLanguageStore instance = DictationLanguageStore();

  /// Test seam — a fake in-memory store stands in, so widget tests never touch
  /// platform storage. Always read through [current].
  static DictationLanguageStore? debugOverride;

  static DictationLanguageStore get current => debugOverride ?? instance;

  static const String _key = 'voice_dictation_language';

  Future<VoiceLanguage> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return decodeVoiceLanguage(prefs.getString(_key));
    } catch (_) {
      return VoiceLanguage.auto;
    }
  }

  Future<void> save(VoiceLanguage language) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, encodeVoiceLanguage(language));
    } catch (_) {
      // A preference that could not be stored is worth less than the turn the
      // user is in the middle of; it will simply be Auto again next launch.
    }
  }
}

/// What choosing this language actually does, said plainly.
///
/// Auto is the one that needs explaining: it is Bangla-first by design, and a
/// user watching Bangla text appear when they spoke English has no way to
/// guess that from the word "Auto" alone.
String dictationLanguageHint(VoiceLanguage language) => switch (language) {
      VoiceLanguage.bangla => 'Always listen for Bangla',
      VoiceLanguage.english => 'Always listen for English',
      VoiceLanguage.auto => 'Bangla where your device has it, else English',
    };
