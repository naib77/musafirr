# Search UI: desktop pill, mobile sheet, turf scope

Moved verbatim from `CLAUDE.md` on 2026-10-01 to keep that file small.
The short rule for each section is still in `CLAUDE.md`; the reasoning is here.

### The search bar is four panels over one draft

`lib/widgets/search/` is the desktop search: Where / When / Who each open their
own popover anchored under that segment, plus a Filters button for type and
purpose. **`_SearchSheet` in `explore_screen.dart` is still the whole of
mobile**, but it is no longer a parallel implementation of everything: the
guest rows and the calendar are now the same widgets the desktop panels use,
and only the Where field is still written twice. The cure the earlier note
described — rebuilding the sheet as a stack of these panels — has been paid for
piece by piece as each duplicate actually cost something.

### The mobile sheet folds; the desktop bar does not

`_SearchSheet` is an accordion of three [`SearchSection`
](../../lib/widgets/search/search_section.dart) cards — Where / When / Who, exactly
one open, the closed ones showing what that step currently holds. Before that
it was every control at once: a text field, a suggestion list, a mode toggle,
two date cards, two time cards and four guest steppers down one scroll.

Three things worth keeping:

- **The sheet owns which section is open, not the cards.** Two open sections
  would put the month grid and the guest steppers on screen together and undo
  the point; a card that tracked its own expansion could not prevent that. Same
  reasoning as `MainShell` owning the selected tab.
- **The collapsed summaries come from `searchPillSummaryFor`** — the desktop
  pill's function, so the two surfaces cannot describe one search differently.
  Only the `SearchFilters` handed to it is built locally (`_summaryFilters`),
  and that is deliberately **not** `_applySearch`'s projection: that one layers
  over the live filters with clear flags because it is about to be committed.
- **The date dialogs are gone.** `showDateRangePicker` / `showDatePicker` are
  full-screen modals on a phone, launched from inside a bottom sheet — two
  layers of chrome for one decision, with the sheet invisible behind. The
  inline `DateCalendar` is simply there instead. The two clock times keep their
  native picker: a two-thumb time control is its own build, and a dialog is a
  fair answer for a value with no spatial meaning.

Type and purpose are **not** two more folds, and they are not together:

- **Property type sits above the three cards.** Seat / room / whole house is
  the widest cut the sheet makes — it changes what the other questions even
  mean — so it is answered first and stays visible while they are worked
  through. The reference puts its own equivalent in the same place.
- **Purpose lives inside Where.** Choosing one is a way of answering *where*:
  picking "Medical" opens the landmark picker, and the hospital that comes back
  becomes the Where text, the search's centre point and the summary that card
  shows. It was only ever a separate row because it arrived from the Explore
  page as one.

Neither is folded away. They are one control each, and burying a control behind
a tap is how the type chips stopped being noticed the last time.

[`PurposePicker`](../../lib/widgets/purpose_picker.dart) (was `PurposeScroll`) is a
`Wrap` now, not a horizontal `ListView`. Both of its call sites sit inside a
padded card, and a horizontal scroller clips at the **padding**, not the card
edge — the last pill came out sliced mid-word with a clear gap after it, which
reads as broken rather than as "scroll me". Two traps if you touch it: a `Wrap`
hands each child the **full line width**, so the pill's `Row` needs
`mainAxisSize: MainAxisSize.min` or every pill becomes its own full-width bar
(that shipped, and the screenshot caught it, not the test — the test now
measures the pill's `Material`, because under that bug the label's own rect is
unchanged); and the pill must not carry a trailing margin of its own, or it
doubles the `Wrap`'s spacing.

`DateCalendar` grew two things for this. **`DateCalendarMode.singleDay`**,
because hourly search is one date and driving it as a range meant the second
tap silently did nothing visible (it produced `range(5, 8)` and the caller kept
`.start`). And a **width-adaptive cell**: the grid was a hard 7 × 40px, which
overflows a 320px phone once the sheet's padding and the card's are taken out.
The measurement lives in `DateCalendar.build`, **not** in `_MonthGrid` — the
grid sits in a `Row`, and a `Row` lays out a non-flexible child with unbounded
width, so a `LayoutBuilder` down there is handed infinity and learns nothing.
The first attempt did exactly that and still overflowed by 40px.

The guest counter is the first control that drift actually cost, and it is now
the worked example of the cure. Mobile's version was a lone 1..16 number, so
when Who grew to adults / children / infants / pets there was nowhere on the
phone to say three of the four. The rows moved into
[`GuestPartyFields`](../../lib/widgets/search/guest_party_fields.dart), stateless over
a `GuestParty` value and a callback — the one shape a `SearchDraft` and a plain
`setState` can both hold — and both surfaces render it. Neither knows how many
rows there are or what the caps are. **Do not add a fifth category to one of
them.**

Two things in that widget are load-bearing and have negative-controlled tests:
adults and children share **one** budget (their sum is `guestCount`, so both
`+` buttons must stop together, or the party can be walked past the cap one row
at a time), while infants and pets have their own ceilings because the database
counts them separately. Each row's `max` is its own value plus the remaining
headroom rather than a bare limit, so a party restored from a wider cap can
still be brought down instead of being stranded above a `max` below its value.

- **Every `SearchStateNotifier` mutator runs a search immediately.** So the
  panels write to a `SearchDraft` and exactly **one** `updateFilters` fires,
  from the Search button. Three panels committing on close would be three
  `search_listings` round trips for one search. `search_pill_test.dart` asserts
  the commit count, not just the result — keep it that way.
- **`filtersFromDraft` is pure and wipes before it sets.** The two date modes
  store their shapes side by side, and passing `null` for the inactive one does
  *not* clear it (`copyWith` reads null as "unchanged"), so a range picked after
  an hourly window used to leave a stale `singleDate` keeping
  `hasActiveFilters` true. It clears both modes' fields first, then writes back
  only the active one. Three tests go red if that is undone.
- **`OverlayPortalController.show()` must never be called from build.** It
  asserts on it, and an assertion thrown inside the overlay child paints a
  **full-screen dark red `ErrorWidget`** — that child covers the window, which
  is what "the whole screen goes red" was. `_setOpen` is the only writer of
  which segment is open and the only caller of `show`/`hide`, and every caller
  of it is an event handler.
- **Nothing reads layout during build.** The scrim used to be positioned from a
  `localToGlobal` inside `build`. `SearchPill` now measures the bar and each
  segment in a post-frame callback and holds the rectangles in state (guarded
  on `attached` as well as `hasSize`, since it runs a frame late). The panel is
  an `AnimatedPositioned` over those numbers.
- **The lifted white segment is ONE card that travels, not a colour on each
  segment.** It was the latter: every `_Segment` cross-faded its own
  background, so Where→When was Where going grey while When went white — two
  dissolves that line up, which the eye reads as "selected", not "moved". The
  card is an `AnimatedPositioned` layered under the segments in
  `SearchPillBar`, moved between their measured slots (a frame late, against
  the Stack, not the bar — the 1px border is `Container` padding), and an
  active segment paints `alpha: 0` of its own. Opening from closed snaps
  (`Duration.zero`) rather than sliding in from wherever the bar was last
  open. The motion test's first version compared the card to the *label*,
  which sits 22px inside the slot, and passed against a snapping card; it
  reads the slot now, and the negative control is `duration: Duration.zero`.
- **The Search button is `Brand.rose`, not the palette's `brand`, and it
  grows a label while any panel is open.** It is the one call to action on
  the page and has to read the same under every palette — under `coral_ink`
  the palette brand is #222222 and it was a black disc like every other icon.
  `Brand.roseDeep` is the gradient's far end; `brand_test.dart` holds white
  on both ends to 4.5:1. The label is the editing-state cue (Airbnb's), and
  **the room it takes comes out of Who's slot only**: the mic, ✕ and button
  live *inside* Who's `Expanded` (flex 4:3:5), because beside the three
  segments their growth squeezed all three — Where and When slid 25px and
  19px as the button opened and the lifted card, measured a frame late,
  chased them. The card for Who covers that whole outer slot (`_whoSlot`), so
  an open Who is a white card with the Search button inside it, which is
  also what Airbnb draws. A motion test pins Where, When and Who's label
  still on every frame of the expansion.
- **Every panel is the same width, and that is load-bearing.** They differed
  per segment and the card animated between them — but the cross-fade lays
  *both* panels out during the transition, so the calendar got laid out at the
  Who panel's width and its fixed 40px month grid overflowed by 45 pixels. Any
  width one panel cannot survive is a width neither can use.
- **Switching segments is a slide and a cross-fade, not a swap.** Position,
  width and contents all changing in one frame is what "it flicks" described.
  `search_pill_motion_test.dart` asserts on the frames *between* states; four
  of its five tests go red if the durations are zeroed.
- **`CallbackShortcuts` needs something focused inside it.** The panel's
  `FocusScope` is `autofocus: true` or Escape does nothing in a panel with no
  text field (Who, Filters).
- **Focusing a text field notifies its controller with unchanged text.** The
  Where panel's listener therefore treats an empty query as "show the default
  destinations", not "show nothing" — the earlier version emptied the list the
  instant the panel opened.
- **Outside-click dismissal is a `TapRegion` group, not the scrim.** The scrim
  starts 16px below the bar on purpose (the header stays bright), so it cannot
  see a click beside or above the bar — the logo, the destinations, the account
  menu, the empty header space — and the panel sat open through all of them.
  The bar, the Filters button and the panel card share `groupId: this` on
  `SearchPill`; a tap landing in none of them closes. `TapRegion` does not
  swallow the tap, so the account menu still opens. **The handler checks
  `ModalRoute.isCurrent` first**: the hourly time pickers are dialogs *above*
  this route, and every tap inside one is "outside" the bar — without the
  guard, picking a time closed the panel under the dialog. The negative
  control is removing `onTapOutside`; one test goes red.
- The landmark picker is a route-level modal sheet, so `SearchPill` closes the
  popover, awaits the pick and reopens it. A bottom sheet over a dropdown reads
  as two competing surfaces.
- **Never animate to or from `Colors.transparent`.** It is transparent
  *black*, and `Color.lerp` walks r/g/b and alpha independently — so fading a
  segment from it to any light colour spends the middle of the animation
  painting a half-opaque near-black. That was the hover flicker: filmed in
  Chrome at 1440px with the cursor parked, a segment went 244 → **179** → 225
  in luminance, a dark pill that flashed and then lightened into the real grey.
  The same lerp ran on every tap, since the lifted card fades in to white, so
  one bug produced both "it flickers on hover" and "it flicks when I switch
  tab". The resting colour is the **bar's own colour at zero alpha** now, and
  the dimmed hover is flattened with `Color.alphaBlend` rather than left
  translucent. `desktop_top_nav.dart` had it twice as well. Two tests in
  `search_pill_motion_test.dart` sample the painted colour every 20ms and fail
  on anything darker than the colour the fade ends on — a settled assertion
  cannot see this by construction, and neither can a screenshot.
- **The contents slide, because the card barely moves.** Where to When is 89px
  at 1440px and When to Who was **24px** — so the `AnimatedPositioned` travel
  the earlier note describes is real but invisible, and a plain cross-fade was
  the whole of what a switch looked like. The outgoing panel now leaves by one
  side and the incoming arrives from the other, 16% of the panel's width, keyed
  on which way along the bar the tap moved (`_travel`). Two things about it:
  `AnimatedSwitcher` hands the **same** builder to both children, so which one
  is incoming has to be read off the key or they move as a block; and the two
  curves are deliberately different (`easeOutCubic` in, `easeInCubic` out)
  because the outgoing child's animation runs *backwards* — with the same curve
  on both, the incoming panel had travelled 72% before the outgoing had moved a
  tenth, which is a dissolve with a slide underneath. Who also anchors its
  panel to the **bar's** right edge rather than its own segment's, since the
  mic and the Search button sit between them; that is both what Airbnb does and
  what gives the card somewhere to travel to.
- **The panel fades in and out; only the travel between segments used to
  animate.** Opening mounted the card whole and dismissing dropped it, so the
  same interaction was smooth in the middle and a cut at both ends. A
  `CurvedAnimation` drives opacity and a 3% drop, and the portal is taken down
  from a **status listener** when the fade reaches zero — not from the tap,
  because `OverlayPortalController.hide()` during a build asserts. The segment
  being closed is held in `_closing` for exactly that long, or the overlay
  child reads a null `_open` and renders nothing in the frame the fade starts.
  The fading card is wrapped in `IgnorePointer` so it cannot eat the click that
  is dismissing it.

`SearchFilters` gained `adults`/`children`/`infants`. `guestCount` is still the
only one that reaches the RPC, derived through `guestCountFor` (infants never
count, floor 1, cap `maxSearchGuests`). **The split is search-only** — bookings,
the price breakdown and the host's reservation list all still carry one number,
so a stay found as "2 adults, 1 child, 1 infant" is booked as 3 guests.

### Turf is one tap in Where, and it cannot be combined with a purpose

Turf reached the app as a `ListingType`, which correctly put it in the Filters
panel beside Seat and Room — and made finding a ground four steps on **desktop**
(open Filters, tick Turf, close, type the area) against Medical's one visible
tap. A ground is not an overflow refinement of a stay search; it is a different
search. [`SearchScopePicker`](../../lib/widgets/search/search_scope_picker.dart) is
an Anything / Turf pair under the Where field, and it writes a `ListingType`
like the Filters chips do.

**It is desktop-only, and that asymmetry is the point.** The mobile sheet
already carries a type chip row above its three cards (see above — it is
deliberately not folded away), so Turf was always one tap there. Adding the
pills to the sheet as well put two selected "Turf" controls one above the
other describing one piece of state, which is what shipped for one build. The
sheet's `_togglePropertyType` carries the exclusion rule instead.

Nothing in the search stack needed changing for it. Verified against live by
inserting a turf in Uttara inside a rolled-back transaction and calling
`search_listings` the way the client does: turf + centre + radius tiers, turf +
`p_location`, turf + dates, turf + 20 players all returned it, and `room` at
the same centre returned the three real rooms. The map needed nothing either —
`mappableListings` filters on coordinates alone, and `isStay` is used only in
the host wizard.

**The rule that makes this more than a shortcut: turf and purpose are mutually
exclusive.** `search_listings` ANDs its predicates and `purpose_tags` is a
column on stays — a turf carries none — so "turf near a hospital" matches
nothing. It does not raise: it returns zero rows, which
`searchListingsFromDb` renders as a plain "no listings found", and the guest
cannot tell that apart from "there are no turfs in this area". So
[`search_scope.dart`](../../lib/services/search/search_scope.dart) owns both
directions — picking Turf drops the purpose and its landmark, picking a purpose
drops Turf — and the purpose section is *hidden* while the scope is turf rather
than shown and ignored.

Three things worth keeping:

- **It is a pure function over values, not a method on the draft.** The desktop
  panel holds a `SearchDraft` and the mobile sheet holds plain `setState`; a
  rule written into either one is a rule the other can contradict. Same reason
  `GuestPartyFields` is stateless over a value.
- **`scopeOf` lights up Turf only when turf is the *only* type.** "Rooms and
  turfs" is a real search the Filters panel can express and is neither scope —
  showing Turf as selected for it would make the next tap silently drop the
  room.
- **Anything removes turf and nothing else.** A guest who narrowed to Room and
  then tapped Anything is saying "not just turf", not "forget what I picked".

Turf did **not** become a `ListingPurpose`, and should not. Purpose is what a
*stay* is for; the type/purpose split is the thing that lets "a room near a
hospital" and "a turf in Uttara" both be expressible.

**The dropdown offers the listings themselves, above the places.** It used to
answer a typed query with places only — "Uttara", "Uttara North Metro Rail
Station", "Uttara University" — which is the right question while the guest has
not said what they want, and the wrong one the moment they pick Turf: a place
row commits them to a round trip before they see a single ground.
`listingSuggestionsFrom` matches title, address and city together (a guest
typing "uttara" means the area, one typing the ground's name means the ground,
and the field cannot tell which), narrowed to the search's types, capped at
four so the place predictions stay reachable. The heading names what it is
offering — "Matching turfs", not "Matching stays" — and the predictions below
are headed "Places" rather than "Search results", which claimed the answer
while sitting under the real one.

Tapping a row **opens that listing and commits no search**. Two consequences:
the bar closes first, because the panel is an overlay and a pushed screen
underneath it is the mistake the landmark picker already avoids; and the shell
routes it through `ExploreScreen.openListingFromShell` rather than pushing
itself, so it uses the one path that passes the `Listing` through `arguments`
and stops the detail screen refetching. **`_exploreScreenKey` is a
`GlobalKey<dynamic>`**, so nothing checks that method exists until it is
called — renaming it fails at runtime, silently, in one dropdown.

**The destination rows count within the scope, not across the catalogue.**
`citySuggestionsFrom` used to count every listing, so a turf-scoped search
offered "Dhaka — 9 stays" where the nine are rooms and seats: tapping the row
and pressing Search returned nothing, and the list had promised otherwise.
It takes the search's types now and names what it counted ("1 turf"), and the
noun falls back to the generic one for two types, because "3 rooms and turfs"
is not a noun. `CitySuggestFn` gained the types parameter for this — the panel
reads them off the draft, so the shell does not have to know.

That makes the list go **empty** for a type the app has none of, and
`citySuggestionsFrom`'s own doc says an empty list reads as broken. So the
panel says "No turfs listed yet — try Anything" rather than showing nothing.

**There are no turf listings on live** (11 seats, 7 rooms, 2 full houses, as of
2026-09-16), so every one of these searches correctly returns nothing until a
host publishes one. Do not read that as the feature being broken — it was the
first thing this investigation had to rule out.
