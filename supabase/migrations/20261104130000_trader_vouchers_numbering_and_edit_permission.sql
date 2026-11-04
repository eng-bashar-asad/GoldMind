-- Every trader movement from now on belongs to a numbered voucher (per branch, per type):
--   TOUT إخراج بضاعة/كسر · TIN إدخال بضاعة · PAY صرف (نقدي/ذهب للتاجر) · REC قبض (من التاجر) · DSC خصم · CNV تسكير
-- Rows saved together (same batch, or the same save for the same trader and type) share one number.
-- Editing or deleting a voucher: the owner, or staff given «edit_vouchers».
create table if not exists public.voucher_counters (
  store_id uuid not null references public.stores(id),
  prefix text not null,
  last_no integer not null default 0,
  primary key (store_id, prefix)
);
alter table public.voucher_counters enable row level security;

alter table public.trader_movements add column if not exists voucher_no text;
create index if not exists trader_movements_voucher_no_idx on public.trader_movements (store_id, voucher_no);

create or replace function public.gm_next_voucher_no(p_store uuid, p_prefix text) returns text
language sql security definer set search_path to 'public' as $$
  insert into voucher_counters (store_id, prefix, last_no) values (p_store, p_prefix, 1)
  on conflict (store_id, prefix) do update set last_no = voucher_counters.last_no + 1
  returning p_prefix || '-' || lpad(last_no::text, 6, '0');
$$;
revoke execute on function public.gm_next_voucher_no(uuid, text) from public, anon, authenticated;

create or replace function public.gm_trader_voucher_prefix(p_source text, p_type text) returns text
language sql immutable set search_path to 'public' as $$
  select case
    when p_source in ('stock_given', 'scrap_given') then 'TOUT'
    when p_source = 'stock_received' then 'TIN'
    when p_source = 'cash_out' or (p_source = 'settlement' and p_type = 'debt_decrease') then 'PAY'
    when p_source = 'cash_in' or (p_source = 'settlement' and p_type = 'debt_increase') then 'REC'
    when p_source = 'discount' then 'DSC'
    when p_source = 'gold_to_cash' then 'CNV'
  end;
$$;

create or replace function public.trg_trader_voucher_no() returns trigger
language plpgsql security definer set search_path to 'public' as $$
declare pf text; v text;
begin
  if new.voucher_no is not null then return new; end if;
  pf := gm_trader_voucher_prefix(new.source, new.movement_type);
  if pf is null then return new; end if;
  select t.voucher_no into v from trader_movements t
   where t.store_id = new.store_id and t.trader_id = new.trader_id and t.voucher_no like pf || '-%'
     and ((new.batch_id is not null and t.batch_id = new.batch_id)
          or (new.batch_id is null and t.batch_id is null and t.created_at = new.created_at and t.created_at > now() - interval '5 minutes'))
   limit 1;
  new.voucher_no := coalesce(v, gm_next_voucher_no(new.store_id, pf));
  return new;
end $$;
create trigger trg_trader_voucher_no before insert on public.trader_movements
  for each row execute function public.trg_trader_voucher_no();

-- edit / delete: owner or «edit_vouchers» (adding stays with «edit_traders»)
create policy trader_movements_voucher_edit on public.trader_movements as restrictive for update to authenticated
  using (public.has_permission('edit_vouchers', store_id)) with check (public.has_permission('edit_vouchers', store_id));
create policy trader_movements_voucher_remove on public.trader_movements as restrictive for delete to authenticated
  using (public.has_permission('edit_vouchers', store_id));

-- «إرجاع للمخزن» changes a voucher too
do $$ begin
  execute replace(replace(pg_get_functiondef('public.trader_return_piece(uuid)'::regprocedure),
    'has_permission(''edit_traders'', m.store_id)', 'has_permission(''edit_vouchers'', m.store_id)'),
    'ليس لديك صلاحية تعديل حسابات التجار', 'ليس لديك صلاحية تعديل وحذف السندات');
end $$;
