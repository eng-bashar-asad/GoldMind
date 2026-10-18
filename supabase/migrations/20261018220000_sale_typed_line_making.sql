-- Typed (manual) gold lines on a sale keep their making charge (المصنعية).
-- Before: fabrication_fee was stored only for lines drawn from a pooled lot; a typed line or a
-- non-pooled lot slice always got 0. Now any non-piece, non-diamond line keeps manual_fab_fee
-- (empty = 0, negative refused). Pieces and diamonds stay 0 as before. Same signature and grants.
create or replace function public.post_sale_invoice(p jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  sid uuid := nullif(p->>'store_id','')::uuid;
  ref uuid := nullif(p->>'client_ref','')::uuid;
  pm text := p->>'payment_method';
  cust uuid := nullif(p->>'customer_id','')::uuid;
  allow_low boolean := coalesce((p->>'confirm_low_price')::boolean, false);
  cash_amt numeric := round(coalesce(nullif(p->>'cash_paid','')::numeric, 0), 2);
  bank_amt numeric := round(coalesce(nullif(p->>'bank_paid','')::numeric, 0), 2);
  sold_at timestamptz := coalesce(nullif(p->>'sold_at','')::timestamptz, now());
  me uuid; inv_id uuid; inv_no text; ex record;
  it jsonb; mode text; price numeric; total numeric := 0; paid numeric; remaining numeric := 0;
  pc record; dp record; lot record;
  k int; w numeric; aw numeric; gp numeric; lows text := '';
  lines jsonb := '[]'::jsonb;
  chk numeric;
begin
  if sid is null then raise exception 'المحل غير محدد'; end if;
  if not has_permission('create_invoice', sid) then
    raise exception 'ليس لديك صلاحية إنشاء فاتورة بيع' using errcode = '42501';
  end if;
  if ref is not null then
    select id, invoice_number into ex from invoices where client_ref = ref and store_id = sid;
    if found then return jsonb_build_object('id', ex.id, 'invoice_number', ex.invoice_number, 'duplicate', true); end if;
  end if;
  if pm is null or pm not in ('cash','bank','credit','mixed') then raise exception 'طريقة دفع غير معروفة'; end if;
  -- a customer added on the sale screen while offline is created with the sale
  if cust is null and nullif(trim(p->'new_customer'->>'name'), '') is not null then
    select id into cust from customers where store_id = sid and name = trim(p->'new_customer'->>'name')
      and coalesce(phone, '') = coalesce(nullif(trim(p->'new_customer'->>'phone'), ''), '') limit 1;
  end if;
  if cust is null and nullif(trim(p->'new_customer'->>'name'), '') is not null then
    insert into customers (store_id, name, phone) values (sid, trim(p->'new_customer'->>'name'), nullif(trim(p->'new_customer'->>'phone'), ''))
    returning id into cust;
  end if;
  if cust is null or not exists (select 1 from customers where id = cust and store_id = sid) then
    raise exception 'الرجاء اختيار عميل من نفس المحل';
  end if;
  if jsonb_typeof(p->'items') <> 'array' or jsonb_array_length(p->'items') = 0 then
    raise exception 'الفاتورة فاضية — ضيف قطعة وحدة على الأقل';
  end if;
  -- offline sales keep their real time, but never in the future or older than 14 days
  if sold_at > now() + interval '5 minutes' or sold_at < now() - interval '14 days' then sold_at := now(); end if;
  select id into me from staff where user_id = auth.uid() and store_id = sid limit 1;

  -- 1) validate + lock every line, build the rows to insert
  for it in select * from jsonb_array_elements(p->'items') loop
    mode := coalesce(it->>'mode', 'manual');
    price := round((it->>'price')::numeric, 2);
    if price is null or price < 0 then raise exception 'سعر غير صحيح بأحد السطور'; end if;
    if coalesce(nullif(it->>'manual_fab_fee','')::numeric, 0) < 0 then raise exception 'المصنعية لا تكون بالسالب'; end if;
    k := nullif(it->>'karat','')::int; w := nullif(it->>'weight','')::numeric; aw := coalesce(nullif(it->>'accounting_weight','')::numeric, w);

    if mode = 'diamond' then
      select * into dp from diamond_pieces where id = (it->>'diamond_piece_id')::uuid and store_id = sid for update;
      if not found then raise exception 'قطعة الماس غير موجودة'; end if;
      if dp.status <> 'available' then raise exception 'القطعة % غير متاحة للبيع (حالتها: %)', coalesce(dp.barcode, dp.id::text), dp.status; end if;
      if lines @> jsonb_build_array(jsonb_build_object('diamond_piece_id', dp.id::text)) then raise exception 'القطعة % مكررة بنفس الفاتورة', coalesce(dp.barcode, dp.id::text); end if;
      k := case when dp.has_gold then dp.gold_karat end;
      w := case when dp.has_gold then dp.gold_weight_grams end; aw := w;
    elsif it ? 'piece_id' and nullif(it->>'piece_id','') is not null then
      select * into pc from pieces where id = (it->>'piece_id')::uuid and store_id = sid for update;
      if not found then raise exception 'القطعة غير موجودة بهالمحل'; end if;
      if pc.status <> 'available' then raise exception 'القطعة % غير متاحة للبيع (حالتها: %)', pc.barcode, pc.status; end if;
      if lines @> jsonb_build_array(jsonb_build_object('piece_id', pc.id::text)) then raise exception 'القطعة % مكررة بنفس الفاتورة', pc.barcode; end if;
      k := pc.karat; w := pc.weight_grams; aw := coalesce(pc.accounting_weight_grams, pc.weight_grams);
    end if;
    if mode = 'stock' then
      select * into lot from gold_stock_lots where id = (it->>'lot_id')::uuid and store_id = sid;
      if not found then raise exception 'رصيد الجملة غير موجود'; end if;
    end if;

    gp := case when k is null then null else (select price_per_gram from gold_prices where store_id = sid and karat = k) end;
    -- currency-mistake guard: a gold line sold under half its gold value
    if gp is not null and aw is not null and aw > 0 and price < gp * aw * 0.5 then
      lows := lows || format(E'\n• %s: %s بدل قيمة ذهب تقريبية %s', coalesce(it->>'barcode', it->>'description', k || 'K'), price, round(gp * aw, 2));
    end if;
    total := total + price;
    lines := lines || jsonb_build_object(
      'piece_id', case when mode <> 'diamond' then nullif(it->>'piece_id','') end,
      'diamond_piece_id', case when mode = 'diamond' then it->>'diamond_piece_id' end,
      'lot_id', case when mode = 'stock' then it->>'lot_id' end,
      'is_pooled', coalesce((it->>'is_pooled')::boolean, false),
      'fee', case when mode = 'diamond' or nullif(it->>'piece_id','') is not null then 0
                  else coalesce(nullif(it->>'manual_fab_fee','')::numeric, 0) end,
      'barcode', it->>'barcode', 'karat', k, 'weight', w, 'aw', aw, 'price', price, 'gp', gp,
      'description', it->>'description', 'description_en', it->>'description_en', 'photo', it->>'photo_url');
  end loop;

  if lows <> '' and not allow_low then
    raise exception 'LOW_PRICE:%', lows using errcode = 'P0001';
  end if;

  total := round(total, 2);
  if pm = 'mixed' then
    if cash_amt < 0 or bank_amt < 0 then raise exception 'مبلغ دفع غير صحيح'; end if;
    if cash_amt + bank_amt > total + 0.01 then raise exception 'المبلغ المدفوع أكبر من إجمالي الفاتورة'; end if;
    remaining := greatest(0, total - cash_amt - bank_amt);
    paid := cash_amt + bank_amt;
  else
    paid := case when pm = 'credit' then 0 else total end;
    remaining := case when pm = 'credit' then total else 0 end;
  end if;

  -- 2) write everything
  inv_no := next_invoice_number(sid, 'INV');
  insert into invoices (store_id, invoice_number, type, customer_id, payment_method, cash_paid_amount, bank_paid_amount,
      gold_value, fabrication_fees, vat_amount, total_amount, amount_paid, status, created_by, created_at, client_ref)
    values (sid, inv_no, 'sale', cust, pm, case when pm = 'mixed' then cash_amt end, case when pm = 'mixed' then bank_amt end,
      0, 0, 0, total, paid, case when remaining > 0.01 then 'unpaid' else 'paid' end, me, sold_at, ref)
    returning id into inv_id;

  -- paid in several currencies: [{currency, amount, rate (per 1 shop currency), method cash|bank}]
  if jsonb_typeof(p->'pay_breakdown') = 'array' and jsonb_array_length(p->'pay_breakdown') > 0 then
    if pm = 'credit' then raise exception 'الدين لا يُقسّم على عملات'; end if;
    if abs(coalesce((select sum((b->>'amount')::numeric / (b->>'rate')::numeric) from jsonb_array_elements(p->'pay_breakdown') b where b->>'method' = 'cash'), 0) - case pm when 'cash' then total when 'mixed' then cash_amt else 0 end) > 0.05
       or abs(coalesce((select sum((b->>'amount')::numeric / (b->>'rate')::numeric) from jsonb_array_elements(p->'pay_breakdown') b where b->>'method' = 'bank'), 0) - case pm when 'bank' then total when 'mixed' then bank_amt else 0 end) > 0.05 then
      raise exception 'مبالغ العملات لا تطابق المدفوع';
    end if;
    update invoices set pay_breakdown = p->'pay_breakdown' where id = inv_id;
  end if;
  if nullif(upper(p->>'pay_currency'), '') is not null and (p->>'pay_fx_rate')::numeric > 0 then
    update invoices set pay_currency = upper(p->>'pay_currency'), pay_fx_rate = (p->>'pay_fx_rate')::numeric where id = inv_id;
  end if;

  insert into invoice_items (invoice_id, piece_id, diamond_piece_id, gold_stock_lot_id, barcode, karat, weight_grams,
      accounting_weight_grams, fabrication_fee, line_total, description, description_en, item_photo_url, gold_price_per_gram)
  select inv_id, (l->>'piece_id')::uuid, (l->>'diamond_piece_id')::uuid, (l->>'lot_id')::uuid, l->>'barcode', (l->>'karat')::int,
      (l->>'weight')::numeric, (l->>'aw')::numeric, (l->>'fee')::numeric, (l->>'price')::numeric, l->>'description',
      l->>'description_en', l->>'photo', (l->>'gp')::numeric
  from jsonb_array_elements(lines) l;

  update pieces set status = 'sold' where id in (select (l->>'piece_id')::uuid from jsonb_array_elements(lines) l where l->>'piece_id' is not null);
  insert into piece_movements (store_id, piece_id, event_type, note, created_by)
    select sid, (l->>'piece_id')::uuid, 'sold', 'بيع بفاتورة ' || inv_no, me from jsonb_array_elements(lines) l where l->>'piece_id' is not null;
  update diamond_pieces set status = 'sold' where id in (select (l->>'diamond_piece_id')::uuid from jsonb_array_elements(lines) l where l->>'diamond_piece_id' is not null);

  for it in select * from jsonb_array_elements(lines) l where l->>'lot_id' is not null loop
    if (it->>'is_pooled')::boolean then
      perform consume_gold_stock_lot_pooled((it->>'lot_id')::uuid, (it->>'weight')::numeric, (it->>'fee')::numeric);
    else
      perform consume_gold_stock_lot((it->>'lot_id')::uuid, (it->>'weight')::numeric);
    end if;
  end loop;

  if paid > 0 then
    insert into cash_movements (store_id, box, direction, amount, description, created_by, invoice_id, created_at)
    values (sid, 'main', 'in', paid,
      case when pm = 'mixed' then format('تحصيل جزئي لفاتورة بيع %s (%s)', inv_no, concat_ws(' + ', case when cash_amt > 0 then cash_amt || ' نقداً' end, case when bank_amt > 0 then bank_amt || ' فيزا/بنك' end))
           else 'تحصيل فاتورة بيع ' || inv_no end, me, inv_id, sold_at);
  end if;
  if remaining > 0.01 then
    insert into customer_debts (store_id, customer_id, invoice_id, movement_type, cash_amount, gold_grams_24k, notes, created_by)
    values (sid, cust, inv_id, 'debt_increase', remaining, 0,
      case when pm = 'credit' then 'فاتورة بيع ' || inv_no else format('متبقي فاتورة بيع %s (دُفع %s من %s)', inv_no, paid, total) end, me);
  end if;

  -- 3) self-check before commit: lines = total, paid + debt = total
  select coalesce(sum(line_total), 0) into chk from invoice_items where invoice_id = inv_id;
  if abs(chk - total) > 0.01 then raise exception 'فحص محاسبي فشل: مجموع السطور % ≠ الإجمالي %', chk, total; end if;
  if abs(paid + remaining - total) > 0.01 then raise exception 'فحص محاسبي فشل: المدفوع + الدين ≠ الإجمالي'; end if;

  return jsonb_build_object('id', inv_id, 'invoice_number', inv_no, 'total', total, 'duplicate', false);
exception when unique_violation then
  if ref is not null then
    select id, invoice_number into ex from invoices where client_ref = ref and store_id = sid;
    if found then return jsonb_build_object('id', ex.id, 'invoice_number', ex.invoice_number, 'duplicate', true); end if;
  end if;
  raise;
end $$;
