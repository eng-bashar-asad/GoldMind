-- Diamond and gold barcodes came from two counters with the same format (no prefix, 6 digits),
-- so diamond piece 000004 and gold piece 000004 both existed: searching or scanning 000004
-- found the gold piece. Diamond barcodes now start with D, and a new barcode is never one
-- that is already used by a gold piece, a diamond piece, or a cancelled old barcode.
-- Nothing is deleted.

-- 1) stores whose two counters produce the same format: diamonds get the D prefix
update public.stores
   set piece_barcode_prefix_diamond = 'D'
 where coalesce(piece_barcode_prefix_diamond, '') = coalesce(piece_barcode_prefix_gold, '');

-- 2) existing diamond pieces whose barcode is also a gold piece's barcode in the same store: add D
--    (the old sticker must be reprinted)
update public.diamond_pieces d
   set barcode = 'D' || d.barcode
 where exists (select 1 from public.pieces p where p.store_id = d.store_id and p.barcode = d.barcode)
   and not exists (select 1 from public.diamond_pieces x where x.store_id = d.store_id and x.barcode = 'D' || d.barcode);

-- 3) next barcode skips numbers already taken in either warehouse
create or replace function public.next_piece_barcode(target_store_id uuid, category text)
returns text language plpgsql security definer set search_path to 'public' as $function$
declare
  result_prefix text;
  result_seq bigint;
  result_width smallint;
  bc text;
  tries int := 0;
begin
  if not is_store_member(target_store_id) then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if category not in ('gold', 'diamond') then
    raise exception 'INVALID_CATEGORY';
  end if;

  loop
    if category = 'diamond' then
      update stores
        set next_piece_seq_diamond = next_piece_seq_diamond + 1
        where id = target_store_id
        returning piece_barcode_prefix_diamond, next_piece_seq_diamond - 1, piece_barcode_seq_width_diamond
        into result_prefix, result_seq, result_width;
    else
      update stores
        set next_piece_seq_gold = next_piece_seq_gold + 1
        where id = target_store_id
        returning piece_barcode_prefix_gold, next_piece_seq_gold - 1, piece_barcode_seq_width_gold
        into result_prefix, result_seq, result_width;
    end if;

    if result_seq is null then
      raise exception 'STORE_NOT_FOUND';
    end if;

    -- lpad(x, 0, ...) truncates to an EMPTY string, not a no-op -- must
    -- only call lpad at all when a width was actually configured.
    bc := coalesce(result_prefix, '') || case
      when result_width is not null and result_width > 0 then lpad(result_seq::text, result_width, '0')
      else result_seq::text
    end;

    tries := tries + 1;
    exit when not exists (select 1 from pieces where store_id = target_store_id and barcode = bc)
          and not exists (select 1 from diamond_pieces where store_id = target_store_id and barcode = bc)
          and not exists (select 1 from piece_barcode_history where old_barcode = bc);
    if tries >= 1000 then raise exception 'BARCODE_COLLISION'; end if;
  end loop;
  return bc;
end;
$function$;
