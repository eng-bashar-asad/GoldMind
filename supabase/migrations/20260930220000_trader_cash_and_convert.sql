-- Trader account: pay out cash / receive cash (also in the daily cashbox), and
-- "تسكير عملات": turn a gold balance into a cash balance at an agreed price.
-- Sign convention as everywhere: debt_decrease moves the balance toward
-- "trader owes the shop", debt_increase toward "the shop owes the trader".

create or replace function public.trader_cash_move(p_trader uuid, p_direction text, p_amount numeric, p_notes text default null, p_daily boolean default true)
returns uuid language plpgsql security definer set search_path = public as $$
declare t record; me uuid; amt numeric := round(coalesce(p_amount, 0), 2); mid uuid; cm uuid; note text;
begin
  select id, store_id, name into t from traders where id = p_trader;
  if t is null then raise exception 'التاجر غير موجود'; end if;
  if not has_permission('edit_traders', t.store_id) then raise exception 'ليس لديك صلاحية تعديل حسابات التجار' using errcode = '42501'; end if;
  if p_direction not in ('out', 'in') then raise exception 'اتجاه غير معروف'; end if;
  if amt <= 0 then raise exception 'المبلغ يجب أن يكون أكبر من صفر'; end if;
  select id into me from staff where user_id = auth.uid() and store_id = t.store_id limit 1;
  note := coalesce(nullif(trim(p_notes), ''), case when p_direction = 'out' then 'صرف كاش للتاجر' else 'قبض كاش من التاجر' end);

  insert into trader_movements (store_id, trader_id, movement_type, weight_grams, karat, gold_24k_equivalent, fab_fee_amount, source, notes, created_by)
    values (t.store_id, t.id, case when p_direction = 'out' then 'debt_decrease' else 'debt_increase' end, 0, null, 0, amt,
            case when p_direction = 'out' then 'cash_out' else 'cash_in' end, note, me)
    returning id into mid;
  insert into cash_movements (store_id, box, direction, amount, description, created_by, trader_movement_id)
    values (t.store_id, 'main', p_direction, amt,
            case when p_direction = 'out' then 'صرف كاش للتاجر ' else 'قبض كاش من التاجر ' end || t.name, me, mid)
    returning id into cm;
  if coalesce(p_daily, true) then
    insert into daily_cash_log (store_id, operation_type, direction, amount, notes, created_by, cash_movement_id)
      values (t.store_id, case when p_direction = 'out' then 'صرف كاش لتاجر' else 'قبض كاش من تاجر' end, p_direction, amt, t.name || ' — ' || note, me, cm);
  end if;
  return mid;
end $$;
grant execute on function public.trader_cash_move(uuid, text, numeric, text, boolean) to authenticated;

-- p_direction 'we_owe_gold': the shop owed the trader gold → that gold is settled
--   and the shop now owes its value in cash. 'they_owe_gold': the reverse.
create or replace function public.trader_gold_to_cash(p_trader uuid, p_weight numeric, p_karat int, p_price numeric, p_direction text, p_notes text default null)
returns numeric language plpgsql security definer set search_path = public as $$
declare t record; me uuid; w numeric := round(coalesce(p_weight, 0), 3); pr numeric := coalesce(p_price, 0);
        k int := coalesce(p_karat, 24); g24 numeric; cash numeric; note text; ref text := gen_random_uuid()::text;
begin
  select id, store_id, name into t from traders where id = p_trader;
  if t is null then raise exception 'التاجر غير موجود'; end if;
  if not has_permission('edit_traders', t.store_id) then raise exception 'ليس لديك صلاحية تعديل حسابات التجار' using errcode = '42501'; end if;
  if p_direction not in ('we_owe_gold', 'they_owe_gold') then raise exception 'اتجاه غير معروف'; end if;
  if w <= 0 or pr <= 0 then raise exception 'أدخل الوزن وسعر الغرام'; end if;
  if k not in (18, 21, 22, 24) then raise exception 'عيار غير معروف'; end if;
  select id into me from staff where user_id = auth.uid() and store_id = t.store_id limit 1;
  g24 := round(w * k / 24.0, 3);
  cash := round(w * pr, 2);
  note := format('تسكير عملات: %s غ عيار %s × %s = %s', w, k, pr, cash) || coalesce(' — ' || nullif(trim(p_notes), ''), '');
  -- gold side is settled, cash side takes its value (zero net in value)
  insert into trader_movements (store_id, trader_id, movement_type, weight_grams, karat, gold_24k_equivalent, fab_fee_amount, source, notes, batch_ref, created_by) values
    (t.store_id, t.id, case when p_direction = 'we_owe_gold' then 'debt_decrease' else 'debt_increase' end, w, k, g24, 0, 'gold_to_cash', note, ref, me),
    (t.store_id, t.id, case when p_direction = 'we_owe_gold' then 'debt_increase' else 'debt_decrease' end, 0, null, 0, cash, 'gold_to_cash', note, ref, me);
  return cash;
end $$;
grant execute on function public.trader_gold_to_cash(uuid, numeric, int, numeric, text, text) to authenticated;
