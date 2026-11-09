-- A piece that was scanned in an inventory count could not be deleted (FK without ON DELETE).
-- The count keeps its scan row (piece_id becomes empty); queued RFID write jobs go with the piece.
-- Run by Bashar (changes delete behaviour).
alter table public.inventory_count_scans drop constraint inventory_count_scans_piece_id_fkey;
alter table public.inventory_count_scans add constraint inventory_count_scans_piece_id_fkey
  foreign key (piece_id) references public.pieces(id) on delete set null;
alter table public.rfid_write_jobs drop constraint rfid_write_jobs_piece_id_fkey;
alter table public.rfid_write_jobs add constraint rfid_write_jobs_piece_id_fkey
  foreign key (piece_id) references public.pieces(id) on delete cascade;
