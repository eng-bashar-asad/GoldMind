-- Goods-in from an intermediary: part of the result can go to the scrap box («كسر 18/21/22/24»)
-- instead of becoming a piece. It enters the box as gold only (no making, like a cut on a sale);
-- the making of those grams (at the original piece's making per gram) is recorded as the expense
-- «خسارة مصنعية», with no cash movement. The voucher still balances the party's weight.
create or replace function public.stock_in_from_party(target_party_id uuid, return_piece_ids uuid[], new_lines jsonb,
  p_notes text, p_return_box text, p_source_piece_ids uuid[])
returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare
  pt record; actor uuid; vid uuid; num text; pc record; ln jsonb; gp numeric;
  k int; wt numeric; aw numeric; fab numeric; bc text; newid uuid; cnt int := 0; rbox text := nullif(trim(p_return_box), '');
  srcs uuid[] := coalesce(p_source_piece_ids, '{}'); src_codes text; new_codes text[] := '{}';
  src_fab numeric := 0; loss numeric := 0; scrap_txt text[] := '{}'; cat_id uuid;
begin
  select * into pt from public.stock_parties where id = target_party_id;
  if pt is null then raise exception 'الجهة غير موجودة'; end if;
  if not public.has_permission('stock_transfers', pt.store_id) then
    raise exception 'ليس لديك صلاحية إخراج/إدخال البضاعة' using errcode = '42501';
  end if;
  select id into actor from public.staff where user_id = auth.uid() and store_id = pt.store_id limit 1;

  -- source pieces: held by this party right now, not also returned as-is, and only with new pieces
  if array_length(srcs, 1) is not null then
    if jsonb_array_length(coalesce(new_lines, '[]'::jsonb)) = 0 then raise exception 'أضف القطع الجديدة المصنوعة من القطعة الأصلية'; end if;
    if srcs && coalesce(return_piece_ids, '{}') then raise exception 'القطعة لا يمكن أن تُعاد كما هي وتُحوَّل لقطع جديدة معاً'; end if;
    for pc in select * from public.pieces where id = any(srcs) for update loop
      if pc.store_id <> pt.store_id then raise exception 'قطعة تابعة لشركة أخرى'; end if;
      if pc.status <> 'at_intermediary' or coalesce((select l.direction from public.stock_voucher_lines l
             join public.stock_vouchers v on v.id = l.voucher_id
             where l.piece_id = pc.id and l.party_id = pt.id order by v.created_at desc limit 1), '') <> 'out' then
        raise exception 'القطعة % ليست لدى هذه الجهة', pc.barcode;
      end if;
    end loop;
    if (select count(*) from public.pieces where id = any(srcs)) <> array_length(srcs, 1) then raise exception 'بعض القطع غير موجودة'; end if;
    select string_agg(barcode, '، ' order by barcode),
           coalesce(sum(coalesce(cost_fabrication_per_gram, 0) * coalesce(accounting_weight_grams, weight_grams, 0))
                    / nullif(sum(coalesce(accounting_weight_grams, weight_grams, 0)), 0), 0)
      into src_codes, src_fab from public.pieces where id = any(srcs);
  end if;

  perform 1 from public.stores where id = pt.store_id for update;
  num := 'IN-' || lpad((select count(*) + 1 from public.stock_vouchers where store_id = pt.store_id and direction = 'in')::text, 5, '0');
  insert into public.stock_vouchers (store_id, party_id, direction, voucher_number, notes, created_by)
  values (pt.store_id, pt.id, 'in', num, nullif(trim(p_notes), ''), actor) returning id into vid;

  for pc in select * from public.pieces where id = any(coalesce(return_piece_ids, '{}')) for update loop
    if pc.store_id <> pt.store_id then raise exception 'قطعة تابعة لشركة أخرى'; end if;
    if pc.status not in ('in_box', 'at_intermediary') then raise exception 'القطعة % ليست لدى جهة (حالتها: %)', pc.barcode, pc.status; end if;
    select price_per_gram into gp from public.gold_prices where store_id = pc.store_id and karat = pc.karat;
    aw := coalesce(pc.accounting_weight_grams, pc.weight_grams, 0);
    insert into public.stock_voucher_lines (voucher_id, store_id, party_id, direction, piece_id, barcode, karat,
      weight_grams, accounting_weight_grams, fab_per_gram, gold_price_per_gram, cost_value)
    values (vid, pc.store_id, pt.id, 'in', pc.id, pc.barcode, pc.karat, pc.weight_grams, aw,
      coalesce(pc.cost_fabrication_per_gram, 0), gp, round(aw * (coalesce(gp, 0) + coalesce(pc.cost_fabrication_per_gram, 0)), 2));
    update public.pieces set status = 'available', box_name = coalesce(rbox, box_name) where id = pc.id;
    insert into public.piece_movements (store_id, piece_id, event_type, note, created_by)
    values (pc.store_id, pc.id, 'stock_in', 'رجوع بالسند ' || num || ' من ' || pt.name || coalesce(' إلى صندوق ' || rbox, ''), actor);
    cnt := cnt + 1;
  end loop;

  for ln in select * from jsonb_array_elements(coalesce(new_lines, '[]'::jsonb)) loop
    k := (ln->>'karat')::int;
    wt := (ln->>'weight')::numeric;
    -- a part that goes to the scrap box («كسر <عيار>»): gold only, its making is lost
    if coalesce((ln->>'to_scrap')::boolean, false) then
      if k not in (18, 21, 22, 24) then raise exception 'عيار غير صحيح'; end if;
      if wt is null or wt <= 0 then raise exception 'وزن غير صحيح'; end if;
      wt := round(wt, 3);
      insert into public.gold_stock_lots (store_id, karat, box_name, weight_grams_total, weight_grams_remaining, cost_fabrication_per_gram, notes, created_by)
      values (pt.store_id, k, 'كسر ' || k, wt, wt, 0, 'من سند الإدخال ' || num || ' — ' || pt.name || coalesce(' — من القطعة ' || src_codes, ''), actor);
      select price_per_gram into gp from public.gold_prices where store_id = pt.store_id and karat = k;
      insert into public.stock_voucher_lines (voucher_id, store_id, party_id, direction, piece_id, barcode, karat,
        weight_grams, accounting_weight_grams, fab_per_gram, gold_price_per_gram, cost_value)
      values (vid, pt.store_id, pt.id, 'in', null, 'كسر ' || k, k, wt, wt, 0, gp, round(wt * coalesce(gp, 0), 2));
      loss := loss + wt * src_fab;
      scrap_txt := scrap_txt || (trim(to_char(wt, 'FM999990.000')) || ' غ لصندوق كسر ' || k);
      cnt := cnt + 1;
      continue;
    end if;
    aw := coalesce(nullif(ln->>'acc_weight', '')::numeric, wt);
    fab := coalesce(nullif(ln->>'fab_per_gram', '')::numeric, 0);
    if k not in (18, 21, 22, 24) then raise exception 'عيار غير صحيح'; end if;
    if wt is null or wt <= 0 or aw <= 0 or fab < 0 then raise exception 'وزن أو مصنعية غير صحيحة'; end if;
    if nullif(trim(ln->>'box_name'), '') is null then raise exception 'اختر الصندوق لكل قطعة جديدة'; end if;
    bc := public.next_piece_barcode(pt.store_id, 'gold');
    insert into public.pieces (store_id, barcode, photo_url, weight_grams, accounting_weight_grams, karat, color, status,
      created_by, cost_fabrication_per_gram, description_ar, piece_type, category1, category2, box_name)
    values (pt.store_id, bc, nullif(ln->>'photo_url', ''), wt, aw, k, coalesce(nullif(ln->>'color', ''), 'Gold'), 'available',
      actor, fab, nullif(ln->>'description_ar', ''), nullif(ln->>'piece_type', ''), nullif(ln->>'category1', ''), nullif(ln->>'category2', ''),
      trim(ln->>'box_name'))
    returning id into newid;
    select price_per_gram into gp from public.gold_prices where store_id = pt.store_id and karat = k;
    insert into public.stock_voucher_lines (voucher_id, store_id, party_id, direction, piece_id, barcode, karat,
      weight_grams, accounting_weight_grams, fab_per_gram, gold_price_per_gram, cost_value)
    values (vid, pt.store_id, pt.id, 'in', newid, bc, k, wt, aw, fab, gp, round(aw * (coalesce(gp, 0) + fab), 2));
    insert into public.piece_movements (store_id, piece_id, event_type, note, created_by)
    values (pt.store_id, newid, 'stock_in', 'قطعة جديدة بالسند ' || num || ' من ' || pt.name || coalesce(' — من القطعة ' || src_codes, ''), actor);
    new_codes := new_codes || bc;
    cnt := cnt + 1;
  end loop;

  if cnt = 0 then raise exception 'لا توجد أي قطعة في السند'; end if;

  -- the making of the grams sent to scrap is a loss (an expense with no cash)
  loss := round(loss, 2);
  if loss > 0 then
    select id into cat_id from public.expense_categories where store_id = pt.store_id and name = 'خسارة مصنعية' limit 1;
    if cat_id is null then insert into public.expense_categories (store_id, name) values (pt.store_id, 'خسارة مصنعية') returning id into cat_id; end if;
    insert into public.expense_entries (store_id, category_id, amount, description, created_by)
    values (pt.store_id, cat_id, loss, 'خسارة مصنعية — ' || array_to_string(scrap_txt, '، ') || ' من القطعة ' || src_codes
            || ' (مصنعيتها ' || trim(to_char(round(src_fab, 2), 'FM999,999,990.00')) || ' للغرام) — السند ' || num, actor);
  end if;

  if array_length(srcs, 1) is not null then
    update public.pieces set status = 'reworked' where id = any(srcs);
    insert into public.piece_movements (store_id, piece_id, event_type, note, created_by)
    select pt.store_id, p.id, 'reworked', 'حُوّلت لقطع جديدة بالسند ' || num || ': ' || array_to_string(new_codes || scrap_txt, '، '), actor
      from public.pieces p where p.id = any(srcs);
  end if;
  return vid;
end;
$function$;

revoke execute on function public.stock_in_from_party(uuid, uuid[], jsonb, text, text, uuid[]) from public, anon;
grant execute on function public.stock_in_from_party(uuid, uuid[], jsonb, text, text, uuid[]) to authenticated;
