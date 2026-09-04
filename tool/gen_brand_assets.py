#!/usr/bin/env python3
"""Regenerate every brand asset from the supplied source artwork.

Replaces the earlier `tool/gen_launcher_icons.py`, which *drew* a placeholder
house silhouette in code because no real mark existed yet. A real mark exists
now, so that script had become a landmine: running it would have silently
reverted the icons to a teal house. This one derives everything from the
artwork in `assets/brand/source/` instead, so re-running it is always safe.

Run from the repo root:

    python3 tool/gen_brand_assets.py

Writes (nothing else in the repo is generated from the artwork):

    assets/brand/logo.png                  512x512  in-app mark, brand rose
    assets/brand/logo_lockup.png           900xN    mark + wordmark
    assets/brand/icon.png                  1024^2   iOS/web master, opaque
    assets/brand/icon_foreground.png       1024^2   Android adaptive foreground
    assets/brand/icon_monochrome.png       1024^2   Android 13+ themed icons
    android/.../mipmap-<d>/ic_launcher.png            legacy, rounded (API 24-25)
    android/.../mipmap-<d>/ic_launcher_round.png      legacy, circular (API 25)
    android/.../mipmap-<d>/ic_launcher_foreground.png adaptive foreground
    android/.../mipmap-<d>/ic_launcher_monochrome.png adaptive monochrome
    android/.../drawable-<d>/ic_notification.png      status-bar icon
    ios/.../LaunchImage.imageset/LaunchImage*.png     iOS launch screen
    web/favicon.ico                                  /favicon.ico probe path
    web/social-card.png                              link-preview card
    store/play/icon-512.png                          Play listing icon

The iOS *app icon* and the web icons are NOT written here —
`dart run flutter_launcher_icons` derives those from `assets/brand/icon.png`,
so run this first and that second. The web files then still need
`sh tool/build_web.sh` and a commit of `build/web` to reach anyone; see
CLAUDE.md.
"""

import os

from PIL import Image, ImageChops, ImageDraw

# --- Brand constants -------------------------------------------------------

# The brand rose. Both source files measure a hair either side of this
# (#C54F63 and #C35364 as the median of their solid interiors), which is well
# inside a just-noticeable difference, so this stays a hand-fixed constant
# rather than being re-derived per run. That matters because the same value is
# hardcoded in five places that a Python script cannot reach: pubspec.yaml's
# flutter_launcher_icons block, android values/colors.xml,
# drawable/ic_launcher_background.xml, web/manifest.json and the
# web/index.html spinner. Re-measuring every run would drift away from all of
# them for no visible gain.
BRAND = (0xC3, 0x50, 0x63)
WHITE = (0xFF, 0xFF, 0xFF)

# Mark width as a fraction of canvas, per output. Width rather than height
# because the mark is ~1.42:1, so width is the binding dimension everywhere.
#
# These three are NOT free choices — they are solved so the mark comes out the
# same visual size on every platform. What matters is the fraction of the
# *visible* icon the mark covers, and the platforms differ in how much of the
# file is visible at all:
#
#   Android adaptive: the canvas is 108dp but a launcher shows only the centre
#                     72dp, so a mark of F*108 reads as F*108/72 = 1.5*F.
#   Everything else:  the whole canvas is visible (iOS and the legacy masks
#                     only round off corners), so the mark reads as F.
#
# Target 0.60 of the visible icon throughout. Hence 0.40 for adaptive
# (0.40*1.5 = 0.60) and a flat 0.60 elsewhere. Getting this wrong is what made
# the Android launcher icon look like a different, more zoomed-in logo than the
# web and iOS icons: 0.52 adaptive reads as 0.78 visible, against 0.60.
FRAC_ADAPTIVE = 0.40
FRAC_LEGACY = 0.60
FRAC_ICON = 0.60
# Sanity-check the identity above rather than trusting the arithmetic to stay
# true if someone edits one number: 108/72 is the adaptive viewport ratio.
assert abs(FRAC_ADAPTIVE * (108 / 72) - FRAC_ICON) < 1e-9, (
    "adaptive and icon fractions no longer render the mark at the same "
    "visible size"
)
# 0.40*108 = 43.2dp, far inside the 66dp circle every launcher mask spares.
assert FRAC_ADAPTIVE * 108 < 66, "adaptive mark escapes the safe zone"
# In-app logo: close to full-bleed, because BrandLogo draws it into a square
# box and the mark is ~1.42:1, so width binds and the vertical letterboxing
# that leaves is intended. Short of 1.0 so the mark never touches the edge of
# whatever tile a caller draws behind it.
FRAC_LOGO = 0.86
# Android status-bar icon. Nearly full-bleed: the system scales a 24dp source
# down into a small slot, so margin here is margin lost twice over.
FRAC_NOTIFICATION = 0.92
# iOS launch screen. The storyboard centres this on the brand rose, so the
# figure is a size in points rather than a fraction of any canvas.
LAUNCH_IMAGE_WIDTH_PT = 128

SS = 4  # supersample factor for the drawn masks and gradients

# Keyed alpha below this fraction of a solid pixel is treated as shadow
# residue and discarded. See cut_mark() for why a floor is needed at all and
# how this number was measured — it is 14% against a measured 9.5% worst case,
# so it has margin without eating into real antialiasing.
NOISE_FLOOR = 0.14

SRC = os.path.join("assets", "brand", "source")
BRAND_DIR = os.path.join("assets", "brand")
RES = os.path.join("android", "app", "src", "main", "res")

# Legacy launcher icons are 48dp, adaptive layers 108dp.
DENSITIES = {"mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0, "xxhdpi": 3.0, "xxxhdpi": 4.0}


# --- Keying ----------------------------------------------------------------


def cut_mark(path):
    """Lift the rose mark off its white background as clean RGBA.

    The source artwork is a flat rose mark on white *with a soft grey drop
    shadow*, and fully opaque — the PNGs carry an all-255 alpha channel, so
    there is no transparency to recover, only to derive.

    A plain white-threshold would keep that shadow as a grey halo: invisible
    against white, glaringly obvious the moment the logo lands on a dark
    surface. So the key is `R - min(G, B)`. The mark is rose, so its red
    channel far exceeds the other two, while the white background and the
    *neutral* part of the shadow both have R == G == B and key to zero in one
    step.

    That leaves one residue no colour trick can remove: the shadow is not
    purely neutral, it is faintly rose-tinted, and a rose shadow over white is
    chromatically identical to a partially transparent rose mark. They are the
    same colour, so nothing in any colour space separates them.

    What does separate them is magnitude. Measured on this artwork, every bit
    of keyed residue more than 10px from the mark peaks at 9.5% of a solid
    pixel's key, while genuine edge antialiasing ramps across the whole range.
    So a levels floor at NOISE_FLOOR discards the residue with margin and
    costs only the outermost sliver of the antialiasing ramp, which is then
    rescaled back to full range rather than left dimmed. Without it the mark
    carries a dusty rose haze on dark backgrounds, and — worse — stray keyed
    speckle lands outside the mark and inflates the alpha bounding box that
    `place()` uses to centre and scale.

    Returns RGBA whose RGB is *uniformly* the brand rose, with all the shape
    carried in alpha. That is deliberate: LANCZOS resampling of RGBA blends
    RGB and alpha independently, so a file with meaningful colour under its
    transparent pixels grows a fringe when scaled. Flat colour cannot.
    """
    src = Image.open(path).convert("RGB")
    r, g, b = src.split()
    # ImageChops.subtract clamps at 0, which is exactly the wanted behaviour
    # for the (rare) pixel that is bluer than it is red.
    key = ImageChops.subtract(r, ImageChops.darker(g, b))

    solid = _solid_level(key)
    floor = NOISE_FLOOR * solid
    span = max(1.0, solid - floor)
    # Rescale so a solid-interior pixel becomes fully opaque, the noise floor
    # becomes fully transparent, and the antialiasing in between lands
    # proportionally across the whole range.
    alpha = key.point(lambda v: max(0, min(255, round((v - floor) * 255 / span))))

    out = Image.new("RGBA", src.size, BRAND + (0,))
    out.putalpha(alpha)
    return out


def _solid_level(key):
    """The key value a fully-inked pixel has.

    Taken as the median of the top of the distribution rather than its plain
    maximum: the maximum is a single outlier pixel, and dividing by it would
    leave the whole mark a few percent translucent.
    """
    hist = key.histogram()
    peak = max(v for v, n in enumerate(hist) if n and v > 0)
    floor = peak * 0.75
    inked = [(v, n) for v, n in enumerate(hist) if v >= floor]
    total = sum(n for _, n in inked)
    seen = 0
    for v, n in inked:
        seen += n
        if seen >= total / 2:
            return max(1, v)
    return max(1, peak)


def recolour(mark, colour):
    """Same alpha, different flat colour — for the knocked-out white mark."""
    out = Image.new("RGBA", mark.size, colour + (0,))
    out.putalpha(mark.split()[3])
    return out


# --- Composition -----------------------------------------------------------


def place(mark, canvas, frac, background=None):
    """Scale `mark` to `frac` of `canvas` width and centre it.

    Centred on the mark's alpha bounding box, not on the source image's
    extents — the source has uneven white margins, and centring on those is
    what left the previous icon.png sitting 41px left of centre on a 1024
    canvas.
    """
    trimmed = mark.crop(mark.split()[3].getbbox())
    w = round(canvas * frac)
    h = max(1, round(w * trimmed.size[1] / trimmed.size[0]))
    scaled = trimmed.resize((w, h), Image.LANCZOS)
    ox, oy = (canvas - w) // 2, (canvas - h) // 2

    if background is not None:
        img = background.convert("RGBA")
        img.alpha_composite(scaled, (ox, oy))
        return img

    # Transparent output: paste the alpha channel and re-flood the colour,
    # rather than alpha_compositing onto a transparent canvas. That
    # composite divides RGB by alpha per pixel, and the integer rounding
    # leaves every low-alpha edge pixel a slightly different rose. Invisible
    # in the file itself, but it seeds a real fringe the next time the file is
    # scaled — and BrandLogo draws logo.png as small as 26px. cut_mark and
    # recolour both guarantee uniform RGB across the whole source, transparent
    # region included, so any pixel names the colour.
    flat = mark.getpixel((0, 0))[:3]
    alpha = Image.new("L", (canvas, canvas), 0)
    alpha.paste(scaled.split()[3], (ox, oy))
    img = Image.new("RGBA", (canvas, canvas), flat + (0,))
    img.putalpha(alpha)
    return img


def rounded_mask(size, radius_frac):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=size * radius_frac, fill=255)
    return m


def circle_mask(size):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).ellipse([0, 0, size - 1, size - 1], fill=255)
    return m


def legacy(mark_white, size, mask):
    """Pre-adaptive launcher icon (API 24-25) and the Play listing.

    Flat brand rose, matching drawable/ic_launcher_background.xml (the adaptive
    path) and assets/brand/icon.png (iOS and web). This used to be a vertical
    gradient here and in the adaptive XML while iOS and web were flat, so the
    same app had two visibly different icons depending on the platform.

    Those launchers apply no mask of their own, so the rounding or circling has
    to be baked in here. Drawn at SS x and downsampled, because PIL has no
    antialiased shape fill and a mask cut at 48px is visibly jagged.
    """
    ss = size * SS
    img = place(mark_white, ss, FRAC_LEGACY, Image.new("RGB", (ss, ss), BRAND))
    if mask is not None:
        img.putalpha(mask(ss))
    return img.resize((size, size), Image.LANCZOS)


def write(path, img):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, "PNG")
    print(f"  {path}  {img.size[0]}x{img.size[1]} {img.mode}")


# --- Main ------------------------------------------------------------------

mark_rose = cut_mark(os.path.join(SRC, "app_icon.png"))
mark_white = recolour(mark_rose, WHITE)
lockup_rose = cut_mark(os.path.join(SRC, "logo_lockup.png"))

print("brand assets:")
write(os.path.join(BRAND_DIR, "logo.png"), place(mark_rose, 512, FRAC_LOGO))

# The lockup keeps its own aspect rather than being boxed: nothing renders it
# into a square, and it is the one asset a human might drop into a document.
lockup = lockup_rose.crop(lockup_rose.split()[3].getbbox())
lockup_h = round(900 * lockup.size[1] / lockup.size[0])
write(
    os.path.join(BRAND_DIR, "logo_lockup.png"),
    lockup.resize((900, lockup_h), Image.LANCZOS),
)

# Opaque on purpose: the App Store rejects a 1024 icon with an alpha channel.
# Flattened here rather than relying on flutter_launcher_icons'
# remove_alpha_ios, so what is committed is what ships.
write(
    os.path.join(BRAND_DIR, "icon.png"),
    place(
        mark_white, 1024, FRAC_ICON, Image.new("RGB", (1024, 1024), BRAND)
    ).convert("RGB"),
)

foreground_1024 = place(mark_white, 1024, FRAC_ADAPTIVE)
write(os.path.join(BRAND_DIR, "icon_foreground.png"), foreground_1024)
# Identical to the foreground by design: Android 13 tints the monochrome layer
# itself, so what it wants is a flat silhouette, not a second design.
write(os.path.join(BRAND_DIR, "icon_monochrome.png"), foreground_1024)

print("android launcher icons:")
for bucket, scale in DENSITIES.items():
    out = os.path.join(RES, f"mipmap-{bucket}")
    legacy_px = round(48 * scale)
    adaptive_px = round(108 * scale)
    # ic_launcher is rounded and ic_launcher_round is a circle, matching what
    # the two resource names promise the launcher.
    write(
        os.path.join(out, "ic_launcher.png"),
        legacy(mark_white, legacy_px, lambda s: rounded_mask(s, 0.22)),
    )
    write(
        os.path.join(out, "ic_launcher_round.png"),
        legacy(mark_white, legacy_px, circle_mask),
    )
    adaptive = place(mark_white, adaptive_px, FRAC_ADAPTIVE)
    write(os.path.join(out, "ic_launcher_foreground.png"), adaptive)
    write(os.path.join(out, "ic_launcher_monochrome.png"), adaptive)

print("android status-bar icon:")
# A separate resource from the launcher icon, and it has to be: Android draws a
# notification's small icon from its ALPHA CHANNEL ONLY, discarding colour and
# painting the silhouette in the system tint. ic_launcher is a rounded square
# that is 96% opaque, so pointing a notification at it renders a solid white
# blob with the mark nowhere in sight — which is what this app shipped.
#
# 24dp is the platform size for a status-bar icon, so these are much smaller
# than the launcher densities.
for bucket, scale in DENSITIES.items():
    write(
        os.path.join(RES, f"drawable-{bucket}", "ic_notification.png"),
        place(mark_white, round(24 * scale), FRAC_NOTIFICATION),
    )

print("ios launch image:")
# Flutter's template ships a 1x1 fully transparent LaunchImage on a white
# storyboard background, so an unbranded iOS cold start is a blank white
# screen. Android's equivalent (drawable/launch_background.xml plus the
# values-v31 SplashScreen entry) is branded, and these two should agree.
#
# Transparent, not rose: LaunchScreen.storyboard paints the brand rose behind
# it, exactly as the Android launch window paints @color/brand_launch_background
# under the foreground layer.
IOS_LAUNCH = os.path.join(
    "ios", "Runner", "Assets.xcassets", "LaunchImage.imageset"
)
for suffix, scale in [("", 1), ("@2x", 2), ("@3x", 3)]:
    w = LAUNCH_IMAGE_WIDTH_PT * scale
    trimmed = mark_white.crop(mark_white.split()[3].getbbox())
    h = max(1, round(w * trimmed.size[1] / trimmed.size[0]))
    # Sized to the mark itself rather than padded into a square: the storyboard
    # centres the image, so any padding baked in here would only offset it.
    write(
        os.path.join(IOS_LAUNCH, f"LaunchImage{suffix}.png"),
        trimmed.resize((w, h), Image.LANCZOS),
    )

print("web social card:")
# The image a shared link shows on WhatsApp, Messenger, Facebook, X and iMessage
# — the app's most public surface, and it carried no image at all before this.
#
# Landscape 1200x630 rather than the 512 app icon: every one of those platforms
# crops or letterboxes a square into a wide card, and several will fall back to
# a tiny thumbnail. This is also the only place the real wordmark ships, so it
# is the one output built from logo_lockup rather than the mark alone.
CARD_W, CARD_H = 1200, 630
card = Image.new("RGB", (CARD_W, CARD_H), BRAND)
lockup_white = recolour(lockup_rose, WHITE)
lw = lockup_white.crop(lockup_white.split()[3].getbbox())
# 0.62 of the width: wide enough to read as the brand at thumbnail size, with
# enough ground left that the card does not look like a cropped banner.
target_w = round(CARD_W * 0.62)
target_h = max(1, round(target_w * lw.size[1] / lw.size[0]))
lw = lw.resize((target_w, target_h), Image.LANCZOS)
card.paste(
    lw, ((CARD_W - target_w) // 2, (CARD_H - target_h) // 2), lw
)
write(os.path.join("web", "social-card.png"), card)

print("web favicon.ico:")
# Browsers, crawlers and feed readers probe /favicon.ico by convention. There
# was no such file, and wrangler.jsonc sets not_found_handling to
# single-page-application, so that request answered **200 with a 16KB HTML
# document**. A 404 would at least let the client fall back cleanly to the
# <link rel="icon"> tags; a 200 hands it a page where it expected an image, on
# every cold load.
#
# flutter_launcher_icons does not emit .ico, and its favicon.png is 16x16 only.
# A multi-size .ico covers the tab at 1x, 2x and the bookmark bar without
# asking any client to upscale 16px artwork.
#
# No <link> tag points at this: modern browsers prefer the PNG links in
# index.html, and adding an .ico link would only compete with them. This file
# exists purely so the conventional path returns an image.
ICO_SIZES = [(16, 16), (32, 32), (48, 48), (64, 64)]
ico = place(mark_white, 256, FRAC_ICON, Image.new("RGB", (256, 256), BRAND))
ico.convert("RGB").save(
    os.path.join("web", "favicon.ico"), format="ICO", sizes=ICO_SIZES
)
print(f"  web/favicon.ico  {'/'.join(str(w) for w, _ in ICO_SIZES)}")

print("play listing icon:")
# 512x512, RGB with no alpha and no rounding of our own: Play applies its own
# mask, and a pre-rounded upload gets double-rounded.
write(os.path.join("store", "play", "icon-512.png"), legacy(mark_white, 512, None).convert("RGB"))
