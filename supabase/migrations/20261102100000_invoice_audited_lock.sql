-- «مدقق» (audited) on invoices (Bashar 2026-11-02): once checked, the invoice is locked for any edit
-- (items, totals, customer, salesperson, cancel, delete) until the owner unchecks it from the invoices list.
-- Checking: the owner or staff with the new permission 'audit_invoices'. Unchecking: the owner only.
-- Still allowed on an audited invoice: debt payments settling it (amount_paid, paid <-> unpaid) and the
-- e-invoice XML export. Returns and exchanges are new documents and are not blocked.
alter table public.invoices add column if not exists audited_at timestamptz;
alter table public.invoices add column if not exists audited_by uuid;

create or replace function public.gm_is_store_owner(p_store uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.staff where user_id = auth.uid() and store_id = p_store and role = 'owner');
$$;
revoke all on function public.gm_is_store_owner(uuid) from public, anon;
grant execute on function public.gm_is_store_owner(uuid) to authenticated;

create or replace function public.gm_invoice_audit_guard()
returns trigger language plpgsql set search_path = public as $$
declare
  free text[] := array['amount_paid', 'status', 'einvoice_xml', 'einvoice_uuid', 'einvoice_status', 'audited_at', 'audited_by'];
begin
  if tg_op = 'DELETE' then
    if old.audited_at is not null then
      raise exception 'الفاتورة % مدققة ولا يمكن حذفها. يستطيع المدير إلغاء إشارة «مدقق» من قائمة الفواتير.', old.invoice_number using errcode = '42501';
    end if;
    return old;
  end if;

  -- who may set / clear the mark (auth.uid() is null for the database owner / maintenance)
  if new.audited_at is distinct from old.audited_at and auth.uid() is not null then
    if new.audited_at is null and not public.gm_is_store_owner(old.store_id) then
      raise exception 'إلغاء إشارة «مدقق» للمدير فقط.' using errcode = '42501';
    end if;
    if new.audited_at is not null and not public.has_permission('audit_invoices', old.store_id) then
      raise exception 'ليست لديك صلاحية تدقيق الفواتير.' using errcode = '42501';
    end if;
  end if;

  -- an audited invoice that stays audited: only payment settling and the e-invoice export may change
  if old.audited_at is not null and new.audited_at is not null then
    if (to_jsonb(new) - free) is distinct from (to_jsonb(old) - free)
       or (new.status is distinct from old.status and not (old.status in ('paid', 'unpaid') and new.status in ('paid', 'unpaid'))) then
      raise exception 'الفاتورة % مدققة ومقفلة على التعديل. يستطيع المدير إلغاء إشارة «مدقق» من قائمة الفواتير.', old.invoice_number using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists invoices_audit_guard on public.invoices;
create trigger invoices_audit_guard before update or delete on public.invoices
  for each row execute function public.gm_invoice_audit_guard();

create or replace function public.gm_invoice_items_audit_guard()
returns trigger language plpgsql set search_path = public as $$
declare inv record;
begin
  select invoice_number, audited_at into inv from public.invoices
   where id = case when tg_op = 'DELETE' then old.invoice_id else new.invoice_id end;
  if inv.audited_at is not null then
    raise exception 'الفاتورة % مدققة ومقفلة على التعديل. يستطيع المدير إلغاء إشارة «مدقق» من قائمة الفواتير.', inv.invoice_number using errcode = '42501';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;

drop trigger if exists invoice_items_audit_guard on public.invoice_items;
create trigger invoice_items_audit_guard before insert or update or delete on public.invoice_items
  for each row execute function public.gm_invoice_items_audit_guard();

-- set / clear the mark from the invoices list (the trigger above checks who may do it)
create or replace function public.set_invoice_audited(p_invoice uuid, p_on boolean)
returns timestamptz language plpgsql security definer set search_path = public as $$
declare inv record; me uuid; v_at timestamptz;
begin
  select id, store_id, invoice_number, audited_at into inv from public.invoices where id = p_invoice;
  if inv.id is null or not public.is_store_member(inv.store_id) then raise exception 'NOT_AUTHORIZED'; end if;
  if p_on and inv.audited_at is not null then return inv.audited_at; end if;
  if not p_on and inv.audited_at is null then return null; end if;
  select id into me from public.staff where user_id = auth.uid() and store_id = inv.store_id limit 1;
  v_at := case when p_on then now() else null end;
  update public.invoices set audited_at = v_at, audited_by = case when p_on then me else null end where id = inv.id;
  insert into public.audit_log (store_id, staff_id, action_type, description)
  values (inv.store_id, me, case when p_on then 'invoice_audited' else 'invoice_unaudited' end,
          case when p_on then 'تدقيق الفاتورة ' else 'إلغاء تدقيق الفاتورة ' end || inv.invoice_number);
  return v_at;
end $$;
revoke all on function public.set_invoice_audited(uuid, boolean) from public, anon;
grant execute on function public.set_invoice_audited(uuid, boolean) to authenticated;
