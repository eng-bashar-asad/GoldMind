-- Repair gold: gold taken out of the scrap box (كسر) for a repair becomes an expense "تصاليح ذهب".
-- The expense is valued at the shop's cost (FIFO over scrap lots, same as scrap given to traders),
-- has NO cash movement (gold never touches the cashbox), and each lot taken is listed in the notes
-- with its date. repair_gold_lines keeps the lot-level detail so deleting the expense returns the gold.

create table if not exists public.repair_gold_lines (
  id uuid primary key default gen_random_uuid(),
  expense_entry_id uuid not null references public.expense_entries(id) on delete cascade,
  lot_id uuid not null references public.gold_stock_lots(id),
  karat integer not null,
  grams numeric not null check (grams > 0),
  cost numeric not null default 0,
  lot_date timestamptz not null,
  created_at timestamptz not null default now()
);
create index if not exists repair_gold_lines_expense_idx on public.repair_gold_lines (expense_entry_id);
create index if not exists repair_gold_lines_lot_idx on public.repair_gold_lines (lot_id);
-- no policies: only the security-definer functions below read or write this table
alter table public.repair_gold_lines enable row level security;

create or replace function public.record_repair_gold(p jsonb) returns uuid
language plpgsql security definer set search_path = public as $f$
declare sid uuid := (p->>'store_id')::uuid;
        kt int := (p->>'karat')::int;
        w numeric := round(coalesce(nullif(p->>'grams', '')::numeric, 0), 3);
        left_w numeric := w; take numeric; avail numeric; total_cost numeric := 0; today_price numeric := 0;
        lot record; cat_id uuid; me uuid; eid uuid; lines text := ''; head text;
        descr text := nullif(trim(p->>'description'), '');
begin
  if not gm_can_expense(sid) or not is_store_member(sid) then raise exception 'ليس لديك صلاحية تسجيل المصاريف' using errcode = '42501'; end if;
  if kt not in (18, 21, 22, 24) then raise exception 'اختر العيار'; end if;
  if w <= 0 then raise exception 'أدخل الغرامات'; end if;
  select coalesce(sum(weight_grams_remaining), 0) into avail from gold_stock_lots
   where store_id = sid and box_name = 'كسر ' || kt and weight_grams_remaining > 0;
  if w > avail + 0.0005 then raise exception 'الوزن أكبر من الموجود في صندوق كسر % (% غ)', kt, round(avail, 3); end if;

  select price_per_gram into today_price from gold_prices where store_id = sid and karat = kt limit 1;
  select id into cat_id from expense_categories where store_id = sid and name = 'تصاليح ذهب' limit 1;
  if cat_id is null then cat_id := save_expense_category(sid, 'تصاليح ذهب'); end if;
  select id into me from staff where user_id = auth.uid() and store_id = sid limit 1;

  insert into expense_entries (store_id, category_id, amount, description, created_by)
    values (sid, cat_id, 0, 'تصليح ذهب', me) returning id into eid;

  for lot in select l.id, l.weight_grams_remaining rem, l.created_at ld,
                    coalesce((select sum(ii.line_total) / nullif(sum(ii.weight_grams), 0) from invoice_items ii join invoices iv on iv.id = ii.invoice_id
                               where ii.gold_stock_lot_id = l.id and iv.type = 'buyRetail'), 0) per_g
               from gold_stock_lots l
              where l.store_id = sid and l.box_name = 'كسر ' || kt and l.weight_grams_remaining > 0
              order by l.created_at, l.id for update of l
  loop
    exit when left_w <= 0.0005;
    take := least(lot.rem, left_w);
    update gold_stock_lots set weight_grams_remaining = round(weight_grams_remaining - take, 3) where id = lot.id;
    insert into repair_gold_lines (expense_entry_id, lot_id, karat, grams, cost, lot_date)
      values (eid, lot.id, kt, take, round(take * lot.per_g, 2), lot.ld);
    total_cost := total_cost + take * lot.per_g;
    lines := lines || E'\n• ' || to_char(lot.ld at time zone 'Asia/Dubai', 'DD/MM/YYYY') || ': '
             || trim(to_char(take, 'FM999990.000')) || ' غ — كلفة ' || trim(to_char(round(take * lot.per_g, 2), 'FM999,999,990.00'));
    left_w := left_w - take;
  end loop;

  head := format('تصليح ذهب عيار %s: %s غ — قيمتها بسعر اليوم %s', kt, trim(to_char(w, 'FM999990.000')),
                 trim(to_char(round(w * coalesce(today_price, 0), 2), 'FM999,999,990.00')))
          || coalesce(' — ' || descr, '');
  update expense_entries set amount = round(total_cost, 2), description = head || lines where id = eid;
  return eid;
end $f$;

grant execute on function public.record_repair_gold(jsonb) to authenticated;

-- Deleting a repair-gold expense puts its grams back into the scrap lots it came from.
create or replace function public.delete_expense(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $f$
declare e record;
begin
  select * into e from expense_entries where id = p_id;
  if e is null then raise exception 'المصروف غير موجود'; end if;
  if not gm_can_expense(e.store_id) or not is_store_member(e.store_id) then raise exception 'ليس لديك صلاحية حذف المصاريف' using errcode = '42501'; end if;
  if exists (select 1 from inventory_gifts where expense_entry_id = p_id) then raise exception 'هذا مصروف هدية — احذفه بإرجاع الهدية إلى المخزن'; end if;
  update gold_stock_lots l set weight_grams_remaining = round(l.weight_grams_remaining + r.grams, 3)
    from repair_gold_lines r where r.expense_entry_id = p_id and r.lot_id = l.id;
  delete from repair_gold_lines where expense_entry_id = p_id;
  delete from expense_entries where id = p_id;
  if e.cash_movement_id is not null then delete from cash_movements where id = e.cash_movement_id; end if; -- its daily-box row goes with it
  return jsonb_build_object('ok', true);
end $f$;
revoke execute on function public.delete_expense(uuid) from public, anon;
grant execute on function public.delete_expense(uuid) to authenticated;
