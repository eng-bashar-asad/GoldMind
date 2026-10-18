-- Weights corrected on a sale (a bracelet or chain gets cut): the piece's standing weight and
-- accounting weight are set here, by staff with the 'edit_sale_weights' permission (owners always).
-- A sale's money comes from its prices, so weights never move cash or debt.
-- When the standing weight goes DOWN (the cut), the grams taken off go into the scrap box
-- («كسر <karat>») as a new stock lot, so the gold is not lost from the books.
create or replace function public.set_piece_weights(p_piece uuid, p_weight numeric, p_acc numeric)
returns void language plpgsql security definer set search_path = public as $$
declare pc record; me uuid; cut numeric;
begin
  select id, store_id, barcode, karat, weight_grams into pc from pieces where id = p_piece for update;
  if pc is null then raise exception 'القطعة غير موجودة'; end if;
  if not has_permission('edit_sale_weights', pc.store_id) then
    raise exception 'ليس لديك صلاحية تعديل أوزان القطع' using errcode = '42501';
  end if;
  if p_weight is null or p_weight <= 0 then raise exception 'الوزن القائم يجب أن يكون أكبر من صفر'; end if;
  if p_acc is null or p_acc <= 0 then raise exception 'الوزن المحاسبي يجب أن يكون أكبر من صفر'; end if;

  cut := round(coalesce(pc.weight_grams, 0) - p_weight, 3);
  if cut > 0 then
    if pc.karat is null then raise exception 'القطعة بدون عيار، ما بنقدر نضيف الفرق لصندوق الكسر'; end if;
    select id into me from staff where user_id = auth.uid() and store_id = pc.store_id limit 1;
    insert into gold_stock_lots (store_id, karat, weight_grams_total, weight_grams_remaining, cost_fabrication_per_gram,
        notes, box_name, created_by)
      values (pc.store_id, pc.karat, cut, cut, 0, 'من تقصير القطعة ' || pc.barcode, 'كسر ' || pc.karat, me);
  end if;

  update pieces set weight_grams = round(p_weight, 3), accounting_weight_grams = round(p_acc, 3) where id = pc.id;
end $$;

revoke all on function public.set_piece_weights(uuid, numeric, numeric) from public, anon;
grant execute on function public.set_piece_weights(uuid, numeric, numeric) to authenticated;
