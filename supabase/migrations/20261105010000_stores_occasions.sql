-- The branch's own list of occasions (home «المواسم»); null = the default list of its country.
-- [{t, kind, md:'MM-DD'} | {t, kind, hijri:[month,day], dates:{'YYYY':'YYYY-MM-DD'}}, off?:true]
alter table public.stores add column if not exists occasions jsonb;
