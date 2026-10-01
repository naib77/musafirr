# Listing cards and the Explore rows

Moved verbatim from `CLAUDE.md` on 2026-10-01 to keep that file small.
The short rule for each section is still in `CLAUDE.md`; the reasoning is here.

### One card size, and the text block sizes itself

`ListingCardModern` is rendered by four surfaces — the search grid, the "See
all" grid, the curated rows and Wishlists — and the first three carried their
own copy of `300` / `0.72`. The rows had drifted to 336px tall against the
grid's 378, so the same listing changed shape depending on which one you were
looking at. `kListingCardMaxExtent` / `kListingCardAspectRatio` are the one
size now; the rows derive their height from the ratio rather than typing it.

**The card's height used to be tied to its width by the flex split, and that
is what made it hard to shrink.** The photo was `flex: 5` against the text's
`flex: 2`, so the text slot was 2/7 of the cell whatever the text needed — at
1440px that is **108 pixels for about 43** (title 15.6 + gap 3 + rate row 16 +
8 of padding). Worse, the fat was load-bearing: narrowing the card narrowed the
text's headroom with it, so any real size reduction walked into an overflow at
a raised text scale.

The text block is its own intrinsic height now and the photo takes the
remainder. Three consequences worth keeping:

- **The inner `Column` must be `MainAxisSize.min`.** The parent `Column` hands
  a non-flex child unbounded height, so the default `max` asks for infinity.
- **The ratio and the flex are no longer the same fact.** Height ≈ width + ~43,
  and 0.82 is that relationship at the widths these grids actually produce —
  which is what keeps the photo roughly square, the shape the card is drawn
  for. Change the text block's contents and the ratio needs re-deriving.
- **Wishlists is deliberately not on the shared constants.** It is a fixed
  two-column grid, so its cell is much narrower and needs a taller ratio to
  reach the same photo; its `0.74` exists to hold the photo where `0.65` put it
  under the old flex.

Two tests in `listing_card_modern_test.dart` pin it by measuring the text
block's height in cells of two different heights. Under the old flex they read
78.3 and 120 — 2/7 of each — and both go red.

### The rate line is a hierarchy, not a string

`_buildRates` draws up to two rates under the photo, and it used to draw them
as one flat `fontSize: 12, w700` string joined with `·`. With the rating beside
it that is six numerals and two slashes at one weight, with nothing leading —
the guest has to read all of it to find the number they wanted.

It is a single `Text.rich` now (one `Text`, for the same reason the type badge
is one: with separate children only the last can shrink, so a narrow card
ellipsizes the wrong half). **The concatenated string is unchanged** — the
spans only carry weight, size and colour:

| Part | |
| --- | --- |
| Lead rate | 12.5, w700, `ink` |
| Its unit | 10, w600, `inkMuted` — it repeats on every card, so it carries almost no information per card |
| `·` | 10, w400, `inkMuted` |
| Second rate | 11, w600, `inkMuted` |
| Its unit | 9.5, w500, `inkMuted` |

The rating that follows is 10.5 with 8px of air before the star, up from 6 —
the phrase now ends on a muted unit, and without the extra gap the star reads
as part of it.

**A screenshot cannot catch this being flattened back**, because the string is
identical either way, so a test reads the spans off the `RichText` and asserts
the lead outweighs the second on all three axes at once. Restoring the flat
style turns it red.

Which rate leads is `offeredPlans` order, not a design choice — for a room
that means the *hourly* rate headlines over the daily. If that ever reads
wrong, it is `headlinePlans` to change, not this function.

### The curated rows are a rhythm, and the gap is a separator

Explore's browse state is a stack of `_CategorySection`s. The gap **between**
groups used to be each section's own top padding, which made it do two jobs: it
also sat above the very first row, under the header, where there is nothing to
separate. That kept it small — 22px against a 251px card — and five groups read
as one dense block.

It is the `ListView.separated` separator now (48px wide, 30 on a phone), so the
between-groups gap and the leading inset are separate numbers. The section's
own padding is only the gap down to its cards (16 / 12), which is what gives
the heading something to belong to: the rule is that the gap above a title must
clearly exceed the gap below it, or the title reads as attached to the row
above.

The heading is set explicitly rather than taken from `titleLarge` /
`titleMedium`, because at 26px the theme's default zero tracking reads as
stretched — it carries `letterSpacing: -0.6` and `height: 1.15`. Its colour is
**`AppColors.ink`, not `colorScheme.onSurface`**: every palette defines `ink`
as its own near-black at 18:1, so the heading follows `active_theme` instead of
being a hardcoded black that fights whichever palette an admin selects.
