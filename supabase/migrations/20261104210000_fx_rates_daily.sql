-- Daily exchange rates (units per 1 USD, from open.er-api.com) kept one row per day, so the home
-- currency box shows today's rates and the history stays. The first app opened each day saves it.
-- The Syrian pound market rate is the store's own manual rate (stores.secondary_currency_rate).
create table if not exists public.fx_rates_daily (
  day date primary key,
  base text not null default 'USD',
  rates jsonb not null,
  source text not null default 'open.er-api.com',
  fetched_at timestamptz not null default now()
);
alter table public.fx_rates_daily enable row level security;
create policy fx_rates_daily_read on public.fx_rates_daily for select to authenticated using (true);

create or replace function public.gm_fx_save(p_day date, p_rates jsonb) returns void
language plpgsql security definer set search_path to 'public' as $$
declare k text; v jsonb; n int := 0;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  if p_day is null or p_day < current_date - 1 or p_day > current_date + 1 then raise exception 'تاريخ غير صالح'; end if;
  if jsonb_typeof(p_rates) <> 'object' then raise exception 'أسعار غير صالحة'; end if;
  for k, v in select * from jsonb_each(p_rates) loop
    n := n + 1;
    if k !~ '^[A-Z]{3}$' or jsonb_typeof(v) <> 'number' or (v #>> '{}')::numeric <= 0 then raise exception 'سعر غير صالح: %', k; end if;
  end loop;
  if n < 5 or n > 250 or coalesce((p_rates->>'USD')::numeric, 0) <> 1 then raise exception 'أسعار غير صالحة'; end if;
  insert into fx_rates_daily (day, rates) values (p_day, p_rates) on conflict (day) do nothing;
end $$;
revoke execute on function public.gm_fx_save(date, jsonb) from public, anon;
grant execute on function public.gm_fx_save(date, jsonb) to authenticated;
