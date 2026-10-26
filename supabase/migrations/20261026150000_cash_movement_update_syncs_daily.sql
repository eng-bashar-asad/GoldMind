-- Editing a cash movement that is not an invoice payment (trader cash in/out, vouchers...) now
-- updates its row in the daily cash box too (amount and in/out). Before, only the main box
-- changed (e.g. a trader payment edited from 150,000 to 100,000 stayed 150,000 in the daily box).
create or replace function public.trg_cash_movement_updated_daily_sync()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.invoice_id is not null then return new; end if; -- invoice money has its own rules
  update daily_cash_log
     set amount = round(coalesce(case when new.fx_currency is not null and new.fx_amount > 0 then new.fx_amount end, new.amount), 2),
         direction = new.direction
   where cash_movement_id = new.id
     and (amount <> round(coalesce(case when new.fx_currency is not null and new.fx_amount > 0 then new.fx_amount end, new.amount), 2)
          or direction <> new.direction);
  return new;
end $$;
revoke execute on function public.trg_cash_movement_updated_daily_sync() from public, anon, authenticated;
create trigger trg_cash_movement_updated_daily_sync after update of amount, direction, fx_amount on public.cash_movements
  for each row execute function public.trg_cash_movement_updated_daily_sync();

-- the one row already out of step (مجد بيطار, 26/10: main box 100,000, daily box 150,000)
update daily_cash_log l set amount = c.amount
  from cash_movements c
 where c.id = l.cash_movement_id and c.invoice_id is null and c.fx_amount is null and l.amount <> c.amount and c.direction = l.direction;
