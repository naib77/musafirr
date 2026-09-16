-- =============================================
-- 131 — make the SMS claim actually respect its batch size
--
-- `admin_claim_sms_batch` (128) was written as
--
--     update sms_recipients r
--        set status = 'sending'
--      where r.id in (select c.id from sms_recipients c
--                      where ... order by ... limit N
--                      for update skip locked)
--     returning ...
--
-- and that **does not reliably return N rows**. Asking for a batch of 1 against
-- a campaign with two pending recipients returned 2, intermittently: five
-- consecutive runs of supabase/tests/128 gave FAIL, PASS, PASS, FAIL, FAIL,
-- with `claimed=2` every time it failed. `IN (subquery)` is a semi-join the
-- planner may re-evaluate rather than materialise once, and `FOR UPDATE SKIP
-- LOCKED` inside it is evaluated against a moving target.
--
-- The CTE form is the canonical fix: the rows are chosen exactly once, then
-- joined to.
--
-- **Why this mattered, given nothing was double-sent.** Claim-before-send means
-- a row this function hands out is never picked up again — that is the property
-- that makes a crash lose a message rather than repeat one. Over-claiming turns
-- that safety into a liability: a "batch of 50" that actually claims the whole
-- campaign leaves EVERY remaining recipient stranded in 'sending' if the worker
-- then dies, instead of just fifty. The time budget in the edge function also
-- stops meaning anything, because the first claim takes everything.
-- =============================================

create or replace function public.admin_claim_sms_batch(
  p_campaign_id uuid,
  p_limit       integer default 50
)
returns table (id uuid, msisdn text, body_rendered text)
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.fn_require_service_role();

  update public.sms_campaigns
     set status = 'sending'
   where sms_campaigns.id = p_campaign_id and status = 'queued';

  return query
  with picked as (
    select c.id
      from public.sms_recipients c
     where c.campaign_id = p_campaign_id
       and c.status = 'pending'
     order by c.created_at, c.id
     limit greatest(1, least(coalesce(p_limit, 50), 200))
     for update skip locked
  )
  update public.sms_recipients r
     set status = 'sending',
         claimed_at = now(),
         attempts = r.attempts + 1
    from picked
   where r.id = picked.id
  returning r.id, r.msisdn, r.body_rendered;
end;
$$;

revoke all on function public.admin_claim_sms_batch(uuid, integer)
  from public, anon, authenticated;
grant execute on function public.admin_claim_sms_batch(uuid, integer) to service_role;

comment on function public.admin_claim_sms_batch(uuid, integer) is
  'Claims at most p_limit pending recipients, marking them sending BEFORE the '
  'provider is called. The CTE is load-bearing: an IN(subquery) form silently '
  'over-claimed — see 131.';
