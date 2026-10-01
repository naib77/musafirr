# App settings, host-response window, palettes and the boot colour

Moved verbatim from `CLAUDE.md` on 2026-10-01 to keep that file small.
The short rule for each section is still in `CLAUDE.md`; the reasoning is here.

## Nothing user-tunable belongs in Dart

App-wide knobs live in the `app_settings` table and are edited from the admin
portal — reads are public, writes are admin-only. `AppSettingsService` loads
them at startup and **fails open** to compiled-in defaults.

Current keys include the proof-of-address requirement, cash payments, the
search area (`search_radius_tiers_m`, `search_landmark_radius_m`,
`search_nearest_fallback_limit`), the colour theme (`active_theme`), the
host-response window (`booking_accept_window_hours`), the forced-update
floor (`android_min_version_code`) and the hourly-stay policy
(`hourly_policy`, a JSON document per listing type — the one structured key;
see the 148 section of `database-booking-and-search.md`). Values are validated on
write — `fn_validate_app_setting` is a CASE dispatching to one
`fn_validate_setting_*` per key — so a bad value is refused at the source
rather than silently sanitised. **Adding a key means adding an arm to that
dispatcher**, and recreating it in full: it is a CASE, so a patch that drops an
arm silently stops validating that key.

### The host-response window is a setting, and the database is its only enforcer

A booking request the host never answers is auto-rejected. That window was 24
hours written into `expire_stale_bookings()` (018) — as an interval *and* as
the number spelled out in three notification strings — plus a fourth copy in
`BookingRules.expirationDuration`. It is `booking_accept_window_hours` now
(119), 1–168, seeded at 24 so nothing changed on apply.

- **Only the cron job cancels anything.** Nothing in Dart expires a real
  booking. The Dart copy of the window (`booking_accept_window.dart`) feeds the
  guest's countdown, and fails open to 24h when settings cannot be read — a
  stale client shows a slightly wrong clock, which is cosmetic, where a client
  that could expire bookings would be a second enforcer of a rule the database
  owns. `BookingRules.isExpired` is a *read*, not an enforcement.
- **The sweep runs every 15 minutes, not hourly.** Hourly was invisible at 24
  hours and is not at 2 — a 2-hour window swept hourly expires somewhere
  between 2 and 3. The window is still a floor rather than a promise: expiry
  happens at the first tick *after* it elapses, so the guest's countdown
  reaches zero while the row is briefly still `pending`. That is the honest way
  round; do not "fix" it by having the client reject.
- **`booking_accept_window_hours()` re-guards the value** with the same regex
  the validator uses, and falls back to 24. Not redundant: rows predate guards,
  and a function that can raise inside a cron job is a job that silently stops
  running for *every* booking. The test writes a junk value past the trigger to
  prove it.
- The prose keeps today's exact wording at 24 (`fn_humanise_hours` only says
  "days" at 48+), so the default configuration changed no visible text.

`active_theme` names one of the palettes in `lib/core/theme/app_palettes.dart`.
The app can only wear a palette it was compiled with, so **adding one means
adding its id to `AppPalettes.all` AND to `fn_validate_setting_active_theme`
(created in 105, id list last extended by 106)** — a test
pins the slug list so the two drifting apart fails rather than silently shipping
a theme no admin can select. That test also holds every palette to WCAG: 4.5:1
for tokens that carry text, 3:1 for ones that only ever tint an icon. There are
no exemptions and the tiers are not advisory — a new palette that fails is a
failing build, so pick colours against a background, not in isolation.

It holds one more axis, added after selection turned out to be invisible: **a
selected chip has to clear 3:1 against an unselected one**, and its label 4.5:1
against its own fill. `chipTheme` used to tint the brand at 14% alpha over
`surfaceMuted`, which works for a colourful brand and not at all for
`coral_ink`, whose brand is #222222 — the tint flattened to #E0E0E0 beside a
#EBEBEB chip, 1.11:1, with `side: BorderSide.none` leaving no second cue. Seven
of the nine selectable chips in the app take their colours from that theme
alone, so all seven read as permanently unselected. Selection is a solid
`brand` fill now, label and checkmark in `surface`; that pairing needs no new
guarantee because brand-on-surface at 4.5:1 *is* surface-on-brand at 4.5:1.

Two traps if you touch it. **Flatten alpha before measuring** — Flutter's
`computeLuminance()` reads only r/g/b, so contrast against a translucent fill
reports the ratio of the tint's source colour, a healthy 13:1 for something
invisible; the test composites with `Color.alphaBlend` first, and without that
line it passes on the bug it exists for. And **`RawChip` resolves only the
label's `color` against widget states**, not the rest of the TextStyle
(`chip.dart` calls `resolveAs<Color?>` on `effectiveLabelStyle.color` alone), so
a `WidgetStateColor` is the single hook a theme has for a selected label and a
`WidgetStateTextStyle` would be read as a plain style. A call site may add its
own size or weight — `merge` only overrides non-null fields — but a `color:` of
its own defeats that hook and paints an ink label on the dark fill.

### The boot chain is brand rose, not the palette

Seven surfaces hardcode **`#C35063`** and cannot follow `active_theme`, because
the OS or the browser paints them before any Dart runs: `values/colors.xml`,
`values-v31/styles.xml`, `LaunchScreen.storyboard`, `web/manifest.json`, the
`web/index.html` boot splash, `tool/gen_brand_assets.py`, and — by choice, to
end the chain in the same colour — `SplashScreen` via
[`Brand.rose`](lib/core/theme/brand.dart). That file lists all seven; if the
brand colour changes they all change together, and nothing can automate it.

`SplashScreen` used to paint `colorScheme.primary`. With the default
`ocean_teal` palette that meant a rose launch window flipped to a **teal**
screen, which reads as a broken load rather than a brand. Do not "fix" it back
to the theme.

The `index.html` splash also had no business having a `prefers-color-scheme:
dark` variant — it was `#0E1F23`, a dark green-teal, and since that background
paints the instant the CSS parses while the icon is still loading, a dark-mode
browser opened on a greenish blank window. A brand colour has no dark variant.

Before hardcoding a number a human might want to change, check whether it
belongs here instead.
