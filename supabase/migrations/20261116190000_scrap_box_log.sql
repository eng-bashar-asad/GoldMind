-- Scrap box statement (بشار 2026-11-16): every gram in or out of a «كسر N» box is written to
-- scrap_box_log, with the document that moved it when it is known (trader voucher, invoice, piece).
-- The statement groups the log by document, so editing a voucher changes its row instead of adding
-- new ones. Movements done before this log existed are rebuilt from the lots and the draw tables;
-- whatever cannot be traced is one «رصيد سابق غير مفصّل» row per box so the balance matches.
-- Scrap vouchers (received gold in a settlement, scrap given out, goods received) can now be edited
-- in weight even after part of their gold was used, as long as the new weight still covers what was used.

create table if not exists public.scrap_box_log (
  id bigserial primary key,
  store_id uuid not null references public.stores(id) on delete cascade,
  lot_id uuid,
  box_name text not null,
  karat int,
  grams numeric not null,
  ref_kind text,          -- trader | invoice | piece | transfer | opening | lot
  ref_id uuid,
  note text,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid()
);
create index if not exists scrap_box_log_box on public.scrap_box_log (store_id, box_name, created_at);
create index if not exists scrap_box_log_lot on public.scrap_box_log (lot_id, created_at);
alter table public.scrap_box_log enable row level security;
drop policy if exists scrap_box_log_read on public.scrap_box_log;
create policy scrap_box_log_read on public.scrap_box_log for select using (is_store_member(store_id));
revoke insert, update, delete on public.scrap_box_log from anon, authenticated;

-- which document is moving the gold right now (set by the voucher triggers / edit function)
create or replace function public.gm_scrap_ref_set(p_kind text, p_id uuid)
returns void language plpgsql as $$ begin perform set_config('gm.scrap_ref', p_kind || ':' || p_id::text, true); end $$;

create or replace function public.trg_scrap_box_log()
returns trigger language plpgsql security definer set search_path = public as $$
declare r text := nullif(current_setting('gm.scrap_ref', true), ''); rk text; rid uuid;
begin
  if r is not null then rk := split_part(r, ':', 1); rid := nullif(split_part(r, ':', 2), '')::uuid; end if;
  if tg_op in ('UPDATE', 'DELETE') and coalesce(old.box_name, '') like 'كسر %' then
    if tg_op = 'DELETE' or new.box_name is distinct from old.box_name then
      if abs(coalesce(old.weight_grams_remaining, 0)) > 0.0005 then
        insert into scrap_box_log (store_id, lot_id, box_name, karat, grams, ref_kind, ref_id)
        values (old.store_id, old.id, old.box_name, old.karat, -old.weight_grams_remaining, rk, rid);
      end if;
      if tg_op = 'DELETE' then return old; end if;
    end if;
  end if;
  if coalesce(new.box_name, '') not like 'كسر %' then return new; end if;
  if tg_op = 'INSERT' or new.box_name is distinct from old.box_name then
    if rk is null then
      rk := case when new.trader_movement_id is not null then 'trader' when new.source_invoice_id is not null then 'invoice' else 'lot' end;
      rid := coalesce(new.trader_movement_id, new.source_invoice_id, new.id);
    end if;
    if abs(coalesce(new.weight_grams_remaining, 0)) > 0.0005 then
      insert into scrap_box_log (store_id, lot_id, box_name, karat, grams, ref_kind, ref_id)
      values (new.store_id, new.id, new.box_name, new.karat, new.weight_grams_remaining, rk, rid);
    end if;
  elsif abs(coalesce(new.weight_grams_remaining, 0) - coalesce(old.weight_grams_remaining, 0)) > 0.0005 then
    insert into scrap_box_log (store_id, lot_id, box_name, karat, grams, ref_kind, ref_id)
    values (new.store_id, new.id, new.box_name, new.karat, round(new.weight_grams_remaining - old.weight_grams_remaining, 3), rk, rid);
  end if;
  return new;
end $$;
drop trigger if exists trg_scrap_box_log on public.gold_stock_lots;
create trigger trg_scrap_box_log after insert or update of weight_grams_remaining, box_name or delete on public.gold_stock_lots
  for each row execute function public.trg_scrap_box_log();

-- ---- history before the log: lots in, draws out, the rest as one row per box ----
insert into scrap_box_log (store_id, lot_id, box_name, karat, grams, ref_kind, ref_id, created_at, created_by)
select l.store_id, l.id, l.box_name, l.karat, l.weight_grams_total,
       case when l.trader_movement_id is not null then 'trader' when l.source_invoice_id is not null then 'invoice' else 'lot' end,
       coalesce(l.trader_movement_id, l.source_invoice_id, l.id), l.created_at, null
  from gold_stock_lots l where l.box_name like 'كسر %' and l.weight_grams_total > 0
   and not exists (select 1 from scrap_box_log x where x.lot_id = l.id);
insert into scrap_box_log (store_id, lot_id, box_name, karat, grams, ref_kind, ref_id, created_at, created_by)
select d.store_id, d.lot_id, l.box_name, l.karat, -d.grams, 'trader', d.movement_id, d.created_at, null
  from trader_scrap_draws d join gold_stock_lots l on l.id = d.lot_id
 where l.box_name like 'كسر %' and exists (select 1 from trader_movements m where m.id = d.movement_id);
insert into scrap_box_log (store_id, lot_id, box_name, karat, grams, ref_kind, ref_id, created_at, created_by)
select d.store_id, d.lot_id, l.box_name, l.karat, -d.grams, 'piece', d.piece_id, d.created_at, null
  from piece_lot_draws d join gold_stock_lots l on l.id = d.lot_id where l.box_name like 'كسر %';
insert into scrap_box_log (store_id, lot_id, box_name, karat, grams, ref_kind, ref_id, note, created_at, created_by)
select l.store_id, null, l.box_name, max(l.karat), round(sum(l.weight_grams_remaining) - coalesce(g.s, 0), 3), 'opening', null,
       'رصيد سابق غير مفصّل (بيع أو تصليح أو تحويل قبل بدء السجل)', now(), null
  from gold_stock_lots l
  left join (select store_id, box_name, sum(grams) s from scrap_box_log group by 1, 2) g on g.store_id = l.store_id and g.box_name = l.box_name
 where l.box_name like 'كسر %'
 group by l.store_id, l.box_name, g.s
having abs(sum(l.weight_grams_remaining) - coalesce(g.s, 0)) > 0.0005;

-- ---- statement: one row per document, newest first is done by the page ----
create or replace function public.scrap_box_statement(p_store uuid, p_box text)
returns table (kind text, ref_id uuid, at timestamptz, grams numeric, title text, sub text,
               trader_id uuid, source text, karat int, editable boolean)
language sql stable security invoker set search_path = public as $$
  with l as (select * from scrap_box_log where store_id = p_store and box_name = p_box),
  r as (
    select l.id, l.created_at, l.grams, l.note, l.karat,
           coalesce(l.ref_kind, x.k, 'other') k, coalesce(l.ref_id, x.rid) rid
      from l left join lateral (
        select 'trader' k, d.movement_id rid from trader_scrap_draws d where d.lot_id = l.lot_id and d.created_at = l.created_at
        union all select 'piece', d.piece_id from piece_lot_draws d where d.lot_id = l.lot_id and d.created_at = l.created_at
        union all select 'trader', m.id from trader_movements m where m.store_id = p_store and coalesce(m.entered_at, m.created_at) = l.created_at
        union all select 'invoice', i.id from invoices i where i.store_id = p_store and i.created_at = l.created_at
        union all select 'transfer', b.id from branch_transfers b where (b.from_store_id = p_store or b.to_store_id = p_store)
                  and (b.created_at = l.created_at or b.received_at = l.created_at)
        limit 1) x on l.ref_kind is null
  ),
  g as (
    select k, rid, case when rid is null then id end solo, min(created_at) at, round(sum(grams), 3) grams,
           max(note) note, max(karat) karat
      from r group by k, rid, case when rid is null then id end
    having abs(sum(grams)) > 0.0005
  )
  select g.k, g.rid,
         coalesce(case g.k when 'trader' then m.created_at when 'invoice' then i.created_at end, g.at),
         g.grams,
         case g.k
           when 'trader' then case m.source when 'settlement' then 'تسكير ذهب من التاجر' when 'scrap_given' then 'إخراج كسر للتاجر'
                                when 'stock_received' then 'استلام من التاجر' when 'stock_given' then 'إخراج للتاجر' else 'سند تاجر' end
                              || coalesce(' ' || t.name, '')
           when 'invoice' then case i.type when 'buyRetail' then 'شراء كسر' when 'sale' then 'بيع' when 'return' then 'مرتجع مبيعات'
                                when 'buyTrader' then 'شراء من تاجر' else 'فاتورة' end
                              || coalesce(' — ' || nullif(coalesce(c.name, i.counterparty_name), ''), '')
           when 'piece' then 'صنع قطعة ' || coalesce(p.barcode, '')
           when 'transfer' then 'تحويل بين الفروع ' || coalesce(b.transfer_number, '')
           when 'opening' then 'رصيد سابق'
           when 'lot' then 'إدخال للصندوق'
           else case when g.grams > 0 then 'إدخال للصندوق' else 'إخراج من الصندوق' end end,
         case g.k when 'trader' then coalesce(m.voucher_no, '') when 'invoice' then i.invoice_number
                  when 'piece' then p.description_ar else g.note end,
         m.trader_id, m.source, g.karat,
         (g.k = 'trader' and m.source in ('settlement', 'scrap_given', 'stock_received'))
    from g
    left join trader_movements m on g.k = 'trader' and m.id = g.rid
    left join traders t on t.id = m.trader_id
    left join invoices i on g.k = 'invoice' and i.id = g.rid
    left join customers c on c.id = i.customer_id
    left join pieces p on g.k = 'piece' and p.id = g.rid
    left join branch_transfers b on g.k = 'transfer' and b.id = g.rid;
$$;
grant execute on function public.scrap_box_statement(uuid, text) to authenticated;

-- ---- vouchers whose gold was partly used can still be edited (not below what was used) ----
create or replace function public.trg_settlement_lot_sync()
returns trigger language plpgsql security definer set search_path = public as $$
declare lt record; nt numeric; used numeric;
begin
  if tg_op = 'UPDATE' and new.weight_grams is not distinct from old.weight_grams and new.karat is not distinct from old.karat
     and new.gold_24k_equivalent is not distinct from old.gold_24k_equivalent then
    return new;
  end if;
  perform gm_scrap_ref_set('trader', old.id);
  for lt in select * from gold_stock_lots where trader_movement_id = old.id for update loop
    used := lt.weight_grams_total - lt.weight_grams_remaining;
    if tg_op = 'UPDATE' then
      nt := round(coalesce(new.gold_24k_equivalent, 0) * 24 / lt.karat, 3);
      if nt < used - 0.0005 then
        raise exception 'الوزن الجديد (% غ) أقل من المستعمل من هذا الذهب (% غ)', nt, round(used, 3);
      end if;
      update gold_stock_lots set weight_grams_total = nt, weight_grams_remaining = round(nt - used, 3) where id = lt.id;
    else
      if used > 0.0005 then
        raise exception 'الذهب المستلم بهذه التسوية استُعمل من المستودع (إنتاج أو بيع) — لا يمكن حذفه. عدّل وزنه بدلاً من ذلك.';
      end if;
      update gold_stock_lots set weight_grams_remaining = 0, notes = coalesce(notes, '') || ' — أُلغي بإلغاء التسوية' where id = lt.id;
    end if;
  end loop;
  return case when tg_op = 'UPDATE' then new else old end;
end $$;

create or replace function public.trg_trader_received_sync()
returns trigger language plpgsql security definer set search_path = public as $$
declare pc record; lt record; aw numeric := coalesce(new.accounting_weight_grams, new.weight_grams); used numeric;
begin
  if new.weight_grams is not distinct from old.weight_grams and new.karat is not distinct from old.karat
     and new.accounting_weight_grams is not distinct from old.accounting_weight_grams
     and new.fab_fee_per_gram is not distinct from old.fab_fee_per_gram then return new; end if;
  perform gm_scrap_ref_set('trader', new.id);
  if new.piece_id is not null then
    select * into pc from pieces where id = new.piece_id for update;
    if pc.id is not null then
      if pc.status <> 'available' then raise exception 'القطعة % لم تعد متوفرة (بيعت أو خرجت) — لا يمكن تعديل وزنها. عدّل الحساب بتسوية.', pc.barcode; end if;
      update pieces set weight_grams = new.weight_grams, accounting_weight_grams = aw, karat = new.karat,
        cost_fabrication_per_gram = coalesce(new.fab_fee_per_gram, cost_fabrication_per_gram) where id = pc.id;
    end if;
  end if;
  if new.gold_stock_lot_id is not null then
    select * into lt from gold_stock_lots where id = new.gold_stock_lot_id for update;
    if lt.id is not null then
      used := lt.weight_grams_total - lt.weight_grams_remaining;
      if used > 0.0005 and new.karat is distinct from old.karat then
        raise exception 'استُعمل جزء من هذا الذهب — لا يمكن تغيير عياره. يمكن تعديل الوزن فقط.';
      end if;
      if new.weight_grams < used - 0.0005 then
        raise exception 'الوزن الجديد (% غ) أقل من المستعمل من هذا الذهب (% غ)', new.weight_grams, round(used, 3);
      end if;
      update gold_stock_lots set weight_grams_total = new.weight_grams, weight_grams_remaining = round(new.weight_grams - used, 3), karat = new.karat,
        cost_fabrication_per_gram = coalesce(new.fab_fee_per_gram, cost_fabrication_per_gram) where id = lt.id;
    end if;
  end if;
  return new;
end $$;

create or replace function public.trg_scrap_given_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare d record; n int := 0;
begin
  if tg_op = 'UPDATE' then
    if (new.weight_grams is distinct from old.weight_grams or new.karat is distinct from old.karat)
       and coalesce(current_setting('gm.scrap_regive', true), '') <> '1' then
      raise exception 'لتعديل وزن إخراج الكسر افتح كشف صندوق الكسر واضغط على الحركة';
    end if;
    return new;
  end if;
  perform gm_scrap_ref_set('trader', old.id);
  for d in select lot_id, grams from trader_scrap_draws where movement_id = old.id loop
    update gold_stock_lots set weight_grams_remaining = round(weight_grams_remaining + d.grams, 3) where id = d.lot_id;
    n := n + 1;
  end loop;
  if n = 0 and coalesce(old.weight_grams, 0) > 0 then
    perform gm_scrap_return_unrecorded(old.store_id, old.karat, old.weight_grams, 'أُرجع من حذف إخراج كسر لتاجر');
  end if;
  return old;
end $$;

-- ---- edit a scrap voucher's weight (and note) from the statement ----
create or replace function public.edit_scrap_movement(p_movement uuid, p_weight numeric, p_notes text default null)
returns void language plpgsql security definer set search_path = public as $$
declare m record; w numeric := round(coalesce(p_weight, 0), 3); lk int; d record; lot record; left_w numeric; take numeric; avail numeric;
        aw numeric;
begin
  select * into m from trader_movements where id = p_movement for update;
  if m.id is null then raise exception 'الحركة غير موجودة'; end if;
  if not has_permission('edit_traders', m.store_id) then raise exception 'ليس لديك صلاحية تعديل حسابات التجار' using errcode = '42501'; end if;
  if w <= 0 then raise exception 'أدخل وزناً صحيحاً'; end if;
  perform gm_scrap_ref_set('trader', m.id);

  if m.source = 'scrap_given' then
    -- put the old weight back, then take the new weight again, oldest gold first
    for d in select id, lot_id, grams from trader_scrap_draws where movement_id = m.id loop
      update gold_stock_lots set weight_grams_remaining = round(weight_grams_remaining + d.grams, 3) where id = d.lot_id;
    end loop;
    delete from trader_scrap_draws where movement_id = m.id;
    select coalesce(sum(weight_grams_remaining), 0) into avail from gold_stock_lots
     where store_id = m.store_id and box_name = 'كسر ' || m.karat and weight_grams_remaining > 0;
    if w > avail + 0.0005 then raise exception 'الوزن أكبر من الموجود في صندوق كسر % (% غ)', m.karat, round(avail, 3); end if;
    left_w := w;
    for lot in select id, weight_grams_remaining rem from gold_stock_lots
                where store_id = m.store_id and box_name = 'كسر ' || m.karat and weight_grams_remaining > 0
                order by created_at, id for update loop
      exit when left_w <= 0.0005;
      take := least(lot.rem, left_w);
      update gold_stock_lots set weight_grams_remaining = round(weight_grams_remaining - take, 3) where id = lot.id;
      insert into trader_scrap_draws (store_id, movement_id, lot_id, grams) values (m.store_id, m.id, lot.id, round(take, 3));
      left_w := left_w - take;
    end loop;
    perform set_config('gm.scrap_regive', '1', true);
    update trader_movements set weight_grams = w, accounting_weight_grams = w, gold_24k_equivalent = round(w * m.karat / 24.0, 3),
      notes = format('إخراج كسر عيار %s: %s غ', m.karat, w)
              || coalesce(' — ' || nullif(trim(coalesce(p_notes, substring(m.notes from ' — (.*)$'))), ''), '')
     where id = m.id;
    perform set_config('gm.scrap_regive', '', true);
  elsif m.source = 'settlement' then
    select karat into lk from gold_stock_lots where trader_movement_id = m.id limit 1;
    if lk is null then raise exception 'هذه التسوية لم تُدخل ذهباً إلى صندوق'; end if;
    -- the weight typed is in the box's karat; the voucher keeps its own karat
    update trader_movements set gold_24k_equivalent = round(w * lk / 24.0, 3),
      weight_grams = round(w * lk / coalesce(nullif(m.karat, 0), lk), 3) where id = m.id;
  elsif m.source = 'stock_received' and m.gold_stock_lot_id is not null then
    aw := case when m.accounting_weight_grams is null or m.accounting_weight_grams = m.weight_grams then w
               else round(m.accounting_weight_grams * w / nullif(m.weight_grams, 0), 3) end;
    update trader_movements set weight_grams = w, accounting_weight_grams = aw,
      gold_24k_equivalent = round(aw * m.karat / 24.0, 3), fab_fee_amount = round(aw * coalesce(fab_fee_per_gram, 0), 2) where id = m.id;
  else
    raise exception 'هذه الحركة لا تُعدَّل من هنا — افتح سندها';
  end if;
  if p_notes is not null and m.source <> 'scrap_given' then
    update trader_movements set notes = nullif(trim(p_notes), '') where id = m.id;
  end if;
end $$;
revoke execute on function public.edit_scrap_movement(uuid, numeric, text) from public, anon;
grant execute on function public.edit_scrap_movement(uuid, numeric, text) to authenticated;
