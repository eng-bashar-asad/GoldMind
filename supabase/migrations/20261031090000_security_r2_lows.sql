-- Security audit R1 follow-up (Low findings).
-- SEC-011: usernames unique regardless of case (no clashes existed when this ran).
create unique index if not exists user_profiles_username_lower_key on public.user_profiles (lower(username));

-- SEC-015: SECURITY DEFINER functions are no longer callable before signing in, except the ones
-- the signed-out screens need (login, public receipts, the RFID programmer device) and the
-- helpers RLS policies and the pre-request hook call. Signed-in users keep exactly what they had.
do $$
declare f record;
  keep text[] := array['get_invoice_receipt','get_repair_receipt','login_email_for','lookup_email_by_username',
    'rfid_device_done','rfid_device_hello','rfid_device_next',
    'gm_pre_request','gm_session_ok','gm_can_expense','has_permission','is_platform_admin','is_store_member','current_store_id'];
begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.prosecdef and not (p.proname = any(keep))
              and has_function_privilege('anon', p.oid, 'EXECUTE') loop
    execute format('grant execute on function %s to authenticated, service_role', f.sig);
    execute format('revoke execute on function %s from public, anon', f.sig);
  end loop;
end $$;

-- new functions: not executable by anon / PUBLIC unless granted on purpose
alter default privileges in schema public revoke execute on functions from public;
alter default privileges in schema public revoke execute on functions from anon;

-- SEC-016: the public receipt (QR link) no longer carries the customer's phone number
-- (the receipt page never shows it); only its last 3 digits remain.
create or replace function public.get_invoice_receipt(p_id uuid)
returns table(invoice_number text, invoice_type text, status text, payment_method text, vat_amount numeric, total_amount numeric,
  created_at timestamp with time zone, store_name text, store_logo_url text, store_address text, store_phone text, store_email text,
  vat_rate numeric, tax_number text, currency text, secondary_currency text, secondary_currency_rate numeric,
  customer_name text, customer_phone text, items jsonb)
language sql security definer set search_path to 'public' as $function$
  select inv.invoice_number, inv.type, inv.status, inv.payment_method, inv.vat_amount, inv.total_amount, inv.created_at,
         s.name, o.logo_url, s.address, s.phone, s.email, s.vat_rate, o.tax_number,
         s.currency, s.secondary_currency, s.secondary_currency_rate,
         c.name, case when coalesce(c.phone, '') = '' then null else '•••' || right(regexp_replace(c.phone, '\D', '', 'g'), 3) end,
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
$function$;
