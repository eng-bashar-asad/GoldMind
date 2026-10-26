-- A sale left (fully or partly) on debt now shows in the daily cash box: the debt part goes in
-- «الداخل» as sold ("مبيعات لـ …", note "بالدين") and the same amount in «الصادر» as
-- «دين على …», the two rows linked. The drawer total does not change. Only debt created by the
-- sale itself (not edits / payments); the part paid from an earlier deposit is left to the
-- deposit rows (gm_deposit_sale_to_daily).
create or replace function public.gm_sale_debt_to_daily(p_invoice uuid, p_amount numeric)
returns void language plpgsql security definer set search_path = public as $$
declare inv record; used numeric; debt numeric; cur text; amt numeric; me uuid; g text;
begin
  select i.id, i.store_id, i.invoice_number, i.type, i.pay_currency, i.pay_fx_rate, coalesce(c.name, '') cname into inv
    from invoices i left join customers c on c.id = i.customer_id where i.id = p_invoice;
  if inv.id is null or inv.type <> 'sale' then return; end if;
  select coalesce(sum(cash_amount), 0) into used from customer_debts
   where invoice_id = p_invoice and source = 'allocation' and movement_type = 'debt_decrease' and entered_at = now();
  debt := round(p_amount - used, 2);
  if debt <= 0.009 then return; end if;
  if inv.pay_currency is not null and inv.pay_fx_rate > 0 then
    amt := round(debt * inv.pay_fx_rate, 2); cur := upper(inv.pay_currency);
  else
    amt := debt; select coalesce(nullif(upper(currency), ''), 'AED') into cur from stores where id = inv.store_id;
  end if;
  select id into me from staff where user_id = auth.uid() and store_id = inv.store_id limit 1;
  g := 'debt_' || substr(replace(p_invoice::text, '-', ''), 1, 12);
  insert into daily_cash_log (store_id, operation_type, direction, amount, currency, notes, created_by, link_group)
  values (inv.store_id, 'مبيعات لـ ' || inv.cname, 'in', amt, cur, inv.invoice_number || ' — بالدين', me, g),
         (inv.store_id, 'دين على ' || inv.cname, 'out', amt, cur, inv.invoice_number, me, g);
end $$;
revoke execute on function public.gm_sale_debt_to_daily(uuid, numeric) from public, anon, authenticated;

create or replace function public.trg_customer_debts_allocate()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform gm_allocate_customer_credit(new.store_id, new.customer_id);
  if new.movement_type = 'debt_increase' and new.invoice_id is not null then
    perform gm_deposit_sale_to_daily(new.invoice_id, new.customer_id);
    if new.source is null then perform gm_sale_debt_to_daily(new.invoice_id, new.cash_amount); end if;
  end if;
  return null;
end $$;
