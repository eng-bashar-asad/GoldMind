-- Re-issue a cancelled sale under its own number (customer brought the pieces back, a new sale replaces it).
-- post_sale_invoice(p) with p.reuse_invoice_id = the cancelled sale:
--   * same store, type sale, status cancelled, not sent for e-invoicing; needs «delete_invoice» like cancelling
--   * the new invoice takes its number; the cancelled one keeps its record as «<number>-ملغاة» (history stays)
--   * the date can be any past date (p.sold_at), not the future
do $$
declare src text := pg_get_functiondef('public.post_sale_invoice(jsonb)'::regprocedure);
  a text := 'sold_at timestamptz :=';
  b text := 'sold_at < now() - interval ''14 days''';
  c text := 'inv_no := next_invoice_number(sid, ''INV'');';
begin
  if (length(src) - length(replace(src, a, ''))) / length(a) <> 1
     or (length(src) - length(replace(src, b, ''))) / length(b) <> 1
     or (length(src) - length(replace(src, c, ''))) / length(c) <> 1 then
    raise exception 'post_sale_invoice changed — update this migration';
  end if;
  src := replace(src, a, 'reuse uuid := nullif(p->>''reuse_invoice_id'','''')::uuid; old_inv record; n_old int; ' || a);
  src := replace(src, b, '(' || b || ' and reuse is null)');
  src := replace(src, c, $r$
    if reuse is not null then
      select * into old_inv from invoices where id = reuse and store_id = sid for update;
      if not found or old_inv.type <> 'sale' or old_inv.status <> 'cancelled' then raise exception 'الفاتورة الأصلية ليست فاتورة بيع ملغاة'; end if;
      if old_inv.einvoice_uuid is not null then raise exception 'لا يمكن إعادة استخدام رقم فاتورة أُرسلت للفوترة الإلكترونية'; end if;
      if old_inv.invoice_number like '%-ملغاة%' then raise exception 'رقم هذه الفاتورة أُعيد استخدامه من قبل'; end if;
      if not has_permission('delete_invoice', sid) then raise exception 'ليس لديك صلاحية إعادة إصدار فاتورة ملغاة' using errcode = '42501'; end if;
      inv_no := old_inv.invoice_number;
      select count(*) into n_old from invoices where store_id = sid and invoice_number like inv_no || '-ملغاة%';
      update invoices set invoice_number = inv_no || '-ملغاة' || case when n_old > 0 then (n_old + 1)::text else '' end where id = reuse;
      insert into audit_log (store_id, action_type, description)
        values (sid, 'invoice_reissued', 'إعادة إصدار الفاتورة الملغاة ' || inv_no || ' بنفس الرقم');
    else
      inv_no := next_invoice_number(sid, 'INV');
    end if;$r$);
  execute src;
end $$;
