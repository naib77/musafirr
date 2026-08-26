# Brand assets

Every file here is **generated**. Do not hand-edit them, and do not hand-resize
one to make another — run the script:

```sh
python3 tool/gen_brand_assets.py     # this directory, Android icons, Play icon
dart run flutter_launcher_icons      # then iOS (15 files) + web (5 files)
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
| `logo_lockup.png` | 900×224 RGBA | nothing in-app; for documents and stores |
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
| `logo.png` | 0.86 | near full-bleed; short of 1.0 so it never touches a caller's tile edge |
| Android adaptive | 0.52 | 56dp on the 108dp canvas — 10dp inside the 66dp guaranteed circle |
| Android legacy / Play | 0.56 | carries its own baked ground, no launcher mask to fear |
| `icon.png` | 0.60 | iOS rounds the corners but crops very little |

The adaptive figure is the one with a hard constraint. Only the centre 66dp of
the 108dp canvas survives every launcher mask; 0.52 leaves margin inside that,
because the safe zone is a floor and not a target — a mark sized right up to it
is compliant and still looks cramped once a launcher crops to its 72dp
viewport.

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
