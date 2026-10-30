-- Multi-branch 3.2: the owner's dashboard. One row per store the caller OWNS (every branch of
-- every company), each in its own currency (nothing is added across currencies).
-- Today = Asia/Dubai day. Read-only; 2FA required like every other read.
create or replace function public.owner_dashboard()
returns table(store_id uuid, store_name text, organization_id uuid, organization_name text, is_head boolean,
  currency text, today_sales numeric, today_invoices int, month_sales numeric,
  drawer jsonb, stock_pieces int, stock jsonb, scrap jsonb, customers_owe numeric, customers_owing int,
  traders_gold24 numeric, traders_cash numeric, incoming_transfers int)
language sql stable security definer set search_path to 'public' as $$
  with mine as (
    select s.id, coalesce(nullif(s.display_name, ''), s.name) nm, s.organization_id, o.name oname,
           (o.head_office_store_id = s.id) head, upper(coalesce(nullif(s.currency, ''), 'AED')) cur
      from staff st join stores s on s.id = st.store_id left join organizations o on o.id = s.organization_id
     where st.user_id = auth.uid() and st.role = 'owner' and public.gm_session_ok()
  ), day as (
    select (date_trunc('day', now() at time zone 'Asia/Dubai')) at time zone 'Asia/Dubai' d0,
           (date_trunc('month', now() at time zone 'Asia/Dubai')) at time zone 'Asia/Dubai' m0
  )
  select m.id, m.nm, m.organization_id, m.oname, coalesce(m.head, false), m.cur,
    coalesce((select sum(i.total_amount) from invoices i, day where i.store_id = m.id and i.type = 'sale' and i.status <> 'cancelled' and i.created_at >= day.d0), 0),
    coalesce((select count(*) from invoices i, day where i.store_id = m.id and i.type = 'sale' and i.status <> 'cancelled' and i.created_at >= day.d0), 0)::int,
    coalesce((select sum(i.total_amount) from invoices i, day where i.store_id = m.id and i.type = 'sale' and i.status <> 'cancelled' and i.created_at >= day.m0), 0),
    coalesce((select jsonb_object_agg(c.cur, c.bal) from (
        select upper(l.currency) cur, round(sum(case l.direction when 'in' then l.amount else -l.amount end), 2) bal
          from daily_cash_log l where l.store_id = m.id group by 1 having abs(sum(case l.direction when 'in' then l.amount else -l.amount end)) >= 0.005) c), '{}'::jsonb),
    coalesce((select count(*) from pieces p where p.store_id = m.id and p.status = 'available'), 0)::int,
    coalesce((select jsonb_object_agg(k.karat, k.w) from (
        select p.karat, round(sum(p.weight_grams), 3) w from pieces p
         where p.store_id = m.id and p.status = 'available' and p.karat is not null group by 1) k), '{}'::jsonb),
    coalesce((select jsonb_object_agg(k.karat, k.w) from (
        select g.karat, round(sum(g.weight_grams_remaining), 3) w from gold_stock_lots g
         where g.store_id = m.id and g.box_name like 'كسر %' and g.weight_grams_remaining > 0 group by 1) k), '{}'::jsonb),
    coalesce((select sum(b) from (
        select sum(case d.movement_type when 'debt_increase' then d.cash_amount else -d.cash_amount end) b
          from customer_debts d where d.store_id = m.id and (d.source is null or d.source <> 'allocation')
         group by d.customer_id) x where b > 0.005), 0),
    coalesce((select count(*) from (
        select sum(case d.movement_type when 'debt_increase' then d.cash_amount else -d.cash_amount end) b
          from customer_debts d where d.store_id = m.id and (d.source is null or d.source <> 'allocation')
         group by d.customer_id) x where b > 0.005), 0)::int,
    coalesce((select round(sum(case t.movement_type when 'debt_decrease' then 1 else -1 end * coalesce(t.gold_24k_equivalent, 0)), 3)
                from trader_movements t where t.store_id = m.id), 0),
    coalesce((select round(sum(case t.movement_type when 'debt_decrease' then 1 else -1 end * coalesce(t.fab_fee_amount, 0)), 2)
                from trader_movements t where t.store_id = m.id), 0),
    coalesce((select count(*) from branch_transfers b where b.to_store_id = m.id and b.status = 'in_transit'), 0)::int
  from mine m
  order by m.oname nulls last, coalesce(m.head, false) desc, m.nm;
$$;
revoke execute on function public.owner_dashboard() from public, anon;
grant execute on function public.owner_dashboard() to authenticated;
