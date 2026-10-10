-- Exchange (تبديل) as ONE sale invoice: the returned pieces are lines with a negative amount
-- (returned_item_id = the line they came from), the new pieces are normal lines, and the invoice
-- total is the difference. Only the difference moves money, in the currency it was paid in.
alter table public.invoice_items add column if not exists returned_item_id uuid references public.invoice_items(id);
alter table public.invoices add column if not exists is_exchange boolean not null default false;
create index if not exists invoice_items_returned_item_idx on public.invoice_items(returned_item_id) where returned_item_id is not null;

create or replace function public.post_sale_exchange(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  sid uuid := nullif(p->>'store_id', '')::uuid;
  orig uuid := nullif(p->>'original_invoice_id', '')::uuid;
  ref uuid := nullif(p->>'client_ref', '')::uuid;
  dir text := coalesce(nullif(p->>'diff_dir', ''), 'none');
  meth text := coalesce(nullif(p->>'diff_method', ''), 'cash');
  amt numeric := round(coalesce(nullif(p->>'diff_amount', '')::numeric, 0), 2);
  paid_amt numeric := round(coalesce(nullif(p->>'paid_amount', '')::numeric, 0), 2);
  cur text := upper(coalesce(nullif(p->>'diff_currency', ''), ''));
  rate numeric := nullif(p->>'diff_rate', '')::numeric;
  o record; ex record; pc record; it record;
  me uuid; base_cur text; fx boolean := false; base_diff numeric := 0; paid_base numeric := 0;
  ret_total numeric; new_total numeric; total numeric;
  n_ret int; n_new int; n_found int; wsum numeric; acc numeric := 0; k int := 0; price numeric;
  inv_id uuid; inv_no text; pm text; old_codes text; new_codes text; gp numeric; bd jsonb;
begin
  if sid is null then raise exception 'المحل غير محدد'; end if;
  if not has_permission('create_invoice', sid) then raise exception 'ليس لديك صلاحية التبديل' using errcode = '42501'; end if;
  if ref is not null then
    select id, invoice_number into ex from invoices where client_ref = ref and store_id = sid;
    if found then return jsonb_build_object('id', ex.id, 'invoice_number', ex.invoice_number, 'duplicate', true); end if;
  end if;
  select * into o from invoices where id = orig and store_id = sid for update;
  if not found or o.type <> 'sale' then raise exception 'فاتورة البيع الأصلية غير موجودة'; end if;
  if o.status = 'cancelled' then raise exception 'الفاتورة الأصلية ملغاة'; end if;
  if o.customer_id is null then raise exception 'الفاتورة بدون زبون — اختر الزبون بتعديل الفاتورة أولاً'; end if;
  if dir not in ('in', 'out', 'none') then raise exception 'اتجاه الفرق غير معروف'; end if;
  if meth not in ('cash', 'bank', 'account', 'partial') or (meth = 'partial' and dir <> 'in') then raise exception 'طريقة دفع الفرق غير معروفة'; end if;
  select id into me from staff where user_id = auth.uid() and store_id = sid limit 1;

  -- returned lines: from this invoice, a real piece, sold (not a returned line), not taken back already
  select count(*), round(sum(line_total), 2), string_agg(coalesce(barcode, description, '—'), '، ')
    into n_ret, ret_total, old_codes
    from invoice_items ii
   where ii.invoice_id = orig and ii.piece_id is not null and ii.line_total > 0
     and ii.id in (select x::uuid from jsonb_array_elements_text(coalesce(p->'item_ids', '[]'::jsonb)) x)
     and not exists (select 1 from invoice_items r join invoices ri on ri.id = r.invoice_id
                      where r.returned_item_id = ii.id and ri.status <> 'cancelled')
     and not exists (select 1 from invoice_items r join invoices ri on ri.id = r.invoice_id
                      where ri.related_invoice_id = orig and ri.type = 'return' and ri.status <> 'cancelled' and r.piece_id = ii.piece_id);
  if n_ret = 0 or n_ret <> (select count(distinct x) from jsonb_array_elements_text(coalesce(p->'item_ids', '[]'::jsonb)) x) then
    raise exception 'القطعة الراجعة غير صحيحة أو رجعت من قبل من هذه الفاتورة';
  end if;

  select coalesce(nullif(upper(currency), ''), 'AED') into base_cur from stores where id = sid;
  if dir = 'none' then amt := 0; end if;
  if amt < 0 or paid_amt < 0 then raise exception 'مبلغ غير صحيح'; end if;
  if dir <> 'none' and amt = 0 then raise exception 'اكتب مبلغ الفرق'; end if;
  if amt > 0 then
    if cur = '' then cur := base_cur; end if;
    fx := cur <> base_cur;
    if fx and (rate is null or rate <= 0) then raise exception 'أدخل سعر صرف % مقابل %', cur, base_cur; end if;
    base_diff := case when fx then round(amt / rate, 2) else amt end;
  end if;
  total := case dir when 'in' then base_diff when 'out' then -base_diff else 0 end;
  new_total := round(ret_total + total, 2);
  if new_total < 0 then raise exception 'الفرق أكبر من قيمة القطع الراجعة'; end if;
  if meth = 'partial' then
    if paid_amt <= 0 or paid_amt >= amt then raise exception 'المدفوع الآن يجب أن يكون أقل من الفرق وأكبر من صفر'; end if;
    paid_base := case when fx then round(paid_amt / rate, 2) else paid_amt end;
  end if;

  select count(*) into n_new from (select distinct x from jsonb_array_elements_text(coalesce(p->'new_piece_ids', '[]'::jsonb)) x) s;
  if n_new = 0 then raise exception 'أضف القطعة الجديدة'; end if;
  select count(*), sum(coalesce(accounting_weight_grams, weight_grams, 0)), string_agg(barcode, '، ')
    into n_found, wsum, new_codes
    from pieces where store_id = sid and status = 'available'
     and id in (select x::uuid from jsonb_array_elements_text(p->'new_piece_ids') x);
  if n_found <> n_new then raise exception 'إحدى القطع الجديدة غير متوفرة للبيع'; end if;

  -- payment of the difference
  pm := case when dir = 'out' or meth = 'account' then 'credit' when meth = 'partial' then 'mixed' when dir = 'none' then 'cash' else meth end;
  inv_no := next_invoice_number(sid, 'INV');
  insert into invoices (store_id, invoice_number, type, customer_id, payment_method, cash_paid_amount, bank_paid_amount,
      gold_value, fabrication_fees, vat_amount, total_amount, amount_paid, status, created_by, client_ref, related_invoice_id, is_exchange)
    values (sid, inv_no, 'sale', o.customer_id, pm,
      case when pm = 'mixed' then paid_base end, case when pm = 'mixed' then 0 end,
      0, 0, 0, total,
      case pm when 'credit' then 0 when 'mixed' then paid_base else total end,
      case when pm = 'credit' and total > 0.009 then 'unpaid' when pm = 'mixed' then 'unpaid' else 'paid' end,
      me, ref, orig, true)
    returning id into inv_id;
  if fx and dir = 'in' and meth in ('cash', 'bank', 'partial') then
    bd := jsonb_build_array(jsonb_build_object('currency', cur, 'amount', case when meth = 'partial' then paid_amt else amt end,
                                               'rate', rate, 'method', case when meth = 'bank' then 'bank' else 'cash' end));
    update invoices set pay_breakdown = bd where id = inv_id;
  end if;

  -- lines: returned pieces with a negative amount, then the new pieces (new value split by weight)
  for it in select * from invoice_items where invoice_id = orig and id in (select x::uuid from jsonb_array_elements_text(p->'item_ids') x) loop
    insert into invoice_items (invoice_id, piece_id, barcode, karat, weight_grams, accounting_weight_grams, fabrication_fee,
        line_total, description, description_en, item_photo_url, gold_price_per_gram, returned_item_id)
      values (inv_id, it.piece_id, it.barcode, it.karat, it.weight_grams, it.accounting_weight_grams, 0,
        -it.line_total, it.description, it.description_en, it.item_photo_url, it.gold_price_per_gram, it.id);
    update pieces set status = 'available' where id = it.piece_id and store_id = sid;
    insert into piece_movements (store_id, piece_id, event_type, note, created_by)
      values (sid, it.piece_id, 'returned', 'رجعت بتبديل بفاتورة ' || inv_no || ' (من الفاتورة ' || o.invoice_number || ') — بدلها ' || new_codes, me);
  end loop;
  for pc in select * from pieces where store_id = sid and id in (select x::uuid from jsonb_array_elements_text(p->'new_piece_ids') x) order by barcode for update loop
    k := k + 1;
    price := case when k = n_new then round(new_total - acc, 2)
                  when coalesce(wsum, 0) > 0 then round(new_total * coalesce(pc.accounting_weight_grams, pc.weight_grams, 0) / wsum, 2)
                  else round(new_total / n_new, 2) end;
    acc := acc + price;
    select price_per_gram into gp from gold_prices where store_id = sid and karat = pc.karat;
    insert into invoice_items (invoice_id, piece_id, barcode, karat, weight_grams, accounting_weight_grams, fabrication_fee,
        line_total, description, description_en, gold_price_per_gram)
      values (inv_id, pc.id, pc.barcode, pc.karat, pc.weight_grams, coalesce(pc.accounting_weight_grams, pc.weight_grams), 0,
        price, coalesce(pc.description_ar, pc.piece_type, 'قطعة'), pc.description_en, gp);
    update pieces set status = 'sold' where id = pc.id;
    insert into piece_movements (store_id, piece_id, event_type, note, created_by)
      values (sid, pc.id, 'sold', 'بيع بفاتورة ' || inv_no || ' — تبديل بدل ' || old_codes || ' (فاتورة ' || o.invoice_number || ')', me);
  end loop;

  -- money: only the difference
  if dir = 'in' and meth in ('cash', 'bank') then
    insert into cash_movements (store_id, box, direction, amount, description, created_by, invoice_id)
      values (sid, 'main', 'in', total, 'فرق تبديل بفاتورة ' || inv_no, me, inv_id);
  elsif dir = 'in' and meth = 'partial' then
    insert into cash_movements (store_id, box, direction, amount, description, created_by, invoice_id)
      values (sid, 'main', 'in', paid_base, 'فرق تبديل (جزء) بفاتورة ' || inv_no, me, inv_id);
    insert into customer_debts (store_id, customer_id, invoice_id, movement_type, cash_amount, gold_grams_24k, notes, created_by)
      values (sid, o.customer_id, inv_id, 'debt_increase', round(total - paid_base, 2), 0, 'باقي فرق تبديل بفاتورة ' || inv_no, me);
  elsif dir = 'in' and meth = 'account' then
    insert into customer_debts (store_id, customer_id, invoice_id, movement_type, cash_amount, gold_grams_24k, notes, created_by)
      values (sid, o.customer_id, inv_id, 'debt_increase', total, 0, 'فرق تبديل بفاتورة ' || inv_no, me);
  elsif dir = 'out' then
    -- the difference is the customer's: as a credit on the account, then paid back if asked
    insert into customer_debts (store_id, customer_id, invoice_id, movement_type, cash_amount, gold_grams_24k, notes, created_by)
      values (sid, o.customer_id, inv_id, 'debt_decrease', -total, 0, 'فرق تبديل لصالح الزبون بفاتورة ' || inv_no, me);
    if meth in ('cash', 'bank') then
      perform cash_voucher(jsonb_build_object('store_id', sid, 'kind', 'out', 'party', 'customer', 'party_id', o.customer_id,
        'amount', amt, 'currency', cur, 'fx_rate', rate, 'method', meth, 'notes', 'رد فرق تبديل بفاتورة ' || inv_no));
    end if;
  end if;

  if abs((select coalesce(sum(line_total), 0) from invoice_items where invoice_id = inv_id) - total) > 0.01 then
    raise exception 'فحص محاسبي فشل: مجموع السطور ≠ الفرق';
  end if;
  return jsonb_build_object('id', inv_id, 'invoice_number', inv_no, 'total', total, 'returned_total', ret_total, 'new_total', new_total, 'duplicate', false);
end $$;
grant execute on function public.post_sale_exchange(jsonb) to authenticated;

-- (applied separately as exchange_aware_return_cancel_restore + restore_status_by_balance, by patching the live bodies:)
-- * post_sales_return refuses lines that are exchange "returned" lines or that were already taken back by an exchange
-- * cancel_invoice: on an exchange invoice the returned lines go back to 'sold', the new ones to 'available'; restore does the opposite
-- * restore_invoice: status = paid when total - amount_paid <= 0.009 (works for negative / credit totals)
