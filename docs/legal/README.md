# Musaafir legal documents — markdown sources

Markdown sources for the platform's user-facing policies. The pages users and
Google Play actually see are the static HTML files under `web/legal/`
(served from `build/web` by the Cloudflare Worker; see `web/legal/_shared.md`).
**Privacy and Terms exist in both places — change one, change the other.** The
other five have no HTML counterpart yet and are not linked from the app.

| Document | Live HTML? | Status |
| --- | --- | --- |
| [privacy-policy.md](privacy-policy.md) | `web/legal/privacy.html` | Mirrors live page (2026-08-26) + payout/law-enforcement cross-links |
| [terms-conditions.md](terms-conditions.md) | `web/legal/terms.html` | Mirrors live page + links to the newer policies below |
| [refund-policy.md](refund-policy.md) | — | Draft. **Numbers (72h window, first-night retention, 10 working days) are unsigned-off proposals** |
| [major-disruptive-events-policy.md](major-disruptive-events-policy.md) | — | Draft. Force majeure; activation is a manual admin decision |
| [nondiscrimination-policy.md](nondiscrimination-policy.md) | — | Draft. Shared-space gender exception reflects seat-type listings |
| [law-enforcement-guidelines.md](law-enforcement-guidelines.md) | — | Draft. Written from the privacy policy's data table |
| [content-and-copyright-policy.md](content-and-copyright-policy.md) | — | Draft. Notice-and-review, not DMCA — Bangladesh has no DMCA machinery |

Provenance: structure informed by Travela (travela.xyz, fetched 2026-08-30 from
their public Firebase RTDB) and Airbnb's legal index (airbnb.com/help/feature/2,
notably articles 2868, 1320, 2867, 2878), then adapted to what this codebase
actually does — pay-after-accept via SSLCommerz, cash bookings, no service fee,
manual disbursements to admin-verified payout methods, phone-OTP identity.
Each file's HTML comment header records its specific sources and open
decisions.

**None of this is legal advice, and none of the drafts have been reviewed by
counsel.** Before the app is public: owner signs off the refund numbers,
counsel reads everything, the five drafts get HTML versions under `web/legal/`,
and all pages' footers link the full set.
