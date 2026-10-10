-- cancel_invoice / restore_invoice: reverse only the invoice's ORIGINAL entries (not earlier
-- cancel/restore rows). Before, each cancel reversed every row ever posted (including previous
-- cancels and restores), so a few cancel/restore cycles multiplied the amounts in the box.
CREATE OR REPLACE FUNCTION public.cancel_invoice(target_invoice_id uuid, reason text DEFAULT NULL::text)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  inv record;
  actor_staff_id uuid;
begin
  select * into inv from public.invoices where id = target_invoice_id;
  if inv is null then raise exception 'INVOICE_NOT_FOUND'; end if;
  if not public.has_permission('delete_invoice', inv.store_id) then raise exception 'NOT_AUTHORIZED'; end if;
  if inv.status = 'cancelled' then raise exception 'ALREADY_CANCELLED'; end if;

  select id into actor_staff_id from public.staff where user_id = auth.uid() and store_id = inv.store_id limit 1;

  -- the invoice stays in the record, marked cancelled (no gaps, no reuse of numbers)
  update public.invoices set status = 'cancelled' where id = target_invoice_id;

  if inv.type = 'sale' then
    update public.pieces set status = 'available'
    where id in (select piece_id from public.invoice_items where invoice_id = target_invoice_id and piece_id is not null);
  elsif inv.type in ('buyTrader', 'buyRetail') then
    update public.pieces set status = 'cancelled'
    where id in (select piece_id from public.invoice_items where invoice_id = target_invoice_id and piece_id is not null);
  end if;

  update public.gold_stock_lots set weight_grams_remaining = 0
    where source_invoice_id = target_invoice_id and weight_grams_remaining > 0;

  -- reversing entries for the original entries only
  insert into public.cash_movements (store_id, box, direction, amount, currency, fx_amount, fx_currency, description, created_by, invoice_id)
  select store_id, box, case when direction = 'in' then 'out' else 'in' end, amount, currency, fx_amount, fx_currency,
         'إلغاء فاتورة ' || inv.invoice_number || coalesce(' — ' || reason, ''), actor_staff_id, target_invoice_id
  from public.cash_movements where invoice_id = target_invoice_id
    and coalesce(description, '') not like 'إلغاء فاتورة%' and coalesce(description, '') not like 'استعادة فاتورة%';

  insert into public.customer_debts (store_id, customer_id, invoice_id, movement_type, cash_amount, gold_grams_24k, notes, created_by)
  select store_id, customer_id, invoice_id,
         case when movement_type = 'debt_increase' then 'debt_decrease' else 'debt_increase' end,
         cash_amount, gold_grams_24k, 'إلغاء فاتورة ' || inv.invoice_number || coalesce(' — ' || reason, ''), actor_staff_id
  from public.customer_debts where invoice_id = target_invoice_id
    and coalesce(notes, '') not like 'إلغاء فاتورة%' and coalesce(notes, '') not like 'استعادة فاتورة%';

  insert into public.trader_movements (store_id, trader_id, invoice_id, movement_type, weight_grams, karat, gold_24k_equivalent, fab_fee_amount, notes)
  select store_id, trader_id, invoice_id,
         case when movement_type = 'debt_increase' then 'debt_decrease' else 'debt_increase' end,
         weight_grams, karat, gold_24k_equivalent, fab_fee_amount, 'إلغاء فاتورة ' || inv.invoice_number || coalesce(' — ' || reason, '')
  from public.trader_movements where invoice_id = target_invoice_id
    and coalesce(notes, '') not like 'إلغاء فاتورة%' and coalesce(notes, '') not like 'استعادة فاتورة%';
end;
$function$;

CREATE OR REPLACE FUNCTION public.restore_invoice(target_invoice_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  inv record;
  actor_staff_id uuid;
  restored_status text;
begin
  select * into inv from public.invoices where id = target_invoice_id;
  if inv is null then raise exception 'INVOICE_NOT_FOUND'; end if;
  if not public.has_permission('delete_invoice', inv.store_id) then raise exception 'NOT_AUTHORIZED'; end if;
  if inv.status != 'cancelled' then raise exception 'NOT_CANCELLED'; end if;

  select id into actor_staff_id from public.staff where user_id = auth.uid() and store_id = inv.store_id limit 1;

  restored_status := case when coalesce(inv.amount_paid, 0) + 0.009 >= inv.total_amount and inv.payment_method <> 'credit' then 'paid' else 'unpaid' end;
  update public.invoices set status = restored_status where id = target_invoice_id;

  if inv.type = 'sale' then
    update public.pieces set status = 'sold'
    where id in (select piece_id from public.invoice_items where invoice_id = target_invoice_id and piece_id is not null);
  elsif inv.type in ('buyTrader', 'buyRetail') then
    update public.pieces set status = 'available'
    where id in (select piece_id from public.invoice_items where invoice_id = target_invoice_id and piece_id is not null);
  end if;

  -- put the original entries' effect back once (a copy in their own direction)
  insert into public.cash_movements (store_id, box, direction, amount, currency, fx_amount, fx_currency, description, created_by, invoice_id)
  select store_id, box, direction, amount, currency, fx_amount, fx_currency, 'استعادة فاتورة ' || inv.invoice_number, actor_staff_id, target_invoice_id
  from public.cash_movements where invoice_id = target_invoice_id
    and coalesce(description, '') not like 'إلغاء فاتورة%' and coalesce(description, '') not like 'استعادة فاتورة%';

  insert into public.customer_debts (store_id, customer_id, invoice_id, movement_type, cash_amount, gold_grams_24k, notes, created_by)
  select store_id, customer_id, invoice_id, movement_type, cash_amount, gold_grams_24k, 'استعادة فاتورة ' || inv.invoice_number, actor_staff_id
  from public.customer_debts where invoice_id = target_invoice_id
    and coalesce(notes, '') not like 'إلغاء فاتورة%' and coalesce(notes, '') not like 'استعادة فاتورة%';

  insert into public.trader_movements (store_id, trader_id, invoice_id, movement_type, weight_grams, karat, gold_24k_equivalent, fab_fee_amount, notes)
  select store_id, trader_id, invoice_id, movement_type, weight_grams, karat, gold_24k_equivalent, fab_fee_amount, 'استعادة فاتورة ' || inv.invoice_number
  from public.trader_movements where invoice_id = target_invoice_id
    and coalesce(notes, '') not like 'إلغاء فاتورة%' and coalesce(notes, '') not like 'استعادة فاتورة%';
end;
$function$;
