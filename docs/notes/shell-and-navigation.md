# Public browsing, auth gates and the desktop header

Moved verbatim from `CLAUDE.md` on 2026-10-01 to keep that file small.
The short rule for each section is still in `CLAUDE.md`; the reasoning is here.

## Browsing is public; acting is not

The whole app used to sit behind one `switch` arm — `unauthenticated →
AuthNavigator` in `app.dart` — so nothing rendered without a session. It now
renders `MainShell` for a visitor too, and login is reached from whatever they
tried to do.

**Return the same widget type from both post-`initializing` arms.** Flutter
updates an element in place when the type and key match, so signing in
mid-session keeps `MainShell`'s state: the selected tab, each tab's scroll
offset, the `_LazyIndexedStack`'s already-built children. Branching to a
different widget would rebuild all of it, which is what the old arm did on
every login.

**Login is a pushed route, and that IS the "return them to what they were
doing" mechanism.** `AuthFlow.ensureSignedIn` pushes and awaits; the listing
detail screen with its dates chosen stays mounted underneath, so the caller
just carries on. There is no pending-intent store to keep in sync — do not add
one. It works because `MainShell` has **no Navigator of its own** (it is a
`_LazyIndexedStack`), so pushes land on the root navigator as siblings of
`home:`, where an auth-driven rebuild of `home:` cannot touch them.

Three gates, all shaped alike — `false` means stop, and the gate has already
said why:

| Gate | Question |
| --- | --- |
| `AuthFlow.ensureSignedIn` | is there a session? |
| `IdentityGate.ensure` | is the identity admin-approved? |
| `PublishGate.ensure` | may this person publish? (composes the other two + address proof) |

`PublishGate` exists because `CreateListingScreen` is pushed from **three**
places and two of them — the host dashboard and the profile screen — were bare
`Navigator.push` calls with no checks at all. Duplicating the guard would have
left the same trap for the fourth caller. Never push that screen directly.

**`if (userId != null)` is not a gate, it is a bypass.** Both identity checks
were written that way, which was safe only while the app was unreachable
without a login: a null user took the `else` branch and got the whole booking
sheet — dates, guests, coupon, Confirm — before a dead-end "Please log in to
book". Require the login; do not tolerate its absence.

`_goToGuestTab` refuses any tab but Explore while signed out, centrally, so a
new shortcut cannot reintroduce that hole. The signed-out nav bar is a
*separate* two-item bar rather than a filter over the five-item list, because
`_guestTabIndex` is a logical id that `_buildGuestContent`,
`_goToGuestTab(0..4)` and `ShellNavState.openGuestTrips()` all index with —
renumbering the destinations would silently repoint every one of them.

### Desktop wears a top header, not a rail

Above `Responsive.wide` (1000px) the shell renders [`DesktopTopNav`
](../../lib/widgets/desktop_top_nav.dart) — brand, centred destinations, account
menu, plus a Where/When/Who search pill on Explore. It replaced an extended
`NavigationRail`, which spent ~220px of every viewport on five fixed labels and
left the search field buried inside a scrolling tab.

Below that breakpoint **nothing changes** — the bottom bar and Explore's own
in-page search row are untouched. There is deliberately no drawer fallback in
that file; the hamburger is the account affordance, not a responsive collapse.

Three things there that are easy to break:

- **The header owns no state.** Destinations, actions and menu items all come
  from `MainShell`, and every selection goes back through `_goToGuestTab` so it
  keeps that gate. A header that tracked its own index is a second navigation
  model, which is exactly what the shared `_guestTabIndex` above exists to
  prevent.
- **`selectedIndex: -1` is a real state, not a bug.** Profile is logical tab 4
  and lives in the account menu rather than the strip, so while it is showing,
  no destination is current — `accountHighlighted` rings the account button
  instead. Do not "fix" it by adding Profile as a fifth destination; the
  indices are shared with the bottom bar (see above).
- **`ExploreScreen.searchInShell` is passed, not re-derived.** The header
  carries the search pill, the leaderboard trophy and the notification bell, so
  Explore hides its whole in-page header row on desktop. The shell decides when
  it draws a header; a second copy of `Responsive.isWide` inside Explore would
  be a second thing to keep in step. The pill drives Explore's *existing*
  search through three public methods on its state — there is one search
  implementation and the header is a remote for it.

`searchPillSummaryFor` (`lib/services/search/search_summary.dart`) is the only
place that renders a whole `SearchFilters` into one line, and it has tests. It
shows nothing for `guestCount == 1`, matching `hasActiveFilters` — otherwise
every untouched pill would look like it was already narrowing the feed. The ✕,
though, keys off `hasActiveFilters` rather than the summary, because a property
type or an amenity is an active search the pill has no segment for.
