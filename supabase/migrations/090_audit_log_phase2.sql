-- 090_audit_log_phase2.sql
-- Phase 2 of the audit trail: extend the append-only log (089) to discount and
-- trust-&-safety events, reusing the same public.fn_audit trigger function.
--   coupons            (create / edit / enable-disable / delete)  → discount
--   coupon_redemptions (each redemption — money off a booking)     → discount
--   reports            (new report + status/resolution changes)    → safety

-- coupons: creation, meaningful edits, enable/disable, and deletion.
drop trigger if exists trg_audit_coupons_ins on public.coupons;
create trigger trg_audit_coupons_ins
  after insert on public.coupons
  for each row execute function public.fn_audit('discount');

drop trigger if exists trg_audit_coupons_upd on public.coupons;
create trigger trg_audit_coupons_upd
  after update on public.coupons
  for each row
  when (old.is_active          is distinct from new.is_active
        or old.discount_type      is distinct from new.discount_type
        or old.discount_value     is distinct from new.discount_value
        or old.max_discount_amount is distinct from new.max_discount_amount
        or old.min_booking_amount is distinct from new.min_booking_amount
        or old.usage_limit        is distinct from new.usage_limit
        or old.per_user_limit     is distinct from new.per_user_limit
        or old.starts_at          is distinct from new.starts_at
        or old.expires_at         is distinct from new.expires_at)
  execute function public.fn_audit('discount');

drop trigger if exists trg_audit_coupons_del on public.coupons;
create trigger trg_audit_coupons_del
  after delete on public.coupons
  for each row execute function public.fn_audit('discount');

-- coupon_redemptions: each redemption (records the discount taken).
drop trigger if exists trg_audit_coupon_redemptions_ins on public.coupon_redemptions;
create trigger trg_audit_coupon_redemptions_ins
  after insert on public.coupon_redemptions
  for each row execute function public.fn_audit('discount');

-- reports: new safety report + admin resolution actions.
drop trigger if exists trg_audit_reports_ins on public.reports;
create trigger trg_audit_reports_ins
  after insert on public.reports
  for each row execute function public.fn_audit('safety');

drop trigger if exists trg_audit_reports_upd on public.reports;
create trigger trg_audit_reports_upd
  after update on public.reports
  for each row
  when (old.status          is distinct from new.status
        or old.resolution_note is distinct from new.resolution_note
        or old.resolved_by     is distinct from new.resolved_by)
  execute function public.fn_audit('safety');
