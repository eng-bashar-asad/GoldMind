-- A piece already given to a trader whose accounting weight is edited later: the trader's account
-- (weight billed, 24k, making) stays as on the voucher, only the profit snapshot follows the piece.
create or replace function public.gm_piece_acc_to_trader_give() returns trigger
language plpgsql security definer set search_path to 'public' as $$
begin
  if new.status = 'given_to_trader'
     and coalesce(new.accounting_weight_grams, new.weight_grams) is distinct from coalesce(old.accounting_weight_grams, old.weight_grams) then
    update trader_movements set piece_acc_weight = coalesce(new.accounting_weight_grams, new.weight_grams)
     where id = (select id from trader_movements where piece_id = new.id and source = 'stock_given' order by created_at desc limit 1);
  end if;
  return new;
end $$;
revoke execute on function public.gm_piece_acc_to_trader_give() from public, anon;
create trigger trg_piece_acc_to_trader_give after update of accounting_weight_grams, weight_grams on public.pieces
  for each row execute function public.gm_piece_acc_to_trader_give();

-- the pieces already edited this way: bring their profit snapshot to the piece's accounting weight
update trader_movements tm set piece_acc_weight = coalesce(p.accounting_weight_grams, p.weight_grams)
  from pieces p
 where p.id = tm.piece_id and p.status = 'given_to_trader' and tm.source = 'stock_given'
   and tm.id = (select id from trader_movements t where t.piece_id = p.id and t.source = 'stock_given' order by created_at desc limit 1)
   and tm.piece_acc_weight is distinct from coalesce(p.accounting_weight_grams, p.weight_grams);
