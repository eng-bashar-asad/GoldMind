-- Editing a piece on a goods-in voucher (stock_in_piece_update) re-works that voucher's scrap rows:
-- what is left of the party's making after the voucher's pieces (as of that voucher) goes with its
-- scrap rows, and the voucher's «خسارة مصنعية» expense is set to the new total (created if missing,
-- set to 0 if nothing is lost any more). Later vouchers are not counted.
create or replace function public.gm_stock_in_rescrap(p_voucher uuid)
returns void language plpgsql security definer set search_path to 'public' as $$
declare v record; fab_bal numeric; aw_bal numeric; avg_fab numeric; loss numeric := 0; sfab numeric; l record;
        txt text[] := '{}'; cat_id uuid; eid uuid; dsc text;
begin
  select sv.*, pt.name party_name into v from stock_vouchers sv join stock_parties pt on pt.id = sv.party_id where sv.id = p_voucher;
  if v is null or not exists (select 1 from stock_voucher_lines where voucher_id = p_voucher and piece_id is null and barcode like 'كسر %') then return; end if;
  select coalesce(sum(case l2.direction when 'out' then 1 else -1 end * l2.fab_per_gram * l2.accounting_weight_grams), 0),
         coalesce(sum(case l2.direction when 'out' then 1 else -1 end * l2.accounting_weight_grams), 0)
    into fab_bal, aw_bal
    from stock_voucher_lines l2 join stock_vouchers v2 on v2.id = l2.voucher_id
   where l2.party_id = v.party_id and v2.created_at <= v.created_at
     and not (l2.voucher_id = p_voucher and l2.piece_id is null and l2.barcode like 'كسر %');
  avg_fab := case when aw_bal > 0.0005 and fab_bal > 0 then fab_bal / aw_bal else 0 end;
  for l in select * from stock_voucher_lines where voucher_id = p_voucher and piece_id is null and barcode like 'كسر %' order by id loop
    sfab := round(least(avg_fab, greatest(fab_bal - loss, 0) / l.weight_grams), 4);
    update stock_voucher_lines set fab_per_gram = sfab,
           cost_value = round(l.weight_grams * (coalesce(l.gold_price_per_gram, 0) + sfab), 2) where id = l.id;
    loss := loss + l.weight_grams * sfab;
    txt := txt || (trim(to_char(l.weight_grams, 'FM999990.000')) || ' غ لصندوق كسر ' || l.karat);
  end loop;
  loss := round(loss, 2);
  dsc := 'خسارة مصنعية — ' || array_to_string(txt, '، ') || ' من ' || v.party_name
         || ' (متوسط المصنعية ' || trim(to_char(round(avg_fab, 2), 'FM999,999,990.00')) || ' للغرام) — السند ' || v.voucher_number;
  select id into cat_id from expense_categories where store_id = v.store_id and name = 'خسارة مصنعية' limit 1;
  if cat_id is not null then
    select id into eid from expense_entries where store_id = v.store_id and category_id = cat_id
       and (description like '%— السند ' || v.voucher_number or description like '%— السند ' || v.voucher_number || ' (%')
     order by created_at limit 1;
  end if;
  if eid is not null then
    update expense_entries set amount = loss, description = dsc || case when loss = 0 then ' (لا خسارة بعد التعديل)' else '' end where id = eid;
  elsif loss > 0 then
    if cat_id is null then insert into expense_categories (store_id, name) values (v.store_id, 'خسارة مصنعية') returning id into cat_id; end if;
    insert into expense_entries (store_id, category_id, amount, description, created_by)
    values (v.store_id, cat_id, loss, dsc, (select id from staff where user_id = auth.uid() and store_id = v.store_id limit 1));
  end if;
end $$;
revoke execute on function public.gm_stock_in_rescrap(uuid) from public, anon, authenticated;

create or replace function public.stock_in_piece_update(p_line uuid, p_weight numeric, p_acc numeric, p_fab numeric,
  p_description text, p_box text, p_photo_url text)
returns void language plpgsql security definer set search_path to 'public' as $$
declare l record; pc record; gp numeric; actor uuid; aw numeric; ch text[] := '{}';
begin
  select * into l from stock_voucher_lines where id = p_line for update;
  if l is null or l.direction <> 'in' or l.piece_id is null then raise exception 'السطر غير موجود أو ليس قطعة مُدخلة'; end if;
  if not has_permission('stock_transfers', l.store_id) then raise exception 'ليس لديك صلاحية إخراج/إدخال البضاعة' using errcode = '42501'; end if;
  select * into pc from pieces where id = l.piece_id for update;
  if pc.status <> 'available' then raise exception 'القطعة % لم تعد في المخزن (حالتها: %)', pc.barcode, pc.status; end if;
  if p_weight is null or p_weight <= 0 then raise exception 'الوزن القائم يجب أن يكون أكبر من صفر'; end if;
  aw := coalesce(nullif(p_acc, 0), p_weight);
  if aw <= 0 or coalesce(p_fab, 0) < 0 then raise exception 'وزن أو مصنعية غير صحيحة'; end if;
  if nullif(trim(p_box), '') is null then raise exception 'اختر الصندوق'; end if;
  select id into actor from staff where user_id = auth.uid() and store_id = l.store_id limit 1;

  if round(p_weight, 3) <> pc.weight_grams then ch := ch || ('القائم ' || pc.weight_grams || ' ← ' || round(p_weight, 3)); end if;
  if round(aw, 3) <> coalesce(pc.accounting_weight_grams, pc.weight_grams) then ch := ch || ('المحاسبي ' || coalesce(pc.accounting_weight_grams, pc.weight_grams) || ' ← ' || round(aw, 3)); end if;
  if coalesce(p_fab, 0) <> coalesce(pc.cost_fabrication_per_gram, 0) then ch := ch || ('المصنعية ' || coalesce(pc.cost_fabrication_per_gram, 0) || ' ← ' || coalesce(p_fab, 0)); end if;
  if trim(p_box) is distinct from pc.box_name then ch := ch || ('الصندوق ' || coalesce(pc.box_name, '—') || ' ← ' || trim(p_box)); end if;
  if nullif(trim(p_description), '') is distinct from pc.description_ar then ch := ch || 'الوصف'::text; end if;
  if nullif(p_photo_url, '') is not null then ch := ch || 'الصورة'::text; end if;
  if array_length(ch, 1) is null then return; end if;

  update pieces set weight_grams = round(p_weight, 3), accounting_weight_grams = round(aw, 3),
         cost_fabrication_per_gram = coalesce(p_fab, 0), box_name = trim(p_box),
         description_ar = nullif(trim(p_description), ''), photo_url = coalesce(nullif(p_photo_url, ''), photo_url)
   where id = pc.id;
  gp := coalesce(l.gold_price_per_gram, 0);
  update stock_voucher_lines set weight_grams = round(p_weight, 3), accounting_weight_grams = round(aw, 3),
         fab_per_gram = coalesce(p_fab, 0), cost_value = round(aw * (gp + coalesce(p_fab, 0)), 2)
   where id = l.id;
  insert into piece_movements (store_id, piece_id, event_type, note, created_by)
  values (l.store_id, pc.id, 'edited', 'تعديل من سند الإدخال: ' || array_to_string(ch, '، '), actor);
  perform gm_stock_in_rescrap(l.voucher_id); -- the voucher's scrap rows take what is left of the making
end $$;

