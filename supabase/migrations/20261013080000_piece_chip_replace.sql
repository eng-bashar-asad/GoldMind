-- Give a piece a new RFID chip number without changing its barcode.
-- The old chip number is kept forever in piece_chip_history as cancelled, so a found
-- old chip shows up in inventory counts as cancelled instead of matching the piece.
-- Nothing is deleted: only additions.

create table if not exists public.piece_chip_history (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  piece_id uuid references public.pieces(id) on delete set null,
  old_epc text not null unique,
  new_epc text not null,
  changed_by uuid references auth.users(id) on delete set null,
  changed_at timestamptz not null default now()
);
create index if not exists piece_chip_history_store_idx on public.piece_chip_history (store_id);

alter table public.piece_chip_history enable row level security;
drop policy if exists "store members read chip history" on public.piece_chip_history;
create policy "store members read chip history" on public.piece_chip_history
  for select to authenticated using (public.is_store_member(store_id));
grant select on public.piece_chip_history to authenticated;

create or replace function public.replace_piece_chip(p_piece_id uuid, p_old_epc text, p_new_epc text)
returns text language plpgsql security definer set search_path = public as $$
declare
  p record;
begin
  select * into p from public.pieces where id = p_piece_id for update;
  if not found then raise exception 'PIECE_NOT_FOUND'; end if;
  if not public.has_permission('edit_piece', p.store_id) then raise exception 'NOT_AUTHORIZED'; end if;
  if p_new_epc is null or p_new_epc !~ '^[0-9A-F]{24}$' then raise exception 'INVALID_EPC'; end if;
  if exists (select 1 from public.pieces where rfid_epc = p_new_epc and id <> p.id)
     or exists (select 1 from public.piece_chip_history where old_epc = p_new_epc) then
    raise exception 'EPC_IN_USE';
  end if;

  insert into public.piece_chip_history (store_id, piece_id, old_epc, new_epc, changed_by)
  values (p.store_id, p.id, p_old_epc, p_new_epc, auth.uid());

  update public.pieces set rfid_epc = p_new_epc, rfid_encoded_at = now() where id = p.id;
  return p_new_epc;
end $$;
revoke all on function public.replace_piece_chip(uuid, text, text) from public, anon;
grant execute on function public.replace_piece_chip(uuid, text, text) to authenticated;
