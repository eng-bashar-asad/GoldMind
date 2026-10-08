-- Cancelling / restoring an invoice leaves a line in each piece's history (cancel_invoice/restore_invoice never logged).
create or replace function public.trg_invoice_status_piece_log() returns trigger language plpgsql security definer set search_path = public as $$
declare sid uuid := (select id from staff where user_id = auth.uid() and store_id = new.store_id limit 1);
begin
  if new.type not in ('sale', 'buyTrader', 'buyRetail') then return new; end if;
  if new.status = 'cancelled' and old.status is distinct from 'cancelled' then
    insert into piece_movements (store_id, piece_id, event_type, note, created_by)
    select new.store_id, ii.piece_id, 'status_changed',
           'إلغاء الفاتورة ' || new.invoice_number || case when new.type = 'sale' then ' — عادت القطعة متوفرة' else '' end, sid
      from invoice_items ii where ii.invoice_id = new.id and ii.piece_id is not null;
  elsif old.status = 'cancelled' and new.status is distinct from 'cancelled' then
    insert into piece_movements (store_id, piece_id, event_type, note, created_by)
    select new.store_id, ii.piece_id, case when new.type = 'sale' then 'sold' else 'restored' end,
           'استعادة الفاتورة ' || new.invoice_number, sid
      from invoice_items ii where ii.invoice_id = new.id and ii.piece_id is not null;
  end if;
  return new;
end $$;
create or replace trigger trg_invoice_status_piece_log after update of status on public.invoices
  for each row execute function public.trg_invoice_status_piece_log();
-- (one-off on 2026-10-08: added the missing "sold" line for 000100 / INV-26 and 0001 / INV-2)
