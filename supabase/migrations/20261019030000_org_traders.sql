-- Multi-branch 2.3 (decision by بشار 2026-10-19): every branch deals with traders (receives and
-- gives goods, pays and receives cash), and each trader has ONE account for the organization.
-- Each movement stays on the branch where it happened (its stock, its cash box); balances are
-- summed over the organization's branches by the screens.
--   * gm_acting_store(home): the branch the request comes from (header x-gm-store, sent by every
--     screen since supabase-config v44) when it belongs to the same organization; else home.
--   * traders and trader_movements readable from any branch of the organization (view_traders).
--   * trader functions record on the acting branch: give_scrap_to_trader, trader_cash_move,
--     trader_discount, trader_gold_to_cash, trader_receive_stock (one line each, patched in place
--     from their live text); cash_voucher and post_purchase_invoice accept a trader of any branch.
-- Single-branch shops: the acting branch is always the store itself, nothing changes. No data
-- is touched. Run it ONCE; a second run stops at the first patch (its text is already changed).

begin;

create or replace function public.gm_acting_store(home uuid)
returns uuid language plpgsql stable security definer set search_path = public as $$
declare h uuid;
begin
  begin
    h := nullif(current_setting('request.headers', true)::json ->> 'x-gm-store', '')::uuid;
  exception when others then h := null;
  end;
  if h is not null and h <> home and h in (select org_store_ids(home)) then return h; end if;
  return home;
end $$;
revoke all on function public.gm_acting_store(uuid) from public, anon;
grant execute on function public.gm_acting_store(uuid) to authenticated;

drop policy if exists traders_select_org on public.traders;
create policy traders_select_org on public.traders for select to authenticated
  using (org_can(store_id, 'view_traders'));

drop policy if exists trader_movements_select_org on public.trader_movements;
create policy trader_movements_select_org on public.trader_movements for select to authenticated
  using (org_can(store_id, 'view_traders'));

create or replace function pg_temp.gm_patch(fn regprocedure, old_txt text, new_txt text)
returns void language plpgsql as $$
declare d text := pg_get_functiondef(fn);
begin
  if position(old_txt in d) = 0 then raise exception 'patch %: expected text not found: %', fn, old_txt; end if;
  execute replace(d, old_txt, new_txt);
end $$;

select pg_temp.gm_patch(f::regprocedure,
  'select id, store_id, name into t from traders where id = p_trader;',
  'select id, gm_acting_store(store_id) as store_id, name into t from traders where id = p_trader;')
from unnest(array[
  'public.give_scrap_to_trader(uuid,integer,numeric,text)',
  'public.trader_cash_move(uuid,text,numeric,text,boolean)',
  'public.trader_discount(uuid,text,numeric,text)',
  'public.trader_gold_to_cash(uuid,numeric,integer,numeric,text,text)',
  'public.trader_receive_stock(uuid,jsonb,numeric,text,text)']) f;

select pg_temp.gm_patch('public.cash_voucher(jsonb)',
  'select id, store_id, name into t from traders where id = pid and store_id = sid;',
  'select id, store_id, name into t from traders where id = pid and store_id in (select org_store_ids(sid));');

select pg_temp.gm_patch('public.post_purchase_invoice(jsonb)',
  'if tid is null or not exists (select 1 from traders where id = tid and store_id = sid) then',
  'if tid is null or not exists (select 1 from traders where id = tid and store_id in (select org_store_ids(sid))) then');

commit;
