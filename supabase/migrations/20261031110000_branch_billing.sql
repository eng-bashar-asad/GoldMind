-- Multi-branch 3.3: subscription billing per branch (decisions 5, 6, 8, 12 of the plan).
--  * yearly only; the price is per branch (the plan's yearly price in the branch currency, else USD)
--  * a branch added mid-year owes yearly × days left to the company's renewal date ÷ 365
--    (recorded on its subscription as branch_due when it is created; it keeps the head office's dates)
--  * one renewal for the whole company: every branch moves to the same new end date
--  * refunds within 14 days of a payment (policy text on the page; payments are recorded by GoldMind)
alter table public.subscriptions add column if not exists branch_due numeric;
alter table public.subscriptions add column if not exists branch_due_currency text;
alter table public.subscriptions add column if not exists branch_due_since timestamptz;

-- the yearly price of a plan for a store: its own currency when the plan has it, else USD
create or replace function public.gm_plan_yearly(p_plan uuid, p_store uuid, out amount numeric, out currency text)
language sql stable security definer set search_path to 'public' as $$
  with s as (select upper(coalesce(nullif(currency, ''), 'USD')) cur from stores where id = p_store),
       p as (select prices, price_yearly from plans where id = p_plan)
  select coalesce((p.prices -> s.cur ->> 'yearly')::numeric, (p.prices -> 'USD' ->> 'yearly')::numeric, p.price_yearly),
         case when p.prices -> s.cur ->> 'yearly' is not null then s.cur else 'USD' end
    from s, p;
$$;
revoke execute on function public.gm_plan_yearly(uuid, uuid) from public, anon;

-- a new branch's subscription (create_branch copies the head office's plan and dates): what it owes
create or replace function public.trg_branch_subscription_due()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare head uuid; org uuid; y record; days numeric;
begin
  select organization_id into org from stores where id = new.store_id;
  if org is null then return new; end if;
  select coalesce(head_office_store_id, primary_store_id) into head from organizations where id = org;
  if head is null or head = new.store_id or new.status <> 'active' or new.current_period_end is null or new.current_period_end <= now() then return new; end if;
  select * into y from gm_plan_yearly(new.plan_id, new.store_id);
  days := ceil(extract(epoch from (new.current_period_end - now())) / 86400);
  new.branch_due := round(coalesce(y.amount, 0) * least(days, 365) / 365, 2);
  new.branch_due_currency := y.currency;
  new.branch_due_since := now();
  return new;
end $$;
create trigger trg_branch_subscription_due before insert on public.subscriptions
  for each row execute function public.trg_branch_subscription_due();

-- the company's billing: one row per branch (owner of the company or a platform admin)
create or replace function public.branch_billing(p_store uuid)
returns table(store_id uuid, store_name text, is_head boolean, plan_name text, status text, period_end timestamptz,
  yearly numeric, currency text, branch_due numeric, branch_due_currency text)
language sql stable security definer set search_path to 'public' as $$
  with o as (select s.organization_id org from stores s where s.id = p_store),
       ok as (select (public.is_platform_admin())
                  or exists (select 1 from staff st join stores s2 on s2.id = st.store_id, o
                              where st.user_id = auth.uid() and st.role = 'owner' and s2.organization_id = o.org) v)
  select s.id, coalesce(nullif(s.display_name, ''), s.name), coalesce(org.head_office_store_id, org.primary_store_id) = s.id,
         p.name_ar, sb.status, coalesce(sb.current_period_end, sb.trial_end),
         y.amount, y.currency, sb.branch_due, sb.branch_due_currency
    from o join stores s on s.organization_id = o.org join organizations org on org.id = o.org
    join subscriptions sb on sb.store_id = s.id join plans p on p.id = sb.plan_id
    cross join lateral gm_plan_yearly(sb.plan_id, s.id) y, ok
   where ok.v and public.gm_session_ok()
   order by 3 desc, s.created_at;
$$;
revoke execute on function public.branch_billing(uuid) from public, anon;
grant execute on function public.branch_billing(uuid) to authenticated;

-- GoldMind (platform admin) records a new branch's prorated payment
create or replace function public.record_branch_payment(p_store uuid, p_payment_ref text default null)
returns void language plpgsql security definer set search_path to 'public' as $$
declare sb record;
begin
  if not public.is_platform_admin() then raise exception 'unauthorized'; end if;
  select * into sb from subscriptions where store_id = p_store for update;
  if sb.id is null then raise exception 'no subscription found for store'; end if;
  if coalesce(sb.branch_due, 0) <= 0 then raise exception 'لا يوجد مبلغ مستحق على هذا الفرع'; end if;
  update subscriptions set branch_due = null, branch_due_since = null, status = 'active', deactivated_at = null,
         payment_ref = coalesce(p_payment_ref, payment_ref), updated_at = now() where id = sb.id;
  insert into audit_log (store_id, action_type, description)
  values (p_store, 'subscription_payment_recorded', 'دفعة اشتراك الفرع حتى تاريخ تجديد الشركة: ' || sb.branch_due || ' ' || coalesce(sb.branch_due_currency, '')
          || coalesce(' - مرجع: ' || p_payment_ref, ''));
end $$;
revoke execute on function public.record_branch_payment(uuid, text) from public, anon;
grant execute on function public.record_branch_payment(uuid, text) to authenticated;

-- GoldMind (platform admin) records the company's renewal: every branch gets the same new end date
create or replace function public.record_org_renewal(p_store uuid, p_months integer, p_payment_ref text default null)
returns timestamptz language plpgsql security definer set search_path to 'public' as $$
declare org uuid; head uuid; base timestamptz; newend timestamptz; n int;
begin
  if not public.is_platform_admin() then raise exception 'unauthorized'; end if;
  if p_months is null or p_months < 1 or p_months > 36 then raise exception 'عدد أشهر غير صحيح'; end if;
  select organization_id into org from stores where id = p_store;
  select coalesce(head_office_store_id, primary_store_id) into head from organizations where id = org;
  select greatest(coalesce(current_period_end, now()), now()) into base from subscriptions where store_id = coalesce(head, p_store);
  newend := base + (p_months || ' months')::interval;
  update subscriptions set status = 'active', current_period_end = newend, branch_due = null, branch_due_since = null,
         deactivated_at = null, payment_ref = coalesce(p_payment_ref, payment_ref), updated_at = now()
   where store_id in (select id from stores where organization_id = org);
  get diagnostics n = row_count;
  insert into audit_log (store_id, action_type, description)
  values (coalesce(head, p_store), 'subscription_payment_recorded', 'تجديد اشتراك الشركة (' || n || ' فروع) ' || p_months || ' شهر حتى '
          || to_char(newend at time zone 'Asia/Dubai', 'DD/MM/YYYY') || coalesce(' - مرجع: ' || p_payment_ref, ''));
  return newend;
end $$;
revoke execute on function public.record_org_renewal(uuid, integer, text) from public, anon;
grant execute on function public.record_org_renewal(uuid, integer, text) to authenticated;

-- platform_admins has no user_id column (it is id): the admin check here always failed.
create or replace function public.record_subscription_payment(p_store_id uuid, p_months integer, p_payment_ref text default null, p_plan_id uuid default null)
returns void language plpgsql security definer set search_path to 'public' as $$
declare v_sub subscriptions%rowtype; v_base timestamptz;
begin
  if not public.is_platform_admin() then raise exception 'unauthorized'; end if;
  select * into v_sub from subscriptions where store_id = p_store_id limit 1;
  if v_sub.id is null then raise exception 'no subscription found for store'; end if;
  v_base := greatest(coalesce(v_sub.current_period_end, now()), now());
  update subscriptions set status = 'active', plan_id = coalesce(p_plan_id, plan_id),
    current_period_end = v_base + (p_months || ' months')::interval,
    payment_ref = coalesce(p_payment_ref, payment_ref), deactivated_at = null, updated_at = now()
  where id = v_sub.id;
  insert into audit_log (store_id, action_type, description)
  values (p_store_id, 'subscription_payment_recorded', 'تسجيل دفعة اشتراك يدوياً: ' || p_months || ' شهر' || coalesce(' - مرجع: ' || p_payment_ref, ''));
end $$;
