-- A piece handed to a trader at a fixed price: the trader owes the price as a
-- cash amount only (no gold / making debt); sale_cost keeps what the piece cost
-- the shop at that moment (gold at the shop price + making cost + diamonds),
-- so the profit report can show price − cost.
alter table public.trader_movements add column if not exists sale_cost numeric;
