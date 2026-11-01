-- Delete pieces 000346, 000404, 000470 from Ahmad Al Khayat Jewellery (requested by Bashar 2026-11-01).
--   000346  إسوارة 18K  25.020 g
--   000404  إسوارة 18K  28.260 g
--   000470  خاتم   18K   5.160 g
-- All three are "available", never sold, no trader/voucher/transfer/lot links.
-- 000346 and 000470 appear in one completed inventory count: those scan rows are kept
-- (count history stays) and only unlinked from the piece. Their piece_movements rows go with them (cascade).
-- Runs as one transaction: if anything is not as expected, nothing is deleted.
begin;

update public.inventory_count_scans set piece_id = null
where piece_id in (
  select id from public.pieces
  where store_id = 'a15f496a-a4b5-4388-b304-5397eaeeda1b'
    and barcode in ('000346', '000404', '000470') and status = 'available');

with gone as (
  delete from public.pieces
  where store_id = 'a15f496a-a4b5-4388-b304-5397eaeeda1b'
    and barcode in ('000346', '000404', '000470') and status = 'available'
  returning barcode)
select count(*) as deleted, string_agg(barcode, ', ' order by barcode) as barcodes from gone;

commit;
