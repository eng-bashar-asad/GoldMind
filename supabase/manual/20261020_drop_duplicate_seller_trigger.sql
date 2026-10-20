-- Run once (بشار). Harmless duplicate left after renaming invoices.seller_id → salesperson_id:
-- trg_invoice_seller and trg_invoice_salesperson both call gm_seller_stamp(); one is enough.
drop trigger if exists trg_invoice_seller on public.invoices;
