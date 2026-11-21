-- An invoice edited from cash to debt (credit): the edit posts "out" of the main box
-- (cash_movements, edit_delta) but the daily box kept showing the sale as received,
-- because the mirror skipped every movement of an invoice whose method is no longer
-- cash / bank / mixed — and the invoice is updated before the movement is posted.
-- Edit deltas are now mirrored whatever the invoice's method; a full reversal shows
-- as an "out" row next to the original sale row (nothing is deleted).
create or replace function public.mirror_invoice_cash_to_daily()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare inv record; r record; first boolean := true; full_base numeric; amt numeric; cur text; note text; op text;
begin
  if new.invoice_id is null then return new; end if;
  -- a change of payment currencies: gm_invoice_daily_rewrite() sets the invoice's rows
  if coalesce(new.description, '') like 'تعديل عملات الدفع%' then return new; end if;
  select id, type, payment_method, pay_breakdown, pay_currency, pay_fx_rate, skip_daily into inv from public.invoices where id = new.invoice_id;
  if inv is null or inv.skip_daily then return new; end if; -- purchase kept out of the daily box
  if new.amount <= 0 then return new; end if;
  -- an edit delta always counts (cash → debt takes the money back out of the box)
  if inv.payment_method not in ('cash', 'bank', 'mixed') and not new.edit_delta then return new; end if;
  op := case inv.type when 'sale' then 'فاتورة بيع' when 'return' then 'مرتجع مبيعات' else 'فاتورة شراء' end;
  if new.edit_delta then
    amt := case when new.fx_currency is not null and new.fx_amount > 0 then new.fx_amount
                when inv.pay_currency is not null and inv.pay_fx_rate > 0 then new.amount * inv.pay_fx_rate else new.amount end;
    cur := coalesce(upper(new.fx_currency), case when inv.pay_currency is not null and inv.pay_fx_rate > 0 then inv.pay_currency end, new.currency);
    select l.id, l.direction, l.amount into r from daily_cash_log l join cash_movements m on m.id = l.cash_movement_id
     where m.invoice_id = inv.id and not m.edit_delta and upper(l.currency) = upper(cur)
     order by l.created_at limit 1;
    if r.id is not null then
      full_base := round(r.amount + case when new.direction = r.direction then amt else -amt end, 2);
      if full_base > 0 then
        update daily_cash_log set amount = full_base where id = r.id;
        perform public.sync_invoice_bank_part(new.invoice_id);
        return new;
      end if;
    end if;
  end if;
  if new.fx_currency is null and inv.pay_breakdown is not null then
    select sum((b->>'amount')::numeric / (b->>'rate')::numeric) into full_base from jsonb_array_elements(inv.pay_breakdown) b;
    if abs(new.amount - full_base) < 0.05 then
      for r in select upper(b->>'currency') c, sum((b->>'amount')::numeric) a from jsonb_array_elements(inv.pay_breakdown) b
               where b->>'method' = 'cash' and (b->>'amount')::numeric > 0 group by 1 order by 1 loop
        insert into public.daily_cash_log (store_id, operation_type, direction, amount, currency, notes, created_by, cash_movement_id, bank_invoice_id)
        values (new.store_id, op, new.direction, round(r.a, 2), r.c, new.description, new.created_by,
                case when first then new.id end, case when first then null else inv.id end);
        first := false;
      end loop;
      return new;
    end if;
  end if;
  amt := round(new.amount, 2); cur := new.currency; note := new.description;
  if new.fx_currency is not null and new.fx_amount > 0 then
    amt := round(new.fx_amount, 2); cur := upper(new.fx_currency);
  elsif inv.pay_currency is not null and inv.pay_fx_rate > 0 and upper(inv.pay_currency) <> upper(coalesce(new.currency, '')) then
    amt := round(new.amount * inv.pay_fx_rate, 2); cur := inv.pay_currency;
  end if;
  insert into public.daily_cash_log (store_id, operation_type, direction, amount, currency, notes, created_by, cash_movement_id)
  values (new.store_id, op, new.direction, amt, cur, note, new.created_by, new.id);
  perform public.sync_invoice_bank_part(new.invoice_id);
  return new;
end $function$;

-- the one edit already missed (INV-2026-000138): add its "out" row on the day it was made
insert into public.daily_cash_log (store_id, operation_type, direction, amount, currency, notes, created_by, cash_movement_id, created_at)
select m.store_id, 'فاتورة بيع', m.direction, round(m.amount, 2), m.currency, m.description, m.created_by, m.id, m.created_at
  from public.cash_movements m join public.invoices i on i.id = m.invoice_id
 where m.edit_delta and i.payment_method not in ('cash', 'bank', 'mixed') and not coalesce(i.skip_daily, false)
   and coalesce(m.description, '') not like 'تعديل عملات الدفع%'
   and not exists (select 1 from public.daily_cash_log l where l.cash_movement_id = m.id);
