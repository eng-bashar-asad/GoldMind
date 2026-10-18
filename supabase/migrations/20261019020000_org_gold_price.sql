-- Multi-branch 2.2 (decision 3): one gold price for the organization, with an optional
-- price of its own for a given branch.
--   * stores.own_gold_price (default false): the branch keeps its own price.
--   * set_gold_ounce_price (same signature, same screens): saving the price on a branch that
--     follows the organization saves it on every branch of the organization that also follows it
--     and uses the same currency; on a branch with its own price, only that branch.
--   * set_branch_own_gold_price(store, own): manage_gold_price on that branch. Switching back to
--     the organization's price copies it from the head office (or another following branch).
-- Single-branch shops: the organization is the store itself, so nothing changes. No data deleted.

begin;

alter table public.stores add column if not exists own_gold_price boolean not null default false;

create or replace function public.set_gold_ounce_price(target_store_id uuid, ounce numeric, rate numeric)
returns void language plpgsql security definer set search_path = public as $function$
declare g24 numeric; cur text; own boolean; s uuid;
begin
  if not public.has_permission('manage_gold_price', target_store_id) then
    raise exception 'ليس لديك صلاحية تعديل سعر الذهب' using errcode = '42501';
  end if;
  select upper(currency), own_gold_price into cur, own from public.stores where id = target_store_id;
  if cur = 'USD' then
    rate := 1;
  end if;
  if ounce is null or ounce <= 0 or ounce > 1000000 then raise exception 'سعر أونصة غير صحيح'; end if;
  if rate is null or rate <= 0 or rate > 1000000 then raise exception 'سعر صرف غير صحيح'; end if;

  g24 := ounce / 31.1034768 * rate;
  -- this branch, plus (when it follows the organization) every following branch in the same currency
  for s in
    select target_store_id
    union
    select b.id from public.stores b
     where not coalesce(own, false) and not b.own_gold_price and upper(b.currency) = cur
       and b.id in (select org_store_ids(target_store_id))
  loop
    insert into public.gold_prices (store_id, karat, price_per_gram, mode, updated_at)
    select s, k, round(g24 * k / 24.0, 2), 'manual_ounce', now()
    from unnest(array[24, 22, 21, 18]) as k
    on conflict (store_id, karat) do update
      set price_per_gram = excluded.price_per_gram, mode = excluded.mode, updated_at = now();

    update public.stores
       set last_gold_ounce_price = ounce, last_gold_ounce_rate = rate
     where id = s;
  end loop;
end;
$function$;

create or replace function public.set_branch_own_gold_price(p_store uuid, p_own boolean)
returns void language plpgsql security definer set search_path = public as $function$
declare src uuid; cur text;
begin
  if not public.has_permission('manage_gold_price', p_store) then
    raise exception 'ليس لديك صلاحية تعديل سعر الذهب' using errcode = '42501';
  end if;
  update public.stores set own_gold_price = coalesce(p_own, false) where id = p_store returning upper(currency) into cur;
  if coalesce(p_own, false) then return; end if;
  -- back to the organization's price: take it from the head office, else another following branch
  select b.id into src from public.stores b
    left join public.organizations o on o.id = b.organization_id
   where b.id in (select org_store_ids(p_store)) and b.id <> p_store
     and not b.own_gold_price and upper(b.currency) = cur
   order by (b.id = o.head_office_store_id) desc, b.created_at
   limit 1;
  if src is null then return; end if;
  insert into public.gold_prices (store_id, karat, price_per_gram, mode, updated_at)
  select p_store, karat, price_per_gram, mode, now() from public.gold_prices where store_id = src
  on conflict (store_id, karat) do update
    set price_per_gram = excluded.price_per_gram, mode = excluded.mode, updated_at = now();
  update public.stores d set last_gold_ounce_price = s.last_gold_ounce_price, last_gold_ounce_rate = s.last_gold_ounce_rate
    from public.stores s where s.id = src and d.id = p_store;
end;
$function$;
revoke all on function public.set_branch_own_gold_price(uuid, boolean) from public, anon;
grant execute on function public.set_branch_own_gold_price(uuid, boolean) to authenticated;

commit;
