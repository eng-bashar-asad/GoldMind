-- Multi-branch plan step 1.5: add a branch to my organization, and mark the head office.
-- * organizations.head_office_store_id: the branch that deals with traders and receives goods
--   (used from step 2.3). Defaults to the primary store; must be a branch of the same organization.
-- * create_branch(from_store, name): organization owner only. New store in the same organization,
--   settings and gold prices copied from the store the owner is in, the owner added with the same
--   permissions, and a subscription that ends with the primary store's (decision 5, co-terming;
--   the prorated charge comes in step 3.3).
-- A new independent company keeps using register_new_company (its own organization, decision 11).
-- No data is deleted.

alter table public.organizations add column if not exists head_office_store_id uuid references public.stores(id) on delete set null;
update public.organizations set head_office_store_id = primary_store_id where head_office_store_id is null;

create or replace function public.check_head_office_in_org()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.head_office_store_id is not null
     and not exists (select 1 from stores where id = new.head_office_store_id and organization_id = new.id) then
    raise exception 'المكتب الرئيسي يجب أن يكون أحد فروع نفس المنشأة';
  end if;
  return new;
end $$;
drop trigger if exists trg_org_head_office_check on public.organizations;
create trigger trg_org_head_office_check before insert or update of head_office_store_id on public.organizations
  for each row execute function public.check_head_office_in_org();

create or replace function public.create_branch(p_from_store uuid, p_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  org uuid;
  me record;
  src record;
  new_id uuid;
  nm text := btrim(coalesce(p_name, ''));
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select organization_id into org from stores where id = p_from_store;
  if org is null or not is_org_owner(org) then
    raise exception 'إضافة فرع متاحة لمالك المنشأة فقط' using errcode = '42501';
  end if;
  if nm = '' then raise exception 'اكتب اسم الفرع'; end if;
  if exists (select 1 from stores where organization_id = org and lower(btrim(name)) = lower(nm)) then
    raise exception 'يوجد فرع بنفس الاسم في هذه المنشأة';
  end if;
  select * into me from staff where store_id = p_from_store and user_id = auth.uid() limit 1;
  select * into src from stores where id = p_from_store;

  -- settings only: address, phone, licence, branch code and emirate, devices and counters start fresh
  insert into stores (name, organization_id, currency, vat_rate, country, gold_price_source, invoice_numbering_mode,
      invoice_print_frame, invoice_print_shape, diamonds_enabled, einvoice_disabled,
      piece_barcode_prefix_gold, piece_barcode_prefix_diamond, piece_barcode_seq_width_gold, piece_barcode_seq_width_diamond,
      secondary_currency, secondary_currency_rate, secondary_currency_rate_updated_at, rfid_enabled, auto_capture_photo_enabled,
      last_gold_ounce_price, last_gold_ounce_rate, fab_rate_retail, fab_rate_wholesale, fab_rate_wholesale2,
      label_mc_multiplier, label_mc_addend, zebra_label_width_mm, zebra_label_height_mm, zebra_label_dpi,
      zebra_label_x_offset_mm, zebra_label_y_offset_mm, zebra_barcode_height_mm, zebra_label_rotate_180, zebra_darkness,
      zebra_field_spacing_mm, zebra_barcode_module_width, allow_biometric_login, debt_alert_days, debt_alert_customers,
      debt_alert_traders, terms_accepted_at, terms_accepted_version)
  values (nm, org, src.currency, src.vat_rate, src.country, src.gold_price_source, src.invoice_numbering_mode,
      src.invoice_print_frame, src.invoice_print_shape, src.diamonds_enabled, src.einvoice_disabled,
      src.piece_barcode_prefix_gold, src.piece_barcode_prefix_diamond, src.piece_barcode_seq_width_gold, src.piece_barcode_seq_width_diamond,
      src.secondary_currency, src.secondary_currency_rate, src.secondary_currency_rate_updated_at, src.rfid_enabled, src.auto_capture_photo_enabled,
      src.last_gold_ounce_price, src.last_gold_ounce_rate, src.fab_rate_retail, src.fab_rate_wholesale, src.fab_rate_wholesale2,
      src.label_mc_multiplier, src.label_mc_addend, src.zebra_label_width_mm, src.zebra_label_height_mm, src.zebra_label_dpi,
      src.zebra_label_x_offset_mm, src.zebra_label_y_offset_mm, src.zebra_barcode_height_mm, src.zebra_label_rotate_180, src.zebra_darkness,
      src.zebra_field_spacing_mm, src.zebra_barcode_module_width, src.allow_biometric_login, src.debt_alert_days, src.debt_alert_customers,
      src.debt_alert_traders, src.terms_accepted_at, src.terms_accepted_version)
  returning id into new_id;

  insert into gold_prices (store_id, karat, price_per_gram, mode)
    select new_id, karat, price_per_gram, mode from gold_prices where store_id = p_from_store;

  -- same plan and end date as the organization's primary store
  insert into subscriptions (store_id, plan_id, status, trial_end, current_period_end, grace_period_days)
    select new_id, s.plan_id, s.status, s.trial_end, s.current_period_end, s.grace_period_days
    from subscriptions s join organizations o on o.primary_store_id = s.store_id
    where o.id = org limit 1;

  insert into staff (user_id, store_id, full_name, role, permissions, contact_phone, whatsapp_phone)
    values (auth.uid(), new_id, coalesce(me.full_name, split_part((select email from auth.users where id = auth.uid()), '@', 1)),
            'owner', me.permissions, me.contact_phone, me.whatsapp_phone);

  insert into audit_log (store_id, staff_id, action_type, description)
    values (p_from_store, me.id, 'branch_created', 'إضافة فرع جديد: ' || nm);

  return new_id;
end $$;
revoke all on function public.create_branch(uuid, text) from public, anon;
grant execute on function public.create_branch(uuid, text) to authenticated;
