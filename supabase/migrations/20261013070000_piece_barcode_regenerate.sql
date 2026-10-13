-- Regenerate a piece's barcode. The old number is kept forever in piece_barcode_history
-- as "cancelled" and is never handed out again, so a stray old sticker shows up in
-- inventory counts as cancelled instead of matching the piece.
-- Nothing is deleted: only additions and a widened check constraint.

create table if not exists public.piece_barcode_history (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  piece_id uuid references public.pieces(id) on delete set null,
  old_barcode text not null unique,
  new_barcode text not null,
  changed_by uuid references auth.users(id) on delete set null,
  changed_at timestamptz not null default now()
);
create index if not exists piece_barcode_history_store_idx on public.piece_barcode_history (store_id);

alter table public.piece_barcode_history enable row level security;
drop policy if exists "store members read barcode history" on public.piece_barcode_history;
create policy "store members read barcode history" on public.piece_barcode_history
  for select to authenticated using (public.is_store_member(store_id));
grant select on public.piece_barcode_history to authenticated;

create or replace function public.regenerate_piece_barcode(p_piece_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
  p record;
  new_bc text;
  tries int := 0;
begin
  select * into p from public.pieces where id = p_piece_id for update;
  if not found then raise exception 'PIECE_NOT_FOUND'; end if;
  if not public.has_permission('edit_piece', p.store_id) then raise exception 'NOT_AUTHORIZED'; end if;
  if p.barcode is null then raise exception 'NO_BARCODE'; end if;

  -- next number from the store's sequence; skip any number already used or cancelled
  loop
    new_bc := public.next_piece_barcode(p.store_id, 'gold');
    tries := tries + 1;
    exit when not exists (select 1 from public.pieces where barcode = new_bc)
          and not exists (select 1 from public.piece_barcode_history where old_barcode = new_bc);
    if tries >= 20 then raise exception 'BARCODE_COLLISION'; end if;
  end loop;

  insert into public.piece_barcode_history (store_id, piece_id, old_barcode, new_barcode, changed_by)
  values (p.store_id, p.id, p.barcode, new_bc, auth.uid());

  -- the chip still holds the old EPC until it is programmed again
  update public.pieces set barcode = new_bc, rfid_epc = null, rfid_encoded_at = null where id = p.id;
  return new_bc;
end $$;
revoke all on function public.regenerate_piece_barcode(uuid) from public, anon;
grant execute on function public.regenerate_piece_barcode(uuid) to authenticated;

-- inventory count scans can now record a cancelled barcode
alter table public.inventory_count_scans drop constraint if exists inventory_count_scans_match_status_check;
alter table public.inventory_count_scans add constraint inventory_count_scans_match_status_check
  check (match_status = any (array['matched'::text, 'unexpected'::text, 'duplicate'::text, 'cancelled'::text]));
