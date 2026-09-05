import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/core/routing/listing_path.dart';

void main() {
  const id = '9c5181a0-b69f-476c-958f-0202c8f8f4d4';

  group('listingIdFromRoute', () {
    test('reads the id out of a listing path', () {
      expect(listingIdFromRoute('/listing/$id'), id);
    });

    test('round-trips with listingRoutePath', () {
      expect(listingIdFromRoute(listingRoutePath(id)), id);
    });

    // A shared link picks these up in the wild — pasted out of an analytics
    // redirect, or with an anchor appended — and the web's initial route is
    // whatever is in the address bar, not a path the app built.
    test('ignores a query string and a fragment', () {
      expect(listingIdFromRoute('/listing/$id?utm_source=whatsapp'), id);
      expect(listingIdFromRoute('/listing/$id#photos'), id);
      expect(listingIdFromRoute('/listing/$id?a=1#b'), id);
    });

    test('the app root is not a listing', () {
      expect(listingIdFromRoute('/'), isNull);
      expect(listingIdFromRoute(''), isNull);
    });

    // Everything below reaches this function in production, because
    // wrangler.jsonc answers every unknown path with index.html. None of them
    // may become a database lookup: fetchListingById would have PostgREST
    // compare a uuid column against the value, which errors rather than
    // returning nothing.
    test('rejects anything that is not a canonical uuid', () {
      for (final route in <String>[
        '/listing/',
        '/listing',
        '/listing/not-a-uuid',
        '/listing/12345',
        // 36 chars, but not a uuid — a length-only check would let this in.
        '/listing/------------------------------------',
        '/listing/$id/extra',
        '/listing/../../etc/passwd',
        '/listings/$id',
        '/LISTING/$id',
        '/wp-admin',
        '/favicon.ico',
      ]) {
        expect(listingIdFromRoute(route), isNull, reason: route);
      }
    });

    test('accepts either case of hex, as uuids are written both ways', () {
      expect(
          listingIdFromRoute('/listing/${id.toUpperCase()}'), id.toUpperCase());
    });
  });
}
