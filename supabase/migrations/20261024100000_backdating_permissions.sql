-- Back-dated operations need a permission, never land in a closed fiscal year, and keep the real
-- time they were entered.
--  * backdate_entries   : add an operation on a past day (daily cash box date field, and the
--                         "تاريخ العملية" field of vouchers / customer debts / traders = x-gm-op-date)
--  * edit_past_cash     : edit or delete daily-cash-box rows of past days
--  * view_past_cashbox  : browse past days in the daily cash box (split from view_past_days,
--                         which now covers invoices and customer movements only)
-- The owner always has all of them (has_permission). Server paths (security-definer functions,
-- service role) are not limited by the daily-cash-box guard; the x-gm-op-date header is checked
-- wherever it lands because it always comes from the app.

-- 1) real entry time (old rows stay null = unknown; screens fall back to created_at)
alter table public.daily_cash_log   add column if not exists entered_at timestamptz;
alter table public.cash_movements   add column if not exists entered_at timestamptz;
alter table public.trader_movements add column if not exists entered_at timestamptz;
alter table public.customer_debts   add column if not exists entered_at timestamptz;
alter table public.piece_movements  add column if not exists entered_at timestamptz;
alter table public.daily_cash_log   alter column entered_at set default now();
alter table public.cash_movements   alter column entered_at set default now();
alter table public.trader_movements alter column entered_at set default now();
alter table public.customer_debts   alter column entered_at set default now();
alter table public.piece_movements  alter column entered_at set default now();

create or replace function public.gm_fiscal_closed(p_store uuid, p_day date) returns boolean
  language sql stable security definer set search_path to 'public' as $$
  select exists (select 1 from fiscal_year_closures
                 where store_id = p_store and fiscal_year = extract(year from p_day)::int);
$$;

-- 2) x-gm-op-date: permission + fiscal lock; entered_at always the real time
create or replace function public.gm_op_date_stamp() returns trigger language plpgsql as $$
declare d date := public.gm_op_date();
begin
  new.entered_at := now();
  if d is not null then
    if auth.uid() is not null and not public.has_permission('backdate_entries', new.store_id) then
      raise exception 'ليس لديك صلاحية تسجيل عملية بتاريخ سابق' using errcode = '42501';
    end if;
    if public.gm_fiscal_closed(new.store_id, d) then
      raise exception 'السنة المالية % مقفلة — لا يمكن التسجيل بتاريخ فيها', extract(year from d)::int using errcode = '42501';
    end if;
    new.created_at := (d + (now() at time zone 'Asia/Dubai')::time) at time zone 'Asia/Dubai';
  end if;
  return new;
end $$;

-- 3) daily cash box rows written straight from the app
create or replace function public.gm_cash_log_guard() returns trigger
  -- security invoker on purpose: current_user tells a direct app write from a server function.
  language plpgsql set search_path to 'public' as $$
declare
  today date := (now() at time zone 'Asia/Dubai')::date;
  st uuid := coalesce(new.store_id, old.store_id);
  od date; nd date;
begin
  if current_user <> 'authenticated' or auth.uid() is null then return coalesce(new, old); end if;
  if tg_op <> 'INSERT' then
    od := (old.created_at at time zone 'Asia/Dubai')::date;
    -- linking/unlinking two rows only touches link_group: allowed on any day
    if tg_op = 'UPDATE' and (to_jsonb(new) - 'link_group') = (to_jsonb(old) - 'link_group') then return new; end if;
    if od < today and not public.has_permission('edit_past_cash', st) then
      raise exception 'ليس لديك صلاحية تعديل أو حذف حركات الأيام السابقة' using errcode = '42501';
    end if;
    if public.gm_fiscal_closed(st, od) then
      raise exception 'السنة المالية % مقفلة', extract(year from od)::int using errcode = '42501';
    end if;
    if tg_op = 'DELETE' then return old; end if;
    if new.created_at is not distinct from old.created_at then return new; end if;
  end if;
  nd := (new.created_at at time zone 'Asia/Dubai')::date;
  if nd < today and not public.has_permission('backdate_entries', st) then
    raise exception 'ليس لديك صلاحية تسجيل حركة بتاريخ سابق' using errcode = '42501';
  end if;
  if nd > today then raise exception 'لا يمكن تسجيل حركة بتاريخ لاحق' using errcode = '22008'; end if;
  if public.gm_fiscal_closed(st, nd) then
    raise exception 'السنة المالية % مقفلة — لا يمكن التسجيل بتاريخ فيها', extract(year from nd)::int using errcode = '42501';
  end if;
  return new;
end $$;

create or replace trigger trg_cash_log_guard before insert or update or delete on public.daily_cash_log
  for each row execute function public.gm_cash_log_guard();

-- 4) carry over what people could already do, so nobody loses anything:
--    the cash box let owner + view_profit_report pick other days (view/add/edit),
--    and view_past_days let them browse past days.
update public.staff set permissions = coalesce(permissions, '{}'::jsonb)
  || jsonb_build_object('backdate_entries', true, 'edit_past_cash', true, 'view_past_cashbox', true)
  where role <> 'owner' and permissions ->> 'view_profit_report' = 'true';
update public.staff set permissions = permissions || jsonb_build_object('view_past_cashbox', true)
  where role <> 'owner' and permissions ->> 'view_past_days' = 'true';
