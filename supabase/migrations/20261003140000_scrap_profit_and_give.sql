-- Scrap box (ذهب كسر bought from individuals):
-- 1) Each scrap purchase line remembers the shop's gold price for its karat at
--    that moment, so "ربح شراء الكسر" = weight × that price − amount paid.
--    It is profit in the reports only; it never touches the cashbox.
-- 2) Scrap can be handed to a trader/refiner at cost from the scrap box: the
--    weight leaves the box (oldest lots first) and the trader owes us that gold.
--    Goods received back are entered with the existing "إدخال بضاعة".

-- Allowed sources: also the trader cash out/in and gold-to-cash rows (added on
-- 30 Sep, rejected by the old check until now) and scrap given out.
alter table public.trader_movements drop constraint trader_movements_source_check,
  add constraint trader_movements_source_check check (source = any (array['settlement','stock_given','stock_received','opening_balance','cash_out','cash_in','gold_to_cash','scrap_given']));

create or replace function public.gm_scrap_price_at_purchase() returns trigger
language plpgsql security definer set search_path = public as $$
declare st uuid; typ text; pr numeric;
begin
  if new.gold_stock_lot_id is null or new.gold_price_per_gram is not null or new.karat is null then return new; end if;
  select store_id, type into st, typ from invoices where id = new.invoice_id;
  if typ is distinct from 'buyRetail' then return new; end if;
  select price_per_gram into pr from gold_prices where store_id = st and karat = new.karat;
  if pr is null then
    select price_per_gram * new.karat / 24.0 into pr from gold_prices where store_id = st and karat = 24;
  end if;
  new.gold_price_per_gram := round(pr, 2);
  return new;
end $$;

create or replace trigger trg_scrap_price_at_purchase before insert on public.invoice_items
  for each row execute function public.gm_scrap_price_at_purchase();

-- Past scrap lines: fill the price only where the shop's price was last changed
-- before the purchase (so today's price is exactly the price at that time).
update invoice_items it set gold_price_per_gram = g.price_per_gram
  from invoices i, gold_prices g
 where i.id = it.invoice_id and i.type = 'buyRetail' and it.gold_stock_lot_id is not null
   and it.gold_price_per_gram is null and g.store_id = i.store_id and g.karat = it.karat
   and g.updated_at <= i.created_at;

create or replace function public.give_scrap_to_trader(p_trader uuid, p_karat int, p_weight numeric, p_notes text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare t record; me uuid; w numeric := round(coalesce(p_weight, 0), 3); left_w numeric; take numeric;
        cost numeric := 0; lot record; avail numeric; note text; mid uuid;
begin
  select id, store_id, name into t from traders where id = p_trader;
  if t is null then raise exception 'التاجر غير موجود'; end if;
  if not has_permission('edit_traders', t.store_id) then raise exception 'ليس لديك صلاحية تعديل حسابات التجار' using errcode = '42501'; end if;
  if w <= 0 then raise exception 'أدخل الوزن'; end if;
  select coalesce(sum(weight_grams_remaining), 0) into avail from gold_stock_lots
   where store_id = t.store_id and box_name = 'كسر ' || p_karat and weight_grams_remaining > 0;
  if w > avail + 0.0005 then raise exception 'الوزن أكبر من الموجود في صندوق كسر % (% غ)', p_karat, round(avail, 3); end if;
  select id into me from staff where user_id = auth.uid() and store_id = t.store_id limit 1;

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
    cost := cost + take * lot.per_g;
    left_w := left_w - take;
  end loop;
  cost := round(cost, 2);

  note := format('إخراج كسر عيار %s بالكلفة: %s غ (كلفته %s)', p_karat, w, cost) || coalesce(' — ' || nullif(trim(p_notes), ''), '');
  insert into trader_movements (store_id, trader_id, movement_type, weight_grams, accounting_weight_grams, karat,
      gold_24k_equivalent, fab_fee_amount, source, notes, created_by)
    values (t.store_id, t.id, 'debt_decrease', w, w, p_karat, round(w * p_karat / 24.0, 3), 0, 'scrap_given', note, me)
    returning id into mid;
  return jsonb_build_object('id', mid, 'cost', cost);
end $$;
revoke all on function public.give_scrap_to_trader(uuid, int, numeric, text) from public, anon;
grant execute on function public.give_scrap_to_trader(uuid, int, numeric, text) to authenticated;
