-- Applied via execute_sql on 2026-10-03 (see the live function for the body):
-- trader_movements.gold_stock_lot_id, and trader_receive_stock(p_trader, p_lines,
-- p_vat_rate, p_batch_ref, p_notes): goods received from a trader go on the
-- trader's account (gold + making incl. VAT) and into stock in one transaction —
-- each line a barcoded piece (box required) or a bulk weight lot for production.
alter table public.trader_movements add column if not exists gold_stock_lot_id uuid references public.gold_stock_lots(id);
