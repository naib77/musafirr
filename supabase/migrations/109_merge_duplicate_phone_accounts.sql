-- 109: Merge the four phone numbers that ended up with two accounts each
--
-- THE BUG. `normalizePhone` (supabase/functions/_shared/otp.ts) decides which
-- account a login lands on: verify-otp turns it into the synthetic auth email
-- `phone.<normalized>@musaafir.app` and creates one account per distinct value.
-- It collapsed `+880…` and `880…` to a leading zero and passed an
-- already-canonical `01…` through, but a bare 10-digit national number matched
-- no branch and was returned unchanged. The login screen renders `+880` as a
-- decorative prefixIcon and submits the raw field text, so users are invited to
-- omit the zero — visually the `+880` replaces it. One human therefore had two
-- identities:
--
--     "01711165212"  ->  phone.01711165212@musaafir.app
--     "1711165212"   ->  phone.1711165212@musaafir.app     <-- second account
--
-- Four numbers hit both. Users submitted identity documents twice, and because
-- IdentityGate blocks listing creation and booking requests on
-- `profiles.verification_status`, the account they happened to log into decided
-- whether they could do anything at all.
--
-- WHY THERE IS NO BULK RENAME HERE. 33 of 38 phone accounts are stored in the
-- bare form, and the stored email is an opaque key that `admin.generateLink`
-- consumes and the client echoes back to redeem the token. Renaming those rows
-- would have to land in the same instant as the edge-function deploy, and every
-- returning user in the gap would be handed a brand-new empty account. So the
-- rows keep whatever spelling they have; the fixed verify-otp looks for the
-- canonical identity and then the legacy one (see `legacyPhoneToEmail`) and uses
-- whichever exists. That is order-independent and needs no data change.
--
-- This migration therefore only does the part code cannot: the four accounts
-- that already exist in both forms.
--
-- POLICY, applied per pair:
--   * The WINNER is the account carrying the substance — listings, bookings,
--     messages, reviews, an approved identity.
--   * The loser's bookings move to the winner. Nothing else needed moving:
--     verified live data showed the losers hold no listings, messages or
--     reviews.
--   * `owner_documents` rows are NOT moved. The table is UNIQUE (user_id,
--     document_type) and every winner already occupies the slots, so a move
--     would collide; the loser's copies stay attached to the dead account as
--     the audit trail of what an admin actually approved.
--   * A loser holding the CANONICAL email is tombstoned — its email is rewritten
--     to a form no phone number can derive, and it is banned. This is required,
--     not tidiness: the fixed verify-otp tries the canonical identity first, so
--     leaving it in place would route the merged user straight back to the empty
--     account.
--   * A loser holding the LEGACY email is left alone. It is already unreachable
--     once the winner answers the canonical lookup, and rewriting it would break
--     that user's login in the window before the new function is deployed.
--
-- Nothing is deleted. Losers remain queryable by id for audit, and the
-- pre-merge state is recoverable from the values recorded below.
--
-- PRE-MERGE STATE (verified live before applying):
--   01711165212  b1c2391c Faisal   legacy    verified  4 listings 6 bookings 2 docs  <- winner
--                e028bdc6 New User canonical verified  0 listings 1 booking  3 docs  <- tombstone
--   01711314754  49e06795 Sajid    legacy    verified  0 listings 7 bookings 3 docs  <- winner
--                2230da32 Sajid    canonical verified  0 listings 0 bookings 3 docs  <- tombstone
--   01839290436  f7f4add5 Takrim   canonical verified  4 listings 4 bookings 3 docs  <- winner
--                d815e437 Takrim   legacy    none      empty                         <- leave
--   01913618480  a00b005e New User legacy    verified  0 listings 0 bookings 3 docs  <- winner
--                981ba504 JENGI    canonical none      empty                         <- tombstone

begin;

-- ---------------------------------------------------------------------------
-- 1. Move the loser's bookings to the winner.
-- ---------------------------------------------------------------------------
-- Only pair 1 has any: e028bdc6 holds a single booking.
update bookings
set tenant_id = 'b1c2391c-7565-4e03-ba2b-f7212b12bdd7'
where tenant_id = 'e028bdc6-8357-4901-9cd1-a187fc3f21ab';

-- ---------------------------------------------------------------------------
-- 2. Carry the human's real name onto the winner where the winner has none.
-- ---------------------------------------------------------------------------
-- Pair 4's winner is the account that holds the approved identity, but the name
-- "JENGI" was typed into the other one. Same person, same phone.
update profiles
set full_name = 'JENGI'
where id = 'a00b005e-d5eb-4570-83f5-c013826b5707'
  and (full_name is null or full_name = '' or full_name = 'New User');

-- ---------------------------------------------------------------------------
-- 3. Tombstone the losers that hold the canonical email.
-- ---------------------------------------------------------------------------
-- `merged-<id>@invalid.musaafir.app` cannot be produced by phoneToEmail for any
-- input, so neither the canonical nor the legacy lookup can ever reach these
-- rows again. auth.identities.email is a GENERATED column over
-- identity_data->>'email' and recomputes itself — do NOT write it directly.
-- provider_id is the user id here (verified live), so it is unaffected.
with tombstoned as (
  select id from (values
    ('e028bdc6-8357-4901-9cd1-a187fc3f21ab'::uuid),
    ('2230da32-16da-4317-9072-505d08d37c99'::uuid),
    ('981ba504-3d81-4183-8923-4e824bd5c757'::uuid)
  ) as t(id)
)
update auth.users u
set email = 'merged-' || u.id::text || '@invalid.musaafir.app',
    -- Far-future ban rather than a delete: the row stays available for audit
    -- and for undoing this migration, but no session can be minted for it.
    banned_until = timestamptz '2999-01-01'
from tombstoned t
where u.id = t.id;

update auth.identities i
set identity_data = jsonb_set(
  i.identity_data,
  '{email}',
  to_jsonb(u.email)
)
from auth.users u
where i.user_id = u.id
  and u.email like 'merged-%@invalid.musaafir.app'
  and i.identity_data->>'email' <> u.email;

-- ---------------------------------------------------------------------------
-- 4. Assert the end state before committing.
-- ---------------------------------------------------------------------------
-- Every invariant is checked here rather than by eyeballing the result
-- afterwards, so a successful COMMIT *is* the verification. Any failure aborts
-- the whole transaction and leaves the database exactly as it was.
--
-- Note what is deliberately NOT asserted: "no number has two live accounts".
-- Takrim's empty legacy row is intentionally left live (tombstoning it would
-- break his login in the window before the fixed verify-otp is deployed), so
-- that blunt check fails by design. What matters is not how many rows exist but
-- which one the resolver picks, which is what this checks.
do $$
declare
  r record;
  v_pick uuid;
  v_bookings integer;
begin
  -- 4a. The resolver must land on the winner for all four numbers. This
  -- mirrors verify-otp exactly: canonical identity first, legacy second.
  for r in
    select * from (values
      ('01711165212', 'b1c2391c-7565-4e03-ba2b-f7212b12bdd7'::uuid, 'Faisal'),
      ('01711314754', '49e06795-e004-4afc-8b5b-e2400fae863a'::uuid, 'Sajid'),
      ('01839290436', 'f7f4add5-aab8-414e-8252-4bfcd0d51d1d'::uuid, 'Takrim'),
      ('01913618480', 'a00b005e-d5eb-4570-83f5-c013826b5707'::uuid, 'JENGI')
    ) as t(canon, expected_winner, who)
  loop
    select coalesce(
      (select id from auth.users
        where email = 'phone.' || r.canon || '@musaafir.app'
          and (banned_until is null or banned_until < now())),
      (select id from auth.users
        where email = 'phone.' || substring(r.canon from 2) || '@musaafir.app'
          and (banned_until is null or banned_until < now()))
    ) into v_pick;

    if v_pick is null then
      raise exception '% (%): no reachable account after merge', r.who, r.canon;
    end if;
    if v_pick <> r.expected_winner then
      raise exception '% (%): resolver picks % but the winner is %',
        r.who, r.canon, v_pick, r.expected_winner;
    end if;
  end loop;

  -- 4b. The moved booking actually moved: winner 6 -> 7, loser 1 -> 0.
  select count(*) into v_bookings from bookings
   where tenant_id = 'b1c2391c-7565-4e03-ba2b-f7212b12bdd7';
  if v_bookings <> 7 then
    raise exception 'Faisal should hold 7 bookings after the move, found %', v_bookings;
  end if;
  select count(*) into v_bookings from bookings
   where tenant_id = 'e028bdc6-8357-4901-9cd1-a187fc3f21ab';
  if v_bookings <> 0 then
    raise exception 'the merged-away account still holds % booking(s)', v_bookings;
  end if;

  -- 4c. The three canonical-holding losers are tombstoned and banned, so
  -- neither lookup can reach them.
  select count(*) into v_bookings from auth.users
   where id in (
     'e028bdc6-8357-4901-9cd1-a187fc3f21ab',
     '2230da32-16da-4317-9072-505d08d37c99',
     '981ba504-3d81-4183-8923-4e824bd5c757'
   )
   and email like 'merged-%@invalid.musaafir.app'
   and banned_until > now();
  if v_bookings <> 3 then
    raise exception 'expected 3 tombstoned losers, found %', v_bookings;
  end if;

  -- 4d. Each identity row agrees with its user row, or the next auth change
  -- resurrects the old address.
  select count(*) into v_bookings
    from auth.identities i join auth.users u on u.id = i.user_id
   where u.email like 'merged-%@invalid.musaafir.app'
     and i.identity_data->>'email' <> u.email;
  if v_bookings <> 0 then
    raise exception '% identity row(s) still carry the pre-merge email', v_bookings;
  end if;

  -- 4e. The name carried across.
  if not exists (
    select 1 from profiles
     where id = 'a00b005e-d5eb-4570-83f5-c013826b5707' and full_name = 'JENGI'
  ) then
    raise exception 'pair 4 winner did not receive the name JENGI';
  end if;

  raise notice 'merge OK: 4 numbers resolve to their winner, 1 booking moved, 3 losers tombstoned';
end $$;

commit;
