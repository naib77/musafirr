# Brand assets

Every file here is **generated**. Do not hand-edit them, and do not hand-resize
one to make another — run the script:

```sh
python3 tool/gen_brand_assets.py     # this dir, Android icons + notification
                                     # icon, iOS launch image, social card,
                                     # Play icon
dart run flutter_launcher_icons      # then the iOS app icon (15) + web (5)
```

The order matters: `flutter_launcher_icons` reads `icon.png`, which the first
command writes.

## Source

`source/app_icon.png` (the mark alone) and `source/logo_lockup.png` (mark +
wordmark), committed so the pipeline is reproducible. They are the supplied
artwork, unmodified. Neither is declared in `pubspec.yaml`, so they cost the app
and the web bundle nothing.

Both are **flat rose on opaque white with a soft drop shadow** — the alpha
channel they carry is all-255, so the transparency in the outputs is derived,
not recovered. If vector source (SVG/AI/PDF) ever turns up, re-export from that
and replace these: nothing here can beat a 900–1024px raster origin.

**Brand colour: `#C35063`.** The two sources measure `#C54F63` and `#C35364` at
the median of their solid interiors — both within a just-noticeable difference
of the constant, which is why it stays a hand-fixed value in the script rather
than being re-derived per run. Five places outside Python hardcode it too
(`pubspec.yaml`, `values/colors.xml`, `ic_launcher_background.xml`,
`web/manifest.json`, the `web/index.html` spinner), and re-measuring would drift
away from all of them for no visible gain.

## Files

| File | Size | Used by |
| --- | --- | --- |
| `logo.png` | 512² RGBA | `BrandLogo` — splash, login, sidebar rail |
| `logo_lockup.png` | 900×224 RGBA | `web/social-card.png`; also for documents |
| `icon.png` | 1024² **RGB** | `flutter_launcher_icons` → iOS + web |
| `icon_foreground.png` | 1024² RGBA | Android adaptive foreground |
| `icon_monochrome.png` | 1024² RGBA | Android 13+ themed icons |

`icon.png` is opaque on purpose: the App Store rejects a 1024 icon with an
alpha channel. It is flattened in the script rather than left to
`remove_alpha_ios`, so what is committed is what ships.

`icon_monochrome.png` is byte-identical to the foreground by design — Android 13
tints that layer itself, so what it wants is a flat silhouette, not a second
design.

## How the transparency is cut

The key is `R - min(G, B)`. The mark is rose, so its red channel far exceeds the
other two, while white and *neutral* grey both have `R == G == B` and key to
zero — background and the neutral part of the shadow go in one step, with no
threshold to tune. A plain white-threshold instead keeps that shadow as a grey
halo: invisible on white, obvious the moment the logo lands on a dark surface.

What that leaves is a residue no colour trick can remove. The shadow is faintly
**rose-tinted**, and a rose shadow over white is chromatically identical to a
partially transparent rose mark — same colour, so no colour space separates
them. Magnitude does: measured on this artwork, keyed residue more than 10px
from the mark peaks at 9.5% of a solid pixel, while real edge antialiasing ramps
across the whole range. So the script applies a levels floor at 14% and rescales
what survives back to full range.

That floor is not cosmetic. Without it, stray keyed speckle reached the far edge
of the 1024 canvas, so the alpha bounding box used for centring and scaling was
measuring **noise** — which left the mark 13% smaller than intended and 41px
off-centre on `icon.png`.

Each output also carries one *uniform* RGB value with all the shape in alpha.
LANCZOS blends colour and alpha independently, so a file with meaningful colour
under its transparent pixels grows a fringe when scaled — and `BrandLogo` draws
`logo.png` as small as 26px.

## Sizing

Mark width as a fraction of canvas, because the mark is ~1.42:1 and width binds
everywhere:

| Output | Fraction | Why |
| --- | --- | --- |
| Android adaptive | 0.40 | 43.2dp of the 108dp canvas |
| Android legacy / Play | 0.60 | own baked mask, whole canvas visible |
| `icon.png` (iOS/web) | 0.60 | iOS rounds corners but crops very little |
| `logo.png` | 0.86 | near full-bleed; short of 1.0 so it never touches a caller's tile edge |
| `ic_notification` | 0.92 | the system scales a 24dp source down again, so margin here is lost twice |
| `social-card.png` | 0.62 | the lockup, not the mark — wide enough to read as a thumbnail |

**The first three are solved, not chosen.** What a user compares is the fraction
of the *visible* icon the mark covers, and the platforms disagree about how much
of the file is visible: a launcher shows only the centre 72dp of the adaptive
108dp canvas, while iOS and the legacy masks show effectively all of theirs. So
an adaptive mark reads 1.5× larger than its fraction suggests, and matching 0.60
visible everywhere means 0.60/1.5 = 0.40 there. The script asserts that identity
so editing one number without the other fails loudly.

Getting it wrong is what made the Android launcher icon look like a different,
more zoomed-in logo than the web and iOS ones — 0.52 adaptive reads as 0.78
visible against their 0.60. 0.40 also sits far inside the 66dp circle every
launcher mask spares, so the safe zone stops being the binding constraint.

The ground is **flat** `#C35063` on every one of them. Android's adaptive
background and legacy PNGs were a vertical gradient while iOS and web were flat,
which is the other half of why the icon differed by platform.

## Why `logo.png` is the mark alone, square, and rose

- **Mark alone**, because "Musaafir" stays live `Text` at every call site: it
  inherits the active theme's ink colour and stays selectable and translatable.
  `logo_lockup.png` is there if you would rather use the real wordmark
  typography, which the app's Plus Jakarta Sans does not match.
- **Square**, because `BrandLogo` renders `width == height == size`. The mark is
  wide, so it is letterboxed into that square — intended, not wasted padding.
- **Rose, and never tinted per theme.** Every call site passes no `color`. A
  logo is not a UI accent: repainting it teal or indigo because an admin picked
  a palette would replace the brand with the theme. `BrandLogo` still *supports*
  tinting for a coloured backdrop; nothing currently needs it.

## After regenerating

Web icons land in `web/`, which is only the source. They reach users only after
`sh tool/build_web.sh` and a commit of `build/web` — see CLAUDE.md.
`landing/favicon.png` and `landing/Icon-192.png` are separate copies of
`web/favicon.png` and `web/icons/Icon-192.png` and must be refreshed by hand.

`flutter_launcher_icons` also strips the trailing newline from
`web/manifest.json` every run. Put it back.

## Why the favicon appears not to update

It was the one brand surface that stayed stale after a deploy, and the cause is
not HTTP caching — `favicon.png` answers `no-cache, must-revalidate`, so a
normal image would refresh. **Browsers keep favicons in a separate, long-lived
store** (Chrome has a favicon database) that is not driven by `Cache-Control`,
so a tab can keep painting an old icon indefinitely. "Clear your cache" is not
a fix you can ship to users.

What a browser cannot ignore is a *different URL*. So `tool/build_web.sh`
appends `?v=<content hash>` to every icon URL in `index.html` — favicon,
`Icon-192` (including its `rel=preload`, which must match or the image
downloads twice) and `social-card.png`. `index.html` is `no-store`, so a
changed hash is found on the next load and the icon is fetched as a URL the
favicon store has never seen. An unchanged icon keeps its hash and stays
cached.

`web/favicon.ico` exists for a second reason: clients probe `/favicon.ico` by
convention, and because `wrangler.jsonc` sets `not_found_handling` to
`single-page-application`, that request used to answer **200 with a 16KB HTML
document**. Nothing points a `<link>` at it — modern browsers prefer the PNG
links — it just makes the conventional path return an image. It carries 16/32/
48/64 so no client upscales 16px artwork.

The social card gets the same treatment against a different cache: WhatsApp,
Messenger, Facebook and X cache an `og:image` per URL, sometimes for weeks.
