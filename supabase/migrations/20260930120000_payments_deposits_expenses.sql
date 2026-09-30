-- Customer payments, deposits (عربون) and expenses — all money that comes in or
-- goes out by hand now lands in the daily cashbox, and payments pay off the
-- customer's invoices oldest first.

-- ---------------------------------------------------------------------------
-- 1) Pay invoices from the customer's free credit, oldest invoice first.
--    free credit = what open invoices still say is owed − what the customer
--    really owes in total. Each allocation writes a zero-sum pair so the
--    customer's balance never changes: a debt_decrease on the invoice and a
--    debt_increase off-invoice.
-- ---------------------------------------------------------------------------
create or replace function public.gm_allocate_customer_credit(sid uuid, cust uuid)
returns void language plpgsql security definer set search_path = public as $$
declare owed numeric; open_rem numeric; credit numeric; r record; a numeric; me uuid;
begin
  if cust is null then return; end if;
  select coalesce(sum(case when movement_type = 'debt_increase' then cash_amount else -cash_amount end), 0)
    into owed from customer_debts where store_id = sid and customer_id = cust;
  select coalesce(sum(total_amount - coalesce(amount_paid, 0)), 0) into open_rem
    from invoices where store_id = sid and customer_id = cust and type = 'sale' and status <> 'cancelled'
     and total_amount - coalesce(amount_paid, 0) > 0.009;
  credit := round(open_rem - owed, 2);
  if credit <= 0.009 then return; end if;
  select id into me from staff where user_id = auth.uid() and store_id = sid limit 1;
  for r in select id, invoice_number, total_amount - coalesce(amount_paid, 0) rem
             from invoices where store_id = sid and customer_id = cust and type = 'sale' and status <> 'cancelled'
              and total_amount - coalesce(amount_paid, 0) > 0.009
            order by created_at, invoice_number for update
  loop
    exit when credit <= 0.009;
    a := least(credit, r.rem);
    insert into customer_debts (store_id, customer_id, invoice_id, movement_type, cash_amount, gold_grams_24k, notes, source, created_by) values
      (sid, cust, r.id, 'debt_decrease', a, 0, 'دفعة مخصّصة للفاتورة ' || r.invoice_number, 'allocation', me),
      (sid, cust, null, 'debt_increase', a, 0, 'تخصيص دفعة للفاتورة ' || r.invoice_number, 'allocation', me);
    update invoices set amount_paid = coalesce(amount_paid, 0) + a,
                        status = case when total_amount - coalesce(amount_paid, 0) - a <= 0.009 then 'paid' else status end
     where id = r.id;
    credit := credit - a;
  end loop;
end $$;
revoke all on function public.gm_allocate_customer_credit(uuid, uuid) from public, anon;

create or replace function public.trg_customer_debts_allocate()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform gm_allocate_customer_credit(new.store_id, new.customer_id);
  return null;
end $$;
drop trigger if exists trg_customer_debts_allocate on public.customer_debts;
create trigger trg_customer_debts_allocate after insert on public.customer_debts
  for each row when (new.source is distinct from 'allocation') execute function public.trg_customer_debts_allocate();

-- ---------------------------------------------------------------------------
-- 2) A payment from a customer: debt goes down, cash goes into the box and,
--    when paid in cash, into the daily cashbox.
-- ---------------------------------------------------------------------------
create or replace function public.record_customer_payment(p_customer uuid, p_amount numeric, p_method text default 'cash', p_notes text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c record; me uuid; amt numeric := round(coalesce(p_amount, 0), 2); cm uuid; note text;
begin
  select id, store_id, name into c from customers where id = p_customer;
  if c is null then raise exception 'العميل غير موجود'; end if;
  if not (has_permission('edit_customers', c.store_id) or has_permission('manage_daily_cashbox', c.store_id)) then
    raise exception 'ليس لديك صلاحية تسجيل دفعات العملاء' using errcode = '42501';
  end if;
  if amt <= 0 then raise exception 'المبلغ يجب أن يكون أكبر من صفر'; end if;
  if coalesce(p_method, 'cash') not in ('cash', 'bank') then raise exception 'طريقة دفع غير معروفة'; end if;
  select id into me from staff where user_id = auth.uid() and store_id = c.store_id limit 1;
  note := coalesce(nullif(trim(p_notes), ''), 'دفعة من العميل');

  insert into cash_movements (store_id, box, direction, amount, description, created_by)
    values (c.store_id, case when p_method = 'bank' then 'bank' else 'main' end, 'in', amt,
            'دفعة من العميل ' || c.name || case when p_method = 'bank' then ' (تحويل/بطاقة)' else '' end, me)
    returning id into cm;
  if coalesce(p_method, 'cash') = 'cash' then
    insert into daily_cash_log (store_id, operation_type, direction, amount, notes, created_by, cash_movement_id)
      values (c.store_id, 'دفعة من عميل', 'in', amt, c.name || ' — ' || note, me, cm);
  end if;
  -- the allocation trigger pays the oldest open invoices from this
  insert into customer_debts (store_id, customer_id, movement_type, cash_amount, gold_grams_24k, notes, source, created_by)
    values (c.store_id, c.id, 'debt_decrease', amt, 0, note, 'payment', me);
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.record_customer_payment(uuid, numeric, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3) Deposits (عربون): a numbered voucher for the customer, the money goes to
--    the daily cashbox and stands on the customer's account as credit.
-- ---------------------------------------------------------------------------
create table if not exists public.customer_deposits (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  deposit_number text not null,
  customer_id uuid not null references public.customers(id),
  amount numeric not null check (amount > 0),
  currency text,
  method text not null default 'cash',
  items jsonb not null default '[]'::jsonb,
  notes text,
  status text not null default 'active' check (status in ('active', 'refunded')),
  created_by uuid,
  created_at timestamptz not null default now(),
  refunded_at timestamptz,
  unique (store_id, deposit_number)
);
alter table public.customer_deposits enable row level security;
drop policy if exists customer_deposits_select on public.customer_deposits;
create policy customer_deposits_select on public.customer_deposits for select
  using (is_store_member(store_id) and (has_permission('view_customers', store_id) or has_permission('manage_daily_cashbox', store_id)));
drop trigger if exists trg_customer_deposits_currency on public.customer_deposits;
create trigger trg_customer_deposits_currency before insert on public.customer_deposits
  for each row execute function public.fill_currency_from_store();

create or replace function public.create_customer_deposit(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c record; me uuid; amt numeric := round(coalesce(nullif(p->>'amount', '')::numeric, 0), 2);
        meth text := coalesce(nullif(p->>'method', ''), 'cash'); num text; dep_id uuid; cm uuid;
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

  insert into customer_deposits (store_id, deposit_number, customer_id, amount, method, items, notes, created_by)
    values (c.store_id, num, c.id, amt, meth, coalesce(p->'items', '[]'::jsonb), nullif(trim(p->>'notes'), ''), me)
    returning id into dep_id;
  insert into cash_movements (store_id, box, direction, amount, description, created_by)
    values (c.store_id, case when meth = 'bank' then 'bank' else 'main' end, 'in', amt, 'عربون ' || num || ' من ' || c.name, me)
    returning id into cm;
  if meth = 'cash' then
    insert into daily_cash_log (store_id, operation_type, direction, amount, notes, created_by, cash_movement_id)
      values (c.store_id, 'عربون', 'in', amt, 'عربون ' || num || ' — ' || c.name, me, cm);
  end if;
  insert into customer_debts (store_id, customer_id, movement_type, cash_amount, gold_grams_24k, notes, source, created_by)
    values (c.store_id, c.id, 'debt_decrease', amt, 0, 'عربون ' || num, 'deposit', me);
  return jsonb_build_object('id', dep_id, 'deposit_number', num);
end $$;
grant execute on function public.create_customer_deposit(jsonb) to authenticated;

create or replace function public.refund_customer_deposit(p_deposit uuid)
returns void language plpgsql security definer set search_path = public as $$
declare d record; me uuid; cm uuid;
begin
  select dp.*, cu.name cname into d from customer_deposits dp join customers cu on cu.id = dp.customer_id where dp.id = p_deposit for update of dp;
  if d is null then raise exception 'العربون غير موجود'; end if;
  if not (has_permission('edit_customers', d.store_id) or has_permission('manage_daily_cashbox', d.store_id)) then
    raise exception 'ليس لديك صلاحية' using errcode = '42501';
  end if;
  if d.status <> 'active' then raise exception 'هذا العربون مُسترجَع مسبقاً'; end if;
  select id into me from staff where user_id = auth.uid() and store_id = d.store_id limit 1;
  update customer_deposits set status = 'refunded', refunded_at = now() where id = d.id;
  insert into cash_movements (store_id, box, direction, amount, description, created_by)
    values (d.store_id, case when d.method = 'bank' then 'bank' else 'main' end, 'out', d.amount, 'استرجاع عربون ' || d.deposit_number || ' إلى ' || d.cname, me)
    returning id into cm;
  if d.method = 'cash' then
    insert into daily_cash_log (store_id, operation_type, direction, amount, notes, created_by, cash_movement_id)
      values (d.store_id, 'استرجاع عربون', 'out', d.amount, d.deposit_number || ' — ' || d.cname, me, cm);
  end if;
  insert into customer_debts (store_id, customer_id, movement_type, cash_amount, gold_grams_24k, notes, source, created_by)
    values (d.store_id, d.customer_id, 'debt_increase', d.amount, 0, 'استرجاع عربون ' || d.deposit_number, 'deposit_refund', me);
end $$;
grant execute on function public.refund_customer_deposit(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4) Expenses: staff who run the daily cashbox can record them; paid from the
--    cashbox means they also leave the daily cashbox.
-- ---------------------------------------------------------------------------
create or replace function public.gm_can_expense(sid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select has_permission('manage_daily_cashbox', sid) or has_permission('view_profit_report', sid)
$$;

create or replace function public.record_expense(p jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare sid uuid := (p->>'store_id')::uuid; me uuid; cat record; amt numeric := round(coalesce(nullif(p->>'amount', '')::numeric, 0), 2);
        eid uuid; cm uuid; descr text := nullif(trim(p->>'description'), '');
begin
  if not gm_can_expense(sid) or not is_store_member(sid) then raise exception 'ليس لديك صلاحية تسجيل المصاريف' using errcode = '42501'; end if;
  select id, name into cat from expense_categories where id = (p->>'category_id')::uuid and store_id = sid;
  if cat is null then raise exception 'اختر نوع المصروف'; end if;
  if amt <= 0 then raise exception 'المبلغ يجب أن يكون أكبر من صفر'; end if;
  select id into me from staff where user_id = auth.uid() and store_id = sid limit 1;
  insert into expense_entries (store_id, category_id, amount, description, attachment_url, created_by)
    values (sid, cat.id, amt, coalesce(descr, cat.name), nullif(p->>'attachment_url', ''), me) returning id into eid;
  insert into cash_movements (store_id, box, direction, amount, description, created_by)
    values (sid, 'main', 'out', amt, 'مصروف ' || cat.name || coalesce(': ' || descr, ''), me) returning id into cm;
  if coalesce((p->>'from_daily_cashbox')::boolean, true) then
    insert into daily_cash_log (store_id, operation_type, direction, amount, notes, created_by, cash_movement_id)
      values (sid, 'مصروف: ' || cat.name, 'out', amt, descr, me, cm);
  end if;
  return eid;
end $$;
grant execute on function public.record_expense(jsonb) to authenticated;

create or replace function public.save_expense_category(p_store uuid, p_name text, p_id uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare nm text := nullif(trim(p_name), ''); rid uuid;
begin
  if not gm_can_expense(p_store) or not is_store_member(p_store) then raise exception 'ليس لديك صلاحية' using errcode = '42501'; end if;
  if nm is null then raise exception 'اكتب اسم نوع المصروف'; end if;
  if exists (select 1 from expense_categories where store_id = p_store and name = nm and id is distinct from p_id) then
    raise exception 'هذا النوع موجود مسبقاً';
  end if;
  if p_id is null then
    insert into expense_categories (store_id, name) values (p_store, nm) returning id into rid;
  else
    if (select name from expense_categories where id = p_id and store_id = p_store) = 'هدايا' then raise exception 'لا يمكن تغيير اسم نوع الهدايا'; end if;
    update expense_categories set name = nm where id = p_id and store_id = p_store returning id into rid;
  end if;
  return rid;
end $$;
grant execute on function public.save_expense_category(uuid, text, uuid) to authenticated;

create or replace function public.delete_expense_category(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare c record;
begin
  select * into c from expense_categories where id = p_id;
  if c is null then return; end if;
  if not gm_can_expense(c.store_id) then raise exception 'ليس لديك صلاحية' using errcode = '42501'; end if;
  if c.name = 'هدايا' then raise exception 'لا يمكن حذف نوع الهدايا'; end if;
  if exists (select 1 from expense_entries where category_id = p_id) then
    raise exception 'لا يمكن حذف نوع عليه مصاريف مسجّلة — يمكنك تغيير اسمه';
  end if;
  delete from expense_categories where id = p_id;
end $$;
grant execute on function public.delete_expense_category(uuid) to authenticated;

-- staff who record expenses may also read them
drop policy if exists expense_entries_select on public.expense_entries;
create policy expense_entries_select on public.expense_entries for select
  using (is_store_member(store_id) and gm_can_expense(store_id));

-- ---------------------------------------------------------------------------
-- 5) Accounting check: count payments allocated to an invoice as paid.
-- ---------------------------------------------------------------------------
create or replace function public.accounting_health_check(sid uuid)
 returns table(severity text, code text, title text, details text, ref_id uuid, ref_label text)
 language plpgsql stable security definer set search_path to 'public'
as $function$
declare scur text;
begin
  if not (has_permission('view_reports', sid)) then
    raise exception 'ليس لديك صلاحية' using errcode = '42501';
  end if;
  select upper(coalesce(nullif(currency,''),'AED')) into scur from stores where id = sid;

  return query
  select 'error', 'gold_price_currency', 'سعر الذهب لا يتناسب مع عملة المحل',
         gold_price_problem(sid, g.karat, g.price_per_gram), null::uuid, g.karat || 'K'
  from gold_prices g where g.store_id = sid and gold_price_problem(sid, g.karat, g.price_per_gram) is not null;

  return query
  select 'warning', 'invoice_currency', 'فاتورة بعملة غير عملة المحل',
         format('الفاتورة بـ %s والمحل بـ %s', i.currency, scur), i.id, i.invoice_number
  from invoices i where i.store_id = sid and i.currency is not null and upper(i.currency) <> scur and i.status <> 'cancelled';

  return query
  select 'error', 'invoice_lines_total', 'مجموع سطور الفاتورة ≠ الإجمالي',
         format('السطور %s — الإجمالي %s', coalesce(x.s, 0), i.total_amount), i.id, i.invoice_number
  from invoices i left join lateral (select sum(line_total) s, count(*) n from invoice_items where invoice_id = i.id) x on true
  where i.store_id = sid and i.type = 'sale' and i.status <> 'cancelled'
    and (x.n = 0 or abs(coalesce(x.s, 0) - i.total_amount) > 0.01);

  -- paid = cash booked on the invoice + later payments allocated to it
  return query
  select 'warning', 'invoice_cash_mismatch', 'المقبوض بالفاتورة ≠ المسجّل بالصندوق والدفعات',
         format('مدفوع %s — بالصندوق %s — دفعات لاحقة %s', i.amount_paid, coalesce(c.s, 0), coalesce(al.s, 0)), i.id, i.invoice_number
  from invoices i
  left join lateral (select sum(case when direction = 'in' then amount else -amount end) s from cash_movements where invoice_id = i.id) c on true
  left join lateral (select sum(cash_amount) s from customer_debts where invoice_id = i.id and source = 'allocation') al on true
  where i.store_id = sid and i.type = 'sale' and i.status <> 'cancelled' and i.payment_method in ('cash','bank','mixed')
    and abs(coalesce(c.s, 0) + coalesce(al.s, 0) - coalesce(i.amount_paid, 0)) > 0.01;

  -- remaining on the invoice = debt still recorded against it
  return query
  select 'warning', 'invoice_debt_mismatch', 'المبلغ المتبقي على العميل غير مسجّل كدين',
         format('متبقي %s — مسجّل دين %s', i.total_amount - coalesce(i.amount_paid,0), coalesce(d.s, 0)), i.id, i.invoice_number
  from invoices i left join lateral (
      select sum(case when movement_type = 'debt_increase' then cash_amount else -cash_amount end) s
        from customer_debts where invoice_id = i.id) d on true
  where i.store_id = sid and i.type = 'sale' and i.status <> 'cancelled'
    and abs((i.total_amount - coalesce(i.amount_paid,0)) - coalesce(d.s, 0)) > 0.01;

  return query
  select 'error', 'cash_currency', 'حركة صندوق لفاتورة بعملة غلط',
         format('%s %s — عملة المحل %s', cm.amount, cm.currency, scur), cm.invoice_id, i.invoice_number
  from cash_movements cm join invoices i on i.id = cm.invoice_id
  where cm.store_id = sid and cm.currency is not null and upper(cm.currency) <> upper(coalesce(i.currency, scur));

  return query
  select 'error', 'piece_still_available', 'قطعة مباعة لكنها ما زالت تظهر متاحة',
         format('القطعة %s بالفاتورة %s', p.barcode, i.invoice_number), p.id, p.barcode
  from invoice_items ii join invoices i on i.id = ii.invoice_id join pieces p on p.id = ii.piece_id
  where i.store_id = sid and i.type = 'sale' and i.status <> 'cancelled' and p.status = 'available';

  return query
  select 'error', 'negative_stock', 'رصيد جملة سالب',
         format('عيار %s: %s غ', l.karat, l.weight_grams_remaining), l.id, l.karat || 'K'
  from gold_stock_lots l where l.store_id = sid and (l.weight_grams_remaining < 0 or coalesce(l.fabrication_pool_remaining, 0) < 0);
end $function$;

alter table public.customer_deposits add constraint customer_deposits_created_by_fkey foreign key (created_by) references public.staff(id) on delete set null;
create index if not exists customer_deposits_store_idx on public.customer_deposits(store_id, created_at desc);
