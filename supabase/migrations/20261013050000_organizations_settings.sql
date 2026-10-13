-- Multi-branch plan step 1.2 — the organization becomes where legal data is edited.
-- Decision 9: e-invoicing identity belongs to the organization (Peppol ID = 0235 + TIN).
-- Nothing existing breaks: every page that reads these fields from stores keeps
-- working, because an organization edit is mirrored into all of its stores.
-- Contains DROP POLICY / DROP TRIGGER / DROP FUNCTION (replacements only, no data
-- removed) — run by the owner.

-- 1) The remaining e-invoicing identity fields move to the organization (copied)
alter table public.organizations
  add column if not exists commercial_registration_number text,
  add column if not exists legal_registration_id_type text,
  add column if not exists emirate_code text,
  add column if not exists peppol_endpoint_id text;

update public.organizations o
   set commercial_registration_number = s.commercial_registration_number,
       legal_registration_id_type = s.legal_registration_id_type,
       emirate_code = s.emirate_code,
       peppol_endpoint_id = s.peppol_endpoint_id
  from public.stores s
 where s.id = o.primary_store_id;

-- 2) Optional per-branch emirate (only when a branch sits in another emirate)
alter table public.stores add column if not exists branch_emirate_code text;

-- 3) Only the owner of the head store edits the organization
create or replace function public.is_org_owner(p_org uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from staff st join organizations o on o.primary_store_id = st.store_id
    where o.id = p_org and st.user_id = auth.uid() and st.role = 'owner');
$$;
revoke all on function public.is_org_owner(uuid) from public, anon;
grant execute on function public.is_org_owner(uuid) to authenticated;

drop policy if exists "owner can update own organization" on public.organizations;
drop policy if exists "org owner can update organization" on public.organizations;
create policy "org owner can update organization" on public.organizations
  for update to authenticated
  using (public.is_org_owner(id)) with check (public.is_org_owner(id));

-- 4) New stores copy all legal fields into their new organization
create or replace function public.ensure_store_organization()
returns trigger language plpgsql security definer set search_path = public as $$
declare new_org uuid;
begin
  insert into organizations (name, primary_store_id, legal_name, tax_number, country, logo_url,
                             commercial_registration_number, legal_registration_id_type, emirate_code, peppol_endpoint_id)
  values (new.name, new.id, new.legal_name, new.tax_number, new.country, new.logo_url,
          new.commercial_registration_number, new.legal_registration_id_type, new.emirate_code, new.peppol_endpoint_id)
  returning id into new_org;
  update stores set organization_id = new_org where id = new.id;
  return null;
end $$;

-- 5) Two-way mirror. pg_trigger_depth() stops the ping-pong between the two triggers.
-- ponytail: stores keep a copy so the 20+ pages that print legal data need no change yet;
-- step 1.3 moves them to store_legal(), then the copies and both triggers can go (contract).
create or replace function public.sync_store_legal_to_org()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if pg_trigger_depth() > 1 then return null; end if;
  update organizations o
     set legal_name = new.legal_name, tax_number = new.tax_number,
         country = new.country, logo_url = new.logo_url,
         commercial_registration_number = new.commercial_registration_number,
         legal_registration_id_type = new.legal_registration_id_type,
         emirate_code = new.emirate_code, peppol_endpoint_id = new.peppol_endpoint_id
   where o.id = new.organization_id and o.primary_store_id = new.id;
  return null;
end $$;
revoke all on function public.sync_store_legal_to_org() from public, anon, authenticated;

drop trigger if exists trg_stores_sync_legal on public.stores;
create trigger trg_stores_sync_legal
  after update of legal_name, tax_number, country, logo_url,
                  commercial_registration_number, legal_registration_id_type, emirate_code, peppol_endpoint_id
  on public.stores for each row
  when (old.legal_name is distinct from new.legal_name or old.tax_number is distinct from new.tax_number
     or old.country is distinct from new.country or old.logo_url is distinct from new.logo_url
     or old.commercial_registration_number is distinct from new.commercial_registration_number
     or old.legal_registration_id_type is distinct from new.legal_registration_id_type
     or old.emirate_code is distinct from new.emirate_code
     or old.peppol_endpoint_id is distinct from new.peppol_endpoint_id)
  execute function public.sync_store_legal_to_org();

create or replace function public.sync_org_legal_to_stores()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if pg_trigger_depth() > 1 then return null; end if;
  update stores s
     set legal_name = new.legal_name, tax_number = new.tax_number,
         country = new.country, logo_url = new.logo_url,
         commercial_registration_number = new.commercial_registration_number,
         legal_registration_id_type = new.legal_registration_id_type,
         emirate_code = new.emirate_code, peppol_endpoint_id = new.peppol_endpoint_id
   where s.organization_id = new.id;
  return null;
end $$;
revoke all on function public.sync_org_legal_to_stores() from public, anon, authenticated;

drop trigger if exists trg_org_sync_legal on public.organizations;
create trigger trg_org_sync_legal
  after update of legal_name, tax_number, country, logo_url,
                  commercial_registration_number, legal_registration_id_type, emirate_code, peppol_endpoint_id
  on public.organizations for each row
  when (old.legal_name is distinct from new.legal_name or old.tax_number is distinct from new.tax_number
     or old.country is distinct from new.country or old.logo_url is distinct from new.logo_url
     or old.commercial_registration_number is distinct from new.commercial_registration_number
     or old.legal_registration_id_type is distinct from new.legal_registration_id_type
     or old.emirate_code is distinct from new.emirate_code
     or old.peppol_endpoint_id is distinct from new.peppol_endpoint_id)
  execute function public.sync_org_legal_to_stores();

-- 6) store_legal() now returns the e-invoicing fields too; a branch emirate wins over the organization's
drop function if exists public.store_legal(uuid);
create function public.store_legal(p_store_id uuid)
returns table (organization_id uuid, organization_name text, legal_name text, tax_number text,
               country text, logo_url text, commercial_registration_number text,
               legal_registration_id_type text, emirate_code text, peppol_endpoint_id text)
language sql stable security invoker set search_path = public as $$
  select s.organization_id, o.name,
         coalesce(o.legal_name, s.legal_name), coalesce(o.tax_number, s.tax_number),
         coalesce(o.country, s.country), coalesce(o.logo_url, s.logo_url),
         coalesce(o.commercial_registration_number, s.commercial_registration_number),
         coalesce(o.legal_registration_id_type, s.legal_registration_id_type),
         coalesce(s.branch_emirate_code, o.emirate_code, s.emirate_code),
         coalesce(o.peppol_endpoint_id, s.peppol_endpoint_id)
  from stores s left join organizations o on o.id = s.organization_id
  where s.id = p_store_id;
$$;
revoke all on function public.store_legal(uuid) from public, anon;
grant execute on function public.store_legal(uuid) to authenticated;

-- 7) Check: every organization equals its head store; otherwise nothing is applied
do $$
begin
  if exists (select 1 from public.organizations o join public.stores s on s.id = o.primary_store_id
             where o.legal_name is distinct from s.legal_name or o.tax_number is distinct from s.tax_number
                or o.country is distinct from s.country or o.logo_url is distinct from s.logo_url
                or o.commercial_registration_number is distinct from s.commercial_registration_number
                or o.legal_registration_id_type is distinct from s.legal_registration_id_type
                or o.emirate_code is distinct from s.emirate_code
                or o.peppol_endpoint_id is distinct from s.peppol_endpoint_id) then
    raise exception 'organization data does not match its head store';
  end if;
end $$;
