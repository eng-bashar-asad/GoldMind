-- Applied via execute_sql: expense_entries.cash_movement_id (backfilled), record_expense links it,
-- update_expense(p_id, p_category, p_amount, p_description) moves the cash movement + daily-box row with it.
-- delete_expense below must be run by the owner in the Supabase SQL Editor (the assistant's tool needs approval for it):
create or replace function public.delete_expense(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $f$
declare e record;
begin
  select * into e from expense_entries where id = p_id;
  if e is null then raise exception 'المصروف غير موجود'; end if;
  if not gm_can_expense(e.store_id) or not is_store_member(e.store_id) then raise exception 'ليس لديك صلاحية حذف المصاريف' using errcode = '42501'; end if;
  if exists (select 1 from inventory_gifts where expense_entry_id = p_id) then raise exception 'هذا مصروف هدية — احذفه بإرجاع الهدية إلى المخزن'; end if;
  delete from expense_entries where id = p_id;
  if e.cash_movement_id is not null then delete from cash_movements where id = e.cash_movement_id; end if; -- its daily-box row goes with it
  return jsonb_build_object('ok', true);
end $f$;
revoke execute on function public.delete_expense(uuid) from public, anon;
grant execute on function public.delete_expense(uuid) to authenticated;
