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

  -- 14) the same piece twice in one sale is refused
  insert into pieces (store_id, barcode, weight_grams, accounting_weight_grams, karat, status) values (usd, 'T-P3', 5, 5, 18, 'available') returning id into p1;
  begin
    perform post_sale_invoice(jsonb_build_object('store_id', usd, 'customer_id', cust, 'payment_method', 'cash',
      'items', jsonb_build_array(jsonb_build_object('piece_id', p1, 'price', 700), jsonb_build_object('piece_id', p1, 'price', 700))));
    raise exception 'FAIL 14: same piece sold twice in one invoice';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;

  -- 15) the same new customer on two offline sales is created once
  r := post_sale_invoice(jsonb_build_object('store_id', usd, 'new_customer', jsonb_build_object('name', 'زبون جديد', 'phone', '050'),
        'payment_method', 'cash', 'items', jsonb_build_array(jsonb_build_object('piece_id', p1, 'price', 700))));
  if (select count(*) from customers where store_id = usd and name = 'زبون جديد') <> 1 then raise exception 'FAIL 15: duplicate new customer'; end if;

  -- ===== purchases (post_purchase_invoice) =====
  declare
    tr uuid; tr_other uuid; ref2 uuid := gen_random_uuid(); pr jsonb; pr2 jsonb; inv uuid;
    lot2 uuid; p4 uuid; s jsonb; ret jsonb; line_piece uuid; line_lot uuid; cnt int; nxt text;
  begin
    insert into traders (store_id, name) values (usd, 'تاجر تجربة') returning id into tr;
    insert into traders (store_id, name) values (aed, 'تاجر محل آخر') returning id into tr_other;

    -- 16) credit purchase from a trader: piece + bulk + diamond box, all in one go
    pr := post_purchase_invoice(jsonb_build_object('store_id', usd, 'type', 'buyTrader', 'trader_id', tr,
      'payment_method', 'credit', 'client_ref', ref2, 'items', jsonb_build_array(
        jsonb_build_object('mode', 'piece', 'karat', 21, 'weight', 8, 'price', 0, 'fab_fee', 40, 'fab_fee_vat', 2, 'description', 'خاتم'),
        jsonb_build_object('mode', 'bulk', 'karat', 18, 'weight', 12, 'price', 0, 'fab_fee', 60, 'fab_fee_vat', 3, 'fab_per_gram', 5),
        jsonb_build_object('mode', 'diamond_bulk', 'diamond_carat', 2, 'diamond_price_per_carat', 500, 'price', 1000, 'box_name', 'صندوق ت'))));
    inv := (pr->>'id')::uuid;
    if (pr->>'invoice_number') not like 'PINV-%' then raise exception 'FAIL 16a: number %', pr->>'invoice_number'; end if;
    if (select total_amount from invoices where id = inv) <> 1000 then raise exception 'FAIL 16b: total'; end if;
    if (select count(*) from invoice_items where invoice_id = inv) <> 3 then raise exception 'FAIL 16c: items'; end if;
    if (select count(*) from pieces p join invoice_items ii on ii.piece_id = p.id where ii.invoice_id = inv and p.status = 'available') <> 1 then raise exception 'FAIL 16d: piece'; end if;
    if (select weight_grams_remaining from gold_stock_lots where source_invoice_id = inv) <> 12 then raise exception 'FAIL 16e: lot'; end if;
    if (select remaining_carat from diamond_stock_lots where source_invoice_id = inv) <> 2 then raise exception 'FAIL 16f: diamond lot'; end if;
    if (select count(*) from trader_movements where invoice_id = inv) <> 3 then raise exception 'FAIL 16g: trader debt rows'; end if;
    if (select sum(gold_24k_equivalent) from trader_movements where invoice_id = inv) <> 16 then raise exception 'FAIL 16h: 24k equivalent (7 + 9)'; end if;
    if (select sum(fab_fee_amount) from trader_movements where invoice_id = inv) <> 1105 then raise exception 'FAIL 16i: cash debt (42 + 63 + 1000)'; end if;
    if exists (select 1 from cash_movements where invoice_id = inv) then raise exception 'FAIL 16j: credit purchase moved cash'; end if;
    if (select vat_amount from invoices where id = inv) <> 5 then raise exception 'FAIL 16k: vat'; end if;

    -- 17) same client_ref again does not double-post
    pr2 := post_purchase_invoice(jsonb_build_object('store_id', usd, 'type', 'buyTrader', 'trader_id', tr,
      'payment_method', 'credit', 'client_ref', ref2, 'items', jsonb_build_array(jsonb_build_object('mode', 'bulk', 'karat', 18, 'weight', 1))));
    if not (pr2->>'duplicate')::boolean or pr2->>'id' <> pr->>'id' then raise exception 'FAIL 17: purchase retry double-posted'; end if;

    -- 18) cash scrap purchase from a person: scrap box, cash out, seller ID kept
    pr := post_purchase_invoice(jsonb_build_object('store_id', usd, 'type', 'buyRetail', 'payment_method', 'cash',
      'counterparty_name', 'بائع', 'seller_id_type', 'passport', 'seller_id_number', 'N123',
      'items', jsonb_build_array(jsonb_build_object('mode', 'bulk', 'karat', 21, 'weight', 5, 'price', 400))));
    inv := (pr->>'id')::uuid;
    if (select box_name from gold_stock_lots where source_invoice_id = inv) <> 'كسر 21' then raise exception 'FAIL 18a: scrap box'; end if;
    if (select sum(amount) from cash_movements where invoice_id = inv and direction = 'out') <> 400 then raise exception 'FAIL 18b: cash out'; end if;
    if (select seller_id_type || seller_id_number from invoices where id = inv) <> 'passportN123' then raise exception 'FAIL 18c: seller id'; end if;

    -- 19) a bad purchase saves nothing and does not burn an invoice number
    select count(*) into cnt from invoices where store_id = usd;
    select next_seq into nxt from invoice_number_counters where store_id = usd and prefix = 'PINV';
    begin
      perform post_purchase_invoice(jsonb_build_object('store_id', usd, 'type', 'buyTrader', 'trader_id', tr_other,
        'payment_method', 'credit', 'items', jsonb_build_array(jsonb_build_object('mode', 'bulk', 'karat', 18, 'weight', 1))));
      raise exception 'FAIL 19a: trader of another store accepted';
    exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
    begin
      perform post_purchase_invoice(jsonb_build_object('store_id', usd, 'type', 'buyTrader', 'trader_id', tr, 'payment_method', 'credit',
        'items', jsonb_build_array(jsonb_build_object('mode', 'bulk', 'karat', 18, 'weight', 3), jsonb_build_object('mode', 'piece', 'karat', 18, 'weight', 0))));
      raise exception 'FAIL 19b: zero weight accepted';
    exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
    if (select count(*) from invoices where store_id = usd) <> cnt then raise exception 'FAIL 19c: partial purchase saved'; end if;
    if (select next_seq from invoice_number_counters where store_id = usd and prefix = 'PINV')::text <> nxt then raise exception 'FAIL 19d: number burned'; end if;

    -- ===== returns (post_sales_return) =====
    insert into pieces (store_id, barcode, weight_grams, accounting_weight_grams, karat, status) values (usd, 'T-P4', 6, 6, 18, 'available') returning id into p4;
    insert into gold_stock_lots (store_id, karat, weight_grams_total, weight_grams_remaining) values (usd, 18, 20, 20) returning id into lot2;
    s := post_sale_invoice(jsonb_build_object('store_id', usd, 'customer_id', cust, 'payment_method', 'cash',
      'items', jsonb_build_array(jsonb_build_object('piece_id', p4, 'price', 800),
                                 jsonb_build_object('mode', 'stock', 'lot_id', lot2, 'karat', 18, 'weight', 3, 'price', 400))));
    select id into line_piece from invoice_items where invoice_id = (s->>'id')::uuid and piece_id = p4;
    select id into line_lot from invoice_items where invoice_id = (s->>'id')::uuid and gold_stock_lot_id = lot2;

    -- 20) returning both lines puts stock back and refunds cash, in one go
    ret := post_sales_return(jsonb_build_object('store_id', usd, 'original_invoice_id', s->>'id', 'refund_method', 'cash',
      'reason', 'مقاس', 'item_ids', jsonb_build_array(line_piece, line_lot)));
    if (ret->>'invoice_number') not like 'RET-%' then raise exception 'FAIL 20a: number'; end if;
    if (select status from pieces where id = p4) <> 'available' then raise exception 'FAIL 20b: piece not back'; end if;
    if (select weight_grams_remaining from gold_stock_lots where id = lot2) <> 20 then raise exception 'FAIL 20c: lot not back'; end if;
    if (select sum(amount) from cash_movements where invoice_id = (ret->>'id')::uuid and direction = 'out') <> 1200 then raise exception 'FAIL 20d: refund'; end if;
    if not exists (select 1 from piece_movements where piece_id = p4 and event_type = 'returned') then raise exception 'FAIL 20e: movement log'; end if;

    -- 21) the same lines cannot be returned twice (piece, then bulk weight)
    begin
      perform post_sales_return(jsonb_build_object('store_id', usd, 'original_invoice_id', s->>'id', 'refund_method', 'cash', 'item_ids', jsonb_build_array(line_piece)));
      raise exception 'FAIL 21a: piece returned twice';
    exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
    begin
      perform post_sales_return(jsonb_build_object('store_id', usd, 'original_invoice_id', s->>'id', 'refund_method', 'cash', 'item_ids', jsonb_build_array(line_lot)));
      raise exception 'FAIL 21b: bulk weight returned twice';
    exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
    if (select weight_grams_remaining from gold_stock_lots where id = lot2) <> 20 then raise exception 'FAIL 21c: lot changed by a refused return'; end if;

    -- 22) a line from another invoice is refused
    begin
      perform post_sales_return(jsonb_build_object('store_id', usd, 'original_invoice_id', r->>'id', 'refund_method', 'cash', 'item_ids', jsonb_build_array(line_piece)));
      raise exception 'FAIL 22: foreign line accepted';
    exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;

    -- 23) credit sale returned as debt reduction
    s := post_sale_invoice(jsonb_build_object('store_id', usd, 'customer_id', cust, 'payment_method', 'credit',
      'items', jsonb_build_array(jsonb_build_object('piece_id', p4, 'price', 900))));
    select id into line_piece from invoice_items where invoice_id = (s->>'id')::uuid;
    ret := post_sales_return(jsonb_build_object('store_id', usd, 'original_invoice_id', s->>'id', 'refund_method', 'debt_reduce', 'item_ids', jsonb_build_array(line_piece)));
    if (select cash_amount from customer_debts where invoice_id = (ret->>'id')::uuid and movement_type = 'debt_decrease') <> 900 then raise exception 'FAIL 23a: debt not reduced'; end if;
    if exists (select 1 from cash_movements where invoice_id = (ret->>'id')::uuid) then raise exception 'FAIL 23b: cash moved on debt reduction'; end if;
  end;

  raise notice 'ALL ACCOUNTING TESTS PASSED';
end $$;
rollback;
