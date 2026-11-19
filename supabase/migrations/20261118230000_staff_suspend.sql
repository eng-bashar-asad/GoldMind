-- Staff «إيقاف مؤقت» (بشار 2026-11-18): a suspended staff member keeps all their data but cannot
-- use the company: membership and permission checks treat the row as absent. They can still read
-- their own staff row, so the app can tell them «تم إيقاف حسابك من قبل الإدارة».
alter table public.staff add column if not exists suspended_at timestamptz;

create or replace function public.is_store_member(target_store_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.staff
    where user_id = auth.uid() and store_id = target_store_id and suspended_at is null
  );
$$;

create or replace function public.has_permission(perm text, target_store_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(
    (select role = 'owner' or (permissions ->> perm) = 'true'
     from public.staff where user_id = auth.uid() and store_id = target_store_id and suspended_at is null),
    false
  );
$$;

drop policy if exists "staff can view own rows" on public.staff;
create policy "staff can view own rows" on public.staff for select using (user_id = (select auth.uid()));

-- the owner is never suspended
create or replace function public.trg_staff_suspend_guard()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.suspended_at is not null and new.role = 'owner' then
    raise exception 'لا يمكن إيقاف مالك الشركة';
  end if;
  return new;
end $$;
drop trigger if exists trg_staff_suspend_guard on public.staff;
create trigger trg_staff_suspend_guard before insert or update of suspended_at, role on public.staff
  for each row execute function public.trg_staff_suspend_guard();

-- the company switcher lists only companies the person may use
create or replace function public.my_stores()
returns table(store_id uuid, store_name text, role text)
language sql stable security definer set search_path = public as $$
  select s.store_id, coalesce(nullif(btrim(st.display_name), ''), st.name), s.role
    from public.staff s join public.stores st on st.id = s.store_id
   where s.user_id = auth.uid() and s.suspended_at is null
   order by 2;
$$;
