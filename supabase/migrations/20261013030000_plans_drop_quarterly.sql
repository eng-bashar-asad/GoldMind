-- Subscriptions are yearly only (multi-branch plan step 0.1): remove the quarterly
-- installment price from every plan. Run manually by the owner (removes data).
update public.plans
set prices = (
  select coalesce(jsonb_object_agg(cur, v - 'quarterly'), '{}'::jsonb)
  from jsonb_each(prices) as e(cur, v)
)
where prices is not null and jsonb_typeof(prices) = 'object'
  and exists (select 1 from jsonb_each(prices) e(cur, v) where v ? 'quarterly');

comment on column public.plans.prices is 'Per-currency price list: {"USD":{yearly,extra_staff_yearly,einvoice_addon_monthly,einvoice_overage}}. Yearly only, paid upfront; refundable within 14 days of subscribing.';
