-- Customer deposit (عربون): the amount can be kept out of the daily cashbox.
-- p.to_cashbox = false -> no cash_movements / daily_cash_log rows; the customer's credit still
-- records the deposit. in_cashbox remembers the choice so a refund only reverses real cash.
-- Old callers that don't send to_cashbox keep the previous behaviour (cashbox = true).

alter table public.customer_deposits add column if not exists in_cashbox boolean not null default true;
-- A piece put on a deposit (matched by its barcode) becomes 'reserved' for that customer only:
-- new sales hide it from everyone else; the depositor can still buy it. Refund releases it.
alter table public.pieces add column if not exists reserved_customer_id uuid references public.customers(id) on delete set null;

create or replace function public.create_customer_deposit(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c record; me uuid; amt numeric := round(coalesce(nullif(p->>'amount', '')::numeric, 0), 2);
        meth text := coalesce(nullif(p->>'method', ''), 'cash'); num text; dep_id uuid; cm uuid;
        to_box boolean := coalesce((p->>'to_cashbox')::boolean, true);
begin
  select id, store_id, name into c from customers where id = (p->>'customer_id')::uuid;
  if c is null then raise exception 'اختر العميل'; end if;
  if not (has_permission('edit_customers', c.store_id) or has_permission('manage_daily_cashbox', c.store_id)) then
    raise exception 'ليس لديك صلاحية تسجيل العربون' using errcode = '42501';
  end if;
  if amt <= 0 then raise exception 'المبلغ يجب أن يكون أكبر من صفر'; end if;
  if meth not in ('cash', 'bank') then raise exception 'طريقة دفع غير معروفة'; end if;
  select id into me from staff where user_id = auth.uid() and store_id = c.store_id limit 1;

  perform pg_advisory_xact_lock(hashtext('deposit:' || c.store_id));
  select 'DEP-' || lpad((coalesce(max(nullif(regexp_replace(deposit_number, '\D', '', 'g'), '')::int), 0) + 1)::text, 6, '0')
    into num from customer_deposits where store_id = c.store_id;

  insert into customer_deposits (store_id, deposit_number, customer_id, amount, method, items, notes, created_by, in_cashbox)
    values (c.store_id, num, c.id, amt, meth, coalesce(p->'items', '[]'::jsonb), nullif(trim(p->>'notes'), ''), me, to_box)
    returning id into dep_id;
  if to_box then
    insert into cash_movements (store_id, box, direction, amount, description, created_by)
      values (c.store_id, case when meth = 'bank' then 'bank' else 'main' end, 'in', amt, 'عربون ' || num || ' من ' || c.name, me)
      returning id into cm;
    if meth = 'cash' then
      insert into daily_cash_log (store_id, operation_type, direction, amount, notes, created_by, cash_movement_id)
        values (c.store_id, 'عربون', 'in', amt, 'عربون ' || num || ' — ' || c.name, me, cm);
    end if;
  end if;
  insert into customer_debts (store_id, customer_id, movement_type, cash_amount, gold_grams_24k, notes, source, created_by)
    values (c.store_id, c.id, 'debt_decrease', amt, 0, 'عربون ' || num, 'deposit', me);
  update pieces set status = 'reserved', reserved_customer_id = c.id
    where store_id = c.store_id and status = 'available'
      and barcode in (select nullif(trim(x->>'barcode'), '') from jsonb_array_elements(coalesce(p->'items', '[]'::jsonb)) x);
  return jsonb_build_object('id', dep_id, 'deposit_number', num);
end $$;

create or replace function public.refund_customer_deposit(p_deposit uuid) returns void
language plpgsql security definer set search_path = public as $$
declare d record; me uuid; cm uuid; left_amt numeric;
begin
  select dp.*, cu.name cname into d from customer_deposits dp join customers cu on cu.id = dp.customer_id where dp.id = p_deposit for update of dp;
  if d is null then raise exception 'العربون غير موجود'; end if;
  if not (has_permission('edit_customers', d.store_id) or has_permission('manage_daily_cashbox', d.store_id)) then
    raise exception 'ليس لديك صلاحية' using errcode = '42501';
  end if;
  if d.status <> 'active' then raise exception 'هذا العربون مُسترجَع مسبقاً'; end if;
  select remaining into left_amt from customer_deposit_remaining(d.store_id) where deposit_id = d.id;
  if coalesce(left_amt, 0) < d.amount - 0.009 then
    raise exception 'هذا العربون استُخدم (كلياً أو جزئياً) في فاتورة، فلا يمكن استرجاعه كاملاً. لإعادة ما تبقّى للزبون استخدم «صرف للزبون» من صفحة حسابه.';
  end if;
  select id into me from staff where user_id = auth.uid() and store_id = d.store_id limit 1;
  update customer_deposits set status = 'refunded', refunded_at = now() where id = d.id;
  update pieces set status = 'available', reserved_customer_id = null
    where store_id = d.store_id and status = 'reserved' and reserved_customer_id = d.customer_id
      and barcode in (select nullif(trim(x->>'barcode'), '') from jsonb_array_elements(coalesce(d.items, '[]'::jsonb)) x);
  if d.in_cashbox then
    insert into cash_movements (store_id, box, direction, amount, description, created_by)
      values (d.store_id, case when d.method = 'bank' then 'bank' else 'main' end, 'out', d.amount, 'استرجاع عربون ' || d.deposit_number || ' إلى ' || d.cname, me)
      returning id into cm;
    if d.method = 'cash' then
      insert into daily_cash_log (store_id, operation_type, direction, amount, notes, created_by, cash_movement_id)
        values (d.store_id, 'استرجاع عربون', 'out', d.amount, d.deposit_number || ' — ' || d.cname, me, cm);
    end if;
  end if;
  insert into customer_debts (store_id, customer_id, movement_type, cash_amount, gold_grams_24k, notes, source, created_by)
    values (d.store_id, d.customer_id, 'debt_increase', d.amount, 0, 'استرجاع عربون ' || d.deposit_number, 'deposit_refund', me);
end $$;
