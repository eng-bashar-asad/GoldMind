-- Run by the owner in the SQL Editor. Return one given piece from a trader to stock:
-- the give-out line leaves the trader's account (gold + making) and the piece is available again
-- with its own gross/accounting weight and making cost (never changed while it was out).
create or replace function public.trader_return_piece(p_movement uuid)
 returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare m record; me uuid; bc text;
begin
  select * into m from trader_movements where id = p_movement and source = 'stock_given' and piece_id is not null;
  if m is null then raise exception 'القطعة غير موجودة في حساب التاجر'; end if;
  if not has_permission('edit_traders', m.store_id) then raise exception 'ليس لديك صلاحية تعديل حسابات التجار' using errcode = '42501'; end if;
  select id into me from staff where user_id = auth.uid() and store_id = m.store_id limit 1;
  delete from trader_movements where id = m.id;
  update pieces set status = 'available' where id = m.piece_id and status = 'given_to_trader' returning barcode into bc;
  insert into piece_movements (store_id, piece_id, event_type, note, created_by)
    values (m.store_id, m.piece_id, 'returned_from_trader', 'مرتجع من التاجر — رجعت إلى المخزن', me);
  return jsonb_build_object('ok', true, 'barcode', bc);
end $function$;
grant execute on function public.trader_return_piece(uuid) to authenticated;
