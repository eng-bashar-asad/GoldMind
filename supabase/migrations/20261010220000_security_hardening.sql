-- Security review (agent-skills security-and-hardening):
-- 1) fixed search_path on the four functions the linter flagged
alter function public.currency_usd_peg set search_path = public;
alter function public.gm_op_date set search_path = public;
alter function public.gm_op_date_stamp set search_path = public;
alter function public.gold_implied_usd_ounce set search_path = public;
-- 2) gm_daily_label is an internal helper (it reads customer/trader names); visitors without a session must not call it
revoke execute on function public.gm_daily_label(text, text, uuid) from public, anon;
