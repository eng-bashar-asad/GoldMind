-- Back-dating movements: client header x-gm-op-date (YYYY-MM-DD, past only) stamps created_at
-- on trader_movements, customer_debts, cash_movements, daily_cash_log, piece_movements.
create or replace function public.gm_op_date() returns date language plpgsql stable as $$
declare h text; d date; today date := (now() at time zone 'Asia/Dubai')::date;
begin
  h := nullif(current_setting('request.headers', true), '')::json->>'x-gm-op-date';
  if h is null or h !~ '^\d{4}-\d{2}-\d{2}$' then return null; end if;
  begin d := h::date; exception when others then return null; end;
  if d >= today or d < today - 3650 then return null; end if;
  return d;
end $$;

create or replace function public.gm_op_date_stamp() returns trigger language plpgsql as $$
declare d date := public.gm_op_date();
begin
  if d is not null then
    new.created_at := (d + (now() at time zone 'Asia/Dubai')::time) at time zone 'Asia/Dubai';
  end if;
  return new;
end $$;

create or replace trigger trg_op_date before insert on public.trader_movements for each row execute function public.gm_op_date_stamp();
create or replace trigger trg_op_date before insert on public.customer_debts for each row execute function public.gm_op_date_stamp();
create or replace trigger trg_op_date before insert on public.cash_movements for each row execute function public.gm_op_date_stamp();
create or replace trigger trg_op_date before insert on public.daily_cash_log for each row execute function public.gm_op_date_stamp();
create or replace trigger trg_op_date before insert on public.piece_movements for each row execute function public.gm_op_date_stamp();
