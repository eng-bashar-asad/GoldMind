-- RFID chip IDs are shop prefix + barcode left-padded with zeros to 16 digits (GMZebra.buildEpcHex),
-- so numeric barcodes "4" and "000004" in the same shop get the SAME chip ID and the reader cannot
-- tell the two pieces apart (inventory count showed «تنبيه تضارب بيانات», 2026-11-01).
-- Reject a barcode that equals another piece's barcode in the same shop once leading zeros are dropped.
-- ponytail: non-numeric barcodes use only their first 8 characters in the chip ID; not guarded here
-- because generated ones share prefixes (GM-..., D...) and are never written to chips. Extend if that changes.
create or replace function public.gm_piece_barcode_epc_guard()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.barcode ~ '^[0-9]{1,16}$' and exists (
    select 1 from public.pieces p
    where p.store_id = new.store_id and p.id <> new.id
      and p.barcode ~ '^[0-9]{1,16}$'
      and ltrim(p.barcode, '0') = ltrim(new.barcode, '0')
  ) then
    raise exception 'الباركود % يطابق باركود قطعة أخرى في المحل بعد حذف الأصفار من اليسار (مثل 4 و 000004)، فتأخذان رقم شريحة RFID نفسه. اختر باركوداً آخر أو اتركه فارغاً ليُولَّد تلقائياً.', new.barcode
      using errcode = 'unique_violation';
  end if;
  return new;
end $$;

drop trigger if exists pieces_barcode_epc_guard on public.pieces;
create trigger pieces_barcode_epc_guard
  before insert or update of barcode, store_id on public.pieces
  for each row execute function public.gm_piece_barcode_epc_guard();
