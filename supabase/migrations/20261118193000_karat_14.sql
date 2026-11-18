-- 14K gold for every company (بشار 2026-11-18): pieces, scrap boxes, trader/party vouchers, repairs.
alter table public.pieces drop constraint if exists pieces_karat_check;
alter table public.pieces add constraint pieces_karat_check check (karat = any (array[14, 18, 21, 22, 24]));

-- the voucher/repair functions validate the karat against the same fixed list: add 14 there too
do $$
declare r record; d text;
begin
  for r in select p.oid from pg_proc p
           where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
             and pg_get_functiondef(p.oid) like '%not in (18, 21, 22, 24)%'
  loop
    d := replace(pg_get_functiondef(r.oid), 'not in (18, 21, 22, 24)', 'not in (14, 18, 21, 22, 24)');
    execute d;
  end loop;
end $$;
