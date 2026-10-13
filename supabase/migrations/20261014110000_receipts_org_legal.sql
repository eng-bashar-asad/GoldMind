-- Multi-branch plan 1.3: the public receipt pages take the logo and TRN from the organization
-- (same rule as store_legal(): organization first, the store's copy as fallback).
-- Same signatures and grants as before, so nothing else changes. Safe to run twice.

create or replace function public.get_invoice_receipt(p_id uuid)
returns table(invoice_number text, invoice_type text, status text, payment_method text, vat_amount numeric,
              total_amount numeric, created_at timestamp with time zone, store_name text, store_logo_url text,
              store_address text, store_phone text, store_email text, vat_rate numeric, tax_number text,
              currency text, secondary_currency text, secondary_currency_rate numeric, customer_name text,
              customer_phone text, items jsonb)
language sql security definer set search_path to 'public' as $function$
  select
    inv.invoice_number, inv.type, inv.status, inv.payment_method, inv.vat_amount, inv.total_amount, inv.created_at,
    s.name,
    coalesce(o.logo_url, s.logo_url),
    s.address, s.phone, s.email, s.vat_rate,
    coalesce(o.tax_number, s.tax_number),
    s.currency, s.secondary_currency, s.secondary_currency_rate,
    c.name, c.phone,
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'description', ii.description,
        'description_en', ii.description_en,
        'karat', ii.karat,
        'weight_grams', ii.weight_grams,
        'line_total', ii.line_total,
        'quantity', 1
      ) order by ii.id)
      from invoice_items ii where ii.invoice_id = inv.id
    ), '[]'::jsonb)
  from invoices inv
  join stores s on s.id = inv.store_id
  left join organizations o on o.id = s.organization_id
  left join customers c on c.id = inv.customer_id
  where inv.id = p_id and inv.status != 'cancelled';
$function$;

create or replace function public.get_repair_receipt(p_id uuid)
returns table(ticket_number text, piece_description text, problem_description text, intake_photo_url text,
              ready_photo_url text, status text, received_at timestamp with time zone,
              ready_at timestamp with time zone, store_name text, store_logo_url text, store_address text,
              store_phone text, received_by_name text, invoice_print_frame text, invoice_print_shape text,
              estimated_cost numeric, actual_cost numeric, vat_rate numeric, tax_number text)
language sql security definer set search_path to 'public' as $function$
  select
    rt.ticket_number, rt.piece_description, rt.problem_description, rt.intake_photo_url, rt.ready_photo_url,
    rt.status, rt.received_at, rt.ready_at,
    s.name,
    coalesce(o.logo_url, s.logo_url),
    s.address, s.phone, st.full_name, s.invoice_print_frame, s.invoice_print_shape,
    rt.estimated_cost, rt.actual_cost, s.vat_rate,
    coalesce(o.tax_number, s.tax_number)
  from repair_tickets rt
  join stores s on s.id = rt.store_id
  left join organizations o on o.id = s.organization_id
  left join staff st on st.id = rt.received_by
  where rt.id = p_id;
$function$;
