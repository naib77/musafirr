# Public browse database changes, shareable URLs and the link-preview Worker

Moved verbatim from `CLAUDE.md` on 2026-10-01 to keep that file small.
The short rule for each section is still in `CLAUDE.md`; the reasoning is here.

### What the database had to change, and what it did not

Almost nothing: `listings`, `listing_facilities`, `reviews` (revealed),
`app_settings`, `landmarks`, `public_profiles` and the `listing-images` bucket
were already `to public`. Search, voice search and the Supabase client needed no
changes at all — the compiled-in key is already the `anon` role.

**113** fixed the one real gap: `facilities` had a `to authenticated` policy, so
a visitor saw **no amenity chips anywhere and got zero results from any search
with an amenity ticked** — silently, because the inner join just collapsed. See
the default-privileges note under Supabase for why a *policy* was the only
thing that could have been broken.

**114** moved the identity gate into the database. Before it, live had 8
bookings from guests with `verification_status = 'none'` and 3 listings owned by
a `role='tenant'` account with no verification — the client gate leaked, and the
live listings INSERT policy checked only `owner_id` (001's version, with the
role clause, never ran here). It is INSERT-time only, so existing rows are
untouched; two owners must finish verification before publishing again.

Both are verified by `supabase/tests/113_114_public_browse_and_identity_test.sql`
— a rolled-back impersonation matrix, 16 rows, run against live. Six of them go
red without the migrations; keep it that way.

### Shareable listing URLs

`/listing/<uuid>` is the only named route; everything else still navigates by
pushing a constructed screen, which is fine — those have no shareable identity.
A card tap passes the `Listing` through `arguments` so nothing re-fetches;
`ListingRoute` fetches by id only when the id came from a pasted link.

`listingIdFromRoute` (`lib/core/routing/listing_path.dart`) is deliberately
strict about the uuid shape, because `not_found_handling:
"single-page-application"` means Cloudflare answers **every** unknown path with
`index.html` — so that function is handed whatever a crawler or a probe asked
for, and a loose pattern would turn `/wp-admin` into a PostgREST query
comparing a uuid column against junk. It has tests; they include the junk.

### The site is now a Worker, for link previews only

`worker/index.js` rewrites the Open Graph tags on `/listing/<uuid>` so a stay
shared to WhatsApp previews as itself. This *has* to happen at the edge: a
crawler reads the HTML and never runs the Dart, so the app cannot set a `<meta>`
in time.

Nothing else changed cost. With both `main` and `assets` set, Cloudflare serves
any request matching a file straight from the asset store **without invoking the
Worker** — `/`, the bundle and every image are exactly as before. Only paths
with no file behind them reach it, and everything but a listing URL is handed
back to `env.ASSETS.fetch` immediately.

Four things in there that are not obvious, and one of them is a security
property:

- **`setAttribute`, never string concatenation.** A listing title is
  host-supplied and lands inside `content="…"`. `HTMLRewriter` escapes it;
  a template string would have injected into every crawler and chat client
  that renders the card. Proven, not assumed — the verify script feeds it a
  `"><script>` title through a stub and a control that swaps in `el.replace`
  goes red.
- **Fetch the shell as `/`, not `/index.html`.** The asset server answers
  `/index.html` with a **307 to `/`**, and returning that redirect verbatim
  sends the crawler to the un-rewritten home page — which looks exactly like
  the Worker never running.
- **A handler object must not have a `text` field.** `HTMLRewriter` reads
  `element`/`text`/`comments` off whatever it is given, so a class with
  `this.text` is silently taken to be declaring a text handler and the whole
  transform dies with *"the provided value is not of type 'function'"*. Hence
  plain handlers.
- **Cache the lookup, never the rewritten HTML.** Caching the page at the edge
  would pin the `main.<hash>.dart.js` reference inside it, and the next deploy
  would hand visitors a shell pointing at a bundle that no longer exists.

It reads `listings.address`, which is the **area** label — 093 moved exact
addresses behind a booking check. Never widen that select to a door number: this
string goes on a public card.

`SUPABASE_URL`/`SUPABASE_ANON_KEY` are `vars` in `wrangler.jsonc` for the same
reason `SupabaseConfig` takes them as `--dart-define`: the two deploy branches
go to different Cloudflare accounts and may point at different projects. Point a
build elsewhere and these need pointing too, or previews describe the wrong
database.

**`sh tool/verify_link_previews.sh`** is the loop — real listing from live, then
the hostile-title stub. Like `verify_phone_parity.sh` it is not in CI, which has
no node step.
