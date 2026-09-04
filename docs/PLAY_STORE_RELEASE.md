# Shipping Musafir to Google Play

Written 2026-08-26 against Flutter 3.44.4, `applicationId co.iobytes.musafir`,
`version: 0.1.0+1`. This is the first-ever production submission, so it covers
the one-time account setup as well as the build.

**Console:** [app list for developer 8303259483353847512](https://play.google.com/console/u/3/developers/8303259483353847512/app-list).
The click-by-click walkthrough is §7; §§1–6 are the things to have ready before
you start clicking.

`docs/WEB_DEPLOYMENT.md` is the web story; this file is Android only — with one
exception. The legal pages Play requires (§5) are served by the web app, so
shipping them means a `build/web` rebuild and deploy. That is the only step here
that touches the web bundle.

---

## 0. Blocker status

Found 2026-08-26, addressed the same day. None of these stopped
`flutter build appbundle` from succeeding — each one stopped the result from
being *shippable*, which is the failure mode this section exists to catch.

| # | Blocker | Status |
|---|---------|--------|
| 1 | No upload keystore — release fell back to **debug signing** | **Fixed.** Upload key generated, `android/key.properties` written, release APK verified signed by `CN=Musaafir` (SHA-1 `2F:47:6C:81:…:97:CA`), not `CN=Android Debug`. |
| 2 | Launcher icon was the stock Flutter logo | **Fixed.** Real adaptive icon (background + foreground + Android 13 monochrome), legacy + round PNGs at all five densities, and a 512×512 store icon — all derived from the supplied brand artwork by `tool/gen_brand_assets.py`. |
| 3 | Privacy policy URL was dead (`musaafir.app` does not resolve) | **Source fixed, needs a deploy.** Policy, terms and account-deletion pages written under `web/legal/`; `legal_links.dart` repointed at the live Worker origin. Not reachable until `sh tool/build_web.sh` + commit + deploy — see §5. |
| 4 | QA master OTP `1234` | **Fixed.** `MASTER_OTP` and `MASTER_OTP_PHONES` unset from the live project on the owner's instruction. The live value was `*` — the wildcard — so this really was an any-number bypass. §6.4. |
| 5 | Google Maps key unrestricted and shared across surfaces | **Partly fixed; the restriction itself is blocked.** Copies of the literal removed from `README.md` and the iOS `.example`. The actual key split + restriction needs Google Cloud Console and a SHA-1 that does not exist until the first Play upload — §2.4. |
| 6 | `READ_MEDIA_IMAGES` requested, Android Photo Picker unused | **Fixed, and it was worse than it looked.** Photo Picker enabled; both permissions gone from the built APK. See §6.3 — removing them from our manifest was *not* sufficient. |

Already fine, no action needed:

- **`targetSdk`** — `flutter.targetSdkVersion` is **36** on 3.44.4, confirmed in
  the built APK. Play requires API 36 for new apps from 2026-08-31.
- **`minSdk` 24** — well above any Play floor.
- **`INTERNET`** is in the release manifest (Flutter only auto-adds it to
  debug/profile; someone already caught that).
- **No background location** — only foreground `ACCESS_*_LOCATION`, which avoids
  Play's background-location review entirely. Keep it that way.
- **`RECORD_AUDIO` survived** all of the above, which matters:
  `speech_to_text` does not declare it and Android's recogniser refuses without
  it (`CLAUDE.md`).

### Verifying it stayed fixed

Two of these regress silently on a dependency bump, so check the **built
artifact**, never the source:

```sh
BT="$HOME/Library/Android/sdk/build-tools/37.0.0"
APK=build/app/outputs/flutter-apk/app-release.apk

# #1 — must NOT say CN=Android Debug
"$BT/apksigner" verify --print-certs "$APK" | grep DN:

# #6 — must print nothing at all
"$BT/aapt2" dump permissions "$APK" | grep -E 'READ_MEDIA_IMAGES|READ_EXTERNAL_STORAGE'

# and RECORD_AUDIO must still be there
"$BT/aapt2" dump permissions "$APK" | grep RECORD_AUDIO
```

---

## 1. Play Console account — DONE

An **organization** account exists, registered with a D-U-N-S number, developer
id `8303259483353847512`. Two consequences worth knowing before you plan
anything:

- **You are exempt from the 12-testers / 14-days rule.** That requirement applies
  only to *personal* accounts created after 2023-11-13. Organization accounts
  registered to a legal entity skip it entirely, so you can go from upload to
  production review without a mandatory 14-day closed test. Run an internal test
  anyway (§7.6) — by choice, for a day, not for three weeks.
- The US$25 fee and identity verification are already behind you.

Still open on the account itself:

- **A payments profile** is only needed for a paid app or Play-billed in-app
  purchases. Musaafir is neither: it is free, there is no `in_app_purchase` or
  Play Billing library in the APK (verified), and SSLCommerz charges for a
  real-world service (a stay) rendered off-app, which sits **outside** Play's
  billing requirement. Say so plainly in the review notes (§8) so a reviewer does
  not read it as billing circumvention.
- **Free vs paid is a one-way door.** You can move paid → free later, never free
  → paid. Pick deliberately in §7.1.

## 2. Make the build signable and shippable

### 2.1 Generate the upload key — DONE

Already generated at `~/keys/musafir-upload.jks`, alias `upload`, RSA 2048,
valid until **2054-01-11**. Kept outside the repo. Losing it is recoverable via
Play (see 2.3); leaking it is not.

**Its fingerprints — you will need these in §2.4:**

```
SHA-1:   2F:47:6C:81:4F:41:C2:F4:68:74:E2:DF:4F:2D:57:A4:18:B4:97:CA
SHA-256: 3A:D7:D9:5D:00:CB:1B:8B:C0:2A:ED:E8:1C:E0:8A:3F:B7:5C:2A:7C:E7:5B:37:32:EF:15:B7:C8:CA:F4:CA:A4
```

<details><summary>How it was generated, if it ever needs redoing</summary>

```sh
keytool -genkey -v \
  -keystore "$HOME/keys/musafir-upload.jks" \
  -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
```

`-validity 10000` (~27 years) is Google's recommendation — an expired upload key
means you can no longer publish updates.

</details>

> **Back up the keystore and its password now.** The password is in
> `android/key.properties` (git-ignored, mode 600) and nowhere else. Copy both
> into a password manager and keep an offline copy of the `.jks`. If you lose
> them before the first upload you simply regenerate; if you lose them *after*,
> you need a Play upload-key reset and a support round-trip.

### 2.2 Wire it in — DONE

`android/key.properties` is written and picked up. Notes for whoever touches it
next:

- `android/.gitignore` already ignores `key.properties`, `*.jks`, `*.keystore`;
  `git check-ignore -v android/key.properties` confirms it.
- The `storeFile` path is **absolute** on purpose. `build.gradle.kts` resolves it
  with `file(...)` from the `:app` module, so a relative path would resolve
  against `android/app/`, not the repo root.

Verified: `flutter build apk --release` produces an APK signed
`CN=Musaafir, OU=Musaafir, O=iObytes, L=Dhaka, ST=Dhaka, C=BD`, SHA-1
`2f476c81…97ca` — matching the upload key, not `CN=Android Debug`.

Note that the APK is **v2-signed only**, with no v1 JAR signature, so there is no
`META-INF/*.RSA` to inspect and `unzip -p … | keytool -printcert` prints nothing.
Use `apksigner`, which reads all signature schemes:

```sh
"$HOME/Library/Android/sdk/build-tools/37.0.0/apksigner" \
  verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

### 2.3 Play App Signing

Play re-signs with its own **app signing key**; yours is only the **upload
key**. Consequences:

- The SHA-1/SHA-256 that end users' devices see is Play's, **not** your
  keystore's. This matters for §2.4 and for anything else keyed on the cert.
- If you lose the upload key you can request a reset. If Play holds the app
  signing key, users are never locked out.

### 2.4 Restrict the Maps key (blocker #5 — YOU MUST DO THIS BY HAND)

There are three `AIza…` keys in the repo, and only one is a problem:

| Key | Where | Verdict |
|---|---|---|
| `AIzaSyBw1u…` | `web/index.html`, `android/local.properties`, and (until now) `README.md` × 6 and the iOS `.example` | **This is the Maps key, and it is one key doing web + Android + iOS + REST.** Split and restrict it. |
| `AIzaSyAzZ0…` | `android/app/google-services.json` | Firebase Android key. Normal to commit; scoped by Firebase. Leave it. |
| `AIzaSyD3jQ…` | `lib/config/firebase_web_config.dart`, `web/firebase-messaging-sw.js` | Firebase **web** key. Public by design. Leave it. |

Already done: the literal was removed from `README.md` and from
`ios/Flutter/Maps.local.xcconfig.example` — an `.example` file carrying a real
key defeats the point of being an example. Note that the README's
`--dart-define=GOOGLE_MAPS_API_KEY=…` was a **no-op** for the Android Maps SDK:
no Dart code reads that variable, and the native key reaches the manifest from
`local.properties`. Those commands were giving false confidence, so they now
carry `$GOOGLE_MAPS_API_KEY` instead.

Scrubbing does **not** undo the exposure — the key is in git history and in the
deployed `build/web/index.html`. Only rotation does. And rotation is on you:
there is no `gcloud` on this machine, and the Play app-signing SHA-1 does not
exist until the first upload.

After the first upload, Play Console → **Test and release → Setup → App
signing** shows both certificates. Then in Google Cloud Console → Credentials:

1. Create a **new, Android-only key** (do not keep reusing the shared one).
2. Restrict it: *Application restrictions → Android apps*, and add **both**
   entries — package `co.iobytes.musafir` with the **Play app signing SHA-1**
   (for store installs) **and** with the **upload SHA-1**
   `2F:47:6C:81:4F:41:C2:F4:68:74:E2:DF:4F:2D:57:A4:18:B4:97:CA` (for local
   release builds and internal-testing sideloads). Miss the first and maps go
   blank for every real user while working perfectly on your machine.
3. Restrict it by API: Maps SDK for Android + whatever Directions/Geocoding the
   app actually calls.
4. Put it in `android/local.properties` as `GOOGLE_MAPS_API_KEY=...`
   (already git-ignored, already read by `build.gradle.kts`).
5. Separately, mint an **HTTP-referrer-restricted** key for
   `web/index.html` (locked to `musafirr.knaib77.workers.dev` and any real
   domain), a third for iOS, and then **delete `AIzaSyBw1u…`** so the
   history-leaked copy stops working. Until that deletion, everything else here
   is mitigation, not a fix.

### 2.5 Version numbering

`pubspec.yaml`'s `version: 0.1.0+1` becomes `versionName 0.1.0` /
`versionCode 1`.

- **`versionCode` must strictly increase and can never be reused** — not even
  for a build you deleted. Bump the `+N` on every single upload, including
  failed ones.
- Consider starting at `1.0.0+1` so the store doesn't advertise `0.1.0`.

## 3. Icons and branding (blocker #2 — DONE, with one caveat)

The five `ic_launcher.png` files were Flutter's own logo — someone else's
trademark, shipped as our brand. Replaced with the real Musaafir mark knocked
out in white on flat brand rose `#C35063`, generated by
**`tool/gen_brand_assets.py`** from the artwork committed under
`assets/brand/source/`:

- `mipmap-anydpi-v26/ic_launcher.xml` + `ic_launcher_round.xml` — adaptive icon
  with background, foreground **and** an Android 13 `<monochrome>` layer for
  themed icons.
- `drawable/ic_launcher_background.xml` — the flat rose as a shape drawable
  referencing `@color/brand_launch_background`, so it stays crisp at any
  launcher mask size, costs no APK bytes, and cannot drift from the launch
  window's colour.
- Legacy `ic_launcher.png` (rounded) and `ic_launcher_round.png` (circular) at all
  five densities, for API 24–25, which predates adaptive icons.
- `android:roundIcon` added to the manifest.
- `store/play/icon-512.png` — the §4 listing icon: 512×512, RGB with **no alpha**
  and no corner rounding of our own, because Play applies its own mask and a
  pre-rounded upload gets double-rounded.

The foreground mark is 43.2dp on the 108dp canvas, well inside the 66dp circle
every launcher mask is guaranteed to spare. That figure is not a taste call: a
launcher shows only the centre 72dp, so 43.2/72 = 60% of the visible icon —
exactly the fraction the iOS, web and Play icons use, which is what makes the
same app's icon look the same on every platform. It previously sat at 56dp,
reading as 78% visible against their 60%, so Android looked zoomed in by
comparison. Verified by compositing the layers under circular, squircle and
square masks.

An earlier pass of these icons was generated with the mark's bounding box
measured *including* keyed drop-shadow speckle, which reached the edge of the
source canvas. That silently scaled the mark to 87% of its intended size and
left `icon.png` 41px off-centre on 1024. `gen_brand_assets.py` now applies a
levels floor before measuring — see `assets/brand/README.md`. If you regenerate
and the mark changes size, that is why.

**It is a competent placeholder, not a designed identity.** When a designer
supplies a real mark, replace `draw_mark()` in the generator and re-run, rather
than hand-resizing five exports.

Two things deliberately left alone:

1. **`web/icons/*` and `web/favicon.png` are still the stock Flutter web icons.**
   Changing them means a `build/web` rebuild, and your working tree already has
   pending `build/web` changes from the `perf/web-immutable-bundle` work. Not a
   Play blocker — do it with the §5 deploy.
2. `web/manifest.json` and the `index.html` spinner hardcode teal by design (see
   `CLAUDE.md`) — browser splash chrome, not theme-driven. Noted so you don't go
   hunting.

One naming decision still open: `android:label` is `"Musaafir"` (two a's) while
the package and repo say `musafir`. Pick one for the store name; a mismatch
between the listing and the on-device label reads as sloppy.

## 4. Store listing assets

Prepare before you open the form; it does not save well half-finished.

| Asset | Spec | Notes |
|---|---|---|
| App name | ≤ 30 chars | See §3 on the spelling |
| Short description | ≤ 80 chars | Shown in search results |
| Full description | ≤ 4000 chars | Keyword-relevant, no ranking claims, no "#1" |
| App icon | 512×512 PNG, 32-bit, no alpha | |
| Feature graphic | 1024×500 PNG/JPG, no alpha | **Required.** Shown at the top of the listing |
| Phone screenshots | 2–8, min 320px, max 3840px, ≤ 2:1 ratio | Real UI. No device frames with fake bezels+marketing text over the whole shot |
| Tablet screenshots | 7" and 10" | Optional but the listing is down-ranked on tablets without them |
| Category | Travel & Local, or House & Home | Travel & Local fits guest↔host stays |
| Contact email | Must be reachable | `support@musaafir.app` needs to actually receive mail (§5) |

Content rating: fill the IARC questionnaire (Play generates ratings from it).
Musafir has user-generated content and user-to-user messaging — answer **yes** to
UGC and to user interaction. Lying here is a policy violation; answering yes
just adds requirements (§6.4), it does not sink the app.

## 5. Privacy policy and support surface (blocker #3 — WRITTEN, NEEDS DEPLOY)

`musaafir.app` does not resolve at all, so every legal link in the app was dead.
Play requires a privacy policy URL that is publicly reachable, not behind a
login, and specific to this app; with location + camera + mic + phone numbers in
play, it is a hard gate. It also requires a **separate** account-deletion URL,
reachable **without installing the app** — a policy page that merely mentions
deletion does not satisfy it, and that field is easy to miss.

Written, as plain static HTML under `web/legal/`:

| File | Serves |
|---|---|
| `privacy.html` | Every category actually collected, read off the code: phone, name, optional email, avatar, foreground location, listing photos and coordinates, bookings, chat, reviews, **NID number + ID images + selfie**, address proof, payout details, push token, and transient mic audio. Names all seven third parties — Supabase, Google Maps, FCM, Google's recogniser, Gemini, the GenNet SMS gateway, SSLCommerz. |
| `terms.html` | Marketplace-not-landlord framing, guest and host duties, payments/payouts incl. cash and SSLCommerz, UGC licence, prohibited conduct, reporting, liability limits, Bangladesh governing law. |
| `delete-account.html` | The deletion request route, what is deleted, what survives and why, and the 30-day commitment. |

They live under `web/`, so `flutter build web` copies them into `build/web` and
the existing Worker (`wrangler.jsonc` → `assets.directory = ./build/web`) serves
them. No new hosting. `web/legal/_shared.md` documents this next to them and is
underscore-prefixed so Flutter's build skips it — the same quirk that makes
`tool/build_web.sh` copy `web/_headers` by hand.

`lib/config/legal_links.dart` now points at
`https://musafirr.knaib77.workers.dev/legal/…`, same origin as the app, so the
link in the store listing and the link behind Profile → Support are literally the
same page and neither can rot while the other works. If `musaafir.app` is later
pointed at the Worker, change `_origin` and every link moves with it.

### What is still on you

1. **Deploy them.** They are source-only right now, and per `CLAUDE.md` a
   source-only commit ships stale code. Run `sh tool/build_web.sh`, commit the
   rebuilt `build/web`, deploy, then `sh tool/verify_deploy.sh`. Your working
   tree already has pending `build/web` changes from the
   `perf/web-immutable-bundle` work — reconcile those first so you know what you
   are shipping. **Until this is deployed, blocker #3 is not actually fixed:**
   the URLs 404.
2. **Make `support@musaafir.app` receive mail.** It is the contact address in the
   listing, the only route for the deletion requests the page promises, and where
   Google emails you. The domain does not resolve today, so the mailbox almost
   certainly does not exist. A promised deletion route that bounces is worse than
   no page at all.
3. **Have a lawyer read them.** The factual claims are accurate as of
   2026-08-26 — they were read off the code, not templated — but the wording is
   not reviewed, and Bangladesh has no single omnibus data-protection statute to
   template against.
4. **Optional but better:** build an in-app account-deletion flow. There is none
   today (`grep -rn deleteAccount lib/` is empty), so the page documents an email
   request. Play accepts that; an in-app path is the stronger answer, and
   `LegalLinks.deleteAccountUrl` is not yet surfaced anywhere in the UI.

## 6. Data safety and declarations

### 6.1 Data safety form (Policy and programmes → App content)

Self-declared, and Play cross-checks it against the binary. Declare at minimum:

- **Personal info** — Name, Phone number. Collected, sent off-device, tied to
  identity. Not shared with third parties for ads.
- **Photos** — collected (listing photos, avatar, **ID document, selfie**).
- **Location** — Approximate **and** Precise. Foreground only.
- **Messages** — in-app messages between guest and host.
- **Audio** — voice search. The recogniser is Google's and we never receive or
  store the audio, so the defensible answer is *not collected*. Declaring it
  collected/ephemeral/not-shared is the safer answer and costs nothing.
- **Encryption in transit** — yes. **Deletion request path** — yes (§5).

The ID/selfie documents are the sensitive part. Be explicit that they exist and
are used for host verification; misdeclaring identity documents is the kind of
thing that gets an app suspended rather than rejected.

### 6.2 Permissions Play will ask about

`RECORD_AUDIO` — declare it as voice search. Do **not** strip it (`CLAUDE.md`:
`speech_to_text` does not declare it itself, and Android's recogniser refuses
without it).

### 6.3 Photo and Video Permissions (blocker #6 — DONE, and it was worse than it looked)

The manifest requested `READ_MEDIA_IMAGES`, and `image_picker_android` 0.8.13+17
defaults `useAndroidPhotoPicker = false`, so the app took broad gallery access
where the system Photo Picker would do. Play's Photo and Video Permissions policy
requires a declaration for that and grants it only where broad access is core to
the app — picking a few listing photos is not that.

Fixed in two parts, because **the obvious half was not enough**:

1. `lib/main.dart` now sets `useAndroidPhotoPicker = true` before anything can
   pick, and the two permissions came out of `AndroidManifest.xml`. The Photo
   Picker returns a per-URI grant, so no permission is needed. `file_picker`
   (used for documents) goes through `ACTION_GET_CONTENT`/SAF and needs none
   either — both plugins' own manifests declare no storage permission.

2. **The built APK still had `READ_EXTERNAL_STORAGE` — uncapped, on every API
   level.** `camera_android_camerax` requests `WRITE_EXTERNAL_STORAGE`, and the
   manifest merger *implies* a matching read permission from it. Nothing in the
   app ever asked for it, and no source file mentioned it. The merger report is
   what named the culprit:

   ```
   uses-permission#android.permission.READ_EXTERNAL_STORAGE
   IMPLIED from …/AndroidManifest.xml reason: io.flutter.plugins.camerax
                                              requested WRITE_EXTERNAL_STORAGE
   ```

   Refusing an *implied* permission takes `tools:node="remove"`, which the
   manifest now carries with the reasoning inline.

   `WRITE_EXTERNAL_STORAGE` is deliberately left: the merger caps it at
   `maxSdkVersion=28`, camerax may genuinely need it on API 24–28, and a capped
   legacy write permission is not what the photo/video policy is about. The
   uncapped **read** was the problem.

**The lesson generalises.** Editing `AndroidManifest.xml` tells you what you
asked for, not what shipped — 16 permissions reach the merged manifest and only 8
come from this repo. After any plugin bump, check the artifact:

```sh
aapt2 dump permissions build/app/outputs/flutter-apk/app-release.apk
```

Nothing in the build will warn you. This is the Android sibling of the stale
plugin registrant trap in `CLAUDE.md`: source looks right, artifact is wrong.

### 6.4 The QA master OTP (blocker #4 — FIXED)

`MASTER_OTP` and `MASTER_OTP_PHONES` were unset from the live project
(`bojkmonskqlhuakxhzcb`) on 2026-08-26, on the owner's explicit instruction.
`secrets list` confirms neither remains. `isMasterOtp()` returns false when
`MASTER_OTP` is empty, so there is now no login bypass for any phone number.

**It was worse than the repo claimed.** `README.md` recorded the secret being set
to a single number (`MASTER_OTP_PHONES='1673293542'`), which would have scoped the
bypass to one phone. The live value was `*` — the wildcard branch of
`masterOtpAllPhones()` — meaning `1234` logged into **any** number on the
platform, and had done since 2026-08-07.

That was established without ever seeing the plaintext: the Management API returns
each secret as a SHA-256 digest, so the digests were compared against candidate
values. `MASTER_OTP` hashed to `1234`; `MASTER_OTP_PHONES` hashed to `*`. Worth
remembering as a way to audit any Supabase secret against a suspected value
without reading it.

Two things this does **not** cover, both worth a decision:

1. **The window is not closed retroactively.** Anyone who knew the code could
   have signed in as any user for roughly 19 days. If that matters, audit
   `auth.users.last_sign_in_at` and the OTP audit trail for logins that do not
   match a real device, and consider invalidating existing sessions.
2. **The Dart side was never the exposure** and needs no change:
   `OtpConfig.masterOtpEnabled` is
   `bool.fromEnvironment('MASTER_OTP_ENABLED', defaultValue: false)`, so a plain
   `flutter build appbundle --release` never carried a bypass. Only the
   explicitly-labelled TESTER commands in `README.md` set it, and those are for
   sideloaded QA builds, never for Play.

Deliberately **not** verified by attempting a login: `CLAUDE.md` warns that
driving a login hits the real `send-otp` function and can send a real SMS, so it
must not be automated against a number you do not own. Confirm it by hand on a
number you control, and expect the Play reviewer to need a genuine test number
(§8) rather than a bypass.

### 6.5 UGC obligations

Because the app carries user listings, photos and chat, Play expects: a way for
users to **report** objectionable content and other users, a way to **block**
users, and a moderation process. `docs/SAFETY.md` may already cover some of
this — confirm the report/block affordances exist in the UI, because a reviewer
looks for them.

## 7. The Play Console, screen by screen

Start at the [app list](https://play.google.com/console/u/3/developers/8303259483353847512/app-list).
Left-nav paths below are current as of 2026-08; Google reorganises this nav every
year or so, so treat the *names* as the stable part and the nesting as a hint.

> **Nothing you fill in goes live when you save it.** The Console batches edits
> and waits for you to submit them. When you are done, open **Publishing
> overview** and click **Send changes for review** — the count of pending changes
> is shown there. Every "why is nothing happening" story about Play Console ends
> here.

### 7.1 Create the app

**App list → Create app** (top right).

| Field | Answer |
|---|---|
| App name | ≤ 30 chars. **Settle the spelling first** — `android:label` says `Musaafir`, the package says `musafir` (§3). This is what users see; it can be changed later. |
| Default language | English (United States) unless you want Bengali as the default. The app already ships Bangla date formatting, so a `bn-BD` translation is a natural follow-up, added later under the store listing. |
| App or game | App |
| Free or paid | **Free.** One-way door — see §1. |
| Contact email | Collected here, not just in store settings. **Public on your listing**, and where Google writes to you — see the §7.5 warning about `support@musaafir.app` not existing yet. |
| Declarations | Developer Program Policies, **and** US export laws. Both required. |
| Play App Signing | You must accept the **Play App Signing Terms of Service**. Not optional and not reversible — it is what makes §2.3 and §7.7 work. |

That lands you on the app **Dashboard**, whose URL now contains the app id. Keep
that tab; every path below is inside it.

### 7.2 The Dashboard, card by card

The Dashboard does **not** present the left-nav structure. It presents collapsible
**task cards**, each with a **View tasks** link that expands into a checklist.
Completed tasks get a green tick and strikethrough. That guided flow is the thing
you actually click through; the left-nav paths in §§7.3–7.8 are just where each
task lives if you'd rather navigate straight to it.

You will see roughly these three cards. Google reorders and renames them, and
the exact set varies with the app, so **tick against your own screen, not against
this list**:

| Card | What it is | Covered in |
|---|---|---|
| **"Start testing now"** — *"Release your app early for internal testing without review"* | Internal test track. The operative words are **without review**: no policy review, so a build reaches testers in minutes instead of days. | §7.6 |
| **"Set up your app"** — *"Provide information about your app and set up your store listing"* | The policy declarations plus the store listing. This is the long one, ~13 tasks. | §7.3, §7.4, §7.5 |
| **"Publish your app on Google Play"** | Select countries and regions, then create the production release. | §7.8 |

There is usually a **Pre-registration** option too. Skip it — it publishes a
store listing before the app exists to collect sign-ups, which is a launch-marketing
tactic, not a step toward being live.

#### The order that actually saves you time

The cards are listed testing-first for a reason, and it is the opposite of how
§§7.3–7.8 are numbered:

1. **Try the internal-testing card first** (§7.6). "Without review" means minutes
   rather than days, so it is the cheapest way to get the real signed artifact
   onto a real device — and this build has three things that have never run on
   physical hardware: the Android Photo Picker (§6.3), the new adaptive icon, and
   a login with no master OTP. Find those before you spend an afternoon on
   declarations. If the Console makes you finish setup tasks first, fine — do
   them, they were mandatory regardless (see the callout below).
2. **Then the "Set up your app" card** (§7.3–§7.5), which is where the waiting is:
   the privacy policy URL has to be live, the support mailbox has to exist, and
   the content-rating questionnaire has to be answered.
3. **Then publish** (§7.8).

> **If "Create new release" is greyed out, the button is not broken.** Google's
> instruction is the same on every track page, internal included: *complete the
> outstanding setup tasks listed on your Dashboard.* So go back to the "Set up
> your app" card and find the unticked task.
>
> What "without review" buys you is the **review wait**, not a blanket exemption
> from setup — an internal release skips policy review and reaches testers in
> minutes, where production review takes days. How much of the card the internal
> track insists on first is not something this doc can promise; find out by
> trying it, which costs one click. If it lets you upload, you have saved
> yourself a day. If it doesn't, work the card and come back — you lose nothing,
> because those tasks were mandatory anyway.

### 7.3 "Provide information about your app" — the declaration tasks

This is the bulk of the **"Set up your app"** card. Each row below is one task in
that checklist; they also all live under **Policy and programmes → App content**
if you prefer navigating directly. Every one must be ticked before the production
**Create new release** button un-greys (§7.2).

Answers for Musaafir, most of them verified against the built APK rather than
guessed:

| Declaration | Answer | Why |
|---|---|---|
| **Privacy policy** | `https://musafirr.knaib77.workers.dev/legal/privacy.html` | §5. **Must be live before you paste it** — the Console fetches it, and it 404s until you deploy. |
| **App access** | *All or some functionality is restricted.* Provide reviewer credentials. | The app is phone-OTP gated. **See §7.4 — this needs a real decision, not just a form fill.** |
| **Ads** | **No**, this app does not contain ads | Verified: no `play-services-ads`, no AdMob, no ad SDK of any kind in the APK. |
| **Content ratings** | Start the IARC questionnaire | Pick the category covering user-generated content / social. Answer **yes** to UGC, **yes** to user-to-user communication, **yes** to sharing location. Lying here is a policy violation; answering yes only adds the §6.5 obligations. |
| **Target audience and content** | **18 and over** only | Your own terms say 18+. Then "could appeal to children": **No**. |
| **Data safety** | The long form — see §6.1 | The most consequential one. Play cross-checks it against the binary. Declare the NID images and selfie honestly. |
| **Advertising ID** | **No**, my app does not use advertising ID | Verified: no `com.google.android.gms.permission.AD_ID` in the merged manifest, and no `firebase-analytics`. |
| **Financial features** | *My app doesn't provide any financial features* | SSLCommerz taking payment for a stay is not a financial product. This declaration is about loans, banking, crypto, investments and insurance — none apply. |
| **Health apps** | No | |
| **Government apps** | No | |
| **News apps** | No | |
| **Data deletion** | `https://musafirr.knaib77.workers.dev/legal/delete-account.html` | A **separate field** from the privacy policy, easy to miss. Must be reachable without installing the app. |

One thing that should *not* appear: the **Foreground service permissions**
declaration. `geolocator_android` contributes a
`GeolocatorLocationService` with `foregroundServiceType="location"`, which looks
alarming in the merged manifest — but no `FOREGROUND_SERVICE*` permission is
declared anywhere, so on `targetSdk 36` that service cannot legally start and the
app never tries. Nothing to justify. If the Console asks anyway, that vestigial
service is the honest explanation.

### 7.4 App access — the reviewer cannot receive your SMS

This is the step most likely to get a first submission rejected, and it now
collides with the master OTP being off (§6.4).

Login requires an OTP delivered by real SMS to a real Bangladeshi number. A Play
reviewer has neither that number nor the phone. Given credentials they cannot
use, they see a login wall, cannot exercise the app, and reject it for
inaccessible content.

**The right fix is the allowlist the code already supports.** `isMasterOtp()`
accepts a master code only for numbers in `MASTER_OTP_PHONES`, and only the
literal `*` means "every number". So:

```sh
# A dedicated reviewer number you control, and a code that is NOT 1234.
npx supabase secrets set \
  MASTER_OTP='<a non-obvious code>' \
  MASTER_OTP_PHONES='01XXXXXXXXX' \
  --project-ref bojkmonskqlhuakxhzcb
```

> **Get the number format right or it silently does nothing.**
> `masterOtpAllowlist()` runs each entry through `normalizePhone()`, which
> collapses `+880…` and `880…` to a **leading `0`** — so the canonical form is
> `01673293542`. Write it as `01673293542` or `+8801673293542` (both normalise to
> the same string). **Do not** write it as `1673293542` without the leading zero:
> that normalises to itself, never matches what the app sends, and the bypass
> just quietly fails to apply.
>
> That is exactly what the command recorded in `README.md` did —
> `MASTER_OTP_PHONES='1673293542'` — which is very likely why it ended up set to
> `*` instead. `*` worked, so the real bug was never found.

Then put that number and code in **App access** as the reviewer credentials.
Verify it yourself first, by hand, on that number.

Why this is not a reopening of blocker #4: the exposure there was the `*`
wildcard, which made `1234` work for *any* account on the platform. A
single-number allowlist with a non-guessable code reaches exactly one throwaway
account. Note it in `CLAUDE.md` when you do it, and remove it once the app is
live and stable.

The alternative — a permanent demo account with a hardcoded bypass — is more code
and a broader hole. Do not use `1234`, and do not use `*`.

### 7.5 The store-listing tasks on the same card

The **"Set up your app"** card finishes with three tasks that are about
presentation rather than policy. In the left nav they are under **Grow → Store
presence**.

**"Set up your store listing"** → *Main store listing.* Assets and character
limits are in §4. `store/play/icon-512.png` is already generated and correct
(512×512, RGB, no alpha). Still to produce:

- **Feature graphic, 1024×500** — required, and the single most common thing
  people discover is missing at the last minute.
- **2–8 phone screenshots** — real UI, not marketing collateral with fake bezels.
- 7" and 10" **tablet screenshots** — optional, but the listing is down-ranked on
  tablets without them.

**"Select an app category and provide contact details"** → *Store settings.*
Category: **Travel & Local** fits guest↔host stays better than House & Home.
Contact details: the **support email is required**; phone number and website are
recommended and worth filling, because a listing with only an email reads as
less trustworthy for a marketplace handling money and ID documents.

> The support email is public on your listing and is where Google writes to you.
> `support@musaafir.app` **does not exist today** — the `musaafir.app` domain does
> not resolve (§5). This is also the address your privacy policy and
> account-deletion page both promise a reply from. Fix it before you paste it
> anywhere.

**"Manage how your app is organised and presented"** — tags and similar
discoverability metadata. Low stakes; fill it in and move on.

### 7.6 "Release your app early for internal testing without review"

**Do this first** (§7.2). Left nav: **Test and release → Testing → Internal
testing**.

Not required for you — the 12-testers rule does not apply to organization
accounts (§1) — but **"without review"** is the point: an internal release skips
policy review entirely and reaches testers within minutes, where a production
review takes days. If **Create new release** is greyed out here, finish the
flagged Dashboard tasks and return (§7.2).

1. **Testers tab → create a tester list.** Up to 100 testers, added by email
   address or Google Group. They must be real Google accounts. Add yourself.
2. Add a **feedback email or URL** so testers have somewhere to report.
3. **Create new release** → upload
   `build/app/outputs/bundle/release/app-release.aab` (§8).
4. **Copy the shareable opt-in link**, open it as a tester, accept, and install
   from the Play Store.
5. **Save changes** — then remember the Dashboard's batching rule (§7) if the
   release does not appear.

Then exercise, on a physical device, against **production** Supabase:

- **Image upload** — this build routes gallery picks through the Android Photo
  Picker instead of `ACTION_GET_CONTENT` (§6.3). Different system UI, never yet
  run on real hardware.
- **A full OTP login** — the master OTP is off (§6.4), so this is the first time
  the real SMS path is the only path.
- **Maps** — expect these to work now and break after §2.4 if you get the
  app-signing SHA-1 wrong.
- Voice search, camera/selfie, push.

Note that installs from the internal track are signed with the **Play app signing
key**, not your upload key — so this is also the first honest test of §7.7.

### 7.7 Collect the app-signing certificate

After the first upload: **Test and release → Setup → App signing.** It shows both
the **app signing** certificate (what users' devices see) and the **upload**
certificate.

Take the app-signing **SHA-1** straight to §2.4 and restrict the Maps key with
it. Skip this and maps render blank for every store user while working perfectly
on your machine — the single most common "it worked in testing" failure for a
Flutter app with maps.

### 7.8 "Publish your app on Google Play"

The last Dashboard card, two tasks. Left nav: **Test and release → Production**.

1. **"Select countries and regions"** — Bangladesh at minimum. This is its own
   task on the card and is easy to skip past; a production release with no
   countries selected cannot roll out.
2. **"Create a new release"** — greyed out until every "Set up your app" task is
   ticked (§7.2). Upload the same AAB, or **promote** the internal-testing
   release, which is better: it ships the exact bytes you just tested.
3. Write release notes.
4. **Staged rollout**: start at 10–20%. A staged rollout can be halted; a 100%
   rollout cannot be un-shipped.
5. **Publishing overview → Send changes for review.**

Expect the **first** review of a brand-new app to take days, occasionally a
couple of weeks, even on a verified organization account. Subsequent updates are
usually hours. Plan the launch date around that, not around the build being
ready.

## 8. Build and upload

```sh
flutter clean                      # cheap here, and see the registrant note below
flutter pub get
flutter analyze                    # must be clean
flutter test
flutter build appbundle --release   # -> build/app/outputs/bundle/release/app-release.aab
```

- **AAB, not APK.** Play has required App Bundles for new apps since 2021.
- Play Console → **Test and release → Testing → Internal testing → Create new
  release** → upload the `.aab`.
- Android has **no analogue of the stale-plugin-registrant trap** described in
  `CLAUDE.md` — that guard is web-specific and `tool/build_web.sh` does not
  cover Android. But the *lesson* transfers: `flutter run` and the release
  bundle are different builds. Install the actual signed artifact on a real
  device and exercise **maps, voice search, camera/selfie, image upload, push**
  before shipping. Those are exactly the paths that work in debug and break in
  release.
- Also verify against **production** Supabase, not a dev project, and check
  `AppSettingsService` reads `app_settings` from the right instance.

Reviewer credentials go in **App content → App access**, and they are not a
formality — see **§7.4**, which is the one step most likely to sink a first
submission. A reviewer cannot receive an SMS on a Bangladeshi number, so
"here is a phone number" is not usable credentials.

## 9. Rollout

1. **Internal testing** (§7.6) — confirm the signed artifact works end to end on a
   real device.
2. **Production, staged** (§7.8) — start at 10–20%. A staged rollout can be
   halted; a 100% rollout cannot be un-shipped.
3. Watch **Android vitals** (crashes/ANRs) for a few days before widening.

No closed-testing stage is required: that is the 12-testers / 14-days rule, and
your organization account is exempt (§1). Add one only if you want a real beta.

## 10. Pre-submit checklist

Done, verified against the built artifact:

- [x] Upload keystore generated, `key.properties` in place, git-ignored
- [x] Release APK verified signed by the upload key, **not** debug
- [x] Launcher + adaptive + round + monochrome icons replaced; 512×512 store icon ready
- [x] `legal_links.dart` points at reachable URLs; privacy / terms / deletion pages written
- [x] Android Photo Picker enabled; no `READ_MEDIA_IMAGES` **or** `READ_EXTERNAL_STORAGE` in the merged manifest
- [x] `RECORD_AUDIO` retained; `targetSdk 36` confirmed in the APK
- [x] `flutter analyze` clean, `dart format` clean, 585 tests pass
- [x] Play Console **organization** account with D-U-N-S exists → exempt from 12 testers / 14 days (§1)
- [x] No ads, no advertising ID, no Play Billing in the APK → three declarations answerable as plain "no" (§7.3)
- [x] **Master OTP unset on the live project** — it had been the `*` wildcard, i.e. any number (§6.4)

Still on you:

- [ ] **Back up the keystore + password** (password manager and an offline copy)
- [ ] **Deploy the legal pages** — `sh tool/build_web.sh`, commit `build/web`, deploy, `sh tool/verify_deploy.sh`. Until then the URLs 404 and #3 is not fixed
- [ ] **`support@musaafir.app` receives mail** — the domain does not resolve today
- [ ] Legal review of the privacy policy and terms
- [ ] Audit the ~19-day master-OTP window for unauthorised logins, if that matters to you (§6.4). The bypass itself is already off
- [ ] Maps key: new Android-restricted key with both SHA-1s, referrer-restricted web key, then **delete the shared key** (§2.4)
- [ ] `versionCode` bumped from 1; `versionName` decided (§2.5) — consider starting at `1.0.0`
- [ ] Store name spelling settled: `Musaafir` vs `Musafir` (§3)
- [ ] **Reviewer credentials that actually work** — set `MASTER_OTP_PHONES` to a single reviewer number, code not `1234` (§7.4). Most likely single cause of a first rejection
- [ ] App created in the Console; free-vs-paid chosen deliberately (one-way door), Play App Signing ToS accepted (§7.1)
- [ ] **Internal testing done first** — "without review", so it needs none of the below (§7.6)
- [ ] All **"Set up your app"** card tasks ticked — production's *Create new release* stays greyed out until they are (§7.2, §7.3)
- [ ] Feature graphic 1024×500 + screenshots uploaded; category and contact details set (§7.5)
- [ ] **"Select countries and regions"** done — its own task, easy to miss (§7.8)
- [ ] After first upload: app-signing SHA-1 collected and fed into the Maps restriction (§7.7)
- [ ] **Publishing overview → Send changes for review** actually clicked (§7)
- [ ] Feature graphic 1024×500 + screenshots produced (§4)
- [ ] Data safety form submitted and matches reality (incl. NID/selfie)
- [ ] Content rating questionnaire done (UGC = yes)
- [ ] Report/block affordances present for UGC (§6.5)
- [ ] Reviewer test account documented in App access (§8)
- [ ] Signed AAB smoke-tested on a physical device against production Supabase —
      maps, voice search, camera/selfie, image upload, push
