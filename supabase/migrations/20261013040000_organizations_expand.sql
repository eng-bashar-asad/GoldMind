-- Multi-branch plan step 1.1 — organizations (expand step; nothing is removed).
-- Every existing store gets its own organization (no merging), and the legal data
-- (legal_name, tax_number, country, logo_url) is copied — not moved — to it.
-- The stores columns stay the source the UI writes to until step 1.2;
-- a trigger mirrors them into the organization so both stay equal.
-- ponytail: the stores→organization mirror is temporary; in 1.2 the organization
-- becomes the place the owner edits, and this trigger is dropped (contract step).

-- 1) Legal columns on organizations
alter table public.organizations
  add column if not exists legal_name text,
  add column if not exists tax_number text,
  add column if not exists country text,
  add column if not exists logo_url text;

-- 2) Backfill: one organization per store that has none
do $$
declare s record; new_org uuid;
begin
  for s in select * from public.stores where organization_id is null loop
    insert into public.organizations (name, primary_store_id, legal_name, tax_number, country, logo_url, created_at)
    values (s.name, s.id, s.legal_name, s.tax_number, s.country, s.logo_url, coalesce(s.created_at, now()))
    returning id into new_org;
    update public.stores set organization_id = new_org where id = s.id;
  end loop;
end $$;

-- 3) New stores (any signup path) get their own organization automatically
create or replace function public.ensure_store_organization()
returns trigger language plpgsql security definer set search_path = public as $$
declare new_org uuid;
begin
  insert into organizations (name, primary_store_id, legal_name, tax_number, country, logo_url)
  values (new.name, new.id, new.legal_name, new.tax_number, new.country, new.logo_url)
  returning id into new_org;
  update stores set organization_id = new_org where id = new.id;
  return null;
end $$;
revoke all on function public.ensure_store_organization() from public, anon, authenticated;

drop trigger if exists trg_stores_ensure_org on public.stores;
create trigger trg_stores_ensure_org after insert on public.stores
  for each row when (new.organization_id is null)
  execute function public.ensure_store_organization();

-- 4) Mirror legal edits made on the head store into its organization
create or replace function public.sync_store_legal_to_org()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update organizations o
     set legal_name = new.legal_name, tax_number = new.tax_number,
         country = new.country, logo_url = new.logo_url
   where o.id = new.organization_id and o.primary_store_id = new.id;
  return null;
end $$;
revoke all on function public.sync_store_legal_to_org() from public, anon, authenticated;

drop trigger if exists trg_stores_sync_legal on public.stores;
create trigger trg_stores_sync_legal after update of legal_name, tax_number, country, logo_url on public.stores
  for each row when (
    old.legal_name is distinct from new.legal_name or old.tax_number is distinct from new.tax_number
    or old.country is distinct from new.country or old.logo_url is distinct from new.logo_url)
  execute function public.sync_store_legal_to_org();

-- 5) Staff of any branch can read their organization (existing policy covers the head store only)
drop policy if exists "branch staff can view their organization" on public.organizations;
create policy "branch staff can view their organization" on public.organizations
  for select to authenticated
  using (exists (select 1 from public.stores s where s.organization_id = organizations.id and public.is_store_member(s.id)));

-- 6) One place to read a store's legal identity (organization first, store as fallback)
create or replace function public.store_legal(p_store_id uuid)
returns table (organization_id uuid, organization_name text, legal_name text, tax_number text, country text, logo_url text)
language sql stable security invoker set search_path = public as $$
  select s.organization_id, o.name,
         coalesce(o.legal_name, s.legal_name), coalesce(o.tax_number, s.tax_number),
         coalesce(o.country, s.country), coalesce(o.logo_url, s.logo_url)
  from stores s left join organizations o on o.id = s.organization_id
  where s.id = p_store_id;
$$;
revoke all on function public.store_legal(uuid) from public, anon;
grant execute on function public.store_legal(uuid) to authenticated;

-- 7) Check: every store has its own organization and the copied data matches
do $$
begin
  if exists (select 1 from public.stores where organization_id is null) then
    raise exception 'store without organization';
  end if;
  if exists (select 1 from public.stores s join public.organizations o on o.id = s.organization_id
             where o.primary_store_id is distinct from s.id
                or o.tax_number is distinct from s.tax_number or o.legal_name is distinct from s.legal_name
                or o.country is distinct from s.country or o.logo_url is distinct from s.logo_url) then
    raise exception 'organization data does not match its store';
  end if;
end $$;
