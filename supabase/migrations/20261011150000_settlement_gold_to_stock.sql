-- Gold received from a trader in a settlement can be put into a stock box (كسر 18/21/22/24).
-- The lot remembers its settlement; editing the settlement re-sizes the lot, removing it empties the lot,
-- both refused once some of that gold was already used (production / sale).
alter table public.gold_stock_lots add column if not exists trader_movement_id uuid;
create index if not exists gold_stock_lots_trader_movement_id_idx on public.gold_stock_lots (trader_movement_id);

create or replace function public.trg_settlement_lot_sync() returns trigger
language plpgsql security definer set search_path = public as $$
declare lt record;
begin
  if tg_op = 'UPDATE' and new.weight_grams is not distinct from old.weight_grams and new.karat is not distinct from old.karat
     and new.gold_24k_equivalent is not distinct from old.gold_24k_equivalent then
    return new;
  end if;
  for lt in select * from gold_stock_lots where trader_movement_id = old.id for update loop
    if lt.weight_grams_remaining <> lt.weight_grams_total then
      raise exception 'الذهب المستلم بهذه التسوية استُعمل من المستودع (إنتاج أو بيع) — لا يمكن تعديله أو حذفه. عدّل الحساب بتسوية جديدة.';
    end if;
    if tg_op = 'UPDATE' then
      update gold_stock_lots set
        weight_grams_total = round(coalesce(new.gold_24k_equivalent, 0) * 24 / lt.karat, 3),
        weight_grams_remaining = round(coalesce(new.gold_24k_equivalent, 0) * 24 / lt.karat, 3)
       where id = lt.id;
    else
      update gold_stock_lots set weight_grams_remaining = 0,
        notes = coalesce(notes, '') || ' — أُلغي بإلغاء التسوية'
       where id = lt.id;
    end if;
  end loop;
  return case when tg_op = 'UPDATE' then new else old end;
end $$;
revoke execute on function public.trg_settlement_lot_sync() from public, anon;

create or replace trigger trg_settlement_lot_sync
  after update or delete on public.trader_movements
  for each row execute function public.trg_settlement_lot_sync();

-- one-off (2026-10-11): the gold received from the trader جليل on 2026-10-08 was recorded on his
-- statement only; it was added to «كسر 18» (375.14 g of 745 = 279.22 g 24K → 372.29 g 18K) and
-- «كسر 21» (139.76 g) by hand, then linked to those settlements here.
update public.gold_stock_lots l set trader_movement_id = tm.id
  from public.trader_movements tm
 where l.trader_id = 'dd59b189-f225-431b-a217-6d7f057b5d98' and l.trader_movement_id is null and l.box_name in ('كسر 18', 'كسر 21')
   and tm.trader_id = l.trader_id and tm.movement_type = 'debt_increase' and tm.created_at = l.created_at;
