-- Who is online: each signed-in device pings staff_heartbeat() about once a
-- minute; the owner's home screen lists staff seen in the last ~2 minutes.
create table if not exists public.staff_presence (
  staff_id uuid primary key references public.staff(id) on delete cascade,
  store_id uuid not null references public.stores(id) on delete cascade,
  last_seen_at timestamptz not null default now(),
  last_page text
);
create index if not exists staff_presence_store_idx on public.staff_presence(store_id);
alter table public.staff_presence enable row level security;

-- Read: colleagues of the same store. No direct writes: only the function below.
drop policy if exists staff_presence_select on public.staff_presence;
create policy staff_presence_select on public.staff_presence
  for select using (public.is_store_member(store_id));

create or replace function public.staff_heartbeat(p_store uuid, p_page text default null)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.staff_presence (staff_id, store_id, last_seen_at, last_page)
  select s.id, s.store_id, now(), left(p_page, 80)
  from public.staff s
  where s.user_id = auth.uid() and s.store_id = p_store
  on conflict (staff_id) do update
    set last_seen_at = excluded.last_seen_at, last_page = excluded.last_page;
$$;
revoke all on function public.staff_heartbeat(uuid, text) from public, anon;
grant execute on function public.staff_heartbeat(uuid, text) to authenticated;
revoke all on table public.staff_presence from anon;
grant select on table public.staff_presence to authenticated;
