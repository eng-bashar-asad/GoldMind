-- مجوهرات بيسان — extra demo activity for the last 7 days up to today (inserts only, no deletes). Run once.

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
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 24, 466.2, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 22, 427.35, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 21, 407.92, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 18, 349.65, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();

perform pg_temp.gm_sell(S, 'سلمى الزعابي', 'حلق هلال 21K', 'cash');
perform pg_temp.gm_shift(S, (((now() at time zone 'Asia/Dubai')::date - 6) + time '10:20') at time zone 'Asia/Dubai');
perform pg_temp.gm_sell(S, 'نورة الكعبي', 'إسوارة نقشة ورد 18K', 'bank');
perform pg_temp.gm_shift(S, (((now() at time zone 'Asia/Dubai')::date - 6) + time '12:45') at time zone 'Asia/Dubai');
perform cash_voucher(jsonb_build_object('store_id', S, 'kind', 'out', 'party', 'expense', 'category_id', (select id from expense_categories where store_id=S and name='ضيافة'), 'amount', 120, 'notes', 'ضيافة الزبائن'));
perform pg_temp.gm_shift(S, (((now() at time zone 'Asia/Dubai')::date - 6) + time '17:30') at time zone 'Asia/Dubai');
end $d$;

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
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 24, 463.8, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 22, 425.15, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 21, 405.83, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 18, 347.85, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();

perform trader_receive_stock((select id from traders where store_id=S and name='الياقوت للمعادن الثمينة'), '[{"kind": "piece", "karat": 18, "weight": 4.86, "acc_weight": 4.86, "fab_per_gram": 10, "description_ar": "خاتم ورد ملكي 18K", "box_name": "الخواتم"}, {"kind": "piece", "karat": 18, "weight": 3.12, "acc_weight": 2.95, "fab_per_gram": 12, "description_ar": "حلق لؤلؤ ناعم 18K", "box_name": "الحلق"}, {"kind": "piece", "karat": 21, "weight": 6.75, "acc_weight": 6.75, "fab_per_gram": 14, "description_ar": "سلسال حرف عربي 21K", "box_name": "السلاسل"}, {"kind": "piece", "karat": 21, "weight": 11.4, "acc_weight": 11.4, "fab_per_gram": 15, "description_ar": "إسوارة مجدولة 21K", "box_name": "الأساور"}, {"kind": "piece", "karat": 21, "weight": 24.3, "acc_weight": 24.05, "fab_per_gram": 18, "description_ar": "عقد ملكي 21K", "box_name": "السلاسل"}, {"kind": "piece", "karat": 21, "weight": 4.2, "acc_weight": 4.2, "fab_per_gram": 9, "description_ar": "محبس سادة لامع 21K", "box_name": "الخواتم"}]'::jsonb, 0, 'Y-1120', 'استلام تشكيلة جديدة');
update pieces set photo_url='https://images.unsplash.com/photo-1603561596973-8166e9e089d1?w=800&q=80&fm=jpg', piece_type='خاتم' where store_id=S and description_ar='خاتم ورد ملكي 18K';
update pieces set photo_url='https://images.unsplash.com/photo-1653227907864-560dce4c252d?w=800&q=80&fm=jpg', piece_type='حلق' where store_id=S and description_ar='حلق لؤلؤ ناعم 18K';
update pieces set photo_url='https://images.unsplash.com/photo-1685970731194-e27b477e87ba?w=800&q=80&fm=jpg', piece_type='سلسال' where store_id=S and description_ar='سلسال حرف عربي 21K';
update pieces set photo_url='https://images.unsplash.com/photo-1602173574767-37ac01994b2a?w=800&q=80&fm=jpg', piece_type='إسوارة' where store_id=S and description_ar='إسوارة مجدولة 21K';
update pieces set photo_url='https://images.unsplash.com/photo-1771734065116-61e16b353ded?w=800&q=80&fm=jpg', piece_type='عقد' where store_id=S and description_ar='عقد ملكي 21K';
update pieces set photo_url='https://images.unsplash.com/photo-1622398925373-3f91b1e275f5?w=800&q=80&fm=jpg', piece_type='محبس' where store_id=S and description_ar='محبس سادة لامع 21K';
perform pg_temp.gm_shift(S, (((now() at time zone 'Asia/Dubai')::date - 5) + time '09:50') at time zone 'Asia/Dubai');
perform pg_temp.gm_sell(S, 'خالد المهيري', 'عقد نقشة تركية 21K', 'mixed');
perform pg_temp.gm_shift(S, (((now() at time zone 'Asia/Dubai')::date - 5) + time '11:15') at time zone 'Asia/Dubai');
perform cash_voucher(jsonb_build_object('store_id', S, 'kind', 'out', 'party', 'expense', 'category_id', (select id from expense_categories where store_id=S and name='كهرباء ومياه'), 'amount', 1350, 'notes', 'فاتورة ديوا'));
perform pg_temp.gm_shift(S, (((now() at time zone 'Asia/Dubai')::date - 5) + time '16:00') at time zone 'Asia/Dubai');
end $d$;

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
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 24, 468.5, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 22, 429.46, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 21, 409.94, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 18, 351.38, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();

perform pg_temp.gm_sell(S, 'مريم الشامسي', 'خاتم فراشة 18K', 'cash');
perform pg_temp.gm_shift(S, (((now() at time zone 'Asia/Dubai')::date - 4) + time '10:40') at time zone 'Asia/Dubai');
perform pg_temp.gm_sell(S, 'حمدان السويدي', 'مباريم مخرّم 21K', 'mixed');
perform pg_temp.gm_shift(S, (((now() at time zone 'Asia/Dubai')::date - 4) + time '13:20') at time zone 'Asia/Dubai');
perform cash_voucher(jsonb_build_object('store_id', S, 'kind', 'out', 'party', 'expense', 'category_id', (select id from expense_categories where store_id=S and name='مواصلات'), 'amount', 85, 'notes', 'توصيل طلبية'));
perform pg_temp.gm_shift(S, (((now() at time zone 'Asia/Dubai')::date - 4) + time '18:10') at time zone 'Asia/Dubai');
end $d$;

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
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 24, 470.1, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 22, 430.93, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 21, 411.34, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 18, 352.58, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();

perform pg_temp.gm_sell(S, 'لطيفة الحمادي', 'سلسال قلب 18K', 'cash');
perform pg_temp.gm_shift(S, (((now() at time zone 'Asia/Dubai')::date - 3) + time '11:05') at time zone 'Asia/Dubai');
perform pg_temp.gm_sell(S, 'عائشة النعيمي', 'حلق فراشة 18K', 'cash');
perform pg_temp.gm_shift(S, (((now() at time zone 'Asia/Dubai')::date - 3) + time '15:35') at time zone 'Asia/Dubai');
perform pg_temp.gm_sell(S, 'نورة الكعبي', 'خاتم ورد ملكي 18K', 'bank');
perform pg_temp.gm_shift(S, (((now() at time zone 'Asia/Dubai')::date - 3) + time '19:00') at time zone 'Asia/Dubai');
end $d$;

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
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 24, 467.4, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 22, 428.45, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 21, 408.97, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 18, 350.55, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();

perform cash_voucher(jsonb_build_object('store_id', S, 'kind', 'out', 'party', 'expense', 'category_id', (select id from expense_categories where store_id=S and name='رواتب'), 'amount', 12000, 'method', 'bank', 'notes', 'رواتب الموظفين'));
perform pg_temp.gm_shift(S, (((now() at time zone 'Asia/Dubai')::date - 2) + time '10:10') at time zone 'Asia/Dubai');
perform pg_temp.gm_sell(S, 'جورجيت عازار', 'طقم سادة لامع 18K', 'mixed');
perform pg_temp.gm_shift(S, (((now() at time zone 'Asia/Dubai')::date - 2) + time '12:30') at time zone 'Asia/Dubai');
perform pg_temp.gm_sell(S, 'سيف الكتبي', 'سلسال حرف عربي 21K', 'cash');
perform pg_temp.gm_shift(S, (((now() at time zone 'Asia/Dubai')::date - 2) + time '17:45') at time zone 'Asia/Dubai');
end $d$;

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
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 24, 471.9, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 22, 432.57, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 21, 412.91, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 18, 353.92, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();

perform pg_temp.gm_sell(S, 'سيف الكتبي', 'إسوارة كارتييه 21K', 'bank');
perform pg_temp.gm_shift(S, (((now() at time zone 'Asia/Dubai')::date - 1) + time '11:25') at time zone 'Asia/Dubai');
perform pg_temp.gm_sell(S, 'شما المزروعي', 'محبس كارتييه 18K', 'cash');
perform pg_temp.gm_shift(S, (((now() at time zone 'Asia/Dubai')::date - 1) + time '14:50') at time zone 'Asia/Dubai');
perform pg_temp.gm_sell(S, 'شما المزروعي', 'حلق لؤلؤ ناعم 18K', 'cash');
perform pg_temp.gm_shift(S, (((now() at time zone 'Asia/Dubai')::date - 1) + time '18:15') at time zone 'Asia/Dubai');
perform cash_voucher(jsonb_build_object('store_id', S, 'kind', 'out', 'party', 'expense', 'category_id', (select id from expense_categories where store_id=S and name='ضيافة'), 'amount', 95, 'notes', 'قهوة وحلويات'));
perform pg_temp.gm_shift(S, (((now() at time zone 'Asia/Dubai')::date - 1) + time '20:05') at time zone 'Asia/Dubai');
end $d$;

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
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 24, 473.0, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 22, 433.58, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 21, 413.88, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();
insert into gold_prices (store_id, karat, price_per_gram, mode) values (S, 18, 354.75, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();

perform pg_temp.gm_sell(S, 'نورة الكعبي', 'سلسال ناعم 21K', 'cash');
perform pg_temp.gm_shift(S, (((now() at time zone 'Asia/Dubai')::date - 0) + time '10:30') at time zone 'Asia/Dubai');
perform pg_temp.gm_sell(S, 'حمدان السويدي', 'إسوارة مجدولة 21K', 'mixed');
perform pg_temp.gm_shift(S, (((now() at time zone 'Asia/Dubai')::date - 0) + time '12:10') at time zone 'Asia/Dubai');
perform cash_voucher(jsonb_build_object('store_id', S, 'kind', 'out', 'party', 'expense', 'category_id', (select id from expense_categories where store_id=S and name='ضيافة'), 'amount', 60, 'notes', 'ضيافة'));
perform pg_temp.gm_shift(S, (((now() at time zone 'Asia/Dubai')::date - 0) + time '13:40') at time zone 'Asia/Dubai');
perform pg_temp.gm_sell(S, 'مريم الشامسي', 'عقد ملكي 21K', 'bank');
perform pg_temp.gm_shift(S, (((now() at time zone 'Asia/Dubai')::date - 0) + time '14:55') at time zone 'Asia/Dubai');
end $d$;
