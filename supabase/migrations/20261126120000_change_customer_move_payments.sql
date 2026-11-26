-- Changing a sale invoice's customer: the screen now asks whether the payments taken later from the
-- old customer's account for this invoice belong to the new customer too (a name correction).
--   p_move_payments = false (as before): those payments go back to the old customer as credit and
--                                        the unpaid amount moves to the new customer.
--   p_move_payments = true:  the invoice keeps them (stays paid as it is); only what is still unpaid
--                            moves to the new customer. Both balances stay as they were.
-- New 3-argument function; the 2-argument one stays (no drop) and calls it with false.

create or replace function public.sale_invoice_change_customer(p_invoice uuid, p_customer uuid, p_move_payments boolean)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare inv record; newc record; oldname text; rem numeric; me uuid; alloc numeric;
begin
  select * into inv from invoices where id = p_invoice for update;
  if inv is null then raise exception 'الفاتورة غير موجودة'; end if;
  if not has_permission('edit_invoice', inv.store_id) then raise exception 'ليس لديك صلاحية تعديل الفواتير' using errcode = '42501'; end if;
  if inv.type <> 'sale' or inv.status = 'cancelled' then raise exception 'يمكن تغيير الزبون لفواتير البيع غير الملغاة فقط'; end if;
  select id, name into newc from customers where id = p_customer and store_id in (select org_store_ids(inv.store_id));
  if newc is null then raise exception 'الزبون غير موجود'; end if;
  if inv.customer_id = newc.id then return; end if;
  select name into oldname from customers where id = inv.customer_id;
  select id into me from staff where user_id = auth.uid() and store_id = inv.store_id limit 1;
  -- unless they move with the invoice, the old customer's later payments applied to it go back to him as credit
  if inv.customer_id is not null and not coalesce(p_move_payments, false) then
    select coalesce(sum(case when movement_type = 'debt_decrease' then cash_amount else -cash_amount end), 0) into alloc
      from customer_debts where invoice_id = inv.id and customer_id = inv.customer_id and source = 'allocation';
    if alloc > 0.009 then
      insert into customer_debts (store_id, customer_id, invoice_id, movement_type, cash_amount, gold_grams_24k, notes, source, created_by) values
        (inv.store_id, inv.customer_id, inv.id, 'debt_increase', alloc, 0, 'إلغاء تخصيص للفاتورة ' || inv.invoice_number || ' (نُقلت إلى ' || newc.name || ')', 'allocation', me),
        (inv.store_id, inv.customer_id, null, 'debt_decrease', alloc, 0, 'إلغاء تخصيص للفاتورة ' || inv.invoice_number || ' (نُقلت إلى ' || newc.name || ')', 'allocation', me);
      update invoices set amount_paid = greatest(coalesce(amount_paid, 0) - alloc, 0), status = case when status = 'paid' then 'unpaid' else status end
       where id = inv.id returning * into inv;
    end if;
  end if;
  rem := round(inv.total_amount - coalesce(inv.amount_paid, 0), 2);
  update invoices set customer_id = newc.id where id = inv.id;
  if rem > 0.009 and inv.customer_id is not null then
    insert into customer_debts (store_id, customer_id, invoice_id, movement_type, cash_amount, gold_grams_24k, notes, source, created_by)
    values (inv.store_id, inv.customer_id, inv.id, 'debt_decrease', rem, 0, 'نقل دين الفاتورة ' || inv.invoice_number || ' إلى ' || newc.name, 'invoice_edit', me);
  end if;
  if rem > 0.009 then
    insert into customer_debts (store_id, customer_id, invoice_id, movement_type, cash_amount, gold_grams_24k, notes, source, created_by)
    values (inv.store_id, newc.id, inv.id, 'debt_increase', rem, 0, 'دين الفاتورة ' || inv.invoice_number || ' منقول من ' || coalesce(oldname, 'زبون سابق'), 'invoice_edit', me);
  end if;
  if inv.customer_id is not null then perform gm_allocate_customer_credit(inv.store_id, inv.customer_id); end if;
  perform gm_allocate_customer_credit(inv.store_id, newc.id);
end $function$;

create or replace function public.sale_invoice_change_customer(p_invoice uuid, p_customer uuid)
 returns void
 language sql
 security definer
 set search_path to 'public'
as $$ select public.sale_invoice_change_customer(p_invoice, p_customer, false) $$;

revoke execute on function public.sale_invoice_change_customer(uuid, uuid, boolean) from public, anon;
grant execute on function public.sale_invoice_change_customer(uuid, uuid, boolean) to authenticated;
