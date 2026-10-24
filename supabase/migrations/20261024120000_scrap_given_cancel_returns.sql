-- Deleting an "إخراج كسر بالكلفة" (scrap given to a trader) movement must put the grams back in
-- the scrap box. Until now give_scrap_to_trader took the grams out of the box's purchases but did
-- not remember which ones, and deleting the movement only removed the row: the grams vanished.
--  * trader_scrap_draws: which purchases (lots) each scrap-given movement took, and how much
--  * deleting the movement gives exactly those grams back (older movements without a record:
--    back into the box's newest purchases, up to their original weight; any rest = a new entry)
--  * the weight of a scrap-given movement cannot be edited (delete it and give again)

create table if not exists public.trader_scrap_draws (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null,
  movement_id uuid not null references public.trader_movements(id) on delete cascade,
  lot_id uuid not null references public.gold_stock_lots(id),
  grams numeric not null check (grams > 0),
  created_at timestamptz not null default now()
);
create index if not exists trader_scrap_draws_movement_idx on public.trader_scrap_draws (movement_id);
alter table public.trader_scrap_draws enable row level security;
create policy "members read scrap draws" on public.trader_scrap_draws for select using (public.is_store_member(store_id));

create or replace function public.give_scrap_to_trader(p_trader uuid, p_karat integer, p_weight numeric, p_notes text default null)
 returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare t record; me uuid; w numeric := round(coalesce(p_weight, 0), 3); left_w numeric; take numeric;
        cost numeric := 0; lot record; avail numeric; mid uuid;
begin
  select id, gm_acting_store(store_id) as store_id, name into t from traders where id = p_trader;
  if t is null then raise exception 'التاجر غير موجود'; end if;
  if not has_permission('edit_traders', t.store_id) then raise exception 'ليس لديك صلاحية تعديل حسابات التجار' using errcode = '42501'; end if;
  if w <= 0 then raise exception 'أدخل الوزن'; end if;
  select coalesce(sum(weight_grams_remaining), 0) into avail from gold_stock_lots
   where store_id = t.store_id and box_name = 'كسر ' || p_karat and weight_grams_remaining > 0;
  if w > avail + 0.0005 then raise exception 'الوزن أكبر من الموجود في صندوق كسر % (% غ)', p_karat, round(avail, 3); end if;
  select id into me from staff where user_id = auth.uid() and store_id = t.store_id limit 1;

  insert into trader_movements (store_id, trader_id, movement_type, weight_grams, accounting_weight_grams, karat,
      gold_24k_equivalent, fab_fee_amount, source, notes, created_by)
    values (t.store_id, t.id, 'debt_decrease', w, w, p_karat, round(w * p_karat / 24.0, 3), 0, 'scrap_given', '', me)
    returning id into mid;

  left_w := w;
  for lot in select l.id, l.weight_grams_remaining rem,
                    coalesce((select sum(ii.line_total) / nullif(sum(ii.weight_grams), 0) from invoice_items ii join invoices iv on iv.id = ii.invoice_id
                               where ii.gold_stock_lot_id = l.id and iv.type = 'buyRetail'), 0) per_g
               from gold_stock_lots l
              where l.store_id = t.store_id and l.box_name = 'كسر ' || p_karat and l.weight_grams_remaining > 0
              order by l.created_at, l.id for update of l
  loop
    exit when left_w <= 0.0005;
    take := least(lot.rem, left_w);
    update gold_stock_lots set weight_grams_remaining = round(weight_grams_remaining - take, 3) where id = lot.id;
    insert into trader_scrap_draws (store_id, movement_id, lot_id, grams) values (t.store_id, mid, lot.id, round(take, 3));
    cost := cost + take * lot.per_g;
    left_w := left_w - take;
  end loop;
  cost := round(cost, 2);

  update trader_movements set notes = format('إخراج كسر عيار %s بالكلفة: %s غ (كلفته %s)', p_karat, w, cost)
      || coalesce(' — ' || nullif(trim(p_notes), ''), '') where id = mid;
  return jsonb_build_object('id', mid, 'cost', cost);
end $function$;

-- grams back into a scrap box when nothing recorded which purchases they came from
create or replace function public.gm_scrap_return_unrecorded(p_store uuid, p_karat int, p_grams numeric, p_note text)
 returns void language plpgsql security definer set search_path to 'public' as $$
declare left_g numeric := round(p_grams, 3); r record; a numeric;
begin
  for r in select id, weight_grams_total - weight_grams_remaining room from gold_stock_lots
            where store_id = p_store and box_name = 'كسر ' || p_karat and weight_grams_remaining < weight_grams_total
            order by created_at desc, id desc for update loop
    exit when left_g <= 0.0005;
    a := least(left_g, r.room);
    update gold_stock_lots set weight_grams_remaining = round(weight_grams_remaining + a, 3) where id = r.id;
    left_g := left_g - a;
  end loop;
  if left_g > 0.0005 then
    insert into gold_stock_lots (store_id, karat, box_name, weight_grams_total, weight_grams_remaining, notes)
      values (p_store, p_karat, 'كسر ' || p_karat, round(left_g, 3), round(left_g, 3), p_note);
  end if;
end $$;

create or replace function public.trg_scrap_given_guard() returns trigger
 language plpgsql security definer set search_path to 'public' as $$
declare d record; n int := 0;
begin
  if tg_op = 'UPDATE' then
    if new.weight_grams is distinct from old.weight_grams or new.karat is distinct from old.karat then
      raise exception 'لا يمكن تعديل وزن إخراج الكسر — احذف الحركة (يرجع الوزن لصندوق الكسر) ثم أخرجه من جديد';
    end if;
    return new;
  end if;
  for d in select lot_id, grams from trader_scrap_draws where movement_id = old.id loop
    update gold_stock_lots set weight_grams_remaining = round(weight_grams_remaining + d.grams, 3) where id = d.lot_id;
    n := n + 1;
  end loop;
  if n = 0 and coalesce(old.weight_grams, 0) > 0 then
    perform gm_scrap_return_unrecorded(old.store_id, old.karat, old.weight_grams, 'أُرجع من حذف إخراج كسر لتاجر');
  end if;
  return old;
end $$;

create or replace trigger trg_scrap_given_guard before update or delete on public.trader_movements
  for each row when (old.source = 'scrap_given') execute function public.trg_scrap_given_guard();
