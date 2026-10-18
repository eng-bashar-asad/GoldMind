-- Multi-branch 2.4 (part 1, pieces): transfer voucher between branches of one organization
-- (decision 13 + بشار 2026-10-19: the receiving branch confirms).
--   * send_branch_transfer(from, to, barcodes, notes): the pieces leave the sending branch's
--     stock at once (status 'in_transit', still on the sender) so its count shows no shortage.
--   * receive_branch_transfer(transfer, barcodes): staff of the receiving branch confirm all or
--     some pieces (by scan); each confirmed piece moves to that branch (same barcode, same
--     specs and cost) and is available there.
--   * cancel_branch_transfer(transfer): the sender takes back the pieces not received yet.
-- Permission: stock_transfers on the branch acting (owners always). No sale, no VAT, no cash.
-- Nothing changes for existing data or single-branch shops. Run it ONCE.

begin;

create table if not exists public.branch_transfers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id),
  from_store_id uuid not null references public.stores(id) on delete cascade,
  to_store_id uuid not null references public.stores(id) on delete cascade,
  transfer_number text not null,
  status text not null default 'in_transit' check (status in ('in_transit', 'received', 'cancelled')),
  notes text,
  created_by uuid references public.staff(id),
  created_at timestamptz not null default now(),
  received_by uuid references public.staff(id),
  received_at timestamptz
);
create index if not exists branch_transfers_to_idx on public.branch_transfers (to_store_id, status);
create index if not exists branch_transfers_from_idx on public.branch_transfers (from_store_id, created_at desc);

-- a copy of what was sent, so the receiving branch sees it before the pieces are its own
create table if not exists public.branch_transfer_items (
  id uuid primary key default gen_random_uuid(),
  transfer_id uuid not null references public.branch_transfers(id) on delete cascade,
  piece_id uuid references public.pieces(id) on delete set null,
  diamond_piece_id uuid references public.diamond_pieces(id) on delete set null,
  barcode text,
  description text,
  karat int,
  weight_grams numeric,
  photo_url text,
  received_at timestamptz,
  received_by uuid references public.staff(id)
);
create index if not exists branch_transfer_items_transfer_idx on public.branch_transfer_items (transfer_id);

alter table public.branch_transfers enable row level security;
alter table public.branch_transfer_items enable row level security;
drop policy if exists branch_transfers_select on public.branch_transfers;
create policy branch_transfers_select on public.branch_transfers for select to authenticated
  using (is_store_member(from_store_id) or is_store_member(to_store_id));
drop policy if exists branch_transfer_items_select on public.branch_transfer_items;
create policy branch_transfer_items_select on public.branch_transfer_items for select to authenticated
  using (transfer_id in (select id from public.branch_transfers t where is_store_member(t.from_store_id) or is_store_member(t.to_store_id)));
grant select on public.branch_transfers, public.branch_transfer_items to authenticated;

create or replace function public.send_branch_transfer(p_from uuid, p_to uuid, p_barcodes text[], p_notes text default null)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare org uuid; me uuid; tid uuid; num text; bc text; pc record; dp record; n int := 0;
begin
  if not has_permission('stock_transfers', p_from) then
    raise exception 'ليس لديك صلاحية نقل البضاعة بين الفروع' using errcode = '42501';
  end if;
  if p_to is null or p_to = p_from or p_to not in (select org_store_ids(p_from)) then
    raise exception 'اختر فرعاً آخر من نفس المنشأة';
  end if;
  if p_barcodes is null or cardinality(p_barcodes) = 0 then raise exception 'أضف قطعة واحدة على الأقل'; end if;
  select organization_id into org from stores where id = p_from;
  select id into me from staff where user_id = auth.uid() and store_id = p_from limit 1;

  perform pg_advisory_xact_lock(hashtext('branch_transfer:' || coalesce(org, p_from)::text));
  select 'TRF-' || lpad((coalesce(max(nullif(regexp_replace(transfer_number, '\D', '', 'g'), '')::int), 0) + 1)::text, 6, '0')
    into num from branch_transfers where coalesce(organization_id, from_store_id) = coalesce(org, p_from);
  insert into branch_transfers (organization_id, from_store_id, to_store_id, transfer_number, notes, created_by)
    values (org, p_from, p_to, num, nullif(trim(p_notes), ''), me) returning id into tid;

  foreach bc in array p_barcodes loop
    bc := nullif(trim(bc), '');
    continue when bc is null;
    select * into pc from pieces where store_id = p_from and barcode = bc for update;
    if found then
      if pc.status <> 'available' then raise exception 'القطعة % غير متاحة للنقل (حالتها: %)', bc, pc.status; end if;
      update pieces set status = 'in_transit' where id = pc.id;
      insert into branch_transfer_items (transfer_id, piece_id, barcode, description, karat, weight_grams, photo_url)
        values (tid, pc.id, pc.barcode, coalesce(pc.description_ar, pc.piece_type), pc.karat, pc.weight_grams, pc.photo_url);
      insert into piece_movements (store_id, piece_id, event_type, note, created_by)
        values (p_from, pc.id, 'transfer_out', 'نقل إلى فرع آخر بسند ' || num, me);
    else
      select * into dp from diamond_pieces where store_id = p_from and barcode = bc for update;
      if not found then raise exception 'القطعة % غير موجودة في هذا الفرع', bc; end if;
      if dp.status <> 'available' then raise exception 'القطعة % غير متاحة للنقل (حالتها: %)', bc, dp.status; end if;
      update diamond_pieces set status = 'in_transit' where id = dp.id;
      insert into branch_transfer_items (transfer_id, diamond_piece_id, barcode, description, karat, weight_grams, photo_url)
        values (tid, dp.id, dp.barcode, dp.description_ar, dp.gold_karat, dp.gold_weight_grams, dp.photo_url);
    end if;
    n := n + 1;
  end loop;
  if n = 0 then raise exception 'أضف قطعة واحدة على الأقل'; end if;
  return jsonb_build_object('id', tid, 'transfer_number', num, 'items', n);
end $function$;

create or replace function public.receive_branch_transfer(p_transfer uuid, p_barcodes text[] default null)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare tr record; it record; me uuid; got int := 0; left_n int;
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
               and (p_barcodes is null or barcode = any(p_barcodes)) for update
  loop
    if it.piece_id is not null then
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
  if p_barcodes is not null and got = 0 then raise exception 'الباركود غير موجود في هذا السند أو استُلم من قبل'; end if;

  select count(*) into left_n from branch_transfer_items where transfer_id = tr.id and received_at is null;
  if left_n = 0 then
    update branch_transfers set status = 'received', received_by = me, received_at = now() where id = tr.id;
  end if;
  return jsonb_build_object('received', got, 'remaining', left_n);
end $function$;

create or replace function public.cancel_branch_transfer(p_transfer uuid)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare tr record; me uuid; back int := 0; d int; got int;
begin
  select * into tr from branch_transfers where id = p_transfer for update;
  if tr is null then raise exception 'سند النقل غير موجود'; end if;
  if not has_permission('stock_transfers', tr.from_store_id) then
    raise exception 'ليس لديك صلاحية إلغاء سند النقل' using errcode = '42501';
  end if;
  if tr.status <> 'in_transit' then raise exception 'هذا السند ليس بالطريق (حالته: %)', tr.status; end if;
  select id into me from staff where user_id = auth.uid() and store_id = tr.from_store_id limit 1;
  update pieces set status = 'available'
    where status = 'in_transit' and store_id = tr.from_store_id
      and id in (select piece_id from branch_transfer_items where transfer_id = tr.id and received_at is null);
  get diagnostics back = row_count;
  update diamond_pieces set status = 'available'
    where status = 'in_transit' and store_id = tr.from_store_id
      and id in (select diamond_piece_id from branch_transfer_items where transfer_id = tr.id and received_at is null);
  get diagnostics d = row_count;
  back := back + d;
  insert into piece_movements (store_id, piece_id, event_type, note, created_by)
    select tr.from_store_id, piece_id, 'transfer_cancelled', 'إلغاء سند النقل ' || tr.transfer_number, me
      from branch_transfer_items where transfer_id = tr.id and received_at is null and piece_id is not null;
  delete from branch_transfer_items where transfer_id = tr.id and received_at is null;
  select count(*) into got from branch_transfer_items where transfer_id = tr.id;
  -- pieces already received stay where they are; the voucher keeps only them
  update branch_transfers set status = case when got > 0 then 'received' else 'cancelled' end where id = tr.id;
  return jsonb_build_object('returned', back, 'kept', got);
end $function$;

revoke all on function public.send_branch_transfer(uuid, uuid, text[], text) from public, anon;
revoke all on function public.receive_branch_transfer(uuid, text[]) from public, anon;
revoke all on function public.cancel_branch_transfer(uuid) from public, anon;
grant execute on function public.send_branch_transfer(uuid, uuid, text[], text) to authenticated;
grant execute on function public.receive_branch_transfer(uuid, text[]) to authenticated;
grant execute on function public.cancel_branch_transfer(uuid) to authenticated;

commit;
