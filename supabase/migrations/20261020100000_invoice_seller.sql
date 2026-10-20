-- The staff member a sale counts for (staff sales report). Empty on old rows = whoever entered it
-- (reports read coalesce(salesperson_id, created_by)).
alter table public.invoices add column if not exists salesperson_id uuid references public.staff(id) on delete set null;
create index if not exists invoices_store_salesperson_created_idx on public.invoices (store_id, salesperson_id, created_at);

-- Rules (server side, the screen only asks):
--  * not chosen -> the person entering the invoice;
--  * someone else can be chosen only by the owner or staff with the 'set_seller' permission,
--    and only a staff member of the same organization (otherwise the entering person is kept);
--  * a return counts for the seller of the original sale;
--  * the client sends the choice as the x-gm-seller header (works through the existing invoice functions).
create or replace function public.gm_seller_stamp() returns trigger
  language plpgsql security definer set search_path to 'public' as $$
declare h text; wanted uuid; allowed boolean;
begin
  if tg_op = 'INSERT' and new.type = 'return' and new.related_invoice_id is not null then
    select coalesce(salesperson_id, created_by) into new.salesperson_id from invoices where id = new.related_invoice_id;
    return new;
  end if;
  wanted := new.salesperson_id;
  if tg_op = 'INSERT' then
    h := nullif(current_setting('request.headers', true), '')::json->>'x-gm-seller';
    if h ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then wanted := h::uuid; end if;
  elsif new.salesperson_id is not distinct from old.salesperson_id then
    return new;
  end if;
  allowed := wanted is not null
    and public.has_permission('set_seller', new.store_id)
    and exists (select 1 from staff where id = wanted and store_id in (select public.org_store_ids(new.store_id)));
  if tg_op = 'INSERT' then
    new.salesperson_id := case when allowed then wanted else new.created_by end;
  elsif not allowed then
    new.salesperson_id := old.salesperson_id;
  end if;
  return new;
end $$;

create trigger trg_invoice_salesperson before insert or update of salesperson_id on public.invoices
  for each row execute function public.gm_seller_stamp();
