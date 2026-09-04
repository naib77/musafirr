/**
 * Per-listing link previews.
 *
 * `index.html` carries one fixed set of Open Graph tags, so every listing
 * shared to WhatsApp, Messenger or Facebook previewed as the same generic
 * card — the same title, the same stock image, whichever stay it pointed at.
 * A Flutter SPA cannot fix that from the client: a crawler reads the HTML and
 * never runs the Dart, so by the time the app could set a `<meta>` the
 * scraper has already left.
 *
 * So `/listing/<uuid>` is rewritten here, at the edge, before the bytes leave.
 *
 * Everything else is untouched and — importantly — never reaches this Worker.
 * With both `main` and `assets` configured, Cloudflare serves a request that
 * matches a file straight from the asset store; only paths with no file behind
 * them get here. `/`, `main.<hash>.dart.js` and every image therefore keep
 * exactly the cost and caching they had before this existed.
 */

/** `/listing/<uuid>` — mirrors listingIdFromRoute in lib/core/routing/. */
const LISTING_PATH =
  /^\/listing\/([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$/;

/** How long to wait on the listing lookup before shipping the generic card. */
const LOOKUP_TIMEOUT_MS = 2000;

/** How long the edge may reuse one listing's lookup. */
const LOOKUP_CACHE_S = 300;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const match = LISTING_PATH.exec(url.pathname);

    // Not a listing URL: hand straight back to the asset store, which applies
    // `not_found_handling: "single-page-application"` and returns index.html
    // for in-app routes like /trips.
    if (!match) return env.ASSETS.fetch(request);

    // The shell, fetched as `/` — NOT as `/index.html`, which the asset server
    // answers with a 307 redirect to `/` for canonicalisation. Returning that
    // redirect verbatim sent the crawler to the un-rewritten home page, which
    // looked exactly like the Worker never running.
    const page = await env.ASSETS.fetch(new Request(new URL('/', url), request));

    // Fail open, always. A preview is a nicety; the page loading is not. Any
    // problem below leaves the generic card in place rather than an error.
    let listing = null;
    try {
      listing = await lookup(match[1], env);
    } catch (err) {
      console.error('listing lookup failed', err);
    }
    if (!listing) return page;

    // HTMLRewriter, not string replacement. `title` is host-supplied text
    // going into an HTML attribute, so `Cox's Bazaar` or a title containing
    // `">` has to be escaped — setAttribute serializes it correctly, and a
    // template string would have been an injection into every crawler and
    // chat client that renders the card.
    const tags = metaFor(listing, url);
    return new HTMLRewriter()
      .on('title', { element: (el) => el.setInnerContent(listing.title) })
      .on('meta', { element: (el) => rewriteMeta(el, tags) })
      .transform(page);
  },
};

/** The tags to overwrite, keyed the way they appear in index.html. */
function metaFor(listing, url) {
  const bits = [placeOf(listing), guestsOf(listing), rateOf(listing)].filter(
    Boolean,
  );
  const description = bits.join(' · ');

  const tags = {
    'og:title': listing.title,
    'og:description': description,
    'og:url': url.href,
    'og:type': 'website',
    description,
  };

  // Only override the image when the listing actually has one; otherwise the
  // stock social card stays, which previews better than a broken image.
  const image = firstImage(listing);
  if (image) {
    tags['og:image'] = image;
    tags['twitter:image'] = image;
    // The stock card is 1200x630. A listing photo is not, and leaving the old
    // dimensions in place makes scrapers crop or letterbox it.
    tags['og:image:width'] = '';
    tags['og:image:height'] = '';
  }
  return tags;
}

function placeOf(listing) {
  // `address` is the AREA label, not the door — migration 093 moved exact
  // addresses into listing_addresses behind a booking check. Worth knowing
  // here, because this string ends up on a public card: reading a column that
  // held the street would publish every host's address to anyone with a link.
  return listing.address || listing.city || '';
}

function guestsOf(listing) {
  const n = Number(listing.max_guests);
  if (!Number.isFinite(n) || n < 1) return '';
  return n === 1 ? '1 guest' : `Up to ${n} guests`;
}

function rateOf(listing) {
  const daily = Number(listing.daily_rate);
  if (Number.isFinite(daily) && daily > 0) {
    return `৳${Math.round(daily).toLocaleString('en-US')}/night`;
  }
  const monthly = Number(listing.monthly_rate);
  if (Number.isFinite(monthly) && monthly > 0) {
    return `৳${Math.round(monthly).toLocaleString('en-US')}/month`;
  }
  return '';
}

function firstImage(listing) {
  const urls = listing.image_urls;
  if (!Array.isArray(urls)) return '';
  const first = urls.find((u) => typeof u === 'string' && u.startsWith('https://'));
  // Absolute only. A scraper does not resolve a relative og:image, and
  // Supabase storage URLs already are.
  return first || '';
}

/**
 * One listing, straight from PostgREST as `anon`.
 *
 * Same credentials and same RLS as the app, so this can only ever read what a
 * signed-out visitor could: the SELECT policy admits `is_active` listings
 * only, which is also the right answer for a preview — an unlisted stay should
 * not keep advertising itself through an old link.
 */
async function lookup(id, env) {
  const base = env.SUPABASE_URL;
  const key = env.SUPABASE_ANON_KEY;
  if (!base || !key) return null;

  const endpoint = new URL('/rest/v1/listings', base);
  endpoint.searchParams.set('id', `eq.${id}`);
  endpoint.searchParams.set('is_active', 'is.true');
  endpoint.searchParams.set(
    'select',
    'title,address,city,max_guests,daily_rate,monthly_rate,image_urls',
  );
  endpoint.searchParams.set('limit', '1');

  const res = await fetch(endpoint, {
    headers: { apikey: key, authorization: `Bearer ${key}`, accept: 'application/json' },
    // Cache the LOOKUP, never the rewritten HTML. Caching the page at the edge
    // would pin the `main.<hash>.dart.js` reference inside it, and a deploy
    // would then hand visitors a shell pointing at a bundle that no longer
    // exists — the stale-entry-point trap this repo has hit before.
    cf: { cacheTtl: LOOKUP_CACHE_S, cacheEverything: true },
    // A slow database must not hold the page. On abort this throws, the caller
    // logs it, and the generic card ships.
    signal: AbortSignal.timeout(LOOKUP_TIMEOUT_MS),
  });
  if (!res.ok) {
    console.error('PostgREST', res.status, await res.text().catch(() => ''));
    return null;
  }
  const rows = await res.json();
  const row = Array.isArray(rows) ? rows[0] : null;
  // A row with no title would produce a card titled "undefined".
  return row && typeof row.title === 'string' && row.title ? row : null;
}

/**
 * Overwrites the `content` of one `<meta>` tag, if [tags] names it.
 *
 * index.html spells them two ways — `property` for Open Graph, `name` for
 * `description` and the Twitter tags — so both are checked. An empty value
 * removes the tag, which is how the stock card's 1200x630 dimensions are
 * dropped for a listing photo that is not that shape.
 *
 * Plain handler objects rather than classes, deliberately: HTMLRewriter reads
 * `element`, `comments` and `text` off whatever it is given, so a class with a
 * `this.text` field is silently taken to be declaring a text handler and the
 * whole transform fails with "the provided value is not of type 'function'".
 */
function rewriteMeta(el, tags) {
  const key = el.getAttribute('property') || el.getAttribute('name');
  if (!key || !(key in tags)) return;
  const value = tags[key];
  if (value === '') {
    el.remove();
    return;
  }
  // setAttribute escapes, which is the reason this is not string replacement:
  // `title` is host-supplied and lands inside an HTML attribute.
  el.setAttribute('content', value);
}
