-- Decision 13 (بشار, 2026-10-18): piece barcodes run on ONE counter per organization, kept on the
-- head office (organizations.head_office_store_id), so a number never repeats across branches and a
-- piece keeps its barcode when it moves between branches (transfers come in step 2.4).
-- Today every organization has a single branch, so its counter is its own store: nothing changes
-- for the existing shops. No data is deleted.

-- the store whose counter, prefix and width a branch uses
create or replace function public.barcode_counter_store(p_store uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select coalesce(o.head_office_store_id, s.id)
  from stores s left join organizations o on o.id = s.organization_id
  where s.id = p_store;
$$;
revoke all on function public.barcode_counter_store(uuid) from public, anon;
grant execute on function public.barcode_counter_store(uuid) to authenticated;

create or replace function public.next_piece_barcode(target_store_id uuid, category text)
returns text language plpgsql security definer set search_path = public as $function$
declare
  result_prefix text; result_seq bigint; result_width smallint; bc text; tries int := 0;
  counter uuid; org uuid;
begin
  if not is_store_member(target_store_id) then raise exception 'NOT_AUTHORIZED'; end if;
  if category not in ('gold', 'diamond') then raise exception 'INVALID_CATEGORY'; end if;
  counter := barcode_counter_store(target_store_id);
  select organization_id into org from stores where id = target_store_id;
  loop
    -- the update locks the counter row, so two branches never get the same number
    if category = 'diamond' then
      update stores set next_piece_seq_diamond = next_piece_seq_diamond + 1 where id = counter
        returning piece_barcode_prefix_diamond, next_piece_seq_diamond - 1, piece_barcode_seq_width_diamond
        into result_prefix, result_seq, result_width;
    else
      update stores set next_piece_seq_gold = next_piece_seq_gold + 1 where id = counter
        returning piece_barcode_prefix_gold, next_piece_seq_gold - 1, piece_barcode_seq_width_gold
        into result_prefix, result_seq, result_width;
    end if;
    if result_seq is null then raise exception 'STORE_NOT_FOUND'; end if;
    bc := coalesce(result_prefix, '') || case
      when result_width is not null and result_width > 0 then lpad(result_seq::text, result_width, '0')
      else result_seq::text end;
    tries := tries + 1;
    -- gold barcodes are unique across the whole database; diamonds within the organization
    exit when not exists (select 1 from pieces where barcode = bc)
          and not exists (select 1 from diamond_pieces d join stores s on s.id = d.store_id
                          where d.barcode = bc and (s.id = target_store_id or s.organization_id = org))
          and not exists (select 1 from piece_barcode_history where old_barcode = bc);
    if tries >= 1000 then raise exception 'BARCODE_COLLISION'; end if;
  end loop;
  return bc;
end;
$function$;

-- resetting the sequence (company settings) changes the organization's counter
create or replace function public.reset_piece_barcode_sequence(target_store_id uuid, category text, new_seq bigint)
returns void language plpgsql security definer set search_path = public as $function$
begin
  perform reset_piece_barcode_sequence(target_store_id, category, new_seq, null::smallint,
    (select case when category = 'diamond' then piece_barcode_prefix_diamond else piece_barcode_prefix_gold end
       from stores where id = barcode_counter_store(target_store_id)));
end;
$function$;

create or replace function public.reset_piece_barcode_sequence(target_store_id uuid, category text, new_seq bigint, seq_width smallint)
returns void language plpgsql security definer set search_path = public as $function$
begin
  perform reset_piece_barcode_sequence(target_store_id, category, new_seq, seq_width,
    (select case when category = 'diamond' then piece_barcode_prefix_diamond else piece_barcode_prefix_gold end
       from stores where id = barcode_counter_store(target_store_id)));
end;
$function$;

create or replace function public.reset_piece_barcode_sequence(target_store_id uuid, category text, new_seq bigint, seq_width smallint default null, new_prefix text default null)
returns void language plpgsql security definer set search_path = public as $function$
declare
  is_owner boolean;
  counter uuid := barcode_counter_store(target_store_id);
begin
  -- the owner of the counter's branch (the head office) manages the organization's barcodes
  select (role = 'owner') into is_owner from staff
    where store_id = counter and user_id = auth.uid() limit 1;
  if not coalesce(is_owner, false) then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if category not in ('gold', 'diamond') then
    raise exception 'INVALID_CATEGORY';
  end if;
  if new_seq < 1 then
    raise exception 'INVALID_SEQ';
  end if;

  if category = 'diamond' then
    update stores set
      next_piece_seq_diamond = new_seq,
      piece_barcode_seq_width_diamond = seq_width,
      piece_barcode_prefix_diamond = nullif(upper(trim(new_prefix)), '')
      where id = counter;
  else
    update stores set
      next_piece_seq_gold = new_seq,
      piece_barcode_seq_width_gold = seq_width,
      piece_barcode_prefix_gold = nullif(upper(trim(new_prefix)), '')
      where id = counter;
  end if;
end;
$function$;
