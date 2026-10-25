-- A sale paid (fully or partly) by an earlier deposit (عربون): the daily cash box shows the
-- whole invoice in «الداخل» and the deposit used in «الصادر» as «عربون سابق», linked together.
-- The drawer total does not change (the deposit money already came in on the deposit's day).
-- Only cash deposits that went into the box are used, oldest first, never more than what is
-- left of each deposit (earlier «عربون سابق» rows count as used).
create or replace function public.gm_deposit_sale_to_daily(p_invoice uuid, p_customer uuid)
returns void language plpgsql security definer set search_path = public as $$
declare inv record; a numeric; take numeric; d record; used numeric; g text; me uuid; cur text; row_id uuid; covered numeric := 0;
begin
  select i.id, i.store_id, i.invoice_number, i.type, coalesce(c.name, '') cname into inv
    from invoices i left join customers c on c.id = i.customer_id where i.id = p_invoice;
  if inv.id is null or inv.type <> 'sale' then return; end if;
  -- credit applied to this invoice in this same transaction
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
  if covered <= 0.009 then return; end if;
  -- the invoice's own cash row grows to the full amount; if it has no cash row, one is added
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
revoke execute on function public.gm_deposit_sale_to_daily(uuid, uuid) from public, anon, authenticated;

create or replace function public.trg_customer_debts_allocate()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform gm_allocate_customer_credit(new.store_id, new.customer_id);
  -- a new sale debt just paid from the customer's credit: show the deposit part in the daily box
  if new.movement_type = 'debt_increase' and new.invoice_id is not null then
    perform gm_deposit_sale_to_daily(new.invoice_id, new.customer_id);
  end if;
  return null;
end $$;
