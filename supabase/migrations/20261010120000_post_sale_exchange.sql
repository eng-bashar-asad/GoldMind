-- Exchange (تبديل) on a sale: the returned pieces go back to stock as a return to the customer's
-- account (no cash), the new pieces are sold on the account at old value ± the difference the user
-- types (amount + currency), and only the difference touches the cash box, in the currency paid.
-- The original invoice and its day in the daily box are never changed.
create or replace function public.post_sale_exchange(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  sid uuid := nullif(p->>'store_id', '')::uuid;
  orig uuid := nullif(p->>'original_invoice_id', '')::uuid;
  ref uuid := nullif(p->>'client_ref', '')::uuid;
  dir text := coalesce(nullif(p->>'diff_dir', ''), 'none');
  meth text := coalesce(nullif(p->>'diff_method', ''), 'cash');
  amt numeric := round(coalesce(nullif(p->>'diff_amount', '')::numeric, 0), 2);
  cur text := upper(coalesce(nullif(p->>'diff_currency', ''), ''));
  rate numeric := nullif(p->>'diff_rate', '')::numeric;
  o record; ex record; pc record;
  base_cur text; base_diff numeric := 0; ret_total numeric; new_total numeric;
  n_new int; n_found int; wsum numeric; acc numeric := 0; k int := 0; price numeric;
  items jsonb := '[]'::jsonb; ret jsonb; sale jsonb; sale_id uuid; ret_id uuid; old_codes text; new_codes text;
begin
  if sid is null then raise exception 'المحل غير محدد'; end if;
  if not has_permission('create_invoice', sid) then raise exception 'ليس لديك صلاحية التبديل' using errcode = '42501'; end if;
  if ref is not null then
    select id, invoice_number into ex from invoices where client_ref = ref and store_id = sid;
    if found then return jsonb_build_object('sale', jsonb_build_object('id', ex.id, 'invoice_number', ex.invoice_number), 'duplicate', true); end if;
  end if;
  select * into o from invoices where id = orig and store_id = sid;
  if not found or o.type <> 'sale' then raise exception 'فاتورة البيع الأصلية غير موجودة'; end if;
  if o.status = 'cancelled' then raise exception 'الفاتورة الأصلية ملغاة'; end if;
  if o.customer_id is null then raise exception 'الفاتورة بدون زبون — اختر الزبون بتعديل الفاتورة أولاً'; end if;
  if dir not in ('in', 'out', 'none') then raise exception 'اتجاه الفرق غير معروف'; end if;
  if meth not in ('cash', 'bank', 'account') then raise exception 'طريقة دفع الفرق غير معروفة'; end if;

  select round(sum(line_total), 2), string_agg(coalesce(barcode, description, '—'), '، ')
    into ret_total, old_codes
    from invoice_items where invoice_id = orig and id in (select x::uuid from jsonb_array_elements_text(coalesce(p->'item_ids', '[]'::jsonb)) x);
  if ret_total is null then raise exception 'اختر القطعة الراجعة'; end if;

  select coalesce(nullif(upper(currency), ''), 'AED') into base_cur from stores where id = sid;
  if dir = 'none' then amt := 0; end if;
  if amt < 0 then raise exception 'مبلغ الفرق غير صحيح'; end if;
  if amt > 0 then
    if cur = '' then cur := base_cur; end if;
    if cur = base_cur then base_diff := amt;
    else
      if rate is null or rate <= 0 then raise exception 'أدخل سعر صرف % مقابل %', cur, base_cur; end if;
      base_diff := round(amt / rate, 2);
    end if;
  end if;
  new_total := round(ret_total + case dir when 'in' then base_diff when 'out' then -base_diff else 0 end, 2);
  if new_total < 0 then raise exception 'الفرق أكبر من قيمة القطع الراجعة'; end if;

  -- new pieces: the new value is split between them by weight
  select count(*) into n_new from (select distinct x from jsonb_array_elements_text(coalesce(p->'new_piece_ids', '[]'::jsonb)) x) s;
  if n_new = 0 then raise exception 'أضف القطعة الجديدة'; end if;
  select count(*), sum(coalesce(accounting_weight_grams, weight_grams, 0)), string_agg(barcode, '، ')
    into n_found, wsum, new_codes
    from pieces where store_id = sid and status = 'available'
     and id in (select x::uuid from jsonb_array_elements_text(p->'new_piece_ids') x);
  if n_found <> n_new then raise exception 'إحدى القطع الجديدة غير متوفرة للبيع'; end if;
  for pc in select * from pieces where store_id = sid and id in (select x::uuid from jsonb_array_elements_text(p->'new_piece_ids') x) order by barcode loop
    k := k + 1;
    price := case when k = n_new then round(new_total - acc, 2)
                  when coalesce(wsum, 0) > 0 then round(new_total * coalesce(pc.accounting_weight_grams, pc.weight_grams, 0) / wsum, 2)
                  else round(new_total / n_new, 2) end;
    acc := acc + price;
    items := items || jsonb_build_object('mode', 'piece', 'piece_id', pc.id, 'price', price, 'barcode', pc.barcode,
      'description', coalesce(pc.description_ar, pc.piece_type, 'قطعة'), 'description_en', pc.description_en);
  end loop;

  -- 1) the returned pieces: back to stock, value credited to the customer's account (no cash)
  ret := post_sales_return(jsonb_build_object('store_id', sid, 'original_invoice_id', orig, 'item_ids', p->'item_ids',
           'refund_method', 'debt_reduce', 'reason', 'تبديل'));
  ret_id := (ret->>'id')::uuid;
  -- 2) the new pieces: sold on the account at the new value
  sale := post_sale_invoice(jsonb_build_object('store_id', sid, 'customer_id', o.customer_id, 'payment_method', 'credit',
           'items', items, 'confirm_low_price', true, 'client_ref', ref));
  sale_id := (sale->>'id')::uuid;
  update invoices set related_invoice_id = orig where id = sale_id;
  update piece_movements set note = note || ' — تبديل بالقطعة ' || new_codes
   where note like 'مرتجع ' || (ret->>'invoice_number') || '%';
  update piece_movements set note = note || ' — تبديل بدل القطعة ' || old_codes || ' (فاتورة ' || o.invoice_number || ')'
   where note = 'بيع بفاتورة ' || (sale->>'invoice_number');
  -- 3) only the difference moves money, in the currency it was paid in
  if amt > 0 and meth in ('cash', 'bank') and dir in ('in', 'out') then
    perform cash_voucher(jsonb_build_object('store_id', sid, 'kind', dir, 'party', 'customer', 'party_id', o.customer_id,
      'amount', amt, 'currency', cur, 'fx_rate', rate, 'method', meth,
      'notes', case dir when 'in' then 'فرق تبديل' else 'رد فرق تبديل' end || ' — ' || o.invoice_number || ' ← ' || (sale->>'invoice_number')));
  end if;
  return jsonb_build_object('sale', sale, 'return', ret, 'returned_total', ret_total, 'new_total', new_total, 'diff_base', base_diff);
end $$;
grant execute on function public.post_sale_exchange(jsonb) to authenticated;
