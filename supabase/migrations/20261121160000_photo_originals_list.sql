-- Owner-only list of original piece photos that now have a «-gm1200.jpg» copy and are referenced nowhere,
-- for the «تحسين الصور» cleanup step. The storage list API returned nothing for staff (no SELECT policy on
-- piece-photos objects), so the page could never find originals to delete (بشار 2026-11-21).
create or replace function public.gm_photo_originals(sid uuid)
returns table(name text, size bigint)
language plpgsql stable security definer set search_path = public, storage as $$
begin
  if not exists (select 1 from public.staff s where s.store_id = sid and s.user_id = auth.uid() and s.role = 'owner' and s.suspended_at is null) then
    raise exception 'owner only';
  end if;
  return query
  with o as (
    select ob.name, coalesce((ob.metadata->>'size')::bigint, 0) sz
    from storage.objects ob where ob.bucket_id = 'piece-photos' and ob.name like sid::text || '/%'
  ), refs as (
    select p.photo_url u from public.pieces p where p.store_id = sid
    union all select ii.item_photo_url from public.invoice_items ii join public.invoices i on i.id = ii.invoice_id where i.store_id = sid
    union all select r.intake_photo_url from public.repair_tickets r where r.store_id = sid
    union all select r.ready_photo_url from public.repair_tickets r where r.store_id = sid
    union all select i.bulk_photos::text from public.invoices i where i.store_id = sid and i.bulk_photos is not null
    union all select d.photo_url from public.diamond_pieces d where d.store_id = sid
    union all select bti.photo_url from public.branch_transfer_items bti where bti.photo_url is not null
  )
  select o.name, o.sz from o
  where o.name not like '%-gm1200.jpg'
    and exists (select 1 from o s where s.name = regexp_replace(o.name, '\.[^./]+$', '') || '-gm1200.jpg')
    and not exists (select 1 from refs where refs.u like '%' || o.name || '%');
end $$;
revoke all on function public.gm_photo_originals(uuid) from public, anon;
grant execute on function public.gm_photo_originals(uuid) to authenticated;
