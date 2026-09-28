-- next_invoice_number(target_store_id, prefix): the parameter "prefix" clashed
-- with invoice_number_counters.prefix inside ON CONFLICT, so every non-sale
-- number (PINV purchases, RET returns) failed with "column reference prefix is
-- ambiguous" since the per-type counters were added on 2026-09-27.
-- Caught by tests/db/accounting.test.sql (test 16).
create or replace function public.next_invoice_number(target_store_id uuid, prefix text)
 returns text language plpgsql security definer set search_path to 'public'
as $function$
declare
  pfx text := $2;  -- the parameter name clashes with invoice_number_counters.prefix
  seq integer;
  yr integer := extract(year from now())::integer;
  stored_year integer;
begin
  if not public.is_store_member(target_store_id) then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if pfx is null or pfx !~ '^[A-Z]{2,6}$' then
    raise exception 'INVALID_PREFIX';
  end if;

  if pfx = 'INV' then
    select next_invoice_seq_year into stored_year from public.stores where id = target_store_id for update;
    if stored_year is null or stored_year <> yr then
      update public.stores set next_invoice_seq = 2, next_invoice_seq_year = yr where id = target_store_id;
      seq := 1;
    else
      update public.stores set next_invoice_seq = next_invoice_seq + 1
       where id = target_store_id returning next_invoice_seq - 1 into seq;
    end if;
  else
    insert into public.invoice_number_counters as c (store_id, prefix, year, next_seq)
    values (target_store_id, pfx, yr,
            coalesce((select max(nullif(split_part(i.invoice_number, '-', 3), '')::integer)
                        from public.invoices i
                       where i.store_id = target_store_id
                         and i.invoice_number ~ ('^' || pfx || '-' || yr || '-[0-9]+$')), 0) + 2)
    on conflict on constraint invoice_number_counters_pkey do update set next_seq = c.next_seq + 1
    returning c.next_seq - 1 into seq;
  end if;

  return pfx || '-' || yr::text || '-' || lpad(seq::text, 6, '0');
end;
$function$;
