-- Multi-branch 2.1 (part 2): one balance per customer across the organization (decision by بشار
-- 2026-10-18), money recorded on the branch that handles it.
--   * gm_allocate / gm_unallocate_customer_credit, customer_credit, customer_deposit_remaining:
--     balance and open invoices counted over every branch of the organization; an allocation row
--     pair goes on the paid invoice's branch (the pair nets to zero, so no branch total moves).
--   * record_customer_payment, customer_cash_out, customer_debt_discount: new optional p_store,
--     the branch taking the money; without it (old screens) they act on the customer's branch as
--     before. The old 4/3-argument versions are replaced (same names, one more optional argument).
--   * create_customer_deposit, cash_voucher, post_sale_invoice, sale_invoice_change_customer:
--     accept a customer from any branch of the same organization; the deposit is recorded on the
--     branch in p->>'store_id' (default: the customer's branch, as before).
-- Single-branch shops: every "organization" filter is the store itself, so nothing changes.
-- No data is touched. Large functions are patched in place from their live text; each patch stops
-- the whole migration if the text it expects is not there.

begin;

-- the branches of a store's organization (just the store when it has none)
create or replace function public.org_store_ids(sid uuid)
returns setof uuid language sql stable security definer set search_path = public as $$
  select b.id from stores a join stores b on b.organization_id = a.organization_id where a.id = sid
  union select sid;
$$;
revoke all on function public.org_store_ids(uuid) from public, anon;
grant execute on function public.org_store_ids(uuid) to authenticated;

-- the organization's branches for the screens: id, shown name, and whether this user may open
-- that branch's invoices (own branch always; others need view_branch_invoices, owners always)
create or replace function public.org_branches(sid uuid)
returns table(id uuid, name text, can_open_invoices boolean)
language sql stable security definer set search_path = public as $$
  select b.id, coalesce(nullif(btrim(b.display_name), ''), b.name),
         b.id = sid or has_permission('view_branch_invoices', b.id) or org_can(b.id, 'view_branch_invoices')
  from stores b where b.id in (select org_store_ids(sid)) and is_store_member(sid)
  order by b.created_at;
$$;
revoke all on function public.org_branches(uuid) from public, anon;
grant execute on function public.org_branches(uuid) to authenticated;

create or replace function public.customer_credit(sid uuid, cust uuid)
returns numeric language sql stable set search_path = public as $$
  select round(greatest(0, -coalesce(sum(case when movement_type = 'debt_increase' then cash_amount else -cash_amount end), 0)), 2)
  from customer_debts where store_id in (select org_store_ids(sid)) and customer_id = cust;
$$;

-- deposits of this branch; what is left of each comes from the customer's organization-wide credit,
-- newest deposits counted first across all branches (as before within one store)
create or replace function public.customer_deposit_remaining(sid uuid)
returns table(deposit_id uuid, remaining numeric) language sql stable set search_path = public as $$
  with cred as (
    select customer_id, greatest(0, -sum(case when movement_type = 'debt_increase' then cash_amount else -cash_amount end)) c
    from customer_debts where store_id in (select org_store_ids(sid)) group by customer_id),
  d as (
    select dp.id, dp.store_id, dp.amount, coalesce(cr.c, 0) c,
           sum(dp.amount) over (partition by dp.customer_id order by dp.created_at desc, dp.id) run
    from customer_deposits dp left join cred cr on cr.customer_id = dp.customer_id
    where dp.store_id in (select org_store_ids(sid)) and dp.status = 'active')
  select id, round(least(amount, greatest(0, c - (run - amount))), 2) from d where store_id = sid;
$$;

create or replace function public.gm_allocate_customer_credit(sid uuid, cust uuid)
returns void language plpgsql security definer set search_path = public as $function$
declare owed numeric; open_rem numeric; credit numeric; r record; a numeric; me uuid;
begin
  if cust is null then return; end if;
  select coalesce(sum(case when movement_type = 'debt_increase' then cash_amount else -cash_amount end), 0)
    into owed from customer_debts where store_id in (select org_store_ids(sid)) and customer_id = cust;
  select coalesce(sum(total_amount - coalesce(amount_paid, 0)), 0) into open_rem
    from invoices where store_id in (select org_store_ids(sid)) and customer_id = cust and type = 'sale' and status <> 'cancelled'
     and total_amount - coalesce(amount_paid, 0) > 0.009;
  credit := round(open_rem - owed, 2);
  if credit <= 0.009 then return; end if;
  select id into me from staff where user_id = auth.uid() and store_id = sid limit 1;
  for r in select id, store_id, invoice_number, total_amount - coalesce(amount_paid, 0) rem
             from invoices where store_id in (select org_store_ids(sid)) and customer_id = cust and type = 'sale' and status <> 'cancelled'
              and total_amount - coalesce(amount_paid, 0) > 0.009
            order by created_at, invoice_number for update
  loop
    exit when credit <= 0.009;
    a := least(credit, r.rem);
    insert into customer_debts (store_id, customer_id, invoice_id, movement_type, cash_amount, gold_grams_24k, notes, source, created_by) values
      (r.store_id, cust, r.id, 'debt_decrease', a, 0, 'دفعة مخصّصة للفاتورة ' || r.invoice_number, 'allocation', me),
      (r.store_id, cust, null, 'debt_increase', a, 0, 'تخصيص دفعة للفاتورة ' || r.invoice_number, 'allocation', me);
    update invoices set amount_paid = coalesce(amount_paid, 0) + a,
                        status = case when total_amount - coalesce(amount_paid, 0) - a <= 0.009 then 'paid' else status end
     where id = r.id;
    credit := credit - a;
  end loop;
end $function$;

create or replace function public.gm_unallocate_customer_credit(sid uuid, cust uuid)
returns void language plpgsql security definer set search_path = public as $function$
declare owed numeric; open_rem numeric; deficit numeric; r record; a numeric; me uuid;
begin
  select coalesce(sum(case when movement_type = 'debt_increase' then cash_amount else -cash_amount end), 0)
    into owed from customer_debts where store_id in (select org_store_ids(sid)) and customer_id = cust;
  select coalesce(sum(total_amount - coalesce(amount_paid, 0)), 0) into open_rem
    from invoices where store_id in (select org_store_ids(sid)) and customer_id = cust and type = 'sale' and status <> 'cancelled'
     and total_amount - coalesce(amount_paid, 0) > 0.009;
  deficit := round(owed - open_rem, 2);
  if deficit <= 0.009 then return; end if;
  select id into me from staff where user_id = auth.uid() and store_id = sid limit 1;
  for r in select d.invoice_id, i.store_id, i.invoice_number, sum(case when d.movement_type = 'debt_decrease' then d.cash_amount else -d.cash_amount end) alloc, max(d.created_at) last_at
             from customer_debts d join invoices i on i.id = d.invoice_id
            where d.store_id in (select org_store_ids(sid)) and d.customer_id = cust and d.source = 'allocation' and i.status <> 'cancelled'
            group by d.invoice_id, i.store_id, i.invoice_number
           having sum(case when d.movement_type = 'debt_decrease' then d.cash_amount else -d.cash_amount end) > 0.009
            order by max(d.created_at) desc
  loop
    exit when deficit <= 0.009;
    a := least(deficit, r.alloc);
    insert into customer_debts (store_id, customer_id, invoice_id, movement_type, cash_amount, gold_grams_24k, notes, source, created_by) values
      (r.store_id, cust, r.invoice_id, 'debt_increase', a, 0, 'إلغاء تخصيص للفاتورة ' || r.invoice_number, 'allocation', me),
      (r.store_id, cust, null, 'debt_decrease', a, 0, 'إلغاء تخصيص للفاتورة ' || r.invoice_number, 'allocation', me);
    update invoices set amount_paid = greatest(coalesce(amount_paid, 0) - a, 0),
                        status = case when status = 'paid' then 'unpaid' else status end
     where id = r.invoice_id;
    deficit := deficit - a;
  end loop;
end $function$;

-- payments, cash-out and discount: the branch taking the money (p_store), default the customer's
drop function if exists public.record_customer_payment(uuid, numeric, text, text);
create function public.record_customer_payment(p_customer uuid, p_amount numeric, p_method text default 'cash', p_notes text default null, p_store uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare c record; st uuid; me uuid; amt numeric := round(coalesce(p_amount, 0), 2); cm uuid; note text;
begin
  select id, store_id, name into c from customers where id = p_customer;
  if c is null then raise exception 'العميل غير موجود'; end if;
  st := coalesce(p_store, c.store_id);
  if st not in (select org_store_ids(c.store_id)) then raise exception 'العميل ليس من هذه المنشأة'; end if;
  if not (has_permission('edit_customers', st) or has_permission('manage_daily_cashbox', st)) then
    raise exception 'ليس لديك صلاحية تسجيل دفعات العملاء' using errcode = '42501';
  end if;
  if amt <= 0 then raise exception 'المبلغ يجب أن يكون أكبر من صفر'; end if;
  if coalesce(p_method, 'cash') not in ('cash', 'bank') then raise exception 'طريقة دفع غير معروفة'; end if;
  select id into me from staff where user_id = auth.uid() and store_id = st limit 1;
  note := coalesce(nullif(trim(p_notes), ''), 'دفعة من العميل');
  insert into cash_movements (store_id, box, direction, amount, description, created_by)
    values (st, case when p_method = 'bank' then 'bank' else 'main' end, 'in', amt,
            'دفعة من العميل ' || c.name || case when p_method = 'bank' then ' (تحويل/بطاقة)' else '' end, me)
    returning id into cm;
  if coalesce(p_method, 'cash') = 'cash' then
    insert into daily_cash_log (store_id, operation_type, direction, amount, notes, created_by, cash_movement_id)
      values (st, 'دفعة من عميل', 'in', amt, c.name || ' — ' || note, me, cm);
  end if;
  insert into customer_debts (store_id, customer_id, movement_type, cash_amount, gold_grams_24k, notes, source, created_by, cash_movement_id)
    values (st, c.id, 'debt_decrease', amt, 0, note, 'payment', me, cm);
  return jsonb_build_object('ok', true);
end $function$;
revoke all on function public.record_customer_payment(uuid, numeric, text, text, uuid) from public, anon;
grant execute on function public.record_customer_payment(uuid, numeric, text, text, uuid) to authenticated;

drop function if exists public.customer_cash_out(uuid, numeric, text, text);
create function public.customer_cash_out(p_customer uuid, p_amount numeric, p_method text default 'cash', p_notes text default null, p_store uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare c record; st uuid; me uuid; amt numeric := round(coalesce(p_amount, 0), 2); cm uuid; note text;
begin
  select id, store_id, name into c from customers where id = p_customer;
  if c is null then raise exception 'العميل غير موجود'; end if;
  st := coalesce(p_store, c.store_id);
  if st not in (select org_store_ids(c.store_id)) then raise exception 'العميل ليس من هذه المنشأة'; end if;
  if not (has_permission('edit_customers', st) or has_permission('manage_daily_cashbox', st)) then
    raise exception 'ليس لديك صلاحية صرف مبالغ للعملاء' using errcode = '42501';
  end if;
  if amt <= 0 then raise exception 'المبلغ يجب أن يكون أكبر من صفر'; end if;
  if coalesce(p_method, 'cash') not in ('cash', 'bank') then raise exception 'طريقة دفع غير معروفة'; end if;
  select id into me from staff where user_id = auth.uid() and store_id = st limit 1;
  note := coalesce(nullif(trim(p_notes), ''), 'صرف للعميل');
  insert into cash_movements (store_id, box, direction, amount, description, created_by)
    values (st, case when p_method = 'bank' then 'bank' else 'main' end, 'out', amt,
            'صرف للعميل ' || c.name || case when p_method = 'bank' then ' (تحويل/بطاقة)' else '' end, me)
    returning id into cm;
  if coalesce(p_method, 'cash') = 'cash' then
    insert into daily_cash_log (store_id, operation_type, direction, amount, notes, created_by, cash_movement_id)
      values (st, 'صرف لعميل', 'out', amt, c.name || ' — ' || note, me, cm);
  end if;
  insert into customer_debts (store_id, customer_id, movement_type, cash_amount, gold_grams_24k, notes, source, created_by, cash_movement_id)
    values (st, c.id, 'debt_increase', amt, 0, note, 'cash_out', me, cm);
  return jsonb_build_object('ok', true);
end $function$;
revoke all on function public.customer_cash_out(uuid, numeric, text, text, uuid) from public, anon;
grant execute on function public.customer_cash_out(uuid, numeric, text, text, uuid) to authenticated;

drop function if exists public.customer_debt_discount(uuid, numeric, text);
create function public.customer_debt_discount(p_customer uuid, p_amount numeric, p_notes text default null, p_store uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare c record; st uuid; me uuid; amt numeric := round(coalesce(p_amount, 0), 2); owed numeric;
begin
  select id, store_id, name into c from customers where id = p_customer;
  if c is null then raise exception 'العميل غير موجود'; end if;
  st := coalesce(p_store, c.store_id);
  if st not in (select org_store_ids(c.store_id)) then raise exception 'العميل ليس من هذه المنشأة'; end if;
  if not has_permission('edit_customers', st) then
    raise exception 'ليس لديك صلاحية تسجيل خصم على دين العميل' using errcode = '42501';
  end if;
  if amt <= 0 then raise exception 'المبلغ يجب أن يكون أكبر من صفر'; end if;
  -- the customer's whole debt across the organization
  select coalesce(sum(case when movement_type = 'debt_increase' then cash_amount else -cash_amount end), 0) into owed
    from customer_debts where customer_id = c.id and store_id in (select org_store_ids(st));
  if amt > round(owed, 2) + 0.009 then raise exception 'الخصم (%) أكبر من دين العميل (%)', amt, round(owed, 2); end if;
  select id into me from staff where user_id = auth.uid() and store_id = st limit 1;
  -- Balance-only: no cash moves. Settles the oldest open invoices like a payment.
  insert into customer_debts (store_id, customer_id, movement_type, cash_amount, gold_grams_24k, notes, source, created_by)
    values (st, c.id, 'debt_decrease', amt, 0, coalesce(nullif(trim(p_notes), ''), 'خصم على الدين'), 'discount', me);
  return jsonb_build_object('ok', true);
end $function$;
revoke all on function public.customer_debt_discount(uuid, numeric, text, uuid) from public, anon;
grant execute on function public.customer_debt_discount(uuid, numeric, text, uuid) to authenticated;

-- patch helper for the large functions: replace one exact piece of the live text, or stop
create or replace function pg_temp.gm_patch(fn regprocedure, old_txt text, new_txt text)
returns void language plpgsql as $$
declare d text := pg_get_functiondef(fn);
begin
  if position(old_txt in d) = 0 then raise exception 'patch %: expected text not found: %', fn, old_txt; end if;
  execute replace(d, old_txt, new_txt);
end $$;

-- create_customer_deposit: recorded on p->>'store_id' (default the customer's branch)
select pg_temp.gm_patch('public.create_customer_deposit(jsonb)',
  'select id, store_id, name into c from customers where id = (p->>''customer_id'')::uuid;',
  'select id, coalesce(nullif(p->>''store_id'', '''')::uuid, store_id) as store_id, store_id as home_store, name into c from customers where id = (p->>''customer_id'')::uuid;
  if c is not null and c.store_id not in (select org_store_ids(c.home_store)) then raise exception ''العميل ليس من هذه المنشأة''; end if;');

-- cash_voucher: a customer from any branch of the organization
select pg_temp.gm_patch('public.cash_voucher(jsonb)',
  'select id, store_id, name into c from customers where id = pid and store_id = sid;',
  'select id, store_id, name into c from customers where id = pid and store_id in (select org_store_ids(sid));');

-- post_sale_invoice: a customer from any branch of the organization (found by name too)
select pg_temp.gm_patch('public.post_sale_invoice(jsonb)',
  'select id into cust from customers where store_id = sid and name = trim(p->''new_customer''->>''name'')',
  'select id into cust from customers where store_id in (select org_store_ids(sid)) and name = trim(p->''new_customer''->>''name'')');
select pg_temp.gm_patch('public.post_sale_invoice(jsonb)',
  'if cust is null or not exists (select 1 from customers where id = cust and store_id = sid) then',
  'if cust is null or not exists (select 1 from customers where id = cust and store_id in (select org_store_ids(sid))) then');

-- sale_invoice_change_customer: the new customer may come from another branch of the organization
select pg_temp.gm_patch('public.sale_invoice_change_customer(uuid,uuid)',
  'select id, name into newc from customers where id = p_customer and store_id = inv.store_id;',
  'select id, name into newc from customers where id = p_customer and store_id in (select org_store_ids(inv.store_id));');

commit;
