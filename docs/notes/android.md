# Android: permissions and forced updates

Moved verbatim from `CLAUDE.md` on 2026-10-01 to keep that file small.
The short rule for each section is still in `CLAUDE.md`; the reasoning is here.

## Android

**Do not strip `RECORD_AUDIO`.** Voice search needs it — Android's recogniser
refuses without it — and `speech_to_text` does *not* declare it in its own
manifest, so the app manifest is the only thing supplying it.
`camera_android_camerax` happens to declare it too, which makes it look
redundant. It is not.

`CAMERA` is the opposite case: `camera_android_camerax` declares it and the
merger folds it in, so it needs no entry of its own.

### Play updates silently; the app only covers the gap

Play replaces an installed app on its own, over Wi-Fi, with no prompt — so
nothing in `AppUpdateService` *delivers* an update. It covers the hours-to-days
gap before Play gets round to it, and that gap matters here in a way it never
does on web.

**Web cannot have this problem; Android can.** `build/web` and the database are
deployed by the same hands, so a visitor's bundle always matches. An APK is on
a phone. And the client picks its PostgREST overload by the **keys it sends**
(see 112 and 118 above), so a build predating a migration can ask for a
signature that no longer exists — which `searchListingsFromDb`'s catch renders
as *"no results"*, not as an error. The user sees an empty, working-looking app.

`android_min_version_code` (122) is the lever: set it to the first versionCode
that speaks the current schema and older builds are pushed through Play's
blocking updater at launch, with no release needed to make it happen.

- **Play's answer is checked before the admin's number, and that ordering is
  the whole safety argument.** `appUpdateActionFor` returns `none` whenever
  Play reports no available update, whatever the floor says. An immediate
  update asks Play to install something newer; with nothing newer to install
  the flow cannot complete and the app is bricked for everyone at once, from a
  text box, and the fix would be a release the locked-out users could not
  reach. A floor typed above any published release is therefore one forced
  update to the newest build, then silence. There is a negative-control test
  for exactly this; do not reorder those two checks.
- **Zero forces nobody**, and it is the seed, the fail-open value, and what
  anything malformed parses to. This is the one setting that can take the app
  away from a user, so fail-open has to mean *don't*.
- **Nothing server-side enforces it, deliberately.** Refusing an old client's
  RPCs would be a second enforcer of a rule with no way to explain itself — the
  old build would render the refusal as an empty screen, which is the failure
  this exists to prevent.
- **A routine update is an offer, never a block.** The `immediateAllowed`
  fallback exists only on the forced path; seizing the screen for a release
  nobody declared required is hostile, and Play's own updater will get there.
- **A flexible download that is never completed sits on disk forever.** Play
  does not re-announce it, so the service re-offers "Restart to finish" on
  every resume, and re-checks `InstallStatus.downloaded` before looking for
  anything newer.
- `checkForUpdate()` **throws for any install Play does not own** — debug
  builds, sideloaded APKs, emulators without Play services, no network. All are
  silent and retried on the next resume. So this cannot be tested by running
  the app; it needs a Play-installed build, which is why the policy is a pure
  function (`lib/services/update/app_update_decision.dart`) with its own tests
  and the service holds no decisions at all.
- **`package_info_plus` is pinned to 9.x on purpose.** `AppUpdateInfo` reports
  what Play *has*, never what is installed, so the floor needs
  `PackageInfo.buildNumber`. 10.1.0+ moved to `win32 ^6`, which `share_plus`
  10.1.4 refuses — taking it means taking `share_plus` 11, whose API is a
  rewrite at every call site. `buildNumber` is identical in both majors.
- An unreadable `buildNumber` is **0 = unknown, and never forces**. Not
  theoretical: it is an empty string on web.

`WebUpdateService` is the other half of this and the two are shaped alike on
purpose — same singleton, same `start(onUpdateAvailable:)`, same banner. They
solve different problems: that one only has to notice a long-lived tab, because
a reload always gets the newest build.
