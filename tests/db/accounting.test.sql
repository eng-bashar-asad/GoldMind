-- Accounting safety tests. Everything runs inside one transaction and is
-- rolled back, so it never changes real data. Any failed check raises an error.
-- Run: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f tests/db/accounting.test.sql
begin;
do $$
declare
  uid uuid := (select id from auth.users order by created_at limit 1);
  usd uuid; aed uuid; cust uuid; p1 uuid; p2 uuid; lot uuid;
  r jsonb; r2 jsonb; ref uuid := gen_random_uuid(); v numeric; n int;
begin
  -- fixtures: a USD store and an AED store owned by the same user
  insert into stores (name, currency, last_gold_ounce_price, last_gold_ounce_rate) values ('TEST USD', 'USD', 4000, 1) returning id into usd;
  insert into stores (name, currency, last_gold_ounce_price, last_gold_ounce_rate) values ('TEST AED', 'AED', 4000, 3.6725) returning id into aed;
  insert into staff (store_id, user_id, full_name, role) values (usd, uid, 'T', 'owner'), (aed, uid, 'T', 'owner');
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_gold_ounce_price(usd, 4000, 3.674);            -- rate must be forced to 1 for USD
  perform set_gold_ounce_price(aed, 4000, 3.6725);
  select price_per_gram into v from gold_prices where store_id = usd and karat = 24;
  if abs(v - 128.60) > 0.05 then raise exception 'FAIL 1: USD 24K should be ~128.60, got %', v; end if;

  -- 2) an AED-sized price in a USD store is refused (the AED/USD mix-up)
  begin
    update gold_prices set price_per_gram = 472.29 where store_id = usd and karat = 24;
    raise exception 'FAIL 2: AED price accepted in USD store';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  -- 3) and a USD-sized price in an AED store too
  begin
    update gold_prices set price_per_gram = 128.60 where store_id = aed and karat = 24;
    raise exception 'FAIL 3: USD price accepted in AED store';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;

  -- 4) invoice in a foreign currency is refused; missing currency is filled
  begin
    insert into invoices (store_id, invoice_number, type, total_amount, currency) values (usd, 'T-1', 'sale', 1, 'AED');
    raise exception 'FAIL 4: AED invoice accepted in USD store';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;

  -- 5) switching store currency converts gold prices
  update stores set currency = 'AED' where id = usd;
  select price_per_gram into v from gold_prices where store_id = usd and karat = 24;
  if abs(v - 128.60 * 3.6725) > 0.1 then raise exception 'FAIL 5: currency switch did not convert (got %)', v; end if;
  update stores set currency = 'USD' where id = usd;

  -- sale fixtures
  insert into customers (store_id, name) values (usd, 'زبون تجربة') returning id into cust;
  insert into pieces (store_id, barcode, weight_grams, accounting_weight_grams, karat, status) values (usd, 'T-P1', 10, 10, 18, 'available') returning id into p1;
  insert into pieces (store_id, barcode, weight_grams, accounting_weight_grams, karat, status) values (usd, 'T-P2', 5, 5, 18, 'available') returning id into p2;
  insert into gold_stock_lots (store_id, karat, weight_grams_total, weight_grams_remaining) values (usd, 18, 20, 20) returning id into lot;

  -- 6) selling far below gold value asks for confirmation (LOW_PRICE)
  begin
    perform post_sale_invoice(jsonb_build_object('store_id', usd, 'customer_id', cust, 'payment_method', 'cash',
      'items', jsonb_build_array(jsonb_build_object('piece_id', p1, 'price', 10))));
    raise exception 'FAIL 6: low price not flagged';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    if sqlerrm not like 'LOW_PRICE:%' then raise exception 'FAIL 6: wrong error %', sqlerrm; end if;
  end;

  -- 7) a mixed-payment sale posts everything in one go
  r := post_sale_invoice(jsonb_build_object('store_id', usd, 'customer_id', cust, 'payment_method', 'mixed',
        'cash_paid', 500, 'bank_paid', 300, 'client_ref', ref,
        'items', jsonb_build_array(
            jsonb_build_object('piece_id', p1, 'price', 1200),
            jsonb_build_object('mode', 'stock', 'lot_id', lot, 'karat', 18, 'weight', 4, 'price', 450))));
  if (select total_amount from invoices where id = (r->>'id')::uuid) <> 1650 then raise exception 'FAIL 7a: total'; end if;
  if (select upper(currency) from invoices where id = (r->>'id')::uuid) <> 'USD' then raise exception 'FAIL 7b: currency'; end if;
  if (select status from pieces where id = p1) <> 'sold' then raise exception 'FAIL 7c: piece not sold'; end if;
  if (select weight_grams_remaining from gold_stock_lots where id = lot) <> 16 then raise exception 'FAIL 7d: lot not consumed'; end if;
  if (select sum(amount) from cash_movements where invoice_id = (r->>'id')::uuid) <> 800 then raise exception 'FAIL 7e: cash'; end if;
  if (select sum(cash_amount) from customer_debts where invoice_id = (r->>'id')::uuid) <> 850 then raise exception 'FAIL 7f: debt'; end if;
  if (select upper(currency) from cash_movements where invoice_id = (r->>'id')::uuid limit 1) <> 'USD' then raise exception 'FAIL 7g: cash currency'; end if;
  if (select gold_price_per_gram from invoice_items where invoice_id = (r->>'id')::uuid and piece_id = p1) is null then raise exception 'FAIL 7h: no gold price snapshot'; end if;

  -- 8) same client_ref again (offline retry) does not double-post
  r2 := post_sale_invoice(jsonb_build_object('store_id', usd, 'customer_id', cust, 'payment_method', 'cash', 'client_ref', ref,
        'items', jsonb_build_array(jsonb_build_object('piece_id', p2, 'price', 700))));
  if not (r2->>'duplicate')::boolean or (r2->>'id') <> (r->>'id') then raise exception 'FAIL 8: duplicate posted'; end if;
  if (select status from pieces where id = p2) <> 'available' then raise exception 'FAIL 8b: retry touched another piece'; end if;

  -- 9) a sold piece cannot be sold again
  begin
    perform post_sale_invoice(jsonb_build_object('store_id', usd, 'customer_id', cust, 'payment_method', 'cash',
      'items', jsonb_build_array(jsonb_build_object('piece_id', p1, 'price', 2000))));
    raise exception 'FAIL 9: sold piece sold twice';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;

  -- 10) paying more than the total is refused and nothing is saved
  select count(*) into n from invoices where store_id = usd;
  begin
    perform post_sale_invoice(jsonb_build_object('store_id', usd, 'customer_id', cust, 'payment_method', 'mixed', 'cash_paid', 5000,
      'items', jsonb_build_array(jsonb_build_object('piece_id', p2, 'price', 700))));
    raise exception 'FAIL 10: overpayment accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  if (select count(*) from invoices where store_id = usd) <> n or (select status from pieces where id = p2) <> 'available' then
    raise exception 'FAIL 10b: partial save after an error';
  end if;

  -- 11) health check is clean for this store
  select count(*) into n from accounting_health_check(usd);
  if n <> 0 then raise exception 'FAIL 11: health check found % issues on a clean store', n; end if;

  -- 12) health check spots a broken invoice (lines ≠ total)
  update invoices set total_amount = total_amount + 1 where id = (r->>'id')::uuid;
  if not exists (select 1 from accounting_health_check(usd) where code = 'invoice_lines_total') then
    raise exception 'FAIL 12: health check missed a wrong total';
  end if;

  -- 13) a customer added offline on the sale screen is created with the sale
  r := post_sale_invoice(jsonb_build_object('store_id', usd, 'new_customer', jsonb_build_object('name', 'زبون جديد', 'phone', '050'),
        'payment_method', 'cash', 'items', jsonb_build_array(jsonb_build_object('piece_id', p2, 'price', 700))));
  if (select c.name from invoices i join customers c on c.id = i.customer_id where i.id = (r->>'id')::uuid) <> 'زبون جديد' then
    raise exception 'FAIL 13: new customer not created';
  end if;

  raise notice 'ALL ACCOUNTING TESTS PASSED';
end $$;
rollback;
