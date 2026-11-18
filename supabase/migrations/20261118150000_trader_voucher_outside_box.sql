-- Cash voucher: «خارج الصندوق» also for traders (only the trader's account changes).
create or replace function public.cash_voucher(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare sid uuid := (p->>'store_id')::uuid; kind text := p->>'kind'; party text := p->>'party';
  pid uuid := nullif(p->>'party_id', '')::uuid; amt numeric := round(coalesce(nullif(p->>'amount', '')::numeric, 0), 2);
  cur text := upper(coalesce(nullif(p->>'currency', ''), '')); rate numeric := nullif(p->>'fx_rate', '')::numeric;
  method text := coalesce(nullif(p->>'method', ''), 'cash'); daily boolean := coalesce((p->>'daily')::boolean, true);
  descr text := nullif(trim(p->>'notes'), ''); base_cur text; base_amt numeric; fx boolean; me uuid; cm uuid; c record; t record; cat record;
  fxnote text := ''; note text; mid uuid; eid uuid;
begin
  if kind not in ('in', 'out') then raise exception 'نوع السند غير معروف'; end if;
  if method not in ('cash', 'bank', 'card', 'none') or (method = 'none' and party = 'expense') then raise exception 'طريقة دفع غير معروفة'; end if;
  if amt <= 0 then raise exception 'المبلغ يجب أن يكون أكبر من صفر'; end if;
  if not is_store_member(sid) then raise exception 'ليس لديك صلاحية' using errcode = '42501'; end if;
  select coalesce(nullif(upper(currency), ''), 'AED') into base_cur from stores where id = sid;
  if cur = '' then cur := base_cur; end if;
  fx := cur <> base_cur;
  if fx then
    if rate is null or rate <= 0 then raise exception 'أدخل سعر صرف % مقابل %', cur, base_cur; end if;
    base_amt := round(amt / rate, 2);
    fxnote := ' (' || trim(to_char(amt, 'FM999,999,999,990.00')) || ' ' || cur || ' بسعر ' || trim(to_char(rate, 'FM999,999,990.####')) || ')';
  else
    base_amt := amt;
  end if;
  select id into me from staff where user_id = auth.uid() and store_id = sid limit 1;

  if party = 'customer' then
    select id, store_id, name into c from customers where id = pid and store_id in (select org_store_ids(sid));
    if c is null then raise exception 'اختر الزبون'; end if;
    if not (has_permission('edit_customers', sid) or has_permission('manage_daily_cashbox', sid)) then raise exception 'ليس لديك صلاحية سندات الزبائن' using errcode = '42501'; end if;
    note := coalesce(descr, case when kind = 'in' then 'دفعة من العميل' else 'صرف للعميل' end) || fxnote;
    if method <> 'none' then
      insert into cash_movements (store_id, box, direction, amount, description, created_by, fx_amount, fx_currency)
        values (sid, case when method in ('bank', 'card') then 'bank' else 'main' end, kind, base_amt,
                case when kind = 'in' then 'دفعة من العميل ' else 'صرف للعميل ' end || c.name
                  || case method when 'bank' then ' (تحويل/بطاقة)' when 'card' then ' (فيزا)' else '' end,
                me, case when fx then amt end, case when fx then cur end) returning id into cm;
      if daily then
        perform gm_cash_daily_rows(sid, kind, method, amt, cur, case when kind = 'in' then 'دفعة من عميل' else 'صرف لعميل' end, c.name || ' — ' || note, me, cm);
      end if;
    else
      note := note || ' (لا يدخل الصندوق اليومي)';
    end if;
    insert into customer_debts (store_id, customer_id, movement_type, cash_amount, gold_grams_24k, notes, source, created_by, cash_movement_id)
      values (sid, c.id, case when kind = 'in' then 'debt_decrease' else 'debt_increase' end, base_amt, 0, note,
              case when kind = 'in' then 'payment' else 'cash_out' end, me, cm);

  elsif party = 'trader' then
    select id, store_id, name into t from traders where id = pid and store_id in (select org_store_ids(sid));
    if t is null then raise exception 'اختر التاجر'; end if;
    if not has_permission('edit_traders', sid) then raise exception 'ليس لديك صلاحية تعديل حسابات التجار' using errcode = '42501'; end if;
    note := coalesce(descr, case when kind = 'out' then 'صرف كاش للتاجر' else 'قبض كاش من التاجر' end) || fxnote
            || case when method = 'none' then ' (لا يدخل الصندوق اليومي)' else '' end;
    insert into trader_movements (store_id, trader_id, movement_type, weight_grams, karat, gold_24k_equivalent, fab_fee_amount, source, notes, created_by)
      values (sid, t.id, case when kind = 'out' then 'debt_decrease' else 'debt_increase' end, 0, null, 0, base_amt,
              case when kind = 'out' then 'cash_out' else 'cash_in' end, note, me) returning id into mid;
    -- none (بشار 2026-11-18): settled outside the daily box/bank — only the trader's account changes
    if method <> 'none' then
      insert into cash_movements (store_id, box, direction, amount, description, created_by, trader_movement_id, fx_amount, fx_currency)
        values (sid, case when method in ('bank', 'card') then 'bank' else 'main' end, kind, base_amt,
                case when kind = 'out' then 'صرف كاش للتاجر ' else 'قبض كاش من التاجر ' end || t.name, me, mid,
                case when fx then amt end, case when fx then cur end) returning id into cm;
      if daily then
        perform gm_cash_daily_rows(sid, kind, method, amt, cur, case when kind = 'out' then 'صرف كاش لتاجر' else 'قبض كاش من تاجر' end, t.name || ' — ' || note, me, cm);
      end if;
    end if;

  elsif party = 'expense' then
    if kind <> 'out' then raise exception 'المصروف يكون سند صرف فقط'; end if;
    if not gm_can_expense(sid) then raise exception 'ليس لديك صلاحية تسجيل المصاريف' using errcode = '42501'; end if;
    select id, name into cat from expense_categories where id = nullif(p->>'category_id', '')::uuid and store_id = sid;
    if cat is null then raise exception 'اختر نوع المصروف'; end if;
    insert into expense_entries (store_id, category_id, amount, description, created_by)
      values (sid, cat.id, base_amt, coalesce(descr, cat.name) || fxnote, me) returning id into eid;
    insert into cash_movements (store_id, box, direction, amount, description, created_by, fx_amount, fx_currency)
      values (sid, case when method in ('bank', 'card') then 'bank' else 'main' end, 'out', base_amt, 'مصروف ' || cat.name || coalesce(': ' || descr, '') || fxnote,
              me, case when fx then amt end, case when fx then cur end) returning id into cm;
    update expense_entries set cash_movement_id = cm where id = eid;
    if daily then
      perform gm_cash_daily_rows(sid, 'out', method, amt, cur, 'مصروف: ' || cat.name, coalesce(descr, '') || fxnote, me, cm);
    end if;
  else
    raise exception 'اختر الطرف: زبون أو تاجر أو مصروف';
  end if;
  return jsonb_build_object('ok', true, 'cash_movement_id', cm, 'base_amount', base_amt, 'base_currency', base_cur);
end $$;
