-- A currency-conversion voucher (تسكير عملات) is two rows sharing batch_ref: the gold row and the cash row.
-- Deleting either one must delete the other, so gold and cash both return to what they were.
create or replace function public.trader_gold_to_cash_delete_pair()
returns trigger language plpgsql set search_path to 'public' as $$
begin
  if old.source = 'gold_to_cash' and old.batch_ref is not null then
    delete from trader_movements
     where trader_id = old.trader_id and source = 'gold_to_cash' and batch_ref = old.batch_ref and id <> old.id;
  end if;
  return old;
end $$;
revoke all on function public.trader_gold_to_cash_delete_pair() from public, anon;

drop trigger if exists trg_gold_to_cash_delete_pair on public.trader_movements;
create trigger trg_gold_to_cash_delete_pair after delete on public.trader_movements
  for each row when (old.source = 'gold_to_cash') execute function public.trader_gold_to_cash_delete_pair();
