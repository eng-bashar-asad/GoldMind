-- Applied via execute_sql on 2026-10-03:
-- pieces.purchase_cost: a piece bought from a trader for a cash price keeps
-- that price; its sale profit is sale price (before VAT) − purchase_cost
-- (gm-profit.js) instead of gold value + making cost. post_purchase_invoice
-- fills it for cash purchases with a price. Data: 000808 (PINV-2026-000007) = 5180.
alter table public.pieces add column if not exists purchase_cost numeric;
