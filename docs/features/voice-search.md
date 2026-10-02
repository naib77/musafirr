# Voice search (Bangla + Banglish)

Say **"ধানমন্ডির দিকে বাসা খোঁজো"** or **"dhanmondir dike basa khojo"** and get
Dhanmondi full-house listings.

Runs at **zero marginal cost**. There is no cloud speech-to-text and no LLM
behind it — only the Android recogniser, the browser Web Speech API, and a
lexicon in Dart. No API key, no billing account, no new backend.

## How it works

Three stages, and only the middle one is new code:

| Stage | Component | Cost |
|---|---|---|
| Audio → text | `speech_to_text` → Android recogniser / Web Speech API | Free, keyless |
| Text → slots | `VoiceQueryParser` (lexicon + stopwords) | Free |
| …when that finds nothing | `RemoteVoiceParser` → `voice-parse` → Gemini Flash-Lite | ~$0.23 / 1,000 |
| Slots → results | `VoiceSearchRunner` → existing geocoder → `SearchStateNotifier` | Already paid for |

The lexicon is the fast path, not the only one. A lexicon knows only the words
someone typed into it, so the model handles the tail — but it is asked ONLY
when the lexicon extracts nothing, or when the place it extracted fails to
geocode twice. The common query (`"dhanmondi room"`) never leaves the device
and never costs anything.

Three rules make the fallback safe to depend on:

* **It cannot break a search.** Offline, timeout, 502, junk JSON — every path
  returns null and the lexicon's answer stands.
* **It is bounded at 4 s.** Past that a voice interaction reads as broken, and
  the poorer local answer is the better product.
* **It never locates anything.** The model returns a place *string*, still
  resolved by the same geocoder a typed search uses. A model emitting
  coordinates is a model that can confidently send a guest to the wrong city.

What it does **not** catch: silent degradation. `"Dhanmondi bottris"` parsed
"successfully" and geocoded "successfully" — to the whole neighbourhood. No
runtime signal exists for that, which is what the miss log is for.

Speaking is the whole interaction: the recogniser stops on its own after a
pause, the chips showing what it heard flash up for ~0.9 s, and the search
fires. Nothing has to be tapped. The **I'm done** link only skips the silence
timeout for someone who has finished early, and the Explore search field is
left holding the resolved place name so a mishearing is visible and clearable.

Two things make that safe to do without a confirm step: an empty parse never
auto-searches (it explains itself and offers a retry), and a recogniser that
closes the mic without ever sending a final result is treated as final — with
no button on screen, a dead mic would otherwise be a dead end.

The parser is deliberately **not** a grammar. It does not need to understand
the sentence — only to strip everything that is definitely not a place name and
hand the remainder to the geocoder, which is the real parser. "ধানমন্ডির দিকে
বাসা খোঁজো" only needs `দিকে`/`খোঁজো` recognised as noise and `বাসা` as a type;
whatever survives is the place.

Voice never invents coordinates. It fills the same `SearchFilters` the search
sheet fills by hand, so results, map framing and empty states are all existing
code.

## Files

```
lib/models/voice_query.dart                      parsed slots
lib/services/voice/voice_query_parser.dart       the lexicon  ← grow this
lib/services/voice/speech_service.dart           platform wrapper
lib/services/voice/voice_support_{stub,web}.dart free capability probe
lib/services/voice/remote_voice_parser.dart      Gemini fallback for the tail
lib/services/voice/voice_search_runner.dart      query → SearchFilters
supabase/functions/voice-parse/index.ts          the Gemini proxy (key stays server-side)
lib/widgets/voice_search_button.dart             mic in the search pill
lib/widgets/voice_listening_sheet.dart           listen → confirm → search
supabase/migrations/096_voice_search_log.sql     the miss log
```

## Where it appears — and where it does not

The mic hides itself wherever speech recognition could never work. That check
(`speechRecognitionMaybeAvailable()`) is a free property lookup, never a
permission prompt, so it is safe to call during `build`.

| Surface | Mic shown | `bn-BD` |
|---|---|---|
| Android app | Yes | Yes |
| Chrome, Edge-on-Chromium\*, Samsung Internet | Yes | Yes |
| Safari / iOS | Yes (API exists) | Apple's engine has no Bengali — English only |
| Firefox | **No** | No Web Speech API at all |
| iOS app | **No** | `SFSpeechRecognizer` has no Bengali locale |

\* caniuse reports Edge as unsupported despite being Chromium; the probe is a
runtime check, so it degrades correctly either way.

A mic button that cannot listen is worse than no mic button — hence the
hiding rather than a failing tap.

## Platform setup

### Web
Nothing. HTTPS and a user gesture are required for microphone access; the PWA
already satisfies both.

> **Privacy:** Chrome's Web Speech API streams audio to Google's servers. This
> needs a line in the privacy policy.

### Android
Already wired in `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />

<queries>
    <!-- Android 11+ package visibility: without this the RecognitionService
         is invisible to the app and initialize() silently returns false, so
         the mic button never appears and nothing explains why. -->
    <intent>
        <action android:name="android.speech.RecognitionService"/>
    </intent>
</queries>
```

Verified present in the merged manifest of a built APK, not just the source.

> The Android platform folder had been deleted by commit `ef97d8b7`
> ("build remvoed") and was restored from `ef97d8b7^`. See
> [Android platform folder](#android-platform-folder-history) below.

### iOS
Out of scope (no Bengali locale), but `NSMicrophoneUsageDescription` and
`NSSpeechRecognitionUsageDescription` are already in `Info.plist` — the plugin
links `Speech.framework`, and App Store review rejects builds that link it
without usage strings, whether or not the code path runs.

## Diagnosing "voice search is not working"

That sentence covers four different failures, and the console tells them apart.

| What you see | Stage that failed |
|---|---|
| No `status: listening` at all | The mic never opened — permission, or no recogniser |
| `status: listening` but no `[VoiceSearch]` line | Nothing was heard, or nothing parsed — the sheet says which |
| `[VoiceSearch] … (name only (geocode miss))` | The place did not geocode; add it to `_placeAliases` |
| `[VoiceSearch] … => 0 result(s)` | Parsed and located fine — there are simply no matching stays |

The `[VoiceSearch]` line is debug-only and prints once per spoken search:

```
[VoiceSearch] "ধানমন্ডির দিকে বাসা খোঁজো" -> place=Dhanmondi (box)
    types=[fullHouse] guests=null maxPrice=null purpose=null => 4 result(s)
```

A `voice_search_log` PGRST205 in the console is **not** a failure of the
search — it only means migration `096` is missing on that environment, so
telemetry is off. It is reported once per run, not once per query.

## Growing the lexicon — the part that matters

The lexicon is what keeps this free, and it is meant to grow from real speech
rather than guesswork. Every spoken query is logged to `voice_search_log` with
what the parser made of it.

Migration `096` was **applied live on 2026-08-22** and recorded in
`schema_migrations` (history 001–096). Read it weekly:

```sql
-- What missed, most common first
select transcript, count(*)
from voice_search_log
where parsed = false
group by transcript
order by count(*) desc
limit 50;

-- Parsed, but found nothing — usually a place alias that is missing
select transcript, parsed_place, count(*)
from voice_search_log
where parsed and result_count = 0
group by transcript, parsed_place
order by count(*) desc
limit 50;
```

Add what you find to the lexicons at the bottom of `voice_query_parser.dart`:

- `_placeAliases` — spelling variants → the English name Google geocodes best.
  Both scripts point at the same value, so a Bengali transcript never has to be
  geocoded as Bengali. **Highest-leverage table by far.**
- `_typeWords`, `_purposeWords` — content words, in both scripts
- `_stopWords` — verbs, postpositions, filler
- `_bengaliCaseSuffixes` / `_latinCaseSuffixes` — case endings

> **Never chain `.select()` onto the log insert.** The table grants INSERT and
> defines no SELECT policy on purpose, so asking for the row back fails with a
> 401 whose message — *"new row violates row-level security policy"* — points
> at the wrong thing entirely. A bare `.insert()` sends
> `Prefer: return=minimal` and is what the app does.

Then add a case to `test/services/voice_query_parser_test.dart`. The suite runs
in under a second.

### Numbers are part of the address

Bangladeshi addresses *are* numbers — Dhanmondi road 32, Uttara sector 18,
Mirpur 10 — and people say them as words. `_numberWords` therefore runs to 40,
in all three scripts, and `_foldNumberWords` turns them into digits inside a
place name. English two-token numbers ("thirty two") are merged; Bangla says
বত্রিশ in one word and needs no merging.

Two guards make that safe:

* A number only converts when **something precedes it**, so it is modifying a
  place rather than being one. Without it "char fasson" (a river island)
  becomes "4 fasson", and a lone misheard "bottris" becomes the place "32".
* `_addressWords` (sector, road, block, nombor…) are never suffix-stripped.
  "sector" ends in the Bangla genitive `-r`, and losing it gave "secto".

This class of bug is invisible from the outside, which is why it has tests:
Google does **not** reject "Dhanmondi bottris". It drops the word it does not
know and returns the whole 2 km neighbourhood — coordinates identical to plain
"Dhanmondi" — so a road-level search silently becomes an area search and
nothing anywhere reports a failure.

### Two traps worth knowing

**Bare vowels are never stripped.** Taking a trailing `i` off **banani** gives
"banan", which geocodes to nothing. An alias hit on the spoken form always wins
before stripping is attempted — that ordering is load-bearing and has a test.

**The table picks the ending, not the loop.** A word can look like it carries
several different case markers, so every candidate stem is generated and
`_placeAliases` decides which one was real. Committing to the first ending that
matched is what used to turn *sylhete* into "sylhe" (it should lose only the
`e`) and *chittagonge* into a non-place. Only when no stem is recognised does
the longest strip win, and the runner still retries with the spoken form.

So a missing word costs you the whole query: **dhakay room dekho** searched for
the literal sentence, because `-ay` was not a known ending and `dekho` was not
a known verb, so both landed in the place name. Adding one suffix and one verb
fixed a whole class — every `-e`/`-y` locative and every bare imperative.

## The fallback is deployed

`voice-parse` was deployed and `GEMINI_API_KEY` set on 2026-08-22, running
`gemini-3.5-flash-lite`. Verified live through the same call the app makes:

```
"dhanmondi bottris e basa lagbe" → place "Dhanmondi 32", fullHouse   (1.0 s)
"haspatal er kache room lagbe 8k" → room, 8000, medical              (1.1 s)
"ami kichu chai please"           → {"parsed": false}
```

Guards checked too: no auth → 401, GET → 405, empty transcript → 400.

To redeploy after an edit:

```bash
supabase functions deploy voice-parse
```

If the key is ever removed the fallback simply stops firing — the function
500s, `RemoteVoiceParser` swallows it, and the lexicon answers alone.

### Use a paid key, not the free tier

Google's own pricing page draws the line explicitly:

| Tier | Data policy |
|---|---|
| Free | "Content used to improve our products" |
| Paid | "Content **not** used to improve our products" |

Voice transcripts are user speech. `voice_search_log` already treats them as
private — insert-only, no select policy, unreadable even by the person who
spoke — and a free key would quietly undo that for the sake of a few cents.

Measured, not estimated: **363 input + 48 output tokens** per call at
`gemini-3.5-flash-lite` ($0.30 / $2.50 per 1M).

| Fallback calls / month | Cost |
|---|---|
| 1,000 | ~$0.23 |
| 10,000 | ~$2.30 |

Only tail queries reach it, so this is a fraction of total voice searches.
A bigger model changes the arithmetic a lot — `gemini-3.7-flash` is
$0.75 / $3.75, roughly 3× again.

### Model IDs rot — twice, in one afternoon

`gemini-2.0-flash` was shut down while this function was being written. Then
`gemini-2.5-flash-lite`, which **ListModels still returns**, answered
`generateContent` with *"no longer available to new users"*. Listing a model
is not the same as being able to call it.

So the id is a secret, not a constant:

```bash
supabase secrets set GEMINI_MODEL=gemini-3.7-flash
```

### Why gemini-3.5-flash-lite

Chosen by measurement. Nine real Banglish/Bengali sentences, both candidates
scoring 9/9 — but on `"bosundhara r-a block e basa"`:

| Model | Answer |
|---|---|
| `gemini-3.1-flash-lite` | `Bashundhara R/A Block **A**` — invented a block letter |
| `gemini-3.5-flash-lite` | `Bashundhara R/A Block` — stopped where the evidence stopped |

Bashundhara R/A is large enough that a wrong block is a wrong journey. The
cheaper model was rejected for hallucinating, not for price.

Re-run that comparison against any candidate before switching.

## Cost if you ever outgrow it

The free path covers Android and Chromium browsers. If Safari/Firefox coverage
or free-form phrasing ever becomes worth paying for:

- **Cloud STT** (Safari/Firefox Bangla): Google STT v2, ~$0.016/min, 60 free
  min/month ≈ 900 free queries.
- **LLM parsing** (unbounded phrasing): ~$1.60 per 1,000 with Haiku 4.5,
  ~$8 with Opus 5, assuming ~1,200 input and ~80 output tokens.

Neither is wired up. Both would slot in behind the existing interfaces —
`VoiceSpeechService` for the first, `VoiceQueryParser` for the second.

## Android platform folder (history)

Commit `ef97d8b7` ("build remvoed", 2026-08-07) set out to delete two build
artifacts — `android/build/reports/problems/problems-report.html` and
`android/hs_err_pid9668.log` — and took the entire Android platform folder with
them: the manifest, both `build.gradle.kts` files, `settings.gradle.kts`,
`MainActivity.kt`, `google-services.json`, all launcher icons and styles, and
`android/.gitignore`. Commit `96648e54` then re-added `gradlew` and 33 MB of
`android/.gradle` caches — exactly the files the deleted `.gitignore` would
have blocked — leaving the folder looking populated while the app could not be
built at all.

Everything except the two genuine artifacts was restored from `ef97d8b7^`, so
the curated configuration survives intact rather than being replaced by
`flutter create` defaults:

- `applicationId` / `namespace` = `co.iobytes.musafir`, matching the
  `package_name` in `google-services.json` — a regenerated folder would have
  used a default id and silently broken Firebase and Maps
- The Maps key stays a `${GOOGLE_MAPS_API_KEY}` manifest placeholder fed from
  git-ignored `local.properties`, never a literal in the manifest
- Release signing still falls back to debug when `key.properties` is absent
- The `PROCESS_TEXT` / `https` / `geo` package-visibility queries that
  `url_launcher` needs on API 30+ are preserved

`android/.gradle` was untracked (`git rm -r --cached`, files left on disk).
`gradlew`, `gradlew.bat` and `GeneratedPluginRegistrant.java` are still tracked
even though `android/.gitignore` lists them; they are harmless and CI may
expect them, so they were left alone.
