-- 081: Rebrand phone-auth synthetic email domain musafir.app -> musaafir.app
--
-- Phone accounts have no real email; verify-otp derives a synthetic Supabase-auth
-- identity `phone.<normalized>@<domain>` (see supabase/functions/_shared/otp.ts,
-- phoneToEmail). It is the primary key phone logins are matched on
-- (get_auth_user_id_by_email -> auth.users.email). The product was renamed to
-- "Musaafir", so this domain must follow — but the code constructor and the
-- stored rows must flip TOGETHER, or existing users fail the lookup and get a
-- new empty account. This migration flips the stored rows; deploy the updated
-- verify-otp immediately after (or before) applying it.
--
-- Storage locations (verified live): auth.users.email and
-- auth.identities.identity_data->>'email'. auth.identities.email is a GENERATED
-- column (lower(identity_data->>'email')) so it recomputes automatically — do
-- NOT update it directly. profiles.email holds no synthetic addresses.
-- Only rows matching the synthetic pattern are touched; real email users are safe.

update auth.users
set email = replace(email, '@musafir.app', '@musaafir.app')
where email like 'phone.%@musafir.app';

update auth.identities
set identity_data = jsonb_set(
  identity_data,
  '{email}',
  to_jsonb(replace(identity_data->>'email', '@musafir.app', '@musaafir.app'))
)
where identity_data->>'email' like 'phone.%@musafir.app';
