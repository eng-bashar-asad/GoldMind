-- Error monitoring: code errors on users' devices are reported here (supabase-config.js)
-- and shown to the platform owner in the admin panel ("أخطاء البرنامج" tab).
create table if not exists public.client_errors (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  user_id uuid default auth.uid(),
  store_id uuid references public.stores(id) on delete cascade,
  page text check (char_length(page) <= 200),
  message text not null check (char_length(message) <= 1000),
  source text check (char_length(source) <= 300),
  line int,
  stack text check (char_length(stack) <= 4000),
  user_agent text check (char_length(user_agent) <= 300),
  app_version text check (char_length(app_version) <= 50)
);
create index if not exists client_errors_created_at_idx on public.client_errors (created_at desc);
create index if not exists client_errors_store_id_idx on public.client_errors (store_id);
alter table public.client_errors enable row level security;
-- any signed-in user may report an error about themselves, for a store they belong to (or none)
create policy "report own errors" on public.client_errors for insert to authenticated
  with check (user_id = (select auth.uid()) and (store_id is null or is_store_member(store_id)));
-- only the platform owner reads them (admin panel)
create policy "platform admins read errors" on public.client_errors for select to authenticated
  using ((select is_platform_admin()));
grant insert on public.client_errors to authenticated;
grant select on public.client_errors to authenticated;
