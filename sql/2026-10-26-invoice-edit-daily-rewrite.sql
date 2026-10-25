-- Run once in the Supabase SQL editor (Bashar).
-- Editing a sale invoice's payment currencies no longer adds "out old / in new" rows to the
-- daily box: the invoice's own rows are rewritten in place (same day), one row per currency.
-- At the end it also tidies the invoices already edited this way (e.g. INV-2026-000066):
-- their extra out/in rows in the daily box are removed and the invoice's rows are rebuilt.
-- Only daily-box rows that belong to those invoices are touched; the main box is not changed.

-- 1) the mirror no longer writes rows for currency-change movements (the rewrite below does)
create or replace function public.mirror_invoice_cash_to_daily()
 returns trigger language plpgsql security definer set search_path to 'public' as $function$
declare inv record; r record; first boolean := true; full_base numeric; amt numeric; cur text; note text; op text;
begin
  if new.invoice_id is null then return new; end if;
  -- a change of payment currencies: gm_invoice_daily_rewrite() sets the invoice's rows
  if coalesce(new.description, '') like 'تعديل عملات الدفع%' then return new; end if;
  select id, type, payment_method, pay_breakdown, pay_currency, pay_fx_rate into inv from public.invoices where id = new.invoice_id;
  if inv is null then return new; end if;
  if inv.payment_method not in ('cash', 'bank', 'mixed') or new.amount <= 0 then return new; end if;
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

-- 2) rewrite a sale invoice's own rows in the daily box from what it was paid now
create or replace function public.gm_invoice_daily_rewrite(p_invoice uuid)
returns void language plpgsql security definer set search_path = public as $$
declare inv record; keep record; r record; first boolean := true; net numeric; dep numeric; cur text; first_cm uuid;
begin
  select i.id, i.store_id, i.invoice_number, i.type, i.status, i.pay_breakdown, i.pay_currency, i.pay_fx_rate, coalesce(c.name, '') cname
    into inv from invoices i left join customers c on c.id = i.customer_id where i.id = p_invoice;
  if inv.id is null or inv.type <> 'sale' or inv.status = 'cancelled' then return; end if;
  if auth.uid() is not null and not has_permission('edit_invoice', inv.store_id) then
    raise exception 'ليس لديك صلاحية تعديل الفواتير' using errcode = '42501';
  end if;
  select id into first_cm from cash_movements where invoice_id = p_invoice and direction = 'in' order by created_at limit 1;
  -- the invoice's first row (its sale day) stays and is rewritten; its other rows go
  select l.id, l.created_at, l.created_by into keep from daily_cash_log l
   where l.direction = 'in' and (l.cash_movement_id in (select id from cash_movements where invoice_id = p_invoice) or l.bank_invoice_id = p_invoice)
   order by l.created_at, l.id limit 1;
  delete from daily_cash_log l
   where (l.cash_movement_id in (select id from cash_movements where invoice_id = p_invoice) or l.bank_invoice_id = p_invoice)
     and l.id is distinct from keep.id;
  if inv.pay_breakdown is not null then
    -- several currencies: one row per currency, cash parts only
    for r in select upper(b->>'currency') c, round(sum((b->>'amount')::numeric), 2) a from jsonb_array_elements(inv.pay_breakdown) b
              where b->>'method' = 'cash' and (b->>'amount')::numeric > 0 group by 1 order by 1 loop
      if first and keep.id is not null then
        update daily_cash_log set amount = r.a, currency = r.c, cash_movement_id = first_cm, bank_invoice_id = null where id = keep.id;
      else
        insert into daily_cash_log (store_id, operation_type, direction, amount, currency, notes, created_by, created_at, cash_movement_id, bank_invoice_id)
        values (inv.store_id, 'مبيعات لـ ' || inv.cname, 'in', r.a, r.c, inv.invoice_number, keep.created_by, coalesce(keep.created_at, now()),
                case when first then first_cm end, case when first then null else p_invoice end);
      end if;
      first := false;
    end loop;
    if first and keep.id is not null then delete from daily_cash_log where id = keep.id; end if;
    return;
  end if;
  -- one currency: what the invoice brought into the main box (+ an earlier deposit used on it);
  -- the card/transfer part is then taken out by sync_invoice_bank_part as on a new sale
  select coalesce(sum(case when direction = 'in' then amount else -amount end), 0) into net from cash_movements where invoice_id = p_invoice;
  select coalesce(sum(amount), 0) into dep from daily_cash_log
   where operation_type = 'عربون سابق' and link_group = 'dep_' || substr(replace(p_invoice::text, '-', ''), 1, 12);
  net := round(net + dep, 2);
  if inv.pay_currency is not null and inv.pay_fx_rate > 0 then net := round(net * inv.pay_fx_rate, 2); cur := upper(inv.pay_currency);
  else select coalesce(nullif(upper(currency), ''), 'AED') into cur from stores where id = inv.store_id; end if;
  if net <= 0.009 then
    if keep.id is not null then delete from daily_cash_log where id = keep.id; end if;
    return;
  end if;
  if keep.id is not null then
    update daily_cash_log set amount = net, currency = cur, cash_movement_id = first_cm, bank_invoice_id = null where id = keep.id;
  else
    insert into daily_cash_log (store_id, operation_type, direction, amount, currency, notes, created_by, cash_movement_id)
    values (inv.store_id, 'مبيعات لـ ' || inv.cname, 'in', net, cur, inv.invoice_number, null, first_cm);
  end if;
  perform sync_invoice_bank_part(p_invoice);
end $$;
revoke execute on function public.gm_invoice_daily_rewrite(uuid) from public, anon;
grant execute on function public.gm_invoice_daily_rewrite(uuid) to authenticated;

-- 3) tidy the invoices already edited the old way
select inv.invoice_number, public.gm_invoice_daily_rewrite(inv.id)
  from invoices inv
 where inv.id in (select invoice_id from cash_movements where description like 'تعديل عملات الدفع%');
