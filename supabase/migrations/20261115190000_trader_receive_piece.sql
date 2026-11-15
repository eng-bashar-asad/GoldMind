-- «مصدر القطعة: من تاجر» on the add-piece screen (بشار 2026-11-15): the piece is saved as usual,
-- then this posts it straight onto the trader's account, exactly like a «إدخال بضاعة» line:
-- gold debt = accounting weight in 24k equivalent, making = accounting weight × making/gram (+ VAT).
create or replace function public.trader_receive_piece(p_trader uuid, p_piece uuid, p_vat_rate numeric default 0, p_batch uuid default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare t record; pc record; me uuid; aw numeric; fab numeric; vat numeric := coalesce(p_vat_rate, 0); mid uuid;
begin
  select id, gm_acting_store(store_id) as store_id, name into t from traders where id = p_trader;
  if t is null then raise exception 'التاجر غير موجود'; end if;
  if not has_permission('edit_traders', t.store_id) then raise exception 'ليس لديك صلاحية تعديل حسابات التجار' using errcode = '42501'; end if;
  select id, store_id, barcode, weight_grams, accounting_weight_grams, karat, cost_fabrication_per_gram into pc from pieces where id = p_piece;
  if pc is null or pc.store_id <> t.store_id then raise exception 'القطعة غير موجودة'; end if;
  if pc.karat not in (18, 21, 22, 24) then raise exception 'عيار غير صحيح'; end if;
  if vat < 0 or vat > 100 then raise exception 'نسبة ضريبة غير صحيحة'; end if;
  if exists (select 1 from trader_movements where piece_id = p_piece and source = 'stock_received') then
    raise exception 'القطعة مسجّلة على حساب تاجر مسبقاً';
  end if;
  aw := coalesce(nullif(pc.accounting_weight_grams, 0), pc.weight_grams);
  fab := greatest(coalesce(pc.cost_fabrication_per_gram, 0), 0);
  select id into me from staff where user_id = auth.uid() and store_id = t.store_id limit 1;
  insert into trader_movements (store_id, trader_id, movement_type, weight_grams, karat, gold_24k_equivalent, accounting_weight_grams,
    fab_fee_per_gram, fab_fee_amount, source, batch_id, notes, created_by, piece_id)
  values (t.store_id, t.id, 'debt_increase', pc.weight_grams, pc.karat, round(aw * pc.karat / 24.0, 3), aw, fab, round(aw * fab * (1 + vat / 100), 2),
    'stock_received', p_batch, 'استلام بضاعة من التاجر — باركود ' || pc.barcode, me, pc.id)
  returning id into mid;
  insert into piece_movements (store_id, piece_id, event_type, note, created_by)
  values (t.store_id, pc.id, 'stock_in', 'استلام من التاجر ' || t.name, me);
  return jsonb_build_object('ok', true, 'movement_id', mid);
end $$;
revoke all on function public.trader_receive_piece(uuid, uuid, numeric, uuid) from public, anon;
grant execute on function public.trader_receive_piece(uuid, uuid, numeric, uuid) to authenticated;
