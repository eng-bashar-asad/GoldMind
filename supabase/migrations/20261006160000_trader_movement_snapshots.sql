-- Applied via SQL. Snapshot, at the moment goods are given to a trader, the piece's
-- accounting weight in stock and the shop's 24k gram price, so the profit report can
-- value the gold difference (weight billed − piece accounting weight) on the voucher day.
alter table trader_movements add column if not exists piece_acc_weight numeric, add column if not exists gold_price_24k numeric;
create or replace function gm_tm_snapshot() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.source = 'stock_given' then
    if new.piece_acc_weight is null and new.piece_id is not null then
      select coalesce(accounting_weight_grams, weight_grams) into new.piece_acc_weight from pieces where id = new.piece_id;
    end if;
    if new.gold_price_24k is null then
      select price_per_gram into new.gold_price_24k from gold_prices where store_id = new.store_id and karat = 24 limit 1;
    end if;
  end if;
  return new;
end $$;
create trigger trg_tm_snapshot before insert on trader_movements for each row execute function gm_tm_snapshot();
