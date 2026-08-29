import 'speech_service.dart';

/// The BCP-47 tag the recogniser should be asked for.
///
/// Split out as a pure function because the decision is subtle and platform
/// dependent, and the bug it fixes was invisible: on web,
/// `speech_to_text`'s `locales()` reads `SpeechRecognition.lang`, which is an
/// empty string until a listen has already set it — so the list comes back
/// EMPTY every time. [VoiceSpeechService] asked for it once during
/// `initialize()`, read "no Bangla", and pinned every Auto search to en-US.
/// Bangladeshi users speaking Bangla got an English recogniser and a sheet
/// saying "Nothing was heard", on every browser.
///
/// The fix is to distinguish "the platform says Bangla is absent" from "the
/// platform cannot tell us" — [canEnumerateLocales]. Only the first is a
/// reason to give up on Bangla.
String resolveSpeechLocaleId({
  required VoiceLanguage language,
  required List<String> availableLocaleIds,
  required bool canEnumerateLocales,
}) {
  final bangla = _firstBangla(availableLocaleIds);

  switch (language) {
    case VoiceLanguage.english:
      return _english;

    case VoiceLanguage.bangla:
      // Asked for explicitly, so honour it even when unlisted — the browser
      // accepts any tag and reports back if it truly cannot serve it.
      return bangla ?? _bangla;

    case VoiceLanguage.auto:
      if (bangla != null) return bangla;
      // Cannot enumerate (web): ask for Bangla anyway. This is a
      // Bangladesh-first product and Chrome's Web Speech API does serve
      // bn-BD; if a browser does not, [fallbackLocaleId] retries in English.
      // Reading an unknowable list as "no Bangla" is the actual bug.
      return canEnumerateLocales ? _english : _bangla;
  }
}

/// What to retry with after the browser rejects [attempted] (Web Speech fires
/// `language-not-supported`). Null when there is nothing left to try, which
/// stops a browser that supports no speech language at all from looping.
String? fallbackLocaleId(String attempted) {
  return _isBangla(attempted) ? _english : null;
}

const String _bangla = 'bn-BD';
const String _english = 'en-US';

bool _isBangla(String id) =>
    id.toLowerCase().replaceAll('-', '_').startsWith('bn');

String? _firstBangla(List<String> ids) {
  // Prefer bn_BD exactly, then any Bengali variant (bn_IN on some devices).
  for (final id in ids) {
    if (id.toLowerCase().replaceAll('-', '_') == 'bn_bd') return id;
  }
  for (final id in ids) {
    if (_isBangla(id)) return id;
  }
  return null;
}
