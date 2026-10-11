-- Deposits (عربون) are customer credit: a sale's remaining debt uses it up automatically
-- (gm_allocate_customer_credit). What is left of each active deposit is derived, never stored,
-- so cancelling or editing an invoice puts it back by itself: the customer's credit
-- (−balance) is spread over their active deposits, newest first.
create or replace function public.customer_deposit_remaining(sid uuid)
returns table(deposit_id uuid, remaining numeric)
language sql stable security invoker set search_path = public as $$
  with cred as (
    select customer_id, greatest(0, -sum(case when movement_type = 'debt_increase' then cash_amount else -cash_amount end)) c
    from customer_debts where store_id = sid group by customer_id),
  d as (
    select dp.id, dp.amount, coalesce(cr.c, 0) c,
           sum(dp.amount) over (partition by dp.customer_id order by dp.created_at desc, dp.id) run
    from customer_deposits dp left join cred cr on cr.customer_id = dp.customer_id
    where dp.store_id = sid and dp.status = 'active')
  select id, round(least(amount, greatest(0, c - (run - amount))), 2) from d;
$$;

-- money the shop holds for a customer (deposits, overpayments) not yet used on an invoice
create or replace function public.customer_credit(sid uuid, cust uuid)
returns numeric language sql stable security invoker set search_path = public as $$
  select round(greatest(0, -coalesce(sum(case when movement_type = 'debt_increase' then cash_amount else -cash_amount end), 0)), 2)
  from customer_debts where store_id = sid and customer_id = cust;
$$;
grant execute on function public.customer_deposit_remaining(uuid) to authenticated;
grant execute on function public.customer_credit(uuid, uuid) to authenticated;
revoke execute on function public.customer_deposit_remaining(uuid) from anon;
revoke execute on function public.customer_credit(uuid, uuid) from anon;

-- a deposit already used on an invoice cannot be handed back as cash in full
create or replace function public.refund_customer_deposit(p_deposit uuid)
 returns void language plpgsql security definer set search_path to 'public' as $function$
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
  insert into cash_movements (store_id, box, direction, amount, description, created_by)
    values (d.store_id, case when d.method = 'bank' then 'bank' else 'main' end, 'out', d.amount, 'استرجاع عربون ' || d.deposit_number || ' إلى ' || d.cname, me)
    returning id into cm;
  if d.method = 'cash' then
    insert into daily_cash_log (store_id, operation_type, direction, amount, notes, created_by, cash_movement_id)
      values (d.store_id, 'استرجاع عربون', 'out', d.amount, d.deposit_number || ' — ' || d.cname, me, cm);
  end if;
  insert into customer_debts (store_id, customer_id, movement_type, cash_amount, gold_grams_24k, notes, source, created_by)
    values (d.store_id, d.customer_id, 'debt_increase', d.amount, 0, 'استرجاع عربون ' || d.deposit_number, 'deposit_refund', me);
end $function$;
