-- Applied via SQL. Customer payments keep a link to their cash movement so they can be
-- edited (customer_payment_update: amount/notes; amount 0 = delete) together with the cash box row.
alter table customer_debts add column if not exists cash_movement_id uuid references cash_movements(id) on delete set null;
-- record_customer_payment now stores cash_movement_id; customer_payment_update(p_id, p_amount, p_notes)
-- updates customer_debts + cash_movements + daily_cash_log, then re-runs gm_allocate/gm_unallocate_customer_credit.
