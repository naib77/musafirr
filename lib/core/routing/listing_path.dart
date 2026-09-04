/// The `/listing/<id>` URL, in both directions.
///
/// Worth its own seam because of how the site is served: `wrangler.jsonc` sets
/// `not_found_handling: "single-page-application"`, so Cloudflare answers
/// **every** unknown path with `index.html`. This function is therefore handed
/// whatever a crawler, a mistyped link, or a probe happened to ask for — not
/// just paths the app generates — and it decides whether that becomes a
/// database lookup.
library;

/// A listing id as it appears in a URL: a canonical uuid.
///
/// Deliberately strict rather than `([^/]+)`. A loose pattern would turn
/// `/listing/../../etc` or a 4KB query string into a Supabase round trip on
/// every crawl, and `fetchListingById` would ask PostgREST to compare a uuid
/// column against it — which is an error, not an empty result.
final RegExp _listingPath = RegExp(
  r'^/listing/([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}'
  r'-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$',
);

/// The listing id in [route], or null when [route] is not a listing URL.
String? listingIdFromRoute(String route) {
  // A named route arrives without a query string, but an initial route on the
  // web is whatever is in the address bar — `?utm_source=…` and `#section`
  // included, since a shared link picks those up in the wild.
  final path = route.split('?').first.split('#').first;
  return _listingPath.firstMatch(path)?.group(1);
}

/// The shareable path for [listingId].
String listingRoutePath(String listingId) => '/listing/$listingId';
