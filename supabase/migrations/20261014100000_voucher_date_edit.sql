-- Change the date of one cash voucher (سند قبض / صرف) for a customer, a trader or an expense.
-- Moves the cash box row, its daily cash log row and the row it created (customer payment,
-- trader movement or expense) to the new day. Keeps the time of day. Amounts never change.
-- Past dates only (up to 10 years back, same rule as the back-dated forms). Invoices are excluded.
create or replace function public.set_voucher_date(p_cash_movement uuid, p_date date)
returns void language plpgsql security definer set search_path = public as $$
declare
  cm record;
  today date := (now() at time zone 'Asia/Dubai')::date;
  new_ts timestamptz;
begin
  select * into cm from cash_movements where id = p_cash_movement;
  if cm is null then raise exception 'السند غير موجود'; end if;
  if cm.invoice_id is not null then raise exception 'هذه الحركة من فاتورة — عدّل تاريخ الفاتورة من صفحتها'; end if;
  if p_date is null or p_date > today or p_date < today - 3650 then raise exception 'اختر تاريخاً سابقاً أو اليوم'; end if;
  if not is_store_member(cm.store_id) then raise exception 'ليس لديك صلاحية' using errcode = '42501'; end if;
  if cm.trader_movement_id is not null and not has_permission('edit_traders', cm.store_id) then
    raise exception 'ليس لديك صلاحية تعديل حسابات التجار' using errcode = '42501';
  end if;
  if exists (select 1 from customer_debts where cash_movement_id = cm.id) and not has_permission('edit_customers', cm.store_id) then
    raise exception 'ليس لديك صلاحية تعديل حسابات الزبائن' using errcode = '42501';
  end if;
  if exists (select 1 from expense_entries where cash_movement_id = cm.id) and not gm_can_expense(cm.store_id) then
    raise exception 'ليس لديك صلاحية تعديل المصاريف' using errcode = '42501';
  end if;

  new_ts := (p_date + (cm.created_at at time zone 'Asia/Dubai')::time) at time zone 'Asia/Dubai';
  update cash_movements set created_at = new_ts where id = cm.id;
  update daily_cash_log set created_at = new_ts where cash_movement_id = cm.id;
  update customer_debts set created_at = new_ts where cash_movement_id = cm.id;
  update expense_entries set created_at = new_ts where cash_movement_id = cm.id;
  if cm.trader_movement_id is not null then
    update trader_movements set created_at = new_ts where id = cm.trader_movement_id;
  end if;
end $$;
revoke all on function public.set_voucher_date(uuid, date) from public, anon;
grant execute on function public.set_voucher_date(uuid, date) to authenticated;
