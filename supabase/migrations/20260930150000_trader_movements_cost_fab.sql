alter table public.trader_movements add column if not exists cost_fab_per_gram numeric;
comment on column public.trader_movements.cost_fab_per_gram is 'Our own making cost per gram for goods given to a trader by weight (no piece) — used for wholesale profit';
