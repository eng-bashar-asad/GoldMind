-- «إخراج» to a party (workshop / intermediary / box) can now take weight from the scrap boxes, not only
-- barcoded pieces (Bashar 2026-11-14). New function so the existing stock_out_to_party stays untouched:
-- p_scrap = [{"karat": 18, "weight": 12.5}, …]; the weight is taken from «كسر <karat>» lots, oldest first,
-- and written as voucher lines with no piece (barcode «كسر <karat>»), like the scrap that comes back in.
create or replace function public.stock_out_to_party_v2(target_party_id uuid, piece_ids uuid[], p_notes text default null,
  p_recipient text default null, p_scrap jsonb default '[]'::jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  pt record; actor uuid; vid uuid; num text; ln jsonb; k int; w numeric; need numeric; lot record; take numeric; gp numeric; have numeric;
  n_scrap int := coalesce(jsonb_array_length(case when jsonb_typeof(p_scrap) = 'array' then p_scrap end), 0);
begin
  select * into pt from public.stock_parties where id = target_party_id;
  if pt is null then raise exception 'الجهة غير موجودة'; end if;
  if not public.has_permission('stock_transfers', pt.store_id) then raise exception 'ليس لديك صلاحية إخراج/إدخال البضاعة' using errcode = '42501'; end if;
  if n_scrap = 0 then -- pieces only: exactly the old function
    return public.stock_out_to_party(target_party_id, piece_ids, p_notes, p_recipient);
  end if;
  if pt.kind = 'gift' then raise exception 'لا يمكن إخراج كسر كهدية'; end if;
  if piece_ids is not null and array_length(piece_ids, 1) is not null then
    vid := public.stock_out_to_party(target_party_id, piece_ids, p_notes, p_recipient); -- the voucher with its pieces
  else
    select id into actor from public.staff where user_id = auth.uid() and store_id = pt.store_id limit 1;
    perform 1 from public.stores where id = pt.store_id for update;
    num := 'OUT-' || lpad((select count(*) + 1 from public.stock_vouchers where store_id = pt.store_id and direction = 'out')::text, 5, '0');
    insert into public.stock_vouchers (store_id, party_id, direction, voucher_number, notes, created_by)
      values (pt.store_id, pt.id, 'out', num, nullif(trim(p_notes), ''), actor) returning id into vid;
  end if;
  select voucher_number into num from public.stock_vouchers where id = vid;
  for ln in select * from jsonb_array_elements(p_scrap) loop
    k := (ln->>'karat')::int; w := round(nullif(ln->>'weight', '')::numeric, 3);
    if k not in (18, 21, 22, 24) then raise exception 'عيار غير صحيح'; end if;
    if w is null or w <= 0 then raise exception 'وزن الكسر غير صحيح'; end if;
    select coalesce(sum(weight_grams_remaining), 0) into have from public.gold_stock_lots
     where store_id = pt.store_id and box_name = 'كسر ' || k and weight_grams_remaining > 0;
    if have + 0.0005 < w then raise exception 'صندوق كسر % فيه % غ فقط', k, trim(to_char(have, 'FM999990.000')); end if;
    need := w;
    for lot in select id, weight_grams_remaining from public.gold_stock_lots
                where store_id = pt.store_id and box_name = 'كسر ' || k and weight_grams_remaining > 0
                order by created_at, id for update loop
      exit when need <= 0;
      take := least(need, lot.weight_grams_remaining);
      update public.gold_stock_lots set weight_grams_remaining = round(weight_grams_remaining - take, 3) where id = lot.id;
      need := need - take;
    end loop;
    select price_per_gram into gp from public.gold_prices where store_id = pt.store_id and karat = k;
    insert into public.stock_voucher_lines (voucher_id, store_id, party_id, direction, piece_id, barcode, karat, weight_grams,
        accounting_weight_grams, fab_per_gram, gold_price_per_gram, cost_value)
      values (vid, pt.store_id, pt.id, 'out', null, 'كسر ' || k, k, w, w, 0, gp, round(w * coalesce(gp, 0), 2));
  end loop;
  return vid;
end $$;
grant execute on function public.stock_out_to_party_v2(uuid, uuid[], text, text, jsonb) to authenticated;
