-- Multi-branch plan step 1.3b (contract): the legal identity lives only on organizations.
-- Drops the copies on stores (legal_name, tax_number, logo_url, commercial_registration_number,
-- legal_registration_id_type, emirate_code, peppol_endpoint_id) and the two-way sync triggers.
-- stores.country stays (decision 10) and is still copied to the organization from its primary store.
-- No unique constraint on any legal field (decision 11).
-- Runs as one transaction: if the safety check fails, nothing changes.

begin;

-- 0) safety: every store has an organization and its copies match it, so nothing is lost
do $$
declare bad int;
begin
  select count(*) into bad from stores s left join organizations o on o.id = s.organization_id
  where o.id is null
     or s.legal_name is distinct from o.legal_name or s.tax_number is distinct from o.tax_number
     or s.logo_url is distinct from o.logo_url
     or s.commercial_registration_number is distinct from o.commercial_registration_number
     or s.legal_registration_id_type is distinct from o.legal_registration_id_type
     or s.emirate_code is distinct from o.emirate_code or s.peppol_endpoint_id is distinct from o.peppol_endpoint_id;
  if bad > 0 then raise exception 'توقف: % فرع بياناته القانونية لا تطابق منشأته — لم يُحذف شيء', bad; end if;
end $$;

-- 1) the two-way sync goes
drop trigger if exists trg_stores_sync_legal on public.stores;
drop trigger if exists trg_org_sync_legal on public.organizations;
drop function if exists public.sync_store_legal_to_org();
drop function if exists public.sync_org_legal_to_stores();

-- 2) country only: primary store → organization (decision 10)
create or replace function public.sync_store_country_to_org()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update organizations set country = new.country where id = new.organization_id and primary_store_id = new.id;
  return null;
end $$;
revoke all on function public.sync_store_country_to_org() from public;
create trigger trg_stores_sync_country after update of country on public.stores
  for each row when (old.country is distinct from new.country) execute function public.sync_store_country_to_org();

-- 3) a new store's organization starts from its name and country only
create or replace function public.ensure_store_organization()
returns trigger language plpgsql security definer set search_path = public as $$
declare new_org uuid;
begin
  insert into organizations (name, primary_store_id, country) values (new.name, new.id, new.country)
    returning id into new_org;
  update stores set organization_id = new_org where id = new.id;
  return null;
end $$;

-- 4) legal data from the organization only; a branch emirate still overrides
create or replace function public.store_legal(p_store_id uuid)
returns table(organization_id uuid, organization_name text, legal_name text, tax_number text, country text, logo_url text,
  commercial_registration_number text, legal_registration_id_type text, emirate_code text, peppol_endpoint_id text)
language sql stable set search_path = public as $$
  select s.organization_id, o.name, o.legal_name, o.tax_number, coalesce(o.country, s.country), o.logo_url,
         o.commercial_registration_number, o.legal_registration_id_type,
         coalesce(s.branch_emirate_code, o.emirate_code), o.peppol_endpoint_id
  from stores s left join organizations o on o.id = s.organization_id
  where s.id = p_store_id;
$$;

-- 5) public receipts: same signatures and grants, logo and TRN from the organization only
create or replace function public.get_invoice_receipt(p_id uuid)
returns table(invoice_number text, invoice_type text, status text, payment_method text, vat_amount numeric, total_amount numeric,
  created_at timestamp with time zone, store_name text, store_logo_url text, store_address text, store_phone text, store_email text,
  vat_rate numeric, tax_number text, currency text, secondary_currency text, secondary_currency_rate numeric,
  customer_name text, customer_phone text, items jsonb)
language sql security definer set search_path = public as $$
  select inv.invoice_number, inv.type, inv.status, inv.payment_method, inv.vat_amount, inv.total_amount, inv.created_at,
    s.name, o.logo_url, s.address, s.phone, s.email, s.vat_rate, o.tax_number,
    s.currency, s.secondary_currency, s.secondary_currency_rate,
    c.name, c.phone,
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'description', ii.description, 'description_en', ii.description_en, 'karat', ii.karat,
        'weight_grams', ii.weight_grams, 'line_total', ii.line_total, 'quantity', 1) order by ii.id)
      from invoice_items ii where ii.invoice_id = inv.id
    ), '[]'::jsonb)
  from invoices inv
  join stores s on s.id = inv.store_id
  left join organizations o on o.id = s.organization_id
  left join customers c on c.id = inv.customer_id
  where inv.id = p_id and inv.status != 'cancelled';
$$;

create or replace function public.get_repair_receipt(p_id uuid)
returns table(ticket_number text, piece_description text, problem_description text, intake_photo_url text, ready_photo_url text,
  status text, received_at timestamp with time zone, ready_at timestamp with time zone, store_name text, store_logo_url text,
  store_address text, store_phone text, received_by_name text, invoice_print_frame text, invoice_print_shape text,
  estimated_cost numeric, actual_cost numeric, vat_rate numeric, tax_number text)
language sql security definer set search_path = public as $$
  select rt.ticket_number, rt.piece_description, rt.problem_description, rt.intake_photo_url, rt.ready_photo_url,
    rt.status, rt.received_at, rt.ready_at,
    s.name, o.logo_url, s.address, s.phone, st.full_name, s.invoice_print_frame, s.invoice_print_shape,
    rt.estimated_cost, rt.actual_cost, s.vat_rate, o.tax_number
  from repair_tickets rt
  join stores s on s.id = rt.store_id
  left join organizations o on o.id = s.organization_id
  left join staff st on st.id = rt.received_by
  where rt.id = p_id;
$$;

-- 6) drop the store copies
alter table public.stores
  drop column legal_name,
  drop column tax_number,
  drop column logo_url,
  drop column commercial_registration_number,
  drop column legal_registration_id_type,
  drop column emirate_code,
  drop column peppol_endpoint_id;

commit;
