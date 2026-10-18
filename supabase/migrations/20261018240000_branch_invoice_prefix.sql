-- Multi-branch plan step 1.4: an optional branch code in front of every invoice number,
-- so numbers stay unique across the branches of one organization: DXB-INV-2026-000120.
-- A store with no code keeps the old format (INV-2026-000120). Counters stay per store.
-- Old invoices keep their numbers; only new ones get the code. No data is deleted.

alter table public.stores add column if not exists branch_code text;
alter table public.stores drop constraint if exists stores_branch_code_format;
alter table public.stores add constraint stores_branch_code_format check (branch_code is null or branch_code ~ '^[A-Z]{2,5}$');
-- one code per branch inside an organization (not a legal field, decision 11 does not apply)
create unique index if not exists stores_org_branch_code_key on public.stores (organization_id, branch_code) where branch_code is not null;

create or replace function public.next_invoice_number(target_store_id uuid, prefix text)
returns text language plpgsql security definer set search_path = public as $function$
declare
  pfx text := $2;  -- the parameter name clashes with invoice_number_counters.prefix
  seq integer;
  yr integer := extract(year from now())::integer;
  stored_year integer;
  code text;
begin
  if not public.is_store_member(target_store_id) then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if pfx is null or pfx !~ '^[A-Z]{2,6}$' then
    raise exception 'INVALID_PREFIX';
  end if;

  if pfx = 'INV' then
    select next_invoice_seq_year, branch_code into stored_year, code from public.stores where id = target_store_id for update;
    if stored_year is null or stored_year <> yr then
      update public.stores set next_invoice_seq = 2, next_invoice_seq_year = yr where id = target_store_id;
      seq := 1;
    else
      update public.stores set next_invoice_seq = next_invoice_seq + 1
       where id = target_store_id returning next_invoice_seq - 1 into seq;
    end if;
  else
    select branch_code into code from public.stores where id = target_store_id;
    insert into public.invoice_number_counters as c (store_id, prefix, year, next_seq)
    values (target_store_id, pfx, yr,
            coalesce((select max((regexp_match(i.invoice_number, '-([0-9]+)$'))[1]::integer)
                        from public.invoices i
                       where i.store_id = target_store_id
                         and i.invoice_number ~ ('^([A-Z]{2,5}-)?' || pfx || '-' || yr || '-[0-9]+$')), 0) + 2)
    on conflict on constraint invoice_number_counters_pkey do update set next_seq = c.next_seq + 1
    returning c.next_seq - 1 into seq;
  end if;

  return coalesce(code || '-', '') || pfx || '-' || yr::text || '-' || lpad(seq::text, 6, '0');
end;
$function$;

-- delete_last_sale_invoice read year and sequence as parts 2 and 3; with a branch code they move,
-- so read them from the end of the number instead. Everything else is unchanged.
create or replace function public.delete_last_sale_invoice(target_invoice_id uuid)
returns text language plpgsql security definer set search_path = public as $function$
declare
  inv record;
  st record;
  inv_seq integer;
  inv_year integer;
  actor uuid;
  parts text[];
begin
  select * into inv from public.invoices where id = target_invoice_id for update;
  if inv is null then raise exception 'الفاتورة غير موجودة'; end if;

  if not exists (select 1 from public.staff where user_id = auth.uid() and store_id = inv.store_id and role = 'owner') then
    raise exception 'حذف الفواتير متاح للمالك فقط' using errcode = '42501';
  end if;
  if inv.type <> 'sale' then raise exception 'الحذف متاح لفواتير المبيعات فقط'; end if;
  if exists (select 1 from public.invoices where related_invoice_id = inv.id) then
    raise exception 'عليها فاتورة مرتجع، ولا يمكن حذفها';
  end if;
  if exists (select 1 from public.invoice_items where invoice_id = inv.id and diamond_stock_lot_id is not null) then
    raise exception 'فيها ماس من رصيد جملة — استخدم الإلغاء بدل الحذف';
  end if;

  -- number format [CODE-]PREFIX-YYYY-NNNNNN; must be the last one issued
  parts := regexp_match(inv.invoice_number, '-([0-9]{4})-([0-9]+)$');
  inv_year := parts[1]::integer;
  inv_seq  := parts[2]::integer;
  select next_invoice_seq, next_invoice_seq_year into st from public.stores where id = inv.store_id for update;
  if inv_seq is null or inv_year is distinct from st.next_invoice_seq_year or inv_seq <> st.next_invoice_seq - 1 then
    raise exception 'يمكن حذف آخر فاتورة فقط (لتجنّب حدوث فراغ في الترقيم). يمكنك إلغاء هذه الفاتورة بدلاً من حذفها.';
  end if;

  select id into actor from public.staff where user_id = auth.uid() and store_id = inv.store_id limit 1;

  -- pieces back to stock
  update public.pieces set status = 'available'
   where status = 'sold' and id in (select piece_id from public.invoice_items where invoice_id = inv.id and piece_id is not null);
  delete from public.piece_movements
   where store_id = inv.store_id and event_type = 'sold' and note = 'بيع بفاتورة ' || inv.invoice_number
     and piece_id in (select piece_id from public.invoice_items where invoice_id = inv.id and piece_id is not null);
  update public.diamond_pieces set status = 'available'
   where status = 'sold' and id in (select diamond_piece_id from public.invoice_items where invoice_id = inv.id and diamond_piece_id is not null);

  -- bulk gold sold from lots goes back to the lot (weight, and pooled fee)
  update public.gold_stock_lots l
     set weight_grams_remaining = l.weight_grams_remaining + x.w,
         fabrication_pool_remaining = case when l.fabrication_pool_remaining is null then null
                                           else l.fabrication_pool_remaining + x.f end
    from (select gold_stock_lot_id, sum(coalesce(weight_grams, 0)) w, sum(coalesce(fabrication_fee, 0)) f
            from public.invoice_items where invoice_id = inv.id and gold_stock_lot_id is not null
           group by gold_stock_lot_id) x
   where l.id = x.gold_stock_lot_id;

  -- money / debt movements created by (or reversing) this invoice
  delete from public.cash_movements where invoice_id = inv.id;
  delete from public.customer_debts where invoice_id = inv.id;
  delete from public.trader_movements where invoice_id = inv.id;

  delete from public.invoices where id = inv.id; -- invoice_items cascade

  update public.stores set next_invoice_seq = inv_seq where id = inv.store_id;

  insert into public.audit_log (store_id, staff_id, action_type, description)
  values (inv.store_id, actor, 'invoice_deleted',
          'حذف فاتورة مبيعات ' || inv.invoice_number || ' بقيمة ' || coalesce(inv.total_amount, 0) || ' — الرقم رجع متاح للفاتورة الجاية');

  return inv.invoice_number;
end;
$function$;
