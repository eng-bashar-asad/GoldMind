-- Edit a customer deposit (عربون) in place: amount, pieces, notes.
-- No refund + new deposit pair any more: the deposit's own cash movement, its daily-log line
-- (synced by trg_cash_movement_updated_daily_sync) and its customer-credit line are changed.
-- A deposit already used on an invoice keeps its amount (pieces and notes can still change).
create or replace function public.update_customer_deposit(p_deposit uuid, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare d record; amt numeric; left_amt numeric; new_items jsonb := coalesce(p->'items', '[]'::jsonb);
begin
  select * into d from customer_deposits where id = p_deposit for update;
  if d is null then raise exception 'العربون غير موجود'; end if;
  if not (has_permission('edit_customers', d.store_id) or has_permission('manage_daily_cashbox', d.store_id)) then
    raise exception 'ليس لديك صلاحية' using errcode = '42501';
  end if;
  if d.status <> 'active' then raise exception 'هذا العربون مُسترجَع، لا يمكن تعديله'; end if;
  if jsonb_typeof(new_items) <> 'array' or jsonb_array_length(new_items) = 0 then
    raise exception 'اكتب وصف القطعة المحجوزة على الأقل';
  end if;
  amt := round(coalesce(nullif(p->>'amount', '')::numeric, d.amount), 2);
  if amt <= 0 then raise exception 'المبلغ يجب أن يكون أكبر من صفر'; end if;

  if amt <> d.amount then
    select remaining into left_amt from customer_deposit_remaining(d.store_id) where deposit_id = d.id;
    if coalesce(left_amt, 0) < d.amount - 0.009 then
      raise exception 'هذا العربون استُخدم في فاتورة، فلا يمكن تغيير مبلغه. يمكنك تعديل القطع والملاحظات فقط.';
    end if;
    if d.in_cashbox then
      update cash_movements set amount = amt
       where store_id = d.store_id and direction = 'in' and invoice_id is null
         and description like 'عربون ' || d.deposit_number || ' %';
    end if;
    update customer_debts set cash_amount = amt
     where store_id = d.store_id and customer_id = d.customer_id and source = 'deposit'
       and notes = 'عربون ' || d.deposit_number;
  end if;

  -- pieces dropped from the deposit go back on sale, newly added ones get reserved
  update pieces set status = 'available', reserved_customer_id = null
   where store_id = d.store_id and status = 'reserved' and reserved_customer_id = d.customer_id
     and barcode in (select nullif(trim(x->>'barcode'), '') from jsonb_array_elements(coalesce(d.items, '[]'::jsonb)) x)
     and barcode not in (select coalesce(nullif(trim(x->>'barcode'), ''), '') from jsonb_array_elements(new_items) x);
  update pieces set status = 'reserved', reserved_customer_id = d.customer_id
   where store_id = d.store_id and status = 'available'
     and barcode in (select nullif(trim(x->>'barcode'), '') from jsonb_array_elements(new_items) x);

  update customer_deposits set amount = amt, items = new_items, notes = nullif(trim(p->>'notes'), '') where id = d.id;
end $$;
revoke execute on function public.update_customer_deposit(uuid, jsonb) from public, anon;
grant execute on function public.update_customer_deposit(uuid, jsonb) to authenticated;

-- One-off cleanup (14/11/2026): DEP-000010 was taken and refunded only to re-enter it as DEP-000011.
-- The pair nets to zero, so drop it from the daily log, cash box, customer account and deposit list.
-- (Matches nothing on any other database.)
delete from customer_debts where id in ('46c352c6-27c3-48d6-95cc-66b7de7fcd19', '928265a0-d8fa-4a7d-9548-d8190391dacc');
delete from daily_cash_log where id in ('3fadf9d0-60e4-4a32-a2bc-68cae6337746', '88148c13-26c2-4844-a5a8-941e8f24136f');
delete from cash_movements where id in ('1e27d694-0653-4104-8014-da9d8309886f', '80361473-a022-49e5-ae57-58bb1e8f13e0');
delete from customer_deposits where id = '1a18bd30-8dd4-4108-8798-ccaa1d200b5e' and status = 'refunded';
