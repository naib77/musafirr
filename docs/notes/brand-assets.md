# Brand assets are generated, not hand-made

Moved verbatim from `CLAUDE.md` on 2026-10-01 to keep that file small.
The short rule for each section is still in `CLAUDE.md`; the reasoning is here.

## Brand assets are generated, not hand-made

`python3 tool/gen_brand_assets.py` derives all of these from the artwork
committed in `assets/brand/source/`:

| Output | Surface |
| --- | --- |
| `assets/brand/logo.png` | in-app `BrandLogo` — splash, login, sidebar rail |
| `assets/brand/icon*.png` | masters for the generators below |
| `mipmap-*/ic_launcher*` | Android launcher: legacy, round, adaptive, monochrome |
| `drawable-*/ic_notification.png` | Android status bar / notification shade |
| `LaunchImage*.png` | iOS launch screen |
| `web/social-card.png` | link previews (og:image) |
| `store/play/icon-512.png` | Play listing |

The iOS **app** icon and the web icons come from
`dart run flutter_launcher_icons` afterwards, in that order — it reads
`icon.png`, which the script writes.

Two of those exist because a launcher icon cannot be reused as they are:

- **`ic_notification`** — Android draws a notification's small icon from the
  **alpha channel alone**, discarding colour. `ic_launcher` is a rounded square
  that is 96% opaque, so pointing a notification at it renders a featureless
  white blob. This app shipped that bug. Wired in `AndroidManifest.xml` *and*
  twice in `firebase_push_notification_service.dart` — all three must agree.
- **`LaunchImage`** — Flutter's template is a 1×1 transparent PNG on a white
  storyboard, so an unbranded iOS cold start is a blank white screen. The
  storyboard background carries the rose; the image is the mark on
  transparency, mirroring how Android layers its launch window.

So **never hand-edit or hand-resize one of those files**: the next regeneration
silently reverts it. Change the script or the source artwork instead.

The source is flat rose on opaque white with a soft, faintly rose-tinted drop
shadow. Keying that cleanly is genuinely fiddly and the reasoning is written up
in `assets/brand/README.md` — read it before touching the pipeline, in
particular why there is a levels floor before the bounding box is measured.

Two footguns after any regeneration: `flutter_launcher_icons` strips the
trailing newline from `web/manifest.json`, and `landing/favicon.png` +
`landing/Icon-192.png` are separate copies that it does not touch.

**The favicon needs a URL change, not a cache header.** Browsers keep favicons
in a private store that ignores `Cache-Control`, so a correct deploy still
leaves the old icon in the tab. `tool/build_web.sh` therefore appends
`?v=<content hash>` to every icon URL in `index.html`; `assets/brand/README.md`
explains it, along with why `web/favicon.ico` has to exist at all (the SPA
not-found rule made `/favicon.ico` answer 200 with an HTML page).
