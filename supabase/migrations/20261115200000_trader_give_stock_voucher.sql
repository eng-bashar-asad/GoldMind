-- «إخراج بضاعة» as ONE voucher (بشار 2026-11-15): barcode pieces + bulk weight + scrap from several boxes
-- (كسر 18، كسر 21 ...) saved together, all-or-nothing, sharing one batch_id.
-- SECURITY INVOKER: the rows go through the same RLS as the page's direct inserts did;
-- scrap lines reuse give_scrap_to_trader (stock draw + cost) and are then tagged with the batch.
create or replace function public.trader_give_stock_voucher(p_trader uuid, p_rows jsonb default '[]', p_scrap jsonb default '[]', p_batch uuid default null)
returns jsonb language plpgsql security invoker set search_path to 'public' as $$
declare s jsonb; r jsonb; pids uuid[]; sid uuid; n int := 0;
begin
  if coalesce(jsonb_array_length(p_rows), 0) + coalesce(jsonb_array_length(p_scrap), 0) = 0 then raise exception 'السند فارغ'; end if;
  select store_id into sid from traders where id = p_trader;
  if sid is null then raise exception 'التاجر غير موجود'; end if;

  for s in select * from jsonb_array_elements(coalesce(p_scrap, '[]')) loop
    r := give_scrap_to_trader(p_trader, (s->>'karat')::int, (s->>'weight')::numeric, nullif(s->>'notes', ''));
    update trader_movements set batch_id = p_batch where id = (r->>'id')::uuid;
    n := n + 1;
  end loop;

  if coalesce(jsonb_array_length(p_rows), 0) > 0 then
    if exists (select 1 from jsonb_array_elements(p_rows) e where (e->>'trader_id')::uuid is distinct from p_trader or e->>'source' <> 'stock_given') then
      raise exception 'سطر لا يخص هذا التاجر';
    end if;
    insert into trader_movements (batch_id, store_id, trader_id, piece_id, movement_type, weight_grams, karat, accounting_weight_grams,
      gold_24k_equivalent, fab_fee_per_gram, fab_fee_amount, sale_cost, cost_fab_per_gram, source, notes)
    select p_batch, x.store_id, x.trader_id, x.piece_id, x.movement_type, x.weight_grams, x.karat, x.accounting_weight_grams,
      x.gold_24k_equivalent, x.fab_fee_per_gram, x.fab_fee_amount, x.sale_cost, x.cost_fab_per_gram, x.source, x.notes
    from jsonb_to_recordset(p_rows) as x(store_id uuid, trader_id uuid, piece_id uuid, movement_type text, weight_grams numeric, karat int,
      accounting_weight_grams numeric, gold_24k_equivalent numeric, fab_fee_per_gram numeric, fab_fee_amount numeric, sale_cost numeric,
      cost_fab_per_gram numeric, source text, notes text);
    n := n + jsonb_array_length(p_rows);

    select array_agg((e->>'piece_id')::uuid) into pids from jsonb_array_elements(p_rows) e where nullif(e->>'piece_id', '') is not null;
    if pids is not null then
      update pieces set status = 'given_to_trader' where id = any(pids) and store_id = sid;
      insert into piece_movements (store_id, piece_id, event_type, note, created_by)
      select sid, unnest(pids), 'given_to_trader', 'إعطاء بضاعة للتاجر',
             (select id from staff where user_id = auth.uid() and store_id = sid limit 1);
    end if;
  end if;
  return jsonb_build_object('ok', true, 'lines', n);
end $$;
revoke all on function public.trader_give_stock_voucher(uuid, jsonb, jsonb, uuid) from public, anon;
grant execute on function public.trader_give_stock_voucher(uuid, jsonb, jsonb, uuid) to authenticated;
