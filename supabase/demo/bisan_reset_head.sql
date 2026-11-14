-- مجوهرات بيسان — demo company: wipe its data and fill it again (the last 10 days up to yesterday).
-- Touches ONLY the store below (checked by id AND name). Keeps the company, its login, staff and subscription.
-- Run in the Supabase SQL editor (whole file). Needs 20261114200000_sell_reserved_piece.sql applied first.
do $w$
declare S uuid := '481681c1-bbd2-4d3f-98a7-0362ac0da632';
begin
  if not exists (select 1 from stores where id = S and name = 'مجوهرات بيسان') then
    raise exception 'المحل التجريبي غير موجود — لم يُحذف شيء';
  end if;
  if position('pc.reserved_customer_id = cust' in (select prosrc from pg_proc where proname = 'post_sale_invoice')) = 0 then
    raise exception 'شغّل ملف 20261114200000_sell_reserved_piece.sql أولاً';
  end if;
  delete from stock_voucher_lines where store_id = S;
  delete from stock_vouchers where store_id = S;
  delete from stock_parties where store_id = S;
  delete from daily_cash_log where store_id = S;
  delete from customer_debts where store_id = S;
  delete from inventory_gifts where store_id = S;
  delete from expense_entries where store_id = S;
  delete from cash_movements where store_id = S;
  delete from trader_scrap_draws where store_id = S;
  delete from trader_movements where store_id = S;
  delete from piece_lot_draws where store_id = S;
  delete from piece_movements where store_id = S;
  delete from piece_barcode_history where store_id = S;
  delete from piece_chip_history where store_id = S;
  delete from rfid_write_jobs where store_id = S;
  delete from inventory_counts where store_id = S;
  update invoices set related_invoice_id = null where store_id = S;
  delete from invoice_items where invoice_id in (select id from invoices where store_id = S);
  delete from invoices where store_id = S;
  delete from customer_deposits where store_id = S;
  delete from repair_tickets where store_id = S;
  delete from pieces where store_id = S;
  delete from piece_intake_batches where store_id = S;
  delete from gold_stock_lots where store_id = S;
  delete from diamond_pieces where store_id = S;
  delete from diamond_stock_lots where store_id = S;
  delete from customer_phones where store_id = S;
  delete from customers where store_id = S;
  delete from traders where store_id = S;
  delete from expense_categories where store_id = S;
  delete from gold_prices where store_id = S;
  delete from invoice_number_counters where store_id = S;
  delete from voucher_counters where store_id = S;
  delete from audit_log where store_id = S;
end $w$;
