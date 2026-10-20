-- Staff added by name only (no login, e.g. listed as a seller) do not count toward the subscription.
-- They start counting when a login is created for them (same row: user_id filled), which also runs the
-- automatic plan check like adding a staff member does.
create or replace function public.get_effective_staff_count(p_store_id uuid) returns integer
  language sql stable set search_path to 'public' as $$
  select count(*)::int from staff where store_id = p_store_id and user_id is not null;
$$;

create trigger trg_auto_upgrade_on_staff_login after update of user_id on public.staff
  for each row when (old.user_id is null and new.user_id is not null)
  execute function public.auto_upgrade_on_staff_change();

create or replace function public.admin_list_stores() returns table(id uuid, name text, country text, currency text, created_at timestamp with time zone, staff_count bigint, plan_name text, subscription_status text, trial_end timestamp with time zone, current_period_end timestamp with time zone, last_activity_at timestamp with time zone)
  language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not public.is_platform_admin() then
    raise exception 'NOT_AUTHORIZED';
  end if;
  return query
    select s.id, s.name, s.country, s.currency, s.created_at,
           (select count(*) from public.staff st where st.store_id = s.id and st.user_id is not null) as staff_count,
           p.name_ar, sub.status, sub.trial_end, sub.current_period_end,
           greatest(
             s.created_at,
             (select max(i.created_at) from public.invoices i where i.store_id = s.id),
             (select max(pc.created_at) from public.pieces pc where pc.store_id = s.id),
             (select max(cm.created_at) from public.cash_movements cm where cm.store_id = s.id),
             (select max(c.created_at) from public.customers c where c.store_id = s.id),
             (select max(al.created_at) from public.audit_log al where al.store_id = s.id)
           ) as last_activity_at
    from public.stores s
    left join public.subscriptions sub on sub.store_id = s.id
    left join public.plans p on p.id = sub.plan_id
    order by s.created_at desc;
end;
$$;
