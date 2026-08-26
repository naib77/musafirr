These three pages are plain static HTML under `web/`, so `flutter build web`
copies them into `build/web` verbatim and the existing Cloudflare Worker
(wrangler.jsonc → assets.directory = ./build/web) serves them. No extra hosting,
no extra deploy step.

They exist because Google Play requires a publicly reachable privacy policy and
an account-deletion request URL, and `lib/config/legal_links.dart` pointed at
`musaafir.app`, which does not resolve. Serving them from the same origin as the
app means the link in the store listing and the link inside the app are the same
URL, and they keep working if the domain is later pointed at this Worker.

`_shared.md` is underscore-prefixed on purpose: Flutter's web build skips
underscore-prefixed files (the same quirk that makes tool/build_web.sh copy
web/_headers by hand), so this note never ships.

NOT LEGAL ADVICE. The factual claims — what is collected, who it goes to — were
read off the code and are accurate as of 2026-08-26. The wording has not been
reviewed by a lawyer, and Bangladesh has no single omnibus data-protection
statute to template against. Have counsel read them before the app is public.
