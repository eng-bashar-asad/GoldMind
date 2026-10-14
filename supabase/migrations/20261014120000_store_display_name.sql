-- Internal name for the company list and the top of the screen (Bashar 2026-10-14).
-- Invoices and printouts keep using stores.name. Empty = fall back to stores.name.
-- Only adds a column and keeps my_stores()'s signature and grants. Safe to run twice.

alter table public.stores add column if not exists display_name text;

create or replace function public.my_stores()
returns table(store_id uuid, store_name text, role text)
language sql stable security definer set search_path to 'public' as $function$
  select s.store_id, coalesce(nullif(btrim(st.display_name), ''), st.name), s.role
  from public.staff s
  join public.stores st on st.id = s.store_id
  where s.user_id = auth.uid()
  order by 2;
$function$;
