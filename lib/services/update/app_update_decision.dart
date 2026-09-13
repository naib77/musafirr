/// Whether to interrupt an Android user about a newer build on Play, and how
/// hard.
///
/// ## Why this exists at all
///
/// Play already updates installed apps on its own, silently, over Wi-Fi. So
/// nothing here is about *delivering* the update — it is about the gap before
/// Play gets round to it, which is hours to days and entirely outside our
/// control.
///
/// That gap matters more here than in most apps because of the deploy-order
/// trap written up in CLAUDE.md: the client picks a PostgREST overload by the
/// keys it sends, so a build that predates a migration can ask for a function
/// that no longer exists — and `searchListingsFromDb`'s catch renders that as
/// "no results" rather than as an error. On web the bundle and the database
/// ship together and the problem cannot arise. On Android the old build is on
/// someone's phone, and the only lever left is to ask them to update.
///
/// ## Why the decision is a pure function
///
/// The interesting part is not the Play API, it is the policy — and the policy
/// has one rule that is genuinely dangerous to get wrong (see
/// [appUpdateActionFor]). Extracting it the way `speech_locale.dart` and
/// `selfie_camera.dart` were extracted means that rule has tests without a
/// device, a Play Store account, or a published release to update *from*.
/// Nothing in this file imports the plugin.
library;

/// What to do about an available update.
enum AppUpdateAction {
  /// Leave it to Play's own background updater.
  none,

  /// Offer it. The app stays usable; the download runs behind it.
  flexible,

  /// Block the app behind Play's full-screen updater. Reserved for builds the
  /// admin has declared too old to talk to the current database.
  immediate,
}

/// The value of `android_min_version_code` that means "never force anyone".
///
/// Zero rather than null so the comparison in [appUpdateActionFor] is a plain
/// `<` with no special case: no real versionCode is below it.
const int kNoForcedUpdate = 0;

/// Play's ceiling for a versionCode. A number above this cannot name a real
/// release, so treating it as the floor would only ever be a typo that forces
/// an update nobody can satisfy.
const int kMaxVersionCode = 2100000000;

/// Reads the raw `android_min_version_code` cell.
///
/// Absent, blank, non-numeric or out of range all fall back to
/// [kNoForcedUpdate] rather than throwing, for the same reason
/// `bookingAcceptWindowFromRaw` does: `AppSettingsService` fails open, and the
/// fail-open direction for a *forced* update has to be "don't force" — a
/// malformed row must never be able to lock users out of the app.
///
/// Mirrors migration 122's validator exactly. A value this clamps is a value
/// that validator would have refused at the keystroke, so the clamping is for
/// rows written before the guard existed.
int minSupportedVersionCodeFromRaw(String? raw) {
  final text = raw?.trim();
  if (text == null || text.isEmpty) return kNoForcedUpdate;
  final code = int.tryParse(text);
  if (code == null || code < 0) return kNoForcedUpdate;
  if (code > kMaxVersionCode) return kNoForcedUpdate;
  return code;
}

/// Reads this build's own versionCode out of `PackageInfo.buildNumber`.
///
/// Returns 0 — "unknown" — for anything unparseable, which [appUpdateActionFor]
/// treats as "never force". That is not a theoretical branch: `buildNumber` is
/// an empty string on web, and a `flutter run` of a locally-built APK has been
/// seen to report a version string rather than a number.
int installedVersionCodeFromRaw(String? raw) {
  final code = int.tryParse(raw?.trim() ?? '');
  if (code == null || code < 0) return 0;
  return code;
}

/// Decides what to do, given what Play said and what the admin configured.
///
/// [updateAvailable] is Play's `UpdateAvailability.updateAvailable`, reduced to
/// a bool so this file need not import the plugin. [flexibleAllowed] and
/// [immediateAllowed] are Play's own verdicts on which flows it can run for
/// this device and release.
///
/// **The load-bearing rule is the first one: no update available means
/// [AppUpdateAction.none], whatever the floor says.** Forcing an immediate
/// update is asking Play to install something newer; if Play has nothing
/// newer, the flow cannot complete and the app is bricked for every user at
/// once, from a text box in the admin portal, with no way back in — the fix
/// would have to be a new release, which is the one thing nobody could then
/// reach. Deriving "is this build too old" from a number an admin typed is
/// only safe because Play's answer is checked first.
///
/// A floor set higher than anything Play actually has is therefore not a
/// lock-out but a single forced update: the user is pushed to the newest
/// release, which still sits below the typo'd floor, and the check after it
/// finds no update available and falls quiet.
///
/// An unknown [installedVersionCode] (0) never forces, because "0 < floor" is
/// true for every floor and the comparison would otherwise be read as "this
/// build is ancient" every time the version could not be parsed.
AppUpdateAction appUpdateActionFor({
  required bool updateAvailable,
  required bool flexibleAllowed,
  required bool immediateAllowed,
  required int installedVersionCode,
  required int minSupportedVersionCode,
}) {
  if (!updateAvailable) return AppUpdateAction.none;

  final tooOld = installedVersionCode > 0 &&
      minSupportedVersionCode > kNoForcedUpdate &&
      installedVersionCode < minSupportedVersionCode;

  if (tooOld) {
    // Play decides whether an immediate update is possible on this device; if
    // it is not, a flexible one is still better than leaving a build we have
    // declared incompatible talking to the database.
    return immediateAllowed
        ? AppUpdateAction.immediate
        : (flexibleAllowed ? AppUpdateAction.flexible : AppUpdateAction.none);
  }

  // A routine update is an offer, never an interruption. Note the deliberate
  // absence of an `immediateAllowed` fallback here: blocking the app behind a
  // full-screen updater for a release nobody said was required is hostile, and
  // Play's own background updater will get there on its own.
  return flexibleAllowed ? AppUpdateAction.flexible : AppUpdateAction.none;
}
