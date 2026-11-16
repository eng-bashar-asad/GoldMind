-- A sale paid partly from money the customer had already paid us (a plain «دفعة من العميل», not a
-- DEP deposit voucher) now shows in the daily box like a deposit (بشار 2026-11-16): the sale row
-- carries the whole invoice and one linked «عربون سابق» row takes the earlier money back out, so
-- the drawer still moves only by the cash received today. Example: INV-2026-000121 رزان خشيفاتي —
-- 2,730 sale, 2,280 earlier payment, 450 cash today.
create or replace function public.gm_deposit_sale_to_daily(p_invoice uuid, p_customer uuid)
returns void language plpgsql security definer set search_path = public as $$
declare inv record; a numeric; take numeric; d record; used numeric; g text; me uuid; cur text; row_id uuid; covered numeric := 0;
begin
  select i.id, i.store_id, i.invoice_number, i.type, coalesce(c.name, '') cname into inv
    from invoices i left join customers c on c.id = i.customer_id where i.id = p_invoice;
  if inv.id is null or inv.type <> 'sale' then return; end if;
  select coalesce(sum(cash_amount), 0) into a from customer_debts
   where invoice_id = p_invoice and source = 'allocation' and movement_type = 'debt_decrease' and entered_at = now();
  if a <= 0.009 then return; end if;
  select coalesce(nullif(upper(currency), ''), 'AED') into cur from stores where id = inv.store_id;
  select id into me from staff where user_id = auth.uid() and store_id = inv.store_id limit 1;
  g := 'dep_' || substr(replace(p_invoice::text, '-', ''), 1, 12);
  for d in select id, deposit_number, amount, created_at from customer_deposits
            where customer_id = p_customer and status = 'active' and method = 'cash' and in_cashbox
              and store_id in (select org_store_ids(inv.store_id))
            order by created_at, deposit_number loop
    exit when a <= 0.009;
    select coalesce(sum(amount), 0) into used from daily_cash_log
     where operation_type = 'عربون سابق' and direction = 'out' and store_id in (select org_store_ids(inv.store_id))
       and notes like d.deposit_number || ' بتاريخ ' || to_char(d.created_at at time zone 'Asia/Dubai', 'DD/MM/YYYY') || ' %';
    take := round(least(a, d.amount - used), 2);
    continue when take <= 0.009;
    insert into daily_cash_log (store_id, operation_type, direction, amount, currency, notes, created_by, link_group)
    values (inv.store_id, 'عربون سابق', 'out', take, cur,
            d.deposit_number || ' بتاريخ ' || to_char(d.created_at at time zone 'Asia/Dubai', 'DD/MM/YYYY') || ' — ' || inv.cname || ' · فاتورة ' || inv.invoice_number,
            me, g);
    a := a - take; covered := covered + take;
  end loop;
  -- what is left was paid earlier as an ordinary payment (balance in the customer's favour)
  if a > 0.009 then
    insert into daily_cash_log (store_id, operation_type, direction, amount, currency, notes, created_by, link_group)
    values (inv.store_id, 'عربون سابق', 'out', round(a, 2), cur,
            'رصيد مدفوع سابقاً — ' || inv.cname || ' · فاتورة ' || inv.invoice_number, me, g);
    covered := covered + round(a, 2);
  end if;
  if covered <= 0.009 then return; end if;
  select l.id into row_id from daily_cash_log l join cash_movements m on m.id = l.cash_movement_id
   where m.invoice_id = p_invoice and not coalesce(m.edit_delta, false) and l.direction = 'in' and upper(l.currency) = cur
   order by l.created_at limit 1;
  if row_id is not null then
    update daily_cash_log set amount = round(amount + covered, 2), link_group = g,
           notes = nullif(trim(coalesce(notes, '') || ' · منها ' || to_char(covered, 'FM999,999,990.00') || ' من عربون سابق'), '')
     where id = row_id;
  else
    insert into daily_cash_log (store_id, operation_type, direction, amount, currency, notes, created_by, link_group)
    values (inv.store_id, 'مبيعات لـ ' || inv.cname, 'in', round(covered, 2), cur,
            inv.invoice_number || ' — مدفوعة من عربون سابق', me, g);
  end if;
end $$;

-- INV-2026-000121 (رزان خشيفاتي, 16/11): show it the same way now
do $$
declare inv uuid := 'fee6a9de-bb1e-44bd-a3f5-6dcdaa24c175'; g text := 'dep_' || substr(replace('fee6a9de-bb1e-44bd-a3f5-6dcdaa24c175', '-', ''), 1, 12);
        row_id uuid; t timestamptz; who uuid;
begin
  if exists (select 1 from daily_cash_log where link_group = g) then return; end if;
  select l.id, l.created_at, l.created_by into row_id, t, who from daily_cash_log l join cash_movements m on m.id = l.cash_movement_id
   where m.invoice_id = inv and l.direction = 'in' and l.amount = 450 order by l.created_at limit 1;
  if row_id is null then return; end if;
  update daily_cash_log set amount = 2730, link_group = g, notes = notes || ' · منها 2,280.00 من عربون سابق' where id = row_id;
  insert into daily_cash_log (store_id, operation_type, direction, amount, currency, notes, created_by, link_group, created_at)
  values ('a15f496a-a4b5-4388-b304-5397eaeeda1b', 'عربون سابق', 'out', 2280, 'USD',
          'رصيد مدفوع سابقاً — رزان خشيفاتي · فاتورة INV-2026-000121', who, g, t);
end $$;
