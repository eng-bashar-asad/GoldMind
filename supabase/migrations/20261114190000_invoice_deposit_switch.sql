-- Edit a sale invoice: was it paid partly from the customer's earlier deposit (عربون), or in full in cash?
-- invoice_set_deposit(inv, false): the deposit part becomes cash paid on the invoice; the deposit is the
--   customer's again (its «عربون سابق» row leaves the daily box, the invoice's cash row keeps the full amount).
-- invoice_set_deposit(inv, true): the customer's credit pays part of the invoice's cash, through the same
--   path as a new sale (debt → gm_allocate_customer_credit → gm_deposit_sale_to_daily).
-- ponytail: single-currency invoices only (no pay_breakdown / pay_currency); upgrade = per-currency rows.
create or replace function public.invoice_set_deposit(p_invoice uuid, p_use boolean) returns numeric
language plpgsql security definer set search_path = public as $$
declare inv record; g text; dep numeric; cm record; me uuid; x numeric; cur text; left_amt numeric; r record; t numeric; row_id uuid;
begin
  select i.*, coalesce(c.name, '') cname into inv from invoices i left join customers c on c.id = i.customer_id
   where i.id = p_invoice for update of i;
  if inv.id is null or inv.type <> 'sale' then raise exception 'الفاتورة غير موجودة'; end if;
  if not has_permission('edit_invoice', inv.store_id) then raise exception 'ليس لديك صلاحية تعديل الفواتير' using errcode = '42501'; end if;
  if inv.status = 'cancelled' then raise exception 'الفاتورة ملغاة'; end if;
  if inv.customer_id is null then raise exception 'الفاتورة بلا زبون'; end if;
  if inv.pay_breakdown is not null or inv.pay_currency is not null then
    raise exception 'هذه الفاتورة مدفوعة بعدة عملات؛ عدّل الدفع من خانات الدفع.';
  end if;
  select id into me from staff where user_id = auth.uid() and store_id = inv.store_id limit 1;
  select coalesce(nullif(upper(currency), ''), 'AED') into cur from stores where id = inv.store_id;
  g := 'dep_' || substr(replace(p_invoice::text, '-', ''), 1, 12);
  select coalesce(sum(amount), 0) into dep from daily_cash_log where link_group = g and operation_type = 'عربون سابق' and direction = 'out';
  select * into cm from cash_movements where invoice_id = p_invoice and direction = 'in' and not coalesce(edit_delta, false)
   order by created_at limit 1;

  if not p_use then
    if dep <= 0.009 then raise exception 'هذه الفاتورة لم يُخصم منها عربون'; end if;
    delete from daily_cash_log where link_group = g and operation_type = 'عربون سابق';
    if cm.id is not null then
      update cash_movements set amount = round(amount + dep, 2),
             description = 'تحصيل فاتورة بيع ' || inv.invoice_number || ' (' || to_char(amount + dep, 'FM999,999,990.00') || ' نقداً)'
       where id = cm.id;
      update daily_cash_log set link_group = null, notes = 'تحصيل ' || inv.invoice_number || ' (' || to_char(cm.amount + dep, 'FM999,999,990.00') || ' نقداً)'
       where cash_movement_id = cm.id;
    else
      -- paid only from the deposit: the drawer gets a real cash movement; its mirrored row replaces the deposit row
      delete from daily_cash_log where link_group = g;
      insert into cash_movements (store_id, box, direction, amount, description, created_by, invoice_id)
        values (inv.store_id, 'main', 'in', dep, 'تحصيل فاتورة بيع ' || inv.invoice_number || ' (' || to_char(dep, 'FM999,999,990.00') || ' نقداً)', me, p_invoice);
    end if;
    -- the deposit no longer pays the invoice: take back the sale's leftover debt and its allocation, up to dep
    t := dep;
    for r in select d.id, d.cash_amount, d.entered_at from customer_debts d
              where d.invoice_id = p_invoice and d.movement_type = 'debt_increase' and d.source is null
              order by d.entered_at desc loop
      exit when t <= 0.009;
      x := least(t, r.cash_amount);
      if r.cash_amount - x <= 0.009 then delete from customer_debts where id = r.id;
      else update customer_debts set cash_amount = round(cash_amount - x, 2) where id = r.id; end if;
      t := t - x;
    end loop;
    t := dep;
    for r in select d.id, d.cash_amount from customer_debts d
              where d.invoice_id = p_invoice and d.source = 'allocation' and d.movement_type = 'debt_decrease'
              order by d.entered_at desc loop
      exit when t <= 0.009;
      x := least(t, r.cash_amount);
      if r.cash_amount - x <= 0.009 then delete from customer_debts where id = r.id;
      else update customer_debts set cash_amount = round(cash_amount - x, 2) where id = r.id; end if;
      t := t - x;
    end loop;
    t := dep;
    for r in select d.id, d.cash_amount from customer_debts d
              where d.customer_id = inv.customer_id and d.invoice_id is null and d.source = 'allocation' and d.movement_type = 'debt_increase'
                and d.notes = 'تخصيص دفعة للفاتورة ' || inv.invoice_number
              order by d.entered_at desc loop
      exit when t <= 0.009;
      x := least(t, r.cash_amount);
      if r.cash_amount - x <= 0.009 then delete from customer_debts where id = r.id;
      else update customer_debts set cash_amount = round(cash_amount - x, 2) where id = r.id; end if;
      t := t - x;
    end loop;
    if inv.payment_method = 'mixed' then
      update invoices set cash_paid_amount = round(coalesce(cash_paid_amount, 0) + dep, 2) where id = p_invoice;
    end if;
    return dep;
  end if;

  -- use the deposit
  if dep > 0.009 then raise exception 'هذه الفاتورة مخصوم منها عربون مسبقاً'; end if;
  if cm.id is null then raise exception 'لا يوجد مبلغ نقدي على هذه الفاتورة ليُخصم من العربون'; end if;
  x := round(least(customer_credit(inv.store_id, inv.customer_id), cm.amount), 2);
  if x <= 0.009 then raise exception 'لا يوجد عربون أو رصيد للزبون'; end if;
  if cm.amount - x <= 0.009 then
    delete from cash_movements where id = cm.id; -- its daily row goes with it
  else
    update cash_movements set amount = round(amount - x, 2),
           description = 'تحصيل جزئي لفاتورة بيع ' || inv.invoice_number || ' (' || to_char(amount - x, 'FM999,999,990.00') || ' نقداً)'
     where id = cm.id;
    update daily_cash_log set amount = round(amount - x, 2),
           notes = 'تحصيل جزئي ' || inv.invoice_number || ' (' || to_char(cm.amount - x, 'FM999,999,990.00') || ' نقداً)'
     where cash_movement_id = cm.id;
  end if;
  update invoices set amount_paid = round(coalesce(amount_paid, 0) - x, 2), status = 'unpaid',
         cash_paid_amount = case when payment_method = 'mixed' then round(coalesce(cash_paid_amount, 0) - x, 2) else cash_paid_amount end
   where id = p_invoice;
  -- same as a sale left partly unpaid: the trigger pays it from the credit and writes the «عربون سابق» rows
  insert into customer_debts (store_id, customer_id, invoice_id, movement_type, cash_amount, gold_grams_24k, notes, created_by)
    values (inv.store_id, inv.customer_id, p_invoice, 'debt_increase', x, 0,
            'متبقي فاتورة بيع ' || inv.invoice_number || ' (من العربون)', me);
  return x;
end $$;
revoke execute on function public.invoice_set_deposit(uuid, boolean) from public, anon;
grant execute on function public.invoice_set_deposit(uuid, boolean) to authenticated;
