-- Edit a piece that came in on a goods-in voucher, from the voucher itself: the piece and its
-- voucher line change together, so the party's balance (gold + making) stays right.
-- Only while the piece is still in stock (available); the edit is logged on the piece.
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
end $$;

revoke execute on function public.stock_in_piece_update(uuid, numeric, numeric, numeric, text, text, text) from public, anon;
grant execute on function public.stock_in_piece_update(uuid, numeric, numeric, numeric, text, text, text) to authenticated;
