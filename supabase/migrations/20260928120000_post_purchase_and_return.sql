-- Purchases and sales returns are posted by ONE database transaction each,
-- like sales (post_sale_invoice): either every row (invoice, items, stock,
-- cash, trader debt) is written, or none is. Before this, the pages wrote
-- them one call at a time from the browser, so a dropped connection could
-- leave half a purchase and ledgers that no longer balance.

-- ---------------------------------------------------------------- purchase
create or replace function public.post_purchase_invoice(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  sid uuid := nullif(p->>'store_id','')::uuid;
  ref uuid := nullif(p->>'client_ref','')::uuid;
  typ text := p->>'type';
  pm text := p->>'payment_method';
  tid uuid := nullif(p->>'trader_id','')::uuid;
  sid_type text := nullif(p->>'seller_id_type','');
  photos jsonb := case when jsonb_typeof(p->'bulk_photos') = 'array' and jsonb_array_length(p->'bulk_photos') > 0 then p->'bulk_photos' end;
  me uuid; inv_id uuid; inv_no text; ex record;
  it jsonb; mode text; price numeric; w numeric; k int; fee numeric; fee_vat numeric; carat numeric; ppc numeric;
  has_gold boolean;
  total numeric := 0; fab_total numeric := 0; vat_total numeric := 0;
  new_id uuid; bc text; chk numeric;
begin
  if sid is null then raise exception 'المحل غير محدد'; end if;
  if not has_permission('create_invoice', sid) then
    raise exception 'ليس لديك صلاحية إنشاء فاتورة شراء' using errcode = '42501';
  end if;
  if ref is not null then
    select id, invoice_number into ex from invoices where client_ref = ref and store_id = sid;
    if found then return jsonb_build_object('id', ex.id, 'invoice_number', ex.invoice_number, 'duplicate', true); end if;
  end if;
  if typ is null or typ not in ('buyTrader', 'buyRetail') then raise exception 'نوع فاتورة الشراء غير معروف'; end if;
  if pm is null or pm not in ('cash', 'credit') then raise exception 'طريقة دفع غير معروفة'; end if;
  if typ = 'buyTrader' then
    if tid is null or not exists (select 1 from traders where id = tid and store_id = sid) then
      raise exception 'الرجاء اختيار تاجر من نفس المحل';
    end if;
  else
    tid := null;
  end if;
  if sid_type is not null and sid_type not in ('emirates_id', 'passport', 'other') then
    raise exception 'نوع مستند الهوية غير معروف';
  end if;
  if jsonb_typeof(p->'items') is distinct from 'array' or jsonb_array_length(p->'items') = 0 then
    raise exception 'الفاتورة فارغة — أضف قطعة واحدة على الأقل';
  end if;
  select id into me from staff where user_id = auth.uid() and store_id = sid limit 1;

  -- 1) validate every line and add up the totals
  for it in select * from jsonb_array_elements(p->'items') loop
    mode := coalesce(it->>'mode', 'piece');
    if mode not in ('piece', 'bulk', 'diamond', 'diamond_bulk') then raise exception 'نوع سطر غير معروف: %', mode; end if;
    price := round(coalesce(nullif(it->>'price','')::numeric, 0), 2);
    fee := round(coalesce(nullif(it->>'fab_fee','')::numeric, 0), 2);
    fee_vat := case when typ = 'buyTrader' then round(coalesce(nullif(it->>'fab_fee_vat','')::numeric, 0), 2) else 0 end;
    if price < 0 or fee < 0 or fee_vat < 0 then raise exception 'مبلغ سالب بأحد السطور'; end if;
    if mode in ('piece', 'bulk') then
      w := nullif(it->>'weight','')::numeric; k := nullif(it->>'karat','')::int;
      if w is null or w <= 0 then raise exception 'وزن غير صحيح بأحد السطور'; end if;
      if k is null or k < 1 or k > 24 then raise exception 'عيار غير صحيح بأحد السطور'; end if;
    elsif mode = 'diamond' then
      carat := nullif(it->>'diamond_carat','')::numeric;
      if carat is null or carat <= 0 then raise exception 'وزن الماس غير صحيح'; end if;
      if coalesce((it->>'has_gold')::boolean, false) then
        w := nullif(it->>'gold_weight','')::numeric; k := nullif(it->>'gold_karat','')::int;
        if w is null or w <= 0 or k is null or k < 1 or k > 24 then raise exception 'وزن أو عيار ذهب قطعة الماس غير صحيح'; end if;
      end if;
    else
      carat := nullif(it->>'diamond_carat','')::numeric;
      if carat is null or carat <= 0 then raise exception 'قيراط صندوق الماس غير صحيح'; end if;
    end if;
    total := total + price;
    fab_total := fab_total + fee;
    vat_total := vat_total + fee_vat;
  end loop;
  total := round(total, 2);

  -- 2) write everything
  inv_no := next_invoice_number(sid, 'PINV');
  insert into invoices (store_id, invoice_number, type, trader_id, counterparty_name, seller_id_type, seller_id_number,
      payment_method, fabrication_fees, vat_amount, total_amount, amount_paid, status, attachment_url, bulk_photos,
      created_by, client_ref)
    values (sid, inv_no, typ, tid,
      case when typ = 'buyRetail' then nullif(trim(p->>'counterparty_name'), '') end,
      case when typ = 'buyRetail' then sid_type end,
      case when typ = 'buyRetail' then nullif(trim(p->>'seller_id_number'), '') end,
      pm, fab_total, case when typ = 'buyTrader' then vat_total else 0 end, total,
      case when pm = 'cash' then total else 0 end, case when pm = 'cash' then 'paid' else 'unpaid' end,
      nullif(p->>'attachment_url', ''), photos, me, ref)
    returning id into inv_id;

  for it in select * from jsonb_array_elements(p->'items') loop
    mode := coalesce(it->>'mode', 'piece');
    price := round(coalesce(nullif(it->>'price','')::numeric, 0), 2);
    fee := round(coalesce(nullif(it->>'fab_fee','')::numeric, 0), 2);
    fee_vat := case when typ = 'buyTrader' then round(coalesce(nullif(it->>'fab_fee_vat','')::numeric, 0), 2) else 0 end;
    w := nullif(it->>'weight','')::numeric; k := nullif(it->>'karat','')::int;

    if mode = 'piece' then
      bc := next_piece_barcode(sid, 'gold');
      insert into pieces (store_id, barcode, weight_grams, karat, description_ar, status, created_by)
        values (sid, bc, w, k, it->>'description', 'available', me) returning id into new_id;
      insert into invoice_items (invoice_id, piece_id, barcode, karat, weight_grams, accounting_weight_grams,
          fabrication_fee, fabrication_fee_vat, line_total, description)
        values (inv_id, new_id, bc, k, w, w, fee, fee_vat, price, it->>'description');

    elsif mode = 'bulk' then
      insert into gold_stock_lots (store_id, karat, weight_grams_total, weight_grams_remaining, cost_fabrication_per_gram,
          trader_id, source_invoice_id, notes, box_name, created_by)
        values (sid, k, w, w, coalesce(nullif(it->>'fab_per_gram','')::numeric, 0), tid, inv_id, it->>'description',
          case when typ = 'buyRetail' then 'كسر ' || k end, me)
        returning id into new_id;
      insert into invoice_items (invoice_id, gold_stock_lot_id, karat, weight_grams, accounting_weight_grams,
          fabrication_fee, fabrication_fee_vat, line_total, description)
        values (inv_id, new_id, k, w, w, fee, fee_vat, price, it->>'description');

    elsif mode = 'diamond_bulk' then
      carat := nullif(it->>'diamond_carat','')::numeric;
      ppc := nullif(it->>'diamond_price_per_carat','')::numeric;
      insert into diamond_stock_lots (store_id, box_name, total_carat, remaining_carat, price_per_carat, trader_id,
          source_invoice_id, notes, created_by)
        values (sid, nullif(trim(it->>'box_name'), ''), carat, carat, ppc, tid, inv_id, it->>'description', me)
        returning id into new_id;
      insert into invoice_items (invoice_id, diamond_stock_lot_id, fabrication_fee, line_total, description)
        values (inv_id, new_id, 0, price, it->>'description');

    else -- diamond piece
      has_gold := coalesce((it->>'has_gold')::boolean, false);
      w := case when has_gold then nullif(it->>'gold_weight','')::numeric end;
      k := case when has_gold then nullif(it->>'gold_karat','')::int end;
      bc := next_piece_barcode(sid, 'diamond');
      insert into diamond_pieces (store_id, barcode, has_gold, gold_weight_grams, gold_karat, gold_cost_fabrication_per_gram,
          diamond_carat, diamond_price_per_carat, shape, clarity, cut, color, certificate_lab, certificate_number,
          description_ar, status, created_by)
        values (sid, bc, has_gold, w, k, nullif(it->>'gold_fab_cost','')::numeric,
          nullif(it->>'diamond_carat','')::numeric, nullif(it->>'diamond_price_per_carat','')::numeric,
          nullif(it->>'shape',''), nullif(it->>'clarity',''), nullif(it->>'cut',''), nullif(it->>'color',''),
          nullif(it->>'cert_lab',''), nullif(it->>'cert_number',''), it->>'description', 'available', me)
        returning id into new_id;
      insert into invoice_items (invoice_id, diamond_piece_id, barcode, karat, weight_grams, accounting_weight_grams,
          fabrication_fee, line_total, description)
        values (inv_id, new_id, bc, k, w, w, 0, price, it->>'description');
    end if;

    -- credit purchase from a trader: what we now owe that trader (gold by
    -- weight, and cash for making charges / diamonds)
    if pm = 'credit' and typ = 'buyTrader' then
      insert into trader_movements (store_id, trader_id, invoice_id, movement_type, weight_grams, karat,
          gold_24k_equivalent, fab_fee_amount, notes, created_by)
        values (sid, tid, inv_id, 'debt_increase',
          case when mode in ('piece', 'bulk', 'diamond') then w end,
          case when mode in ('piece', 'bulk', 'diamond') then k end,
          case when mode in ('piece', 'bulk', 'diamond') and w is not null and k is not null then round(w * k / 24.0, 3) else 0 end,
          case when mode in ('diamond', 'diamond_bulk') then price else round(fee + fee_vat, 2) end,
          coalesce(nullif(it->>'description', ''), 'فاتورة شراء ' || inv_no), me);
    end if;
  end loop;

  if pm = 'cash' and total > 0 then
    insert into cash_movements (store_id, box, direction, amount, description, created_by, invoice_id)
      values (sid, 'main', 'out', total, 'دفع فاتورة شراء ' || inv_no, me, inv_id);
  end if;

  -- 3) self-check before commit
  select coalesce(sum(line_total), 0) into chk from invoice_items where invoice_id = inv_id;
  if abs(chk - total) > 0.01 then raise exception 'فحص محاسبي فشل: مجموع السطور % ≠ الإجمالي %', chk, total; end if;

  return jsonb_build_object('id', inv_id, 'invoice_number', inv_no, 'total', total, 'duplicate', false);
exception when unique_violation then
  if ref is not null then
    select id, invoice_number into ex from invoices where client_ref = ref and store_id = sid;
    if found then return jsonb_build_object('id', ex.id, 'invoice_number', ex.invoice_number, 'duplicate', true); end if;
  end if;
  raise;
end $function$;

-- ------------------------------------------------------------ sales return
create or replace function public.post_sales_return(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  sid uuid := nullif(p->>'store_id','')::uuid;
  ref uuid := nullif(p->>'client_ref','')::uuid;
  orig uuid := nullif(p->>'original_invoice_id','')::uuid;
  rm text := p->>'refund_method';
  reason text := nullif(trim(p->>'reason'), '');
  o record; ex record; lr record;
  ids uuid[]; me uuid; inv_id uuid; inv_no text;
  total numeric; chk numeric; sold numeric; back numeric; note text;
begin
  if sid is null then raise exception 'المحل غير محدد'; end if;
  if not (has_permission('create_invoice', sid) or has_permission('delete_invoice', sid)) then
    raise exception 'ليس لديك صلاحية تسجيل مرتجع' using errcode = '42501';
  end if;
  if ref is not null then
    select id, invoice_number into ex from invoices where client_ref = ref and store_id = sid;
    if found then return jsonb_build_object('id', ex.id, 'invoice_number', ex.invoice_number, 'duplicate', true); end if;
  end if;
  if rm is null or rm not in ('cash', 'bank', 'debt_reduce') then raise exception 'طريقة رد غير معروفة'; end if;

  -- lock the original sale: two returns of the same invoice queue up here
  select * into o from invoices where id = orig and store_id = sid for update;
  if not found then raise exception 'الفاتورة الأصلية غير موجودة'; end if;
  if o.type <> 'sale' then raise exception 'يمكن إرجاع فواتير البيع فقط'; end if;
  if o.status = 'cancelled' then raise exception 'الفاتورة الأصلية ملغاة'; end if;
  if rm = 'debt_reduce' and o.customer_id is null then raise exception 'لا يوجد عميل لتخفيض دينه'; end if;

  select array_agg(distinct x::uuid) into ids from jsonb_array_elements_text(coalesce(p->'item_ids', '[]'::jsonb)) x;
  if ids is null or cardinality(ids) = 0 then raise exception 'اختر قطعة واحدة على الأقل للإرجاع'; end if;
  if exists (select 1 from unnest(ids) i where not exists (select 1 from invoice_items where id = i and invoice_id = orig)) then
    raise exception 'أحد السطور المختارة ليس من الفاتورة الأصلية';
  end if;
  -- pieces / diamonds already returned (by a return that is still valid)
  if exists (
    select 1 from invoice_items s
      join invoice_items r on (r.piece_id = s.piece_id or r.diamond_piece_id = s.diamond_piece_id)
      join invoices ri on ri.id = r.invoice_id
     where s.id = any(ids) and ri.related_invoice_id = orig and ri.type = 'return' and ri.status <> 'cancelled') then
    raise exception 'بعض القطع المختارة أُرجعت مسبقاً';
  end if;
  -- bulk weight: never return more than was sold from each lot on this invoice
  for lr in select gold_stock_lot_id lid, sum(coalesce(weight_grams, 0)) w
              from invoice_items where id = any(ids) and gold_stock_lot_id is not null group by 1 loop
    select coalesce(sum(weight_grams), 0) into sold from invoice_items where invoice_id = orig and gold_stock_lot_id = lr.lid;
    select coalesce(sum(r.weight_grams), 0) into back from invoice_items r join invoices ri on ri.id = r.invoice_id
     where ri.related_invoice_id = orig and ri.type = 'return' and ri.status <> 'cancelled' and r.gold_stock_lot_id = lr.lid;
    if back + lr.w > sold + 0.0005 then raise exception 'وزن المرتجع من رصيد الجملة أكبر من الوزن المباع'; end if;
  end loop;

  select round(sum(line_total), 2) into total from invoice_items where id = any(ids);
  select id into me from staff where user_id = auth.uid() and store_id = sid limit 1;
  inv_no := next_invoice_number(sid, 'RET');
  note := 'مرتجع ' || inv_no || ' لفاتورة ' || o.invoice_number || coalesce(' — ' || reason, '');

  insert into invoices (store_id, invoice_number, type, related_invoice_id, customer_id, payment_method,
      total_amount, amount_paid, status, created_by, client_ref)
    values (sid, inv_no, 'return', orig, o.customer_id, case when rm = 'debt_reduce' then 'credit' else rm end,
      total, total, 'paid', me, ref)
    returning id into inv_id;

  insert into invoice_items (invoice_id, piece_id, gold_stock_lot_id, diamond_piece_id, barcode, karat, weight_grams,
      accounting_weight_grams, fabrication_fee, line_total, description, description_en, gold_price_per_gram, item_photo_url)
    select inv_id, piece_id, gold_stock_lot_id, diamond_piece_id, barcode, karat, weight_grams,
      accounting_weight_grams, 0, line_total, description, description_en, gold_price_per_gram, item_photo_url
      from invoice_items where id = any(ids);

  -- stock back in
  update pieces set status = 'available'
   where status = 'sold' and store_id = sid and id in (select piece_id from invoice_items where id = any(ids) and piece_id is not null);
  insert into piece_movements (store_id, piece_id, event_type, note, created_by)
    select sid, piece_id, 'returned', note, me from invoice_items where id = any(ids) and piece_id is not null;
  update diamond_pieces set status = 'available'
   where status = 'sold' and store_id = sid and id in (select diamond_piece_id from invoice_items where id = any(ids) and diamond_piece_id is not null);
  -- bulk weight (and the pooled making charge taken with it) back onto its lot, row-locked
  update gold_stock_lots l
     set weight_grams_remaining = l.weight_grams_remaining + x.w,
         fabrication_pool_remaining = case when l.fabrication_pool_remaining is null then null
                                           else l.fabrication_pool_remaining + x.f end
    from (select gold_stock_lot_id, sum(coalesce(weight_grams, 0)) w, sum(coalesce(fabrication_fee, 0)) f
            from invoice_items where id = any(ids) and gold_stock_lot_id is not null group by gold_stock_lot_id) x
   where l.id = x.gold_stock_lot_id and l.store_id = sid;

  -- money side, dated today
  if rm = 'debt_reduce' then
    insert into customer_debts (store_id, customer_id, invoice_id, movement_type, cash_amount, gold_grams_24k, notes, created_by)
      values (sid, o.customer_id, inv_id, 'debt_decrease', total, 0, note, me);
  elsif total > 0 then
    insert into cash_movements (store_id, box, direction, amount, description, created_by, invoice_id)
      values (sid, 'main', 'out', total, 'رد مبلغ ' || note, me, inv_id);
  end if;

  select coalesce(sum(line_total), 0) into chk from invoice_items where invoice_id = inv_id;
  if abs(chk - total) > 0.01 then raise exception 'فحص محاسبي فشل: مجموع سطور المرتجع % ≠ %', chk, total; end if;

  return jsonb_build_object('id', inv_id, 'invoice_number', inv_no, 'total', total, 'duplicate', false);
exception when unique_violation then
  if ref is not null then
    select id, invoice_number into ex from invoices where client_ref = ref and store_id = sid;
    if found then return jsonb_build_object('id', ex.id, 'invoice_number', ex.invoice_number, 'duplicate', true); end if;
  end if;
  raise;
end $function$;

revoke all on function public.post_purchase_invoice(jsonb) from public, anon;
revoke all on function public.post_sales_return(jsonb) from public, anon;
grant execute on function public.post_purchase_invoice(jsonb) to authenticated;
grant execute on function public.post_sales_return(jsonb) to authenticated;
