-- Staff rows: someone with manage_staff (not the owner) cannot make himself or anyone an owner,
-- cannot attach/move logins or stores, cannot touch the owner's row, and cannot hand out a
-- permission he does not have himself. Only direct writes from the app (database role
-- 'authenticated') are checked: the trusted server paths -- edge functions with the service
-- role, and security-definer functions such as join_company_by_invite / create_branch /
-- register_new_company, which run as their owner -- do their own checks.
create or replace function public.gm_staff_guard() returns trigger
  -- security invoker on purpose: current_user must be the caller's role, not the owner's.
  language plpgsql set search_path to 'public' as $$
declare
  me record;
  k text;
  st uuid := coalesce(new.store_id, old.store_id);
begin
  if current_user <> 'authenticated' or auth.uid() is null then return coalesce(new, old); end if;
  select role, permissions into me from staff where user_id = auth.uid() and store_id = st;
  if tg_op = 'DELETE' then
    if old.role = 'owner' then raise exception 'لا يمكن حذف مالك الحساب' using errcode = '42501'; end if;
    return old;
  end if;
  if tg_op = 'UPDATE' then
    if new.store_id is distinct from old.store_id then raise exception 'لا يمكن نقل الموظف لمتجر آخر' using errcode = '42501'; end if;
    if new.role is distinct from old.role then raise exception 'لا يمكن تغيير دور الموظف' using errcode = '42501'; end if;
    if new.user_id is distinct from old.user_id then raise exception 'لا يمكن تغيير حساب دخول الموظف من هنا' using errcode = '42501'; end if;
  else
    if new.role is distinct from 'staff' then raise exception 'الموظف الجديد يُضاف بدور موظف فقط' using errcode = '42501'; end if;
    if new.user_id is not null then raise exception 'حساب الدخول يُنشأ من شاشة الموظفين فقط' using errcode = '42501'; end if;
  end if;
  if me.role = 'owner' then return new; end if;
  -- Not the owner from here on.
  if tg_op = 'UPDATE' and old.role = 'owner' then raise exception 'لا يمكن تعديل حساب المالك' using errcode = '42501'; end if;
  for k in select key from jsonb_each_text(coalesce(new.permissions, '{}'::jsonb)) where value = 'true' loop
    if coalesce(me.permissions ->> k, '') <> 'true'
       and (tg_op = 'INSERT' or coalesce(old.permissions ->> k, '') <> 'true') then
      raise exception 'لا يمكنك منح صلاحية لا تملكها (%)', k using errcode = '42501';
    end if;
  end loop;
  return new;
end $$;

create or replace trigger trg_staff_guard before insert or update or delete on public.staff
  for each row execute function public.gm_staff_guard();
