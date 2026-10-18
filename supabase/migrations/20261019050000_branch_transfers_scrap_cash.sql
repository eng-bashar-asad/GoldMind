-- Multi-branch 2.4 (part 2): scrap gold and cash between branches, always confirmed by the
-- receiving branch (decision by بشار 2026-10-19).
--   * scrap: weight taken from the sender's «كسر <karat>» box (oldest lot first) as soon as it is
--     sent; on receipt it becomes a new lot in the receiver's «كسر <karat>» box at the same
--     average making cost. Cancelling puts the grams back into the very lots they came from.
--   * cash: out of the sender's box (main or bank) when sent; into the receiver's same box on
--     receipt; back into the sender's box on cancel. Only between branches in the same currency.
-- Replaces the three transfer functions of 20261019040000 (one more optional argument each).
-- Nothing changes for existing data or single-branch shops. Run it ONCE.

begin;

alter table public.branch_transfer_items add column if not exists kind text not null default 'piece';
alter table public.branch_transfer_items drop constraint if exists branch_transfer_items_kind_check;
alter table public.branch_transfer_items add constraint branch_transfer_items_kind_check check (kind in ('piece', 'scrap', 'cash'));
alter table public.branch_transfer_items add column if not exists amount numeric;
alter table public.branch_transfer_items add column if not exists cash_box text;
alter table public.branch_transfer_items add column if not exists box_name text;
alter table public.branch_transfer_items add column if not exists fab_per_gram numeric;
alter table public.branch_transfer_items add column if not exists lot_draws jsonb;

drop function if exists public.send_branch_transfer(uuid, uuid, text[], text);
create function public.send_branch_transfer(p_from uuid, p_to uuid, p_barcodes text[] default null, p_notes text default null,
                                            p_scrap jsonb default null, p_cash jsonb default null)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare org uuid; me uuid; tid uuid; num text; bc text; pc record; dp record; n int := 0;
  s jsonb; k int; w numeric; left_w numeric; take numeric; lot record; draws jsonb; fab_sum numeric; box text;
  amt numeric; cbox text; cm uuid; cur_from text; cur_to text;
begin
  if not has_permission('stock_transfers', p_from) then
    raise exception 'ليس لديك صلاحية نقل البضاعة بين الفروع' using errcode = '42501';
  end if;
  if p_to is null or p_to = p_from or p_to not in (select org_store_ids(p_from)) then
    raise exception 'اختر فرعاً آخر من نفس المنشأة';
  end if;
  select organization_id, upper(currency) into org, cur_from from stores where id = p_from;
  select upper(currency) into cur_to from stores where id = p_to;
  select id into me from staff where user_id = auth.uid() and store_id = p_from limit 1;

  perform pg_advisory_xact_lock(hashtext('branch_transfer:' || coalesce(org, p_from)::text));
  select 'TRF-' || lpad((coalesce(max(nullif(regexp_replace(transfer_number, '\D', '', 'g'), '')::int), 0) + 1)::text, 6, '0')
    into num from branch_transfers where coalesce(organization_id, from_store_id) = coalesce(org, p_from);
  insert into branch_transfers (organization_id, from_store_id, to_store_id, transfer_number, notes, created_by)
    values (org, p_from, p_to, num, nullif(trim(p_notes), ''), me) returning id into tid;

  -- pieces
  foreach bc in array coalesce(p_barcodes, array[]::text[]) loop
    bc := nullif(trim(bc), '');
    continue when bc is null;
    select * into pc from pieces where store_id = p_from and barcode = bc for update;
    if found then
      if pc.status <> 'available' then raise exception 'القطعة % غير متاحة للنقل (حالتها: %)', bc, pc.status; end if;
      update pieces set status = 'in_transit' where id = pc.id;
      insert into branch_transfer_items (transfer_id, kind, piece_id, barcode, description, karat, weight_grams, photo_url)
        values (tid, 'piece', pc.id, pc.barcode, coalesce(pc.description_ar, pc.piece_type), pc.karat, pc.weight_grams, pc.photo_url);
      insert into piece_movements (store_id, piece_id, event_type, note, created_by)
        values (p_from, pc.id, 'transfer_out', 'نقل إلى فرع آخر بسند ' || num, me);
    else
      select * into dp from diamond_pieces where store_id = p_from and barcode = bc for update;
      if not found then raise exception 'القطعة % غير موجودة في هذا الفرع', bc; end if;
      if dp.status <> 'available' then raise exception 'القطعة % غير متاحة للنقل (حالتها: %)', bc, dp.status; end if;
      update diamond_pieces set status = 'in_transit' where id = dp.id;
      insert into branch_transfer_items (transfer_id, kind, diamond_piece_id, barcode, description, karat, weight_grams, photo_url)
        values (tid, 'piece', dp.id, dp.barcode, dp.description_ar, dp.gold_karat, dp.gold_weight_grams, dp.photo_url);
    end if;
    n := n + 1;
  end loop;

  -- scrap: [{karat, weight}] from «كسر <karat>», oldest lot first
  for s in select * from jsonb_array_elements(coalesce(p_scrap, '[]'::jsonb)) loop
    k := (s->>'karat')::int; w := round((s->>'weight')::numeric, 3);
    if k is null or w is null or w <= 0 then raise exception 'وزن كسر غير صحيح'; end if;
    box := 'كسر ' || k; left_w := w; draws := '[]'::jsonb; fab_sum := 0;
    for lot in select * from gold_stock_lots where store_id = p_from and box_name = box and weight_grams_remaining > 0
               order by created_at, id for update loop
      exit when left_w <= 0;
      take := least(left_w, lot.weight_grams_remaining);
      update gold_stock_lots set weight_grams_remaining = weight_grams_remaining - take where id = lot.id;
      draws := draws || jsonb_build_object('lot_id', lot.id, 'w', take);
      fab_sum := fab_sum + take * coalesce(lot.cost_fabrication_per_gram, 0);
      left_w := left_w - take;
    end loop;
    if left_w > 0.0005 then raise exception 'المتوفر في صندوق % أقل من %غ', box, w; end if;
    insert into branch_transfer_items (transfer_id, kind, description, karat, weight_grams, box_name, fab_per_gram, lot_draws)
      values (tid, 'scrap', box, k, w, box, round(fab_sum / w, 4), draws);
    n := n + 1;
  end loop;

  -- cash: {amount, box: main|bank}
  if p_cash is not null and coalesce((p_cash->>'amount')::numeric, 0) > 0 then
    amt := round((p_cash->>'amount')::numeric, 2);
    cbox := case when p_cash->>'box' = 'bank' then 'bank' else 'main' end;
    if cur_from is distinct from cur_to then raise exception 'لا يمكن نقل النقد بين فرعين بعملتين مختلفتين'; end if;
    insert into cash_movements (store_id, box, direction, amount, description, created_by)
      values (p_from, cbox, 'out', amt, 'نقل نقد إلى فرع آخر بسند ' || num, me) returning id into cm;
    if cbox = 'main' then
      insert into daily_cash_log (store_id, operation_type, direction, amount, notes, created_by, cash_movement_id)
        values (p_from, 'نقل نقد لفرع آخر', 'out', amt, 'سند ' || num, me, cm);
    end if;
    insert into branch_transfer_items (transfer_id, kind, description, amount, cash_box)
      values (tid, 'cash', case when cbox = 'bank' then 'نقد (بنك)' else 'نقد' end, amt, cbox);
    n := n + 1;
  end if;

  if n = 0 then raise exception 'أضف قطعة أو كسراً أو نقداً'; end if;
  return jsonb_build_object('id', tid, 'transfer_number', num, 'items', n);
end $function$;

drop function if exists public.receive_branch_transfer(uuid, text[]);
create function public.receive_branch_transfer(p_transfer uuid, p_barcodes text[] default null, p_items uuid[] default null)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare tr record; it record; me uuid; got int := 0; left_n int; cm uuid;
begin
  select * into tr from branch_transfers where id = p_transfer for update;
  if tr is null then raise exception 'سند النقل غير موجود'; end if;
  if not (has_permission('stock_transfers', tr.to_store_id) or has_permission('add_piece', tr.to_store_id)) then
    raise exception 'ليس لديك صلاحية استلام البضاعة في هذا الفرع' using errcode = '42501';
  end if;
  if tr.status <> 'in_transit' then raise exception 'هذا السند ليس بالطريق (حالته: %)', tr.status; end if;
  select id into me from staff where user_id = auth.uid() and store_id = tr.to_store_id limit 1;

  for it in select * from branch_transfer_items
             where transfer_id = tr.id and received_at is null
               and ((p_barcodes is null and p_items is null)
                    or barcode = any(coalesce(p_barcodes, array[]::text[]))
                    or id = any(coalesce(p_items, array[]::uuid[]))) for update
  loop
    if it.kind = 'scrap' then
      insert into gold_stock_lots (store_id, karat, weight_grams_total, weight_grams_remaining, cost_fabrication_per_gram, notes, created_by, box_name)
        values (tr.to_store_id, it.karat, it.weight_grams, it.weight_grams, it.fab_per_gram, 'استلام كسر من فرع آخر بسند ' || tr.transfer_number, me, it.box_name);
    elsif it.kind = 'cash' then
      insert into cash_movements (store_id, box, direction, amount, description, created_by)
        values (tr.to_store_id, it.cash_box, 'in', it.amount, 'استلام نقد من فرع آخر بسند ' || tr.transfer_number, me) returning id into cm;
      if it.cash_box = 'main' then
        insert into daily_cash_log (store_id, operation_type, direction, amount, notes, created_by, cash_movement_id)
          values (tr.to_store_id, 'استلام نقد من فرع آخر', 'in', it.amount, 'سند ' || tr.transfer_number, me, cm);
      end if;
    elsif it.piece_id is not null then
      update pieces set store_id = tr.to_store_id, status = 'available' where id = it.piece_id and status = 'in_transit';
      insert into piece_movements (store_id, piece_id, event_type, note, created_by)
        values (tr.to_store_id, it.piece_id, 'transfer_in', 'استلام من فرع آخر بسند ' || tr.transfer_number, me);
    elsif it.diamond_piece_id is not null then
      if exists (select 1 from diamond_pieces where store_id = tr.to_store_id and barcode = it.barcode and id <> it.diamond_piece_id) then
        raise exception 'يوجد في هذا الفرع قطعة ألماس أخرى بنفس الباركود %', it.barcode;
      end if;
      update diamond_pieces set store_id = tr.to_store_id, status = 'available' where id = it.diamond_piece_id and status = 'in_transit';
    end if;
    update branch_transfer_items set received_at = now(), received_by = me where id = it.id;
    got := got + 1;
  end loop;
  if (p_barcodes is not null or p_items is not null) and got = 0 then
    raise exception 'غير موجود في هذا السند أو استُلم من قبل';
  end if;

  select count(*) into left_n from branch_transfer_items where transfer_id = tr.id and received_at is null;
  if left_n = 0 then
    update branch_transfers set status = 'received', received_by = me, received_at = now() where id = tr.id;
  end if;
  return jsonb_build_object('received', got, 'remaining', left_n);
end $function$;

create or replace function public.cancel_branch_transfer(p_transfer uuid)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare tr record; it record; d jsonb; me uuid; back int := 0; got int; cm uuid;
begin
  select * into tr from branch_transfers where id = p_transfer for update;
  if tr is null then raise exception 'سند النقل غير موجود'; end if;
  if not has_permission('stock_transfers', tr.from_store_id) then
    raise exception 'ليس لديك صلاحية إلغاء سند النقل' using errcode = '42501';
  end if;
  if tr.status <> 'in_transit' then raise exception 'هذا السند ليس بالطريق (حالته: %)', tr.status; end if;
  select id into me from staff where user_id = auth.uid() and store_id = tr.from_store_id limit 1;

  for it in select * from branch_transfer_items where transfer_id = tr.id and received_at is null for update loop
    if it.kind = 'scrap' then
      for d in select * from jsonb_array_elements(coalesce(it.lot_draws, '[]'::jsonb)) loop
        update gold_stock_lots set weight_grams_remaining = weight_grams_remaining + (d->>'w')::numeric
         where id = (d->>'lot_id')::uuid;
      end loop;
    elsif it.kind = 'cash' then
      insert into cash_movements (store_id, box, direction, amount, description, created_by)
        values (tr.from_store_id, it.cash_box, 'in', it.amount, 'إلغاء نقل نقد بسند ' || tr.transfer_number, me) returning id into cm;
      if it.cash_box = 'main' then
        insert into daily_cash_log (store_id, operation_type, direction, amount, notes, created_by, cash_movement_id)
          values (tr.from_store_id, 'إلغاء نقل نقد لفرع آخر', 'in', it.amount, 'سند ' || tr.transfer_number, me, cm);
      end if;
    elsif it.piece_id is not null then
      update pieces set status = 'available' where id = it.piece_id and status = 'in_transit' and store_id = tr.from_store_id;
      insert into piece_movements (store_id, piece_id, event_type, note, created_by)
        values (tr.from_store_id, it.piece_id, 'transfer_cancelled', 'إلغاء سند النقل ' || tr.transfer_number, me);
    elsif it.diamond_piece_id is not null then
      update diamond_pieces set status = 'available' where id = it.diamond_piece_id and status = 'in_transit' and store_id = tr.from_store_id;
    end if;
    delete from branch_transfer_items where id = it.id;
    back := back + 1;
  end loop;
  select count(*) into got from branch_transfer_items where transfer_id = tr.id;
  -- what was already received stays there; the voucher keeps only that
  update branch_transfers set status = case when got > 0 then 'received' else 'cancelled' end where id = tr.id;
  return jsonb_build_object('returned', back, 'kept', got);
end $function$;

revoke all on function public.send_branch_transfer(uuid, uuid, text[], text, jsonb, jsonb) from public, anon;
revoke all on function public.receive_branch_transfer(uuid, text[], uuid[]) from public, anon;
revoke all on function public.cancel_branch_transfer(uuid) from public, anon;
grant execute on function public.send_branch_transfer(uuid, uuid, text[], text, jsonb, jsonb) to authenticated;
grant execute on function public.receive_branch_transfer(uuid, text[], uuid[]) to authenticated;
grant execute on function public.cancel_branch_transfer(uuid) to authenticated;

commit;
