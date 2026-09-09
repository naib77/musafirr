-- Verification for 119_configurable_booking_accept_window.sql.
--
-- Mutating (it writes a setting and inserts bookings), so it MUST run inside a
-- transaction you roll back:
--
--   begin;
--   \i supabase/tests/119_booking_accept_window_test.sql
--   rollback;
--
-- Or against live via the Management API with the body between begin/rollback.
-- No psql metacommands, so it runs either way.
--
-- Every row PASS. The load-bearing ones are 04/05 (the configured number is
-- what actually decides, in both directions) and 08 (a junk row falls back to
-- 24 instead of raising inside a cron job, which would silently stop the sweep
-- for every booking).

create temp table res(name text, value text) on commit drop;

-- 01 -- the reader defaults to 24 with no row at all
delete from public.app_settings where key = 'booking_accept_window_hours';
insert into res values ('01_default_without_row',
  public.booking_accept_window_hours()::text);

-- 02 -- and reads the row once it exists
insert into public.app_settings (key, value)
values ('booking_accept_window_hours', '6');
insert into res values ('02_reads_the_setting',
  public.booking_accept_window_hours()::text);

-- 03 -- the validator refuses what the app could not honour
do $$
declare bad text; msg text;
begin
  foreach bad in array array['0', '169', 'soon', '', '-4', '2.5'] loop
    begin
      update public.app_settings set value = bad
       where key = 'booking_accept_window_hours';
      insert into res values ('03_rejects_' || coalesce(nullif(bad, ''), 'blank'),
        'ACCEPTED -- no guard');
    exception when others then
      insert into res values ('03_rejects_' || coalesce(nullif(bad, ''), 'blank'),
        'REFUSED');
    end;
  end loop;
  -- and accepts the edges
  update public.app_settings set value = '1' where key = 'booking_accept_window_hours';
  update public.app_settings set value = '168' where key = 'booking_accept_window_hours';
  msg := 'ACCEPTED';
  insert into res values ('03_accepts_1_and_168', msg);
exception when others then
  insert into res values ('03_accepts_1_and_168', 'REFUSED ' || sqlerrm);
end $$;

-- ── fixtures: two pending bookings, 3 and 12 hours old ─────────────────────
create temp table fixture_ids(label text, id uuid) on commit drop;

do $$
declare
  v_listing uuid;
  v_guest   uuid;
  v_id      uuid;
begin
  select l.id into v_listing from public.listings l where l.is_active order by l.created_at limit 1;
  select p.id into v_guest from public.profiles p
   where p.id <> (select owner_id from public.listings where id = v_listing) limit 1;

  foreach v_id in array array[
    '11111111-0000-0000-0000-000000000001'::uuid,
    '11111111-0000-0000-0000-000000000002'::uuid]
  loop
    -- Three things this insert has to respect:
    --  * starts_at / ends_at, NOT start_date / end_date -- the live column
    --    names differ from the ones the Dart model uses;
    --  * far-future dates, so auto_complete_elapsed_bookings does not also
    --    move these rows while the sweep under test is running;
    --  * NON-OVERLAPPING windows for the two fixtures, or bookings_no_overlap
    --    (078, per listing) and bookings_no_tenant_overlap (111, per guest)
    --    both reject the second insert with 23P01.
    insert into public.bookings
      (id, listing_id, tenant_id, booking_status, starts_at, ends_at,
       total_price, created_at)
    values (
      v_id, v_listing, v_guest, 'pending',
      case when v_id::text like '%1' then now() + interval '30 days'
           else now() + interval '40 days' end,
      case when v_id::text like '%1' then now() + interval '31 days'
           else now() + interval '41 days' end,
      1000,
      case when v_id::text like '%1' then now() - interval '3 hours'
           else now() - interval '12 hours' end);
    insert into fixture_ids values (
      case when v_id::text like '%1' then 'three_hours_old' else 'twelve_hours_old' end,
      v_id);
  end loop;
end $$;

-- Runs the sweep at a given window and reports which fixtures survived.
create or replace function pg_temp.sweep(p_hours text)
returns text language plpgsql as $$
declare survivors text;
begin
  update public.app_settings set value = p_hours
   where key = 'booking_accept_window_hours';
  -- Reset the fixtures, so each scenario starts from the same place.
  update public.bookings set booking_status = 'pending', rejection_reason = null
   where id in (select id from fixture_ids);
  perform public.expire_stale_bookings();
  select coalesce(string_agg(f.label, ',' order by f.label), 'none')
    into survivors
    from fixture_ids f
    join public.bookings b on b.id = f.id
   where b.booking_status = 'pending';
  return survivors;
end $$;

-- 04 -- a 24-hour window (the default) expires neither
insert into res values ('04_window_24_keeps_both', pg_temp.sweep('24'));

-- 05 -- a 6-hour window expires only the older one. This is the whole feature:
--       the number in app_settings, not a literal in the function, decides.
insert into res values ('05_window_6_expires_the_older',
  pg_temp.sweep('6'));

-- 06 -- a 1-hour window expires both
insert into res values ('06_window_1_expires_both', pg_temp.sweep('1'));

-- 07 -- the rejection reason quotes the CONFIGURED window, not 24
do $$
declare reason text;
begin
  perform pg_temp.sweep('6');
  select b.rejection_reason into reason
    from public.bookings b
    join fixture_ids f on f.id = b.id
   where f.label = 'twelve_hours_old';
  insert into res values ('07_reason_quotes_window',
    case when reason like '%6 hours%' then 'OK' else 'WRONG: ' || coalesce(reason, 'null') end);
end $$;

-- 08 -- a junk value falls back to 24 rather than raising. A raise here would
--       abort the cron job and stop expiry for EVERY booking, silently.
do $$
declare survivors text;
begin
  -- Written past the validator on purpose: this models a row that predates the
  -- guard, which is the only way such a value can exist.
  alter table public.app_settings disable trigger trg_validate_app_setting;
  update public.app_settings set value = 'whenever'
   where key = 'booking_accept_window_hours';
  alter table public.app_settings enable trigger trg_validate_app_setting;

  update public.bookings set booking_status = 'pending', rejection_reason = null
   where id in (select id from fixture_ids);
  perform public.expire_stale_bookings();
  select coalesce(string_agg(f.label, ',' order by f.label), 'none') into survivors
    from fixture_ids f join public.bookings b on b.id = f.id
   where b.booking_status = 'pending';
  insert into res values ('08_junk_falls_back_to_24', survivors);
exception when others then
  insert into res values ('08_junk_falls_back_to_24', 'RAISED: ' || sqlerrm);
end $$;

-- 09 -- the wording helper: 24 keeps today's exact text, 48+ reads as days
insert into res values ('09_humanise',
  public.fn_humanise_hours(1) || '|' ||
  public.fn_humanise_hours(6) || '|' ||
  public.fn_humanise_hours(24) || '|' ||
  public.fn_humanise_hours(48) || '|' ||
  public.fn_humanise_hours(168));

-- 10 -- the reader is not a public endpoint (116's rule)
do $$ declare ok text; begin
  execute 'set local role anon';
  begin
    perform public.booking_accept_window_hours();
    ok := 'CALLABLE -- grant not revoked';
  exception when insufficient_privilege then ok := 'REVOKED';
  end;
  reset role;
  insert into res values ('10_reader_not_public', ok);
end $$;

-- 11 -- the cron job sweeps often enough for a short window to mean something
insert into res
select '11_cron_schedule', coalesce(
  (select schedule from cron.job where jobname = 'expire-stale-bookings'),
  'NO JOB');

select name,
       value,
       case
         when name like '01%' then case when value = '24' then 'PASS' else 'FAIL' end
         when name like '02%' then case when value = '6' then 'PASS' else 'FAIL' end
         when name like '03_rejects%' then case when value = 'REFUSED' then 'PASS' else 'FAIL' end
         when name like '03_accepts%' then case when value = 'ACCEPTED' then 'PASS' else 'FAIL' end
         when name like '04%' then
           case when value = 'three_hours_old,twelve_hours_old' then 'PASS' else 'FAIL' end
         when name like '05%' then
           case when value = 'three_hours_old' then 'PASS' else 'FAIL' end
         when name like '06%' then case when value = 'none' then 'PASS' else 'FAIL' end
         when name like '07%' then case when value = 'OK' then 'PASS' else 'FAIL' end
         when name like '08%' then
           case when value = 'three_hours_old,twelve_hours_old' then 'PASS' else 'FAIL' end
         when name like '09%' then
           case when value = '1 hour|6 hours|24 hours|2 days|7 days' then 'PASS' else 'FAIL' end
         when name like '10%' then case when value = 'REVOKED' then 'PASS' else 'FAIL' end
         when name like '11%' then case when value = '*/15 * * * *' then 'PASS' else 'FAIL' end
         else '?'
       end as verdict
  from res order by name;
