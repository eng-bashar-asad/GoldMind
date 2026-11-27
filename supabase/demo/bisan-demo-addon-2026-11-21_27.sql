-- مجوهرات بيسان — demo activity 21–27 Nov 2026 (inserts through the real RPCs, no deletes). Run once.

-- 2026-11-21
do $d$ declare r jsonb; S uuid := '481681c1-bbd2-4d3f-98a7-0362ac0da632'; begin
perform set_config('request.jwt.claims', json_build_object('sub', '92164ef6-df33-43d1-a5a7-d66199974ec5', 'role', 'authenticated')::text, true);
execute $f$ create or replace function pg_temp.gm_shift(sid uuid, ts timestamptz) returns void language plpgsql as $g$ declare t text; begin foreach t in array array['cash_movements','customer_debts','daily_cash_log','piece_movements','trader_movements'] loop execute format('update public.%I set created_at=$1, entered_at=$1 where store_id=$2 and created_at=now()', t) using ts, sid; end loop; foreach t in array array['customer_deposits','customers','customer_phones','expense_entries','gold_stock_lots','invoices','pieces','stock_vouchers','stock_parties','traders','piece_intake_batches','piece_lot_draws','trader_scrap_draws','audit_log'] loop begin execute format('update public.%I set created_at=$1 where store_id=$2 and created_at=now()', t) using ts, sid; exception when undefined_column or undefined_table then null; end; end loop; update public.gold_prices set updated_at = ts where store_id = sid and updated_at = now(); end $g$ $f$;
execute $f$ create or replace function pg_temp.gm_sell(sid uuid, cust text, descr text, meth text) returns void language plpgsql as $g$
declare p record; pr numeric; cu uuid; body jsonb; begin
  select id, barcode, karat, weight_grams into p from public.pieces where store_id=sid and description_ar=descr and status='available' limit 1;
  if p.id is null then raise notice 'skip %', descr; return; end if;
  select id into cu from public.customers where store_id=sid and name=cust limit 1;
  if cu is null then insert into public.customers (store_id, name, phone, phone_country_code) values (sid, cust, '05' || (50000000 + floor(random()*49999999))::bigint::text, '+971') returning id into cu; end if;
  pr := round(p.weight_grams * ((select price_per_gram from public.gold_prices where store_id=sid and karat=p.karat) + case when p.karat=18 then 42 else 34 end));
  body := jsonb_build_object('store_id', sid, 'client_ref', gen_random_uuid(), 'customer_id', cu, 'payment_method', meth, 'confirm_low_price', true,
    'items', jsonb_build_array(jsonb_build_object('mode','manual','piece_id',p.id,'barcode',p.barcode,'karat',p.karat,'weight',p.weight_grams,'price',pr,'description',descr)));
  if meth='mixed' then body := body || jsonb_build_object('cash_paid', round(pr*0.4), 'bank_paid', pr - round(pr*0.4)); end if;
  perform public.post_sale_invoice(body);
end $g$ $f$;
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 24, 474.2, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 22, 434.68, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 21, 414.92, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 18, 355.65, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
perform pg_temp.gm_shift(S, (timestamp '2026-11-21 09:00') at time zone 'Asia/Dubai');
perform pg_temp.gm_sell(S, 'مريم الشامسي', 'حلق هلال 18K', 'cash');
perform pg_temp.gm_shift(S, (timestamp '2026-11-21 10:40') at time zone 'Asia/Dubai');
perform pg_temp.gm_sell(S, 'سيف الكتبي', 'خاتم نقشة تركية 21K', 'bank');
perform pg_temp.gm_shift(S, (timestamp '2026-11-21 13:05') at time zone 'Asia/Dubai');
perform cash_voucher(jsonb_build_object('store_id', S, 'kind', 'out', 'party', 'expense', 'category_id', (select id from expense_categories where store_id=S and name='ضيافة'), 'amount', 95, 'notes', 'قهوة وتمر للزبائن'));
perform pg_temp.gm_shift(S, (timestamp '2026-11-21 17:20') at time zone 'Asia/Dubai');
end $d$;

-- 2026-11-22
do $d$ declare r jsonb; S uuid := '481681c1-bbd2-4d3f-98a7-0362ac0da632'; begin
perform set_config('request.jwt.claims', json_build_object('sub', '92164ef6-df33-43d1-a5a7-d66199974ec5', 'role', 'authenticated')::text, true);
execute $f$ create or replace function pg_temp.gm_shift(sid uuid, ts timestamptz) returns void language plpgsql as $g$ declare t text; begin foreach t in array array['cash_movements','customer_debts','daily_cash_log','piece_movements','trader_movements'] loop execute format('update public.%I set created_at=$1, entered_at=$1 where store_id=$2 and created_at=now()', t) using ts, sid; end loop; foreach t in array array['customer_deposits','customers','customer_phones','expense_entries','gold_stock_lots','invoices','pieces','stock_vouchers','stock_parties','traders','piece_intake_batches','piece_lot_draws','trader_scrap_draws','audit_log'] loop begin execute format('update public.%I set created_at=$1 where store_id=$2 and created_at=now()', t) using ts, sid; exception when undefined_column or undefined_table then null; end; end loop; update public.gold_prices set updated_at = ts where store_id = sid and updated_at = now(); end $g$ $f$;
execute $f$ create or replace function pg_temp.gm_sell(sid uuid, cust text, descr text, meth text) returns void language plpgsql as $g$
declare p record; pr numeric; cu uuid; body jsonb; begin
  select id, barcode, karat, weight_grams into p from public.pieces where store_id=sid and description_ar=descr and status='available' limit 1;
  if p.id is null then raise notice 'skip %', descr; return; end if;
  select id into cu from public.customers where store_id=sid and name=cust limit 1;
  if cu is null then insert into public.customers (store_id, name, phone, phone_country_code) values (sid, cust, '05' || (50000000 + floor(random()*49999999))::bigint::text, '+971') returning id into cu; end if;
  pr := round(p.weight_grams * ((select price_per_gram from public.gold_prices where store_id=sid and karat=p.karat) + case when p.karat=18 then 42 else 34 end));
  body := jsonb_build_object('store_id', sid, 'client_ref', gen_random_uuid(), 'customer_id', cu, 'payment_method', meth, 'confirm_low_price', true,
    'items', jsonb_build_array(jsonb_build_object('mode','manual','piece_id',p.id,'barcode',p.barcode,'karat',p.karat,'weight',p.weight_grams,'price',pr,'description',descr)));
  if meth='mixed' then body := body || jsonb_build_object('cash_paid', round(pr*0.4), 'bank_paid', pr - round(pr*0.4)); end if;
  perform public.post_sale_invoice(body);
end $g$ $f$;
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 24, 476.0, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 22, 436.33, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 21, 416.5, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 18, 357.0, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
perform pg_temp.gm_shift(S, (timestamp '2026-11-22 09:00') at time zone 'Asia/Dubai');
perform trader_receive_stock((select id from traders where store_id=S and name='مؤسسة الرواسي للذهب'), '[{"kind": "piece", "karat": 21, "weight": 4.15, "acc_weight": 4.15, "fab_per_gram": 12, "description_ar": "خاتم فراشة 21K", "box_name": "الخواتم"}, {"kind": "piece", "karat": 18, "weight": 3.05, "acc_weight": 2.9, "fab_per_gram": 14, "description_ar": "حلق نجمة 18K", "box_name": "الحلق"}, {"kind": "piece", "karat": 21, "weight": 9.8, "acc_weight": 9.8, "fab_per_gram": 13, "description_ar": "سلسال كارتييه 21K", "box_name": "السلاسل"}, {"kind": "piece", "karat": 21, "weight": 13.2, "acc_weight": 13.05, "fab_per_gram": 15, "description_ar": "إسوارة نقشة شامية 21K", "box_name": "الأساور"}, {"kind": "piece", "karat": 18, "weight": 3.9, "acc_weight": 3.9, "fab_per_gram": 16, "description_ar": "خاتم مرصّع زركون 18K", "box_name": "الخواتم"}, {"kind": "piece", "karat": 21, "weight": 31.6, "acc_weight": 31.35, "fab_per_gram": 17, "description_ar": "مباريم نقشة خليجية 21K", "box_name": "الأساور"}]'::jsonb, 0, 'R-1122', 'استلام تشكيلة الأسبوع');
update pieces set photo_url='https://images.unsplash.com/photo-1611955167811-4711904bb9f8?w=800&q=80&fm=jpg', piece_type='خاتم' where store_id=S and description_ar='خاتم فراشة 21K';
update pieces set photo_url='https://images.unsplash.com/photo-1671644730555-916aa8d8157f?w=800&q=80&fm=jpg', piece_type='حلق' where store_id=S and description_ar='حلق نجمة 18K';
update pieces set photo_url='https://images.unsplash.com/photo-1773929345739-94db8a4ccd0c?w=800&q=80&fm=jpg', piece_type='سلسال' where store_id=S and description_ar='سلسال كارتييه 21K';
update pieces set photo_url='https://images.unsplash.com/photo-1777999802051-f6f0296e76af?w=800&q=80&fm=jpg', piece_type='إسوارة' where store_id=S and description_ar='إسوارة نقشة شامية 21K';
update pieces set photo_url='https://images.unsplash.com/photo-1631982690223-8aa4be0a2497?w=800&q=80&fm=jpg', piece_type='خاتم' where store_id=S and description_ar='خاتم مرصّع زركون 18K';
update pieces set photo_url='https://images.unsplash.com/photo-1679156271456-d6068c543ee7?w=800&q=80&fm=jpg', piece_type='مباريم' where store_id=S and description_ar='مباريم نقشة خليجية 21K';
perform pg_temp.gm_shift(S, (timestamp '2026-11-22 09:45') at time zone 'Asia/Dubai');
perform pg_temp.gm_sell(S, 'دانة اليماحي', 'سلسال فراشة 18K', 'mixed');
perform pg_temp.gm_shift(S, (timestamp '2026-11-22 12:30') at time zone 'Asia/Dubai');
perform cash_voucher(jsonb_build_object('store_id', S, 'kind', 'in', 'party', 'customer', 'party_id', (select id from customers where store_id=S and name='حمدان الفلاسي'), 'amount', 2000, 'method', 'cash', 'notes', 'دفعة على الحساب'));
perform pg_temp.gm_shift(S, (timestamp '2026-11-22 16:10') at time zone 'Asia/Dubai');
end $d$;

-- 2026-11-23
do $d$ declare r jsonb; S uuid := '481681c1-bbd2-4d3f-98a7-0362ac0da632'; begin
perform set_config('request.jwt.claims', json_build_object('sub', '92164ef6-df33-43d1-a5a7-d66199974ec5', 'role', 'authenticated')::text, true);
execute $f$ create or replace function pg_temp.gm_shift(sid uuid, ts timestamptz) returns void language plpgsql as $g$ declare t text; begin foreach t in array array['cash_movements','customer_debts','daily_cash_log','piece_movements','trader_movements'] loop execute format('update public.%I set created_at=$1, entered_at=$1 where store_id=$2 and created_at=now()', t) using ts, sid; end loop; foreach t in array array['customer_deposits','customers','customer_phones','expense_entries','gold_stock_lots','invoices','pieces','stock_vouchers','stock_parties','traders','piece_intake_batches','piece_lot_draws','trader_scrap_draws','audit_log'] loop begin execute format('update public.%I set created_at=$1 where store_id=$2 and created_at=now()', t) using ts, sid; exception when undefined_column or undefined_table then null; end; end loop; update public.gold_prices set updated_at = ts where store_id = sid and updated_at = now(); end $g$ $f$;
execute $f$ create or replace function pg_temp.gm_sell(sid uuid, cust text, descr text, meth text) returns void language plpgsql as $g$
declare p record; pr numeric; cu uuid; body jsonb; begin
  select id, barcode, karat, weight_grams into p from public.pieces where store_id=sid and description_ar=descr and status='available' limit 1;
  if p.id is null then raise notice 'skip %', descr; return; end if;
  select id into cu from public.customers where store_id=sid and name=cust limit 1;
  if cu is null then insert into public.customers (store_id, name, phone, phone_country_code) values (sid, cust, '05' || (50000000 + floor(random()*49999999))::bigint::text, '+971') returning id into cu; end if;
  pr := round(p.weight_grams * ((select price_per_gram from public.gold_prices where store_id=sid and karat=p.karat) + case when p.karat=18 then 42 else 34 end));
  body := jsonb_build_object('store_id', sid, 'client_ref', gen_random_uuid(), 'customer_id', cu, 'payment_method', meth, 'confirm_low_price', true,
    'items', jsonb_build_array(jsonb_build_object('mode','manual','piece_id',p.id,'barcode',p.barcode,'karat',p.karat,'weight',p.weight_grams,'price',pr,'description',descr)));
  if meth='mixed' then body := body || jsonb_build_object('cash_paid', round(pr*0.4), 'bank_paid', pr - round(pr*0.4)); end if;
  perform public.post_sale_invoice(body);
end $g$ $f$;
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 24, 471.8, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 22, 432.48, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 21, 412.83, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 18, 353.85, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
perform pg_temp.gm_shift(S, (timestamp '2026-11-23 09:00') at time zone 'Asia/Dubai');
insert into customers (store_id, name, phone, phone_country_code) select S, 'لطيفة الحمادي', '0556180427', '+971' where not exists (select 1 from customers where store_id=S and name='لطيفة الحمادي');
r := post_sale_invoice(jsonb_build_object('store_id', S, 'client_ref', gen_random_uuid(), 'customer_id', (select id from customers where store_id=S and name='لطيفة الحمادي'), 'payment_method', 'credit', 'confirm_low_price', true, 'items', jsonb_build_array(jsonb_build_object('mode','manual','piece_id',(select id from pieces where store_id=S and description_ar='عقد تصميم إيطالي 21K' and status='available' limit 1),'barcode',(select barcode from pieces where id=(select id from pieces where store_id=S and description_ar='عقد تصميم إيطالي 21K' and status='available' limit 1)),'karat',(select karat from pieces where id=(select id from pieces where store_id=S and description_ar='عقد تصميم إيطالي 21K' and status='available' limit 1)),'weight',(select weight_grams from pieces where id=(select id from pieces where store_id=S and description_ar='عقد تصميم إيطالي 21K' and status='available' limit 1)),'price',12450,'description','عقد تصميم إيطالي 21K'))));
perform pg_temp.gm_shift(S, (timestamp '2026-11-23 11:15') at time zone 'Asia/Dubai');
perform cash_voucher(jsonb_build_object('store_id', S, 'kind', 'in', 'party', 'customer', 'party_id', (select id from customers where store_id=S and name='لطيفة الحمادي'), 'amount', 5000, 'method', 'bank', 'notes', 'دفعة أولى من ثمن العقد'));
perform pg_temp.gm_shift(S, (timestamp '2026-11-23 11:25') at time zone 'Asia/Dubai');
r := post_purchase_invoice(jsonb_build_object('store_id', S, 'client_ref', gen_random_uuid(), 'type', 'buyRetail', 'payment_method', 'cash', 'counterparty_name', 'عمر الحوسني', 'seller_id_type', 'emirates_id', 'seller_id_number', '784-1987-3392014-6', 'items', '[{"mode": "bulk", "karat": 21, "weight": 9.4, "price": 3764.14, "description": "كسر 21 — خاتمين وحلق قديم"}]'::jsonb));
perform pg_temp.gm_shift(S, (timestamp '2026-11-23 14:50') at time zone 'Asia/Dubai');
perform cash_voucher(jsonb_build_object('store_id', S, 'kind', 'out', 'party', 'expense', 'category_id', (select id from expense_categories where store_id=S and name='مواصلات'), 'amount', 60, 'notes', 'توصيل طلبية'));
perform pg_temp.gm_shift(S, (timestamp '2026-11-23 18:05') at time zone 'Asia/Dubai');
end $d$;

-- 2026-11-24
do $d$ declare r jsonb; S uuid := '481681c1-bbd2-4d3f-98a7-0362ac0da632'; begin
perform set_config('request.jwt.claims', json_build_object('sub', '92164ef6-df33-43d1-a5a7-d66199974ec5', 'role', 'authenticated')::text, true);
execute $f$ create or replace function pg_temp.gm_shift(sid uuid, ts timestamptz) returns void language plpgsql as $g$ declare t text; begin foreach t in array array['cash_movements','customer_debts','daily_cash_log','piece_movements','trader_movements'] loop execute format('update public.%I set created_at=$1, entered_at=$1 where store_id=$2 and created_at=now()', t) using ts, sid; end loop; foreach t in array array['customer_deposits','customers','customer_phones','expense_entries','gold_stock_lots','invoices','pieces','stock_vouchers','stock_parties','traders','piece_intake_batches','piece_lot_draws','trader_scrap_draws','audit_log'] loop begin execute format('update public.%I set created_at=$1 where store_id=$2 and created_at=now()', t) using ts, sid; exception when undefined_column or undefined_table then null; end; end loop; update public.gold_prices set updated_at = ts where store_id = sid and updated_at = now(); end $g$ $f$;
execute $f$ create or replace function pg_temp.gm_sell(sid uuid, cust text, descr text, meth text) returns void language plpgsql as $g$
declare p record; pr numeric; cu uuid; body jsonb; begin
  select id, barcode, karat, weight_grams into p from public.pieces where store_id=sid and description_ar=descr and status='available' limit 1;
  if p.id is null then raise notice 'skip %', descr; return; end if;
  select id into cu from public.customers where store_id=sid and name=cust limit 1;
  if cu is null then insert into public.customers (store_id, name, phone, phone_country_code) values (sid, cust, '05' || (50000000 + floor(random()*49999999))::bigint::text, '+971') returning id into cu; end if;
  pr := round(p.weight_grams * ((select price_per_gram from public.gold_prices where store_id=sid and karat=p.karat) + case when p.karat=18 then 42 else 34 end));
  body := jsonb_build_object('store_id', sid, 'client_ref', gen_random_uuid(), 'customer_id', cu, 'payment_method', meth, 'confirm_low_price', true,
    'items', jsonb_build_array(jsonb_build_object('mode','manual','piece_id',p.id,'barcode',p.barcode,'karat',p.karat,'weight',p.weight_grams,'price',pr,'description',descr)));
  if meth='mixed' then body := body || jsonb_build_object('cash_paid', round(pr*0.4), 'bank_paid', pr - round(pr*0.4)); end if;
  perform public.post_sale_invoice(body);
end $g$ $f$;
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 24, 473.5, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 22, 434.04, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 21, 414.31, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 18, 355.12, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
perform pg_temp.gm_shift(S, (timestamp '2026-11-24 09:00') at time zone 'Asia/Dubai');
perform pg_temp.gm_sell(S, 'طارق المزروعي', 'محبس ناعم 21K', 'cash');
perform pg_temp.gm_shift(S, (timestamp '2026-11-24 10:20') at time zone 'Asia/Dubai');
perform pg_temp.gm_sell(S, 'حصة المنصوري', 'إسوارة تصميم إيطالي 21K', 'cash');
perform pg_temp.gm_shift(S, (timestamp '2026-11-24 15:35') at time zone 'Asia/Dubai');
perform cash_voucher(jsonb_build_object('store_id', S, 'kind', 'out', 'party', 'expense', 'category_id', (select id from expense_categories where store_id=S and name='كهرباء ومياه'), 'amount', 1240, 'notes', 'فاتورة الكهرباء والمياه'));
perform pg_temp.gm_shift(S, (timestamp '2026-11-24 17:00') at time zone 'Asia/Dubai');
end $d$;

-- 2026-11-25
do $d$ declare r jsonb; S uuid := '481681c1-bbd2-4d3f-98a7-0362ac0da632'; begin
perform set_config('request.jwt.claims', json_build_object('sub', '92164ef6-df33-43d1-a5a7-d66199974ec5', 'role', 'authenticated')::text, true);
execute $f$ create or replace function pg_temp.gm_shift(sid uuid, ts timestamptz) returns void language plpgsql as $g$ declare t text; begin foreach t in array array['cash_movements','customer_debts','daily_cash_log','piece_movements','trader_movements'] loop execute format('update public.%I set created_at=$1, entered_at=$1 where store_id=$2 and created_at=now()', t) using ts, sid; end loop; foreach t in array array['customer_deposits','customers','customer_phones','expense_entries','gold_stock_lots','invoices','pieces','stock_vouchers','stock_parties','traders','piece_intake_batches','piece_lot_draws','trader_scrap_draws','audit_log'] loop begin execute format('update public.%I set created_at=$1 where store_id=$2 and created_at=now()', t) using ts, sid; exception when undefined_column or undefined_table then null; end; end loop; update public.gold_prices set updated_at = ts where store_id = sid and updated_at = now(); end $g$ $f$;
execute $f$ create or replace function pg_temp.gm_sell(sid uuid, cust text, descr text, meth text) returns void language plpgsql as $g$
declare p record; pr numeric; cu uuid; body jsonb; begin
  select id, barcode, karat, weight_grams into p from public.pieces where store_id=sid and description_ar=descr and status='available' limit 1;
  if p.id is null then raise notice 'skip %', descr; return; end if;
  select id into cu from public.customers where store_id=sid and name=cust limit 1;
  if cu is null then insert into public.customers (store_id, name, phone, phone_country_code) values (sid, cust, '05' || (50000000 + floor(random()*49999999))::bigint::text, '+971') returning id into cu; end if;
  pr := round(p.weight_grams * ((select price_per_gram from public.gold_prices where store_id=sid and karat=p.karat) + case when p.karat=18 then 42 else 34 end));
  body := jsonb_build_object('store_id', sid, 'client_ref', gen_random_uuid(), 'customer_id', cu, 'payment_method', meth, 'confirm_low_price', true,
    'items', jsonb_build_array(jsonb_build_object('mode','manual','piece_id',p.id,'barcode',p.barcode,'karat',p.karat,'weight',p.weight_grams,'price',pr,'description',descr)));
  if meth='mixed' then body := body || jsonb_build_object('cash_paid', round(pr*0.4), 'bank_paid', pr - round(pr*0.4)); end if;
  perform public.post_sale_invoice(body);
end $g$ $f$;
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 24, 478.9, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 22, 438.99, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 21, 419.04, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 18, 359.17, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
perform pg_temp.gm_shift(S, (timestamp '2026-11-25 09:00') at time zone 'Asia/Dubai');
perform pg_temp.gm_sell(S, 'جواهر الطنيجي', 'مباريم سحب يدوي 21K', 'mixed');
perform pg_temp.gm_shift(S, (timestamp '2026-11-25 11:00') at time zone 'Asia/Dubai');
perform cash_voucher(jsonb_build_object('store_id', S, 'kind', 'out', 'party', 'trader', 'party_id', (select id from traders where store_id=S and name='مؤسسة الرواسي للذهب'), 'amount', 3000, 'method', 'cash', 'notes', 'دفعة على حساب المصنعية'));
perform pg_temp.gm_shift(S, (timestamp '2026-11-25 13:40') at time zone 'Asia/Dubai');
perform cash_voucher(jsonb_build_object('store_id', S, 'kind', 'out', 'party', 'expense', 'category_id', (select id from expense_categories where store_id=S and name='تسويق وإعلان'), 'amount', 450, 'notes', 'إعلان إنستغرام'));
perform pg_temp.gm_shift(S, (timestamp '2026-11-25 16:30') at time zone 'Asia/Dubai');
end $d$;

-- 2026-11-26
do $d$ declare r jsonb; S uuid := '481681c1-bbd2-4d3f-98a7-0362ac0da632'; begin
perform set_config('request.jwt.claims', json_build_object('sub', '92164ef6-df33-43d1-a5a7-d66199974ec5', 'role', 'authenticated')::text, true);
execute $f$ create or replace function pg_temp.gm_shift(sid uuid, ts timestamptz) returns void language plpgsql as $g$ declare t text; begin foreach t in array array['cash_movements','customer_debts','daily_cash_log','piece_movements','trader_movements'] loop execute format('update public.%I set created_at=$1, entered_at=$1 where store_id=$2 and created_at=now()', t) using ts, sid; end loop; foreach t in array array['customer_deposits','customers','customer_phones','expense_entries','gold_stock_lots','invoices','pieces','stock_vouchers','stock_parties','traders','piece_intake_batches','piece_lot_draws','trader_scrap_draws','audit_log'] loop begin execute format('update public.%I set created_at=$1 where store_id=$2 and created_at=now()', t) using ts, sid; exception when undefined_column or undefined_table then null; end; end loop; update public.gold_prices set updated_at = ts where store_id = sid and updated_at = now(); end $g$ $f$;
execute $f$ create or replace function pg_temp.gm_sell(sid uuid, cust text, descr text, meth text) returns void language plpgsql as $g$
declare p record; pr numeric; cu uuid; body jsonb; begin
  select id, barcode, karat, weight_grams into p from public.pieces where store_id=sid and description_ar=descr and status='available' limit 1;
  if p.id is null then raise notice 'skip %', descr; return; end if;
  select id into cu from public.customers where store_id=sid and name=cust limit 1;
  if cu is null then insert into public.customers (store_id, name, phone, phone_country_code) values (sid, cust, '05' || (50000000 + floor(random()*49999999))::bigint::text, '+971') returning id into cu; end if;
  pr := round(p.weight_grams * ((select price_per_gram from public.gold_prices where store_id=sid and karat=p.karat) + case when p.karat=18 then 42 else 34 end));
  body := jsonb_build_object('store_id', sid, 'client_ref', gen_random_uuid(), 'customer_id', cu, 'payment_method', meth, 'confirm_low_price', true,
    'items', jsonb_build_array(jsonb_build_object('mode','manual','piece_id',p.id,'barcode',p.barcode,'karat',p.karat,'weight',p.weight_grams,'price',pr,'description',descr)));
  if meth='mixed' then body := body || jsonb_build_object('cash_paid', round(pr*0.4), 'bank_paid', pr - round(pr*0.4)); end if;
  perform public.post_sale_invoice(body);
end $g$ $f$;
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 24, 480.3, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 22, 440.28, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 21, 420.26, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 18, 360.22, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
perform pg_temp.gm_shift(S, (timestamp '2026-11-26 09:00') at time zone 'Asia/Dubai');
perform pg_temp.gm_sell(S, 'نوف العامري', 'خاتم فراشة 21K', 'bank');
perform pg_temp.gm_shift(S, (timestamp '2026-11-26 10:55') at time zone 'Asia/Dubai');
perform pg_temp.gm_sell(S, 'ريتا خوري', 'حلق مخرّم 18K', 'cash');
perform pg_temp.gm_shift(S, (timestamp '2026-11-26 12:20') at time zone 'Asia/Dubai');
perform cash_voucher(jsonb_build_object('store_id', S, 'kind', 'in', 'party', 'customer', 'party_id', (select id from customers where store_id=S and name='لطيفة الحمادي'), 'amount', 3000, 'method', 'cash', 'notes', 'دفعة ثانية من ثمن العقد'));
perform pg_temp.gm_shift(S, (timestamp '2026-11-26 17:45') at time zone 'Asia/Dubai');
end $d$;

-- 2026-11-27
do $d$ declare r jsonb; S uuid := '481681c1-bbd2-4d3f-98a7-0362ac0da632'; begin
perform set_config('request.jwt.claims', json_build_object('sub', '92164ef6-df33-43d1-a5a7-d66199974ec5', 'role', 'authenticated')::text, true);
execute $f$ create or replace function pg_temp.gm_shift(sid uuid, ts timestamptz) returns void language plpgsql as $g$ declare t text; begin foreach t in array array['cash_movements','customer_debts','daily_cash_log','piece_movements','trader_movements'] loop execute format('update public.%I set created_at=$1, entered_at=$1 where store_id=$2 and created_at=now()', t) using ts, sid; end loop; foreach t in array array['customer_deposits','customers','customer_phones','expense_entries','gold_stock_lots','invoices','pieces','stock_vouchers','stock_parties','traders','piece_intake_batches','piece_lot_draws','trader_scrap_draws','audit_log'] loop begin execute format('update public.%I set created_at=$1 where store_id=$2 and created_at=now()', t) using ts, sid; exception when undefined_column or undefined_table then null; end; end loop; update public.gold_prices set updated_at = ts where store_id = sid and updated_at = now(); end $g$ $f$;
execute $f$ create or replace function pg_temp.gm_sell(sid uuid, cust text, descr text, meth text) returns void language plpgsql as $g$
declare p record; pr numeric; cu uuid; body jsonb; begin
  select id, barcode, karat, weight_grams into p from public.pieces where store_id=sid and description_ar=descr and status='available' limit 1;
  if p.id is null then raise notice 'skip %', descr; return; end if;
  select id into cu from public.customers where store_id=sid and name=cust limit 1;
  if cu is null then insert into public.customers (store_id, name, phone, phone_country_code) values (sid, cust, '05' || (50000000 + floor(random()*49999999))::bigint::text, '+971') returning id into cu; end if;
  pr := round(p.weight_grams * ((select price_per_gram from public.gold_prices where store_id=sid and karat=p.karat) + case when p.karat=18 then 42 else 34 end));
  body := jsonb_build_object('store_id', sid, 'client_ref', gen_random_uuid(), 'customer_id', cu, 'payment_method', meth, 'confirm_low_price', true,
    'items', jsonb_build_array(jsonb_build_object('mode','manual','piece_id',p.id,'barcode',p.barcode,'karat',p.karat,'weight',p.weight_grams,'price',pr,'description',descr)));
  if meth='mixed' then body := body || jsonb_build_object('cash_paid', round(pr*0.4), 'bank_paid', pr - round(pr*0.4)); end if;
  perform public.post_sale_invoice(body);
end $g$ $f$;
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 24, 482.1, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 22, 441.93, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 21, 421.84, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 18, 361.58, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
perform pg_temp.gm_shift(S, (timestamp '2026-11-27 09:00') at time zone 'Asia/Dubai');
perform pg_temp.gm_sell(S, 'منصور الشحي', 'سلسال هلال 21K', 'cash');
perform pg_temp.gm_shift(S, (timestamp '2026-11-27 10:30') at time zone 'Asia/Dubai');
perform pg_temp.gm_sell(S, 'ميثاء الكعبي', 'حلق نجمة 18K', 'bank');
perform pg_temp.gm_shift(S, (timestamp '2026-11-27 12:15') at time zone 'Asia/Dubai');
perform cash_voucher(jsonb_build_object('store_id', S, 'kind', 'in', 'party', 'customer', 'party_id', (select id from customers where store_id=S and name='حمدان الفلاسي'), 'amount', 2317, 'method', 'bank', 'notes', 'تسديد باقي الحساب'));
perform pg_temp.gm_shift(S, (timestamp '2026-11-27 15:40') at time zone 'Asia/Dubai');
perform cash_voucher(jsonb_build_object('store_id', S, 'kind', 'out', 'party', 'expense', 'category_id', (select id from expense_categories where store_id=S and name='ضيافة'), 'amount', 80, 'notes', 'ضيافة'));
perform pg_temp.gm_shift(S, (timestamp '2026-11-27 16:50') at time zone 'Asia/Dubai');
end $d$;
