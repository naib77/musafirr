# Edge function type-checking and accessibility labels

Moved verbatim from `CLAUDE.md` on 2026-10-01 to keep that file small.
The short rule for each section is still in `CLAUDE.md`; the reasoning is here.

### An edge function is TypeScript nobody was checking

Three of the thirteen did not `deno check` at all. The one that mattered:
`messenger-webhook` called `.catch()` on a `PostgrestFilterBuilder`, which is
a thenable with no such method — the "best-effort" analytics guard was a
runtime `TypeError`. `validate-discount` passed a possibly-null discount into
a function that could not take one.

- All nine `esm.sh/@supabase/supabase-js@2` imports are **pinned to 2.45.4**.
  Unpinned, the specifier resolves to whatever is newest on the day, and two
  files that resolved differently produced `SupabaseClient<any, "public",
  any>` against `SupabaseClient<unknown, never, GenericSchema>` — not
  assignable, for no change on our side.
- **`ReturnType<typeof createClient>` is not the type `createClient(url, key)`
  returns.** The bare form picks the unparameterised overload. Annotate
  helpers with `SupabaseClient` (via a local `Db` alias), not with
  `ReturnType`.
- CI has an `edge-functions` job now: Deno, `deno check` on every
  `supabase/functions/*/index.ts`. Its own job rather than a step inside
  `analyze-test`, because it needs Deno rather than Flutter and a TypeScript
  failure should be legible apart from a Dart one.

### A Tooltip does not name a control

Served in a browser with assistive technology switched on — Flutter builds the
semantics tree only when something asks — the app produced 38 semantics nodes
and **8 labels**. The Search button, the wishlist hearts, the account menu,
the notification bell and the leaderboard trophy were all `button` with no
name.

Nearly every one of them already had a `Tooltip`. **`Tooltip` sets
`SemanticsProperties.tooltip`; `label` stays empty.** Same for
`PopupMenuButton.tooltip` and `IconButton.tooltip`. Wrap in
`Semantics(button: true, label: …)` and, where a tooltip already says the
right thing, pass the same string to both rather than inventing a second one
to keep in step.

Two consequences, and the second is why this is not only an accessibility
item: a screen reader user hears "button" with no idea what it does, and the
end-to-end strategy in `docs/qa/qa-plan.md` selects controls **by accessibility
label**, so an unnamed control cannot be driven by a test either.

`test/widgets/accessibility_labels_test.dart` pins the names.
**`find.bySemanticsLabel` is not the finder to use here** — it reads the label
off the render object's own node and comes back empty for a control whose node
is merged into a parent, which is most of these; it answered 0 for a heart the
same test can see the label on. Match on the `Semantics` widget's
`properties.label` instead.
