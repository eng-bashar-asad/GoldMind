-- Program RFID chips from the computer/phone with a handheld (Chainway C72)
-- lying on the desk as the "encoder": the page queues a job, the handheld
-- (native screen, no sign-in) picks it up with the shop's device key, writes
-- the chip and reports back; the piece then gets its rfid_epc.
-- ponytail: the device key is a shared secret typed once into the handheld;
-- upgrade path = per-device keys / a real encoder printer.

alter table public.stores add column if not exists rfid_device_key text;

create table if not exists public.rfid_write_jobs (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id),
  piece_id uuid not null references public.pieces(id),
  barcode text not null,
  epc text not null check (epc ~ '^[0-9A-F]{24}$'),
  status text not null default 'pending' check (status in ('pending','working','done','failed','cancelled')),
  message text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  done_at timestamptz
);
create index if not exists rfid_write_jobs_pending on public.rfid_write_jobs (store_id, created_at) where status in ('pending','working');
alter table public.rfid_write_jobs enable row level security;
create policy rfid_jobs_select on public.rfid_write_jobs for select using (is_store_member(store_id));
create policy rfid_jobs_insert on public.rfid_write_jobs for insert with check (has_permission('edit_piece', store_id));
create policy rfid_jobs_update on public.rfid_write_jobs for update using (has_permission('edit_piece', store_id));

-- staff: create / replace the shop's device key (shown once in the settings page)
create or replace function public.rfid_device_key_reset(p_store uuid) returns text
language plpgsql security definer set search_path = public as $$
declare k text;
begin
  if not has_permission('edit_piece', p_store) then raise exception 'ليس لديك صلاحية' using errcode = '42501'; end if;
  k := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));
  update stores set rfid_device_key = k where id = p_store;
  return k;
end $$;

-- handheld: who am I linked to
create or replace function public.rfid_device_hello(p_key text) returns jsonb
language sql security definer set search_path = public as $$
  select jsonb_build_object('store', name, 'prefix', upper(substr(replace(id::text, '-', ''), 1, 8)))
    from stores where rfid_device_key is not null and length(p_key) >= 12 and rfid_device_key = upper(trim(p_key));
$$;

-- handheld: oldest waiting job (younger than 5 minutes), marked as being worked on
create or replace function public.rfid_device_next(p_key text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare st uuid; j record;
begin
  select id into st from stores where rfid_device_key is not null and length(p_key) >= 12 and rfid_device_key = upper(trim(p_key));
  if st is null then raise exception 'رمز الربط غير صحيح'; end if;
  update rfid_write_jobs set status = 'cancelled', message = 'انتهت المهلة'
   where store_id = st and status in ('pending','working') and created_at < now() - interval '5 minutes';
  select * into j from rfid_write_jobs where store_id = st and status = 'pending' order by created_at limit 1 for update skip locked;
  if j.id is null then return null; end if;
  update rfid_write_jobs set status = 'working' where id = j.id;
  return jsonb_build_object('id', j.id, 'barcode', j.barcode, 'epc', j.epc);
end $$;

-- handheld: result of a job; a success stores the chip number on the piece
create or replace function public.rfid_device_done(p_key text, p_job uuid, p_ok boolean, p_msg text default null) returns void
language plpgsql security definer set search_path = public as $$
declare st uuid; j record;
begin
  select id into st from stores where rfid_device_key is not null and length(p_key) >= 12 and rfid_device_key = upper(trim(p_key));
  if st is null then raise exception 'رمز الربط غير صحيح'; end if;
  select * into j from rfid_write_jobs where id = p_job and store_id = st and status in ('pending','working');
  if j.id is null then return; end if;
  update rfid_write_jobs set status = case when p_ok then 'done' else 'failed' end, message = left(p_msg, 300), done_at = now() where id = j.id;
  if p_ok then update pieces set rfid_epc = j.epc, rfid_encoded_at = now() where id = j.piece_id and store_id = st; end if;
end $$;

revoke all on function public.rfid_device_key_reset(uuid) from public, anon;
grant execute on function public.rfid_device_key_reset(uuid) to authenticated;
grant execute on function public.rfid_device_hello(text), public.rfid_device_next(text), public.rfid_device_done(text, uuid, boolean, text) to anon, authenticated;
