-- =============================================
-- 132 — settlement columns cannot be written by a client. Run inside
-- begin; … rollback; against live, after (or in the same transaction as) 132.
--
-- Rows 1–3 are the hole itself and go red without the migration (verified:
-- both writes succeeded on live before it). Rows 4–6 are the paths that must
-- keep working: the host's cash confirmation, the guest's method choice and
-- the admin's refund switch — the first two run as SECURITY DEFINER with a
-- real auth.uid(), which is exactly what a naive "non-admin touched
-- payment_status" guard would break. Row 7 is the negative control on the
-- fixture and row 8 the service-role path the IPN function uses: the same guest can still cancel, so the guard is not "guests
-- cannot update at all".
--
-- Every impersonated block ends by restoring role postgres AND clearing the
-- claims: with a stale `sub` still set, auth.uid() is non-null and the guard
-- (correctly) treats even postgres as a signed-in non-admin.
--
-- Fixture: a fresh confirmed booking on a real listing by a real verified
-- tenant, inserted as postgres. It exists only inside this transaction.
-- =============================================

create temp table t_result (n int, name text, ok boolean, detail text) on commit drop;
grant select, insert on t_result to anon, authenticated, service_role;

do $$
declare
  v_listing  uuid;
  v_host     uuid;
  v_guest    uuid;
  v_admin    uuid;
  v_booking  uuid;
  v_status   text;
  v_method   text;
  v_msg      text;
  v_hint     text;
begin
  -- A listing whose owner is not the guest, a verified guest, an admin.
  select l.id, l.owner_id into v_listing, v_host
    from public.listings l where l.is_active order by l.created_at limit 1;
  select p.id into v_guest from public.profiles p
   where p.verification_status = 'verified' and p.id <> v_host
   order by p.created_at limit 1;
  select p.id into v_admin from public.profiles p where p.role = 'admin' limit 1;

  insert into public.bookings
    (tenant_id, listing_id, starts_at, ends_at, guest_count, total_price,
     booking_status, payment_status, pricing_unit, unit_count)
  values
    (v_guest, v_listing, now() + interval '400 days', now() + interval '401 days',
     1, 1000, 'confirmed', 'unpaid', 'day', 1)
  returning id into v_booking;

  -- ---- 1  guest sets own booking paid ---------------------------------------
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_guest, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    update public.bookings set payment_status = 'paid' where id = v_booking;
    insert into t_result values (1, 'guest cannot mark own booking paid', false, 'update accepted');
  exception when others then
    get stacked diagnostics v_msg = message_text, v_hint = pg_exception_hint;
    insert into t_result values (1, 'guest cannot mark own booking paid',
      v_hint = 'payment_columns_protected', v_msg);
  end;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);

  -- ---- 2  host sets booking paid --------------------------------------------
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_host, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    update public.bookings set payment_status = 'paid' where id = v_booking;
    insert into t_result values (2, 'host cannot mark booking paid by table write', false, 'update accepted');
  exception when others then
    get stacked diagnostics v_msg = message_text, v_hint = pg_exception_hint;
    insert into t_result values (2, 'host cannot mark booking paid by table write',
      v_hint = 'payment_columns_protected', v_msg);
  end;

  -- ---- 3  host sets paid_at / payment_method directly -----------------------
  begin
    update public.bookings set paid_at = now(), payment_method = 'cash' where id = v_booking;
    insert into t_result values (3, 'paid_at and payment_method are protected too', false, 'update accepted');
  exception when others then
    get stacked diagnostics v_msg = message_text, v_hint = pg_exception_hint;
    insert into t_result values (3, 'paid_at and payment_method are protected too',
      v_hint = 'payment_columns_protected', v_msg);
  end;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);

  -- Whatever rows 1–3 did (they succeed without the migration), start the
  -- happy paths from a clean unpaid booking so they measure the RPCs alone.
  update public.bookings set payment_status = 'unpaid', payment_method = 'online',
    paid_at = null where id = v_booking;

  -- ---- 4  guest chooses cash through the RPC (still works) ------------------
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_guest, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.set_booking_payment_method(v_booking, 'cash');
    select payment_method into v_method from public.bookings where id = v_booking;
    insert into t_result values (4, 'guest can still choose cash through set_booking_payment_method',
      v_method = 'cash', 'payment_method=' || coalesce(v_method, 'null'));
  exception when others then
    get stacked diagnostics v_msg = message_text;
    insert into t_result values (4, 'guest can still choose cash through set_booking_payment_method', false, v_msg);
  end;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);

  -- ---- 5  host confirms cash through the RPC (still works) ------------------
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_host, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.mark_cash_payment(v_booking);
    select payment_status into v_status from public.bookings where id = v_booking;
    insert into t_result values (5, 'host can still confirm cash through mark_cash_payment',
      v_status = 'paid', 'payment_status=' || v_status);
  exception when others then
    get stacked diagnostics v_msg = message_text;
    insert into t_result values (5, 'host can still confirm cash through mark_cash_payment', false, v_msg);
  end;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);

  -- ---- 6  an admin is exempt from the guard ---------------------------------
  -- Run as postgres with an admin's auth.uid(), so only the TRIGGER is under
  -- test. Doing this as role `authenticated` measures RLS instead: bookings
  -- has no admin UPDATE policy, so the console's refund switch matches zero
  -- rows on live today — a separate finding, recorded in
  -- docs/qa/payment-test-plan.md, not this row's business.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  begin
    update public.bookings set payment_status = 'refunded'
     where id = v_booking and payment_status = 'paid';
    select payment_status into v_status from public.bookings where id = v_booking;
    insert into t_result values (6, 'an admin (trigger exemption) can still mark refunded',
      v_status = 'refunded', 'payment_status=' || v_status);
  exception when others then
    get stacked diagnostics v_msg = message_text;
    insert into t_result values (6, 'an admin (trigger exemption) can still mark refunded', false, v_msg);
  end;
  perform set_config('request.jwt.claims', '', true);

  -- ---- 7  negative control: the guest can still cancel ----------------------
  update public.bookings set payment_status = 'unpaid', paid_at = null,
    booking_status = 'confirmed' where id = v_booking;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_guest, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    update public.bookings set booking_status = 'cancelled' where id = v_booking;
    select booking_status into v_status from public.bookings where id = v_booking;
    insert into t_result values (7, 'the guest can still cancel (guard is column-scoped)',
      v_status = 'cancelled', 'booking_status=' || v_status);
  exception when others then
    get stacked diagnostics v_msg = message_text;
    insert into t_result values (7, 'the guest can still cancel (guard is column-scoped)', false, v_msg);
  end;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);

  -- ---- 8  the service role (the IPN function) is untouched ------------------
  update public.bookings set payment_status = 'unpaid', paid_at = null where id = v_booking;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'service_role', true);
  begin
    update public.bookings set payment_status = 'paid' where id = v_booking;
    select payment_status into v_status from public.bookings where id = v_booking;
    insert into t_result values (8, 'service_role (sslcommerz-ipn) can still settle',
      v_status = 'paid', 'payment_status=' || v_status);
  exception when others then
    get stacked diagnostics v_msg = message_text;
    insert into t_result values (8, 'service_role (sslcommerz-ipn) can still settle', false, v_msg);
  end;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;
select n, case when ok then 'PASS' else 'FAIL' end as outcome, name, detail
  from t_result order by n;
