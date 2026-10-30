--
-- PostgreSQL database dump
--

\restrict j570AKsyiQ0gzzXjRLt7j55k7f0NOQyUQgpv3QEveB28KiMzzImhjbhRmhX177r


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: accounting_health_check(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.accounting_health_check(sid uuid) RETURNS TABLE(severity text, code text, title text, details text, ref_id uuid, ref_label text)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare scur text;
begin
  if not (has_permission('view_reports', sid)) then
    raise exception 'ليس لديك صلاحية' using errcode = '42501';
  end if;
  select upper(coalesce(nullif(currency,''),'AED')) into scur from stores where id = sid;

  return query
  select 'error', 'gold_price_currency', 'سعر الذهب لا يتناسب مع عملة المحل',
         gold_price_problem(sid, g.karat, g.price_per_gram), null::uuid, g.karat || 'K'
  from gold_prices g where g.store_id = sid and gold_price_problem(sid, g.karat, g.price_per_gram) is not null;

  return query
  select 'warning', 'invoice_currency', 'فاتورة بعملة غير عملة المحل',
         format('الفاتورة بـ %s والمحل بـ %s', i.currency, scur), i.id, i.invoice_number
  from invoices i where i.store_id = sid and i.currency is not null and upper(i.currency) <> scur and i.status <> 'cancelled';

  return query
  select 'error', 'invoice_lines_total', 'مجموع سطور الفاتورة ≠ الإجمالي',
         format('السطور %s — الإجمالي %s', coalesce(x.s, 0), i.total_amount), i.id, i.invoice_number
  from invoices i left join lateral (select sum(line_total) s, count(*) n from invoice_items where invoice_id = i.id) x on true
  where i.store_id = sid and i.type = 'sale' and i.status <> 'cancelled'
    and (x.n = 0 or abs(coalesce(x.s, 0) - i.total_amount) > 0.01);

  return query
  select 'warning', 'invoice_cash_mismatch', 'المقبوض بالفاتورة ≠ المسجّل بالصندوق والدفعات',
         format('مدفوع %s — بالصندوق %s — دفعات لاحقة %s', i.amount_paid, coalesce(c.s, 0), coalesce(al.s, 0)), i.id, i.invoice_number
  from invoices i
  left join lateral (select sum(case when direction = 'in' then amount else -amount end) s from cash_movements where invoice_id = i.id) c on true
  left join lateral (select sum(case when movement_type = 'debt_decrease' then cash_amount else -cash_amount end) s
                       from customer_debts where invoice_id = i.id and source = 'allocation') al on true
  where i.store_id = sid and i.type = 'sale' and i.status <> 'cancelled' and i.payment_method in ('cash','bank','mixed')
    and abs(coalesce(c.s, 0) + coalesce(al.s, 0) - coalesce(i.amount_paid, 0)) > 0.01;

  return query
  select 'warning', 'invoice_debt_mismatch', 'المبلغ المتبقي على العميل غير مسجّل كدين',
         format('متبقي %s — مسجّل دين %s', i.total_amount - coalesce(i.amount_paid,0), coalesce(d.s, 0)), i.id, i.invoice_number
  from invoices i left join lateral (
      select sum(case when movement_type = 'debt_increase' then cash_amount else -cash_amount end) s
        from customer_debts where invoice_id = i.id) d on true
  where i.store_id = sid and i.type = 'sale' and i.status <> 'cancelled'
    and abs((i.total_amount - coalesce(i.amount_paid,0)) - coalesce(d.s, 0)) > 0.01;

  return query
  select 'error', 'cash_currency', 'حركة صندوق لفاتورة بعملة غلط',
         format('%s %s — عملة المحل %s', cm.amount, cm.currency, scur), cm.invoice_id, i.invoice_number
  from cash_movements cm join invoices i on i.id = cm.invoice_id
  where cm.store_id = sid and cm.currency is not null and upper(cm.currency) <> upper(coalesce(i.currency, scur));

  return query
  select 'error', 'piece_still_available', 'قطعة مباعة لكنها ما زالت تظهر متاحة',
         format('القطعة %s بالفاتورة %s', p.barcode, i.invoice_number), p.id, p.barcode
  from invoice_items ii join invoices i on i.id = ii.invoice_id join pieces p on p.id = ii.piece_id
  where i.store_id = sid and i.type = 'sale' and i.status <> 'cancelled' and p.status = 'available'
    and ii.line_total >= 0
    and not exists (
      select 1 from invoice_items r join invoices ri on ri.id = r.invoice_id
       where r.piece_id = p.id and ri.status <> 'cancelled' and ri.created_at >= i.created_at and ri.id <> i.id
         and (ri.type = 'return' or r.line_total < 0 or r.returned_item_id = ii.id));

  return query
  select 'warning', 'daily_box_missing', 'دفعة فاتورة نقدية غير ظاهرة بالصندوق اليومي',
         format('%s %s %s بتاريخ %s', case cm.direction when 'in' then 'قبض' else 'صرف' end, cm.amount, coalesce(cm.currency, scur), to_char(cm.created_at, 'YYYY-MM-DD')),
         cm.invoice_id, i.invoice_number
  from cash_movements cm join invoices i on i.id = cm.invoice_id
  where cm.store_id = sid and cm.box = 'main' and cm.created_at >= '2026-08-08'
    and not coalesce(cm.edit_delta, false)
    and coalesce(cm.description, '') not like 'تعديل عملات الدفع%' -- currency changes: the invoice's own rows are rewritten
    and not exists (select 1 from daily_cash_log l where l.cash_movement_id = cm.id);

  return query
  select 'error', 'negative_stock', 'رصيد جملة سالب',
         format('عيار %s: %s غ', l.karat, l.weight_grams_remaining), l.id, l.karat || 'K'
  from gold_stock_lots l where l.store_id = sid and (l.weight_grams_remaining < 0 or coalesce(l.fabrication_pool_remaining, 0) < 0);
end $$;


--
-- Name: admin_create_store(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_create_store(company_name text, owner_email text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  new_store_id uuid;
begin
  if not public.is_platform_admin() then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if company_name is null or length(trim(company_name)) = 0 then
    raise exception 'COMPANY_NAME_REQUIRED';
  end if;
  if owner_email is null or length(trim(owner_email)) = 0 then
    raise exception 'OWNER_EMAIL_REQUIRED';
  end if;

  insert into public.stores (name) values (trim(company_name)) returning id into new_store_id;

  insert into public.subscriptions (store_id, plan_id, status, trial_end)
  select new_store_id, p.id, 'trialing', now() + interval '30 days'
  from public.plans p where p.key = 'pro';

  insert into public.store_invites (id, store_id, email, role, status, permissions, invited_by)
  values (
    gen_random_uuid(), new_store_id, lower(trim(owner_email)), 'owner', 'pending',
    jsonb_build_object(
      'view_inventory', true, 'add_piece', true, 'edit_piece', true, 'delete_piece', true,
      'view_customers', true, 'add_customers', true, 'edit_customers', true,
      'view_traders', true, 'add_traders', true, 'edit_traders', true,
      'view_invoices', true, 'create_invoice', true, 'delete_invoice', true,
      'view_reports', true, 'view_profit_report', true, 'edit_settings', true,
      'manage_staff', true, 'manage_gold_price', true, 'manage_subscription', true
    ),
    null
  );

  return new_store_id;
end;
$$;


--
-- Name: admin_delete_store(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_delete_store(target_store_id uuid) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if not public.is_platform_admin() then
    raise exception 'NOT_AUTHORIZED';
  end if;
  delete from public.stores where id = target_store_id;
  return true;
end;
$$;


--
-- Name: admin_extend_subscription(uuid, text, timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_extend_subscription(target_store_id uuid, p_status text, p_trial_end timestamp with time zone DEFAULT NULL::timestamp with time zone, p_current_period_end timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if not public.is_platform_admin() then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_status not in ('trialing', 'active') then
    raise exception 'INVALID_STATUS';
  end if;

  if exists (select 1 from subscriptions where store_id = target_store_id) then
    update subscriptions
      set status = p_status,
          trial_end = case when p_status = 'trialing' then p_trial_end else trial_end end,
          current_period_end = case when p_status = 'active' then p_current_period_end else current_period_end end,
          updated_at = now()
      where store_id = target_store_id;
  else
    insert into subscriptions (store_id, plan_id, status, trial_end, current_period_end)
    select target_store_id, id, p_status, p_trial_end, p_current_period_end
    from plans where key = 'basic';
  end if;
end;
$$;


--
-- Name: admin_invite_staff(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_invite_staff(target_store_id uuid, invite_email text, invite_role text DEFAULT 'staff'::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  new_invite_id uuid;
  perms jsonb;
begin
  if not public.is_platform_admin() then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if invite_email is null or length(trim(invite_email)) = 0 then
    raise exception 'EMAIL_REQUIRED';
  end if;
  if invite_role not in ('staff', 'owner') then
    raise exception 'INVALID_ROLE';
  end if;

  if invite_role = 'owner' then
    perms := jsonb_build_object(
      'view_inventory', true, 'add_piece', true, 'edit_piece', true, 'delete_piece', true,
      'view_customers', true, 'add_customers', true, 'edit_customers', true,
      'view_traders', true, 'add_traders', true, 'edit_traders', true,
      'view_invoices', true, 'create_invoice', true, 'delete_invoice', true,
      'view_reports', true, 'view_profit_report', true, 'edit_settings', true,
      'manage_staff', true, 'manage_gold_price', true, 'manage_subscription', true
    );
  else
    perms := '{}'::jsonb;
  end if;

  if exists (
    select 1 from public.store_invites
    where store_id = target_store_id and lower(email) = lower(trim(invite_email)) and status = 'pending'
  ) then
    raise exception 'ALREADY_INVITED';
  end if;

  if exists (
    select 1 from public.staff st join auth.users u on u.id = st.user_id
    where st.store_id = target_store_id and lower(u.email) = lower(trim(invite_email))
  ) then
    raise exception 'ALREADY_MEMBER';
  end if;

  insert into public.store_invites (id, store_id, email, role, status, permissions, invited_by)
  values (gen_random_uuid(), target_store_id, lower(trim(invite_email)), invite_role, 'pending', perms, null)
  returning id into new_invite_id;

  return new_invite_id;
end;
$$;


--
-- Name: admin_list_platform_admin_accounts(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_list_platform_admin_accounts() RETURNS TABLE(email text, username text)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if not public.is_platform_admin() then
    raise exception 'NOT_AUTHORIZED';
  end if;
  return query
    select pa.email, up.username
    from public.platform_admins pa
    left join public.user_profiles up on up.id = pa.id
    order by pa.email;
end;
$$;


--
-- Name: admin_list_store_invites(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_list_store_invites(target_store_id uuid) RETURNS TABLE(invite_id uuid, email text, role text, status text, created_at timestamp with time zone)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if not public.is_platform_admin() then
    raise exception 'NOT_AUTHORIZED';
  end if;
  return query
    select si.id, si.email, si.role, si.status, si.created_at
    from public.store_invites si
    where si.store_id = target_store_id
    order by si.created_at desc;
end;
$$;


--
-- Name: admin_list_store_staff(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_list_store_staff(target_store_id uuid) RETURNS TABLE(staff_id uuid, full_name text, role text, email text, joined_at timestamp with time zone)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if not public.is_platform_admin() then
    raise exception 'NOT_AUTHORIZED';
  end if;
  return query
    select st.id, st.full_name, st.role, u.email::text, st.created_at
    from public.staff st
    join auth.users u on u.id = st.user_id
    where st.store_id = target_store_id
    order by st.created_at asc;
end;
$$;


--
-- Name: admin_list_stores(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_list_stores() RETURNS TABLE(id uuid, name text, country text, currency text, created_at timestamp with time zone, staff_count bigint, plan_name text, subscription_status text, trial_end timestamp with time zone, current_period_end timestamp with time zone, last_activity_at timestamp with time zone)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


--
-- Name: admin_list_support_requests(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_list_support_requests() RETURNS TABLE(id uuid, store_id uuid, store_name text, subject text, message text, status text, admin_reply text, created_at timestamp with time zone)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if not public.is_platform_admin() then
    raise exception 'NOT_AUTHORIZED';
  end if;
  return query
    select r.id, r.store_id, s.name, r.subject, r.message, r.status, r.admin_reply, r.created_at
    from public.support_requests r
    join public.stores s on s.id = r.store_id
    order by r.created_at desc;
end;
$$;


--
-- Name: admin_remove_staff(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_remove_staff(target_staff_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if not public.is_platform_admin() then
    raise exception 'NOT_AUTHORIZED';
  end if;
  delete from public.staff where id = target_staff_id;
end;
$$;


--
-- Name: admin_revoke_invite(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_revoke_invite(target_invite_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if not public.is_platform_admin() then
    raise exception 'NOT_AUTHORIZED';
  end if;
  update public.store_invites set status = 'revoked' where id = target_invite_id and status = 'pending';
end;
$$;


--
-- Name: admin_update_store(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_update_store(target_store_id uuid, new_name text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if not public.is_platform_admin() then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if new_name is null or length(trim(new_name)) = 0 then
    raise exception 'COMPANY_NAME_REQUIRED';
  end if;
  update public.stores set name = trim(new_name) where id = target_store_id;
end;
$$;


--
-- Name: admin_update_support_request(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_update_support_request(request_id uuid, new_status text, reply text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if not public.is_platform_admin() then
    raise exception 'NOT_AUTHORIZED';
  end if;
  update public.support_requests
  set status = coalesce(new_status, status),
      admin_reply = coalesce(reply, admin_reply),
      updated_at = now()
  where id = request_id;
  return true;
end;
$$;


--
-- Name: auto_upgrade_on_staff_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auto_upgrade_on_staff_change() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_store_id uuid;
  v_sub subscriptions%rowtype;
  v_plan plans%rowtype;
  v_next_plan plans%rowtype;
  v_count int;
begin
  v_store_id := coalesce(new.store_id, old.store_id);
  if v_store_id is null then return coalesce(new, old); end if;

  select * into v_sub from subscriptions where store_id = v_store_id limit 1;
  if v_sub.id is null then return coalesce(new, old); end if;

  select * into v_plan from plans where id = v_sub.plan_id;
  if v_plan.staff_upgrade_threshold is null or v_plan.next_plan_key is null then return coalesce(new, old); end if;

  v_count := public.get_effective_staff_count(v_store_id);
  if v_count >= v_plan.staff_upgrade_threshold then
    select * into v_next_plan from plans where key = v_plan.next_plan_key;
    if v_next_plan.id is not null and v_sub.plan_id <> v_next_plan.id then
      update subscriptions set plan_id = v_next_plan.id, last_auto_upgrade_at = now(), updated_at = now()
      where id = v_sub.id;
      insert into audit_log (store_id, action_type, description)
      values (v_store_id, 'auto_plan_upgrade', 'ترقية تلقائية من ' || v_plan.name_ar || ' إلى ' || v_next_plan.name_ar || ' بسبب تجاوز عدد الموظفين ' || v_count);
      insert into support_requests (store_id, subject, message, status, preferred_language)
      values (v_store_id, 'ترقية تلقائية للاشتراك', 'تم ترقية المتجر تلقائياً إلى خطة ' || v_next_plan.name_ar || ' لتجاوز عدد الموظفين (' || v_count || '). الرجاء إصدار فاتورة الفرق للعميل.', 'open', 'ar');
    end if;
  end if;
  return coalesce(new, old);
end;
$$;


--
-- Name: barcode_counter_store(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.barcode_counter_store(p_store uuid) RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select coalesce(o.head_office_store_id, s.id)
    from stores s left join organizations o on o.id = s.organization_id
      where s.id = p_store;
      $$;


--
-- Name: cancel_branch_transfer(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cancel_branch_transfer(p_transfer uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         declare tr record; it record; d jsonb; me uuid; back int := 0; got int; cm uuid;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         begin
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           select * into tr from branch_transfers where id = p_transfer for update;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             if tr is null then raise exception 'سند النقل غير موجود'; end if;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               if not has_permission('stock_transfers', tr.from_store_id) then
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   raise exception 'ليس لديك صلاحية إلغاء سند النقل' using errcode = '42501';
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     end if;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       if tr.status <> 'in_transit' then raise exception 'هذا السند ليس بالطريق (حالته: %)', tr.status; end if;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         select id into me from staff where user_id = auth.uid() and store_id = tr.from_store_id limit 1;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           for it in select * from branch_transfer_items where transfer_id = tr.id and received_at is null for update loop
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               if it.kind = 'scrap' then
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     for d in select * from jsonb_array_elements(coalesce(it.lot_draws, '[]'::jsonb)) loop
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             update gold_stock_lots set weight_grams_remaining = weight_grams_remaining + (d->>'w')::numeric
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      where id = (d->>'lot_id')::uuid;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            end loop;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                elsif it.kind = 'cash' then
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      insert into cash_movements (store_id, box, direction, amount, description, created_by)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              values (tr.from_store_id, it.cash_box, 'in', it.amount, 'إلغاء نقل نقد بسند ' || tr.transfer_number, me) returning id into cm;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    if it.cash_box = 'main' then
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            insert into daily_cash_log (store_id, operation_type, direction, amount, notes, created_by, cash_movement_id)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      values (tr.from_store_id, 'إلغاء نقل نقد لفرع آخر', 'in', it.amount, 'سند ' || tr.transfer_number, me, cm);
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            end if;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                elsif it.piece_id is not null then
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      update pieces set status = 'available' where id = it.piece_id and status = 'in_transit' and store_id = tr.from_store_id;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            insert into piece_movements (store_id, piece_id, event_type, note, created_by)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    values (tr.from_store_id, it.piece_id, 'transfer_cancelled', 'إلغاء سند النقل ' || tr.transfer_number, me);
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        elsif it.diamond_piece_id is not null then
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              update diamond_pieces set status = 'available' where id = it.diamond_piece_id and status = 'in_transit' and store_id = tr.from_store_id;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  end if;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      delete from branch_transfer_items where id = it.id;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          back := back + 1;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            end loop;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              select count(*) into got from branch_transfer_items where transfer_id = tr.id;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                -- what was already received stays there; the voucher keeps only that
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  update branch_transfers set status = case when got > 0 then 'received' else 'cancelled' end where id = tr.id;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    return jsonb_build_object('returned', back, 'kept', got);
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    end $$;


--
-- Name: cancel_invoice(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cancel_invoice(target_invoice_id uuid, reason text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  inv record;
  actor_staff_id uuid;
begin
  select * into inv from public.invoices where id = target_invoice_id;
  if inv is null then raise exception 'INVOICE_NOT_FOUND'; end if;
  if not public.has_permission('delete_invoice', inv.store_id) then raise exception 'NOT_AUTHORIZED'; end if;
  if inv.status = 'cancelled' then raise exception 'ALREADY_CANCELLED'; end if;

  select id into actor_staff_id from public.staff where user_id = auth.uid() and store_id = inv.store_id limit 1;

  update public.invoices set status = 'cancelled' where id = target_invoice_id;

  if inv.type = 'sale' then
    update public.pieces set status = 'available'
    where id in (select piece_id from public.invoice_items where invoice_id = target_invoice_id and piece_id is not null and returned_item_id is null);
    update public.pieces set status = 'sold'
    where id in (select piece_id from public.invoice_items where invoice_id = target_invoice_id and piece_id is not null and returned_item_id is not null);
  elsif inv.type in ('buyTrader', 'buyRetail') then
    update public.pieces set status = 'cancelled'
    where id in (select piece_id from public.invoice_items where invoice_id = target_invoice_id and piece_id is not null);
  end if;

  update public.gold_stock_lots set weight_grams_remaining = 0
    where source_invoice_id = target_invoice_id and weight_grams_remaining > 0;

  insert into public.cash_movements (store_id, box, direction, amount, currency, fx_amount, fx_currency, description, created_by, invoice_id)
  select store_id, box, case when direction = 'in' then 'out' else 'in' end, amount, currency, fx_amount, fx_currency,
         'إلغاء فاتورة ' || inv.invoice_number || coalesce(' — ' || reason, ''), actor_staff_id, target_invoice_id
  from public.cash_movements where invoice_id = target_invoice_id
    and coalesce(description, '') not like 'إلغاء فاتورة%' and coalesce(description, '') not like 'استعادة فاتورة%';

  insert into public.customer_debts (store_id, customer_id, invoice_id, movement_type, cash_amount, gold_grams_24k, notes, created_by)
  select store_id, customer_id, invoice_id,
         case when movement_type = 'debt_increase' then 'debt_decrease' else 'debt_increase' end,
         cash_amount, gold_grams_24k, 'إلغاء فاتورة ' || inv.invoice_number || coalesce(' — ' || reason, ''), actor_staff_id
  from public.customer_debts where invoice_id = target_invoice_id
    and coalesce(notes, '') not like 'إلغاء فاتورة%' and coalesce(notes, '') not like 'استعادة فاتورة%';

  insert into public.trader_movements (store_id, trader_id, invoice_id, movement_type, weight_grams, karat, gold_24k_equivalent, fab_fee_amount, notes)
  select store_id, trader_id, invoice_id,
         case when movement_type = 'debt_increase' then 'debt_decrease' else 'debt_increase' end,
         weight_grams, karat, gold_24k_equivalent, fab_fee_amount, 'إلغاء فاتورة ' || inv.invoice_number || coalesce(' — ' || reason, '')
  from public.trader_movements where invoice_id = target_invoice_id
    and coalesce(notes, '') not like 'إلغاء فاتورة%' and coalesce(notes, '') not like 'استعادة فاتورة%';
end;
$$;


--
-- Name: cash_voucher(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cash_voucher(p jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
-- One receipt/payment voucher (سند قبض / سند صرف) for a customer, a trader or an expense,
-- in any currency: the account is kept in the store currency (amount ÷ rate), the cash box
-- gets the money in the currency it was actually paid in.
declare sid uuid := (p->>'store_id')::uuid; kind text := p->>'kind'; party text := p->>'party';
  pid uuid := nullif(p->>'party_id', '')::uuid; amt numeric := round(coalesce(nullif(p->>'amount', '')::numeric, 0), 2);
  cur text := upper(coalesce(nullif(p->>'currency', ''), '')); rate numeric := nullif(p->>'fx_rate', '')::numeric;
  method text := coalesce(nullif(p->>'method', ''), 'cash'); daily boolean := coalesce((p->>'daily')::boolean, true);
  descr text := nullif(trim(p->>'notes'), ''); base_cur text; base_amt numeric; fx boolean; me uuid; cm uuid; c record; t record; cat record;
  fxnote text := ''; note text; mid uuid; eid uuid;
begin
  if kind not in ('in', 'out') then raise exception 'نوع السند غير معروف'; end if;
  if method not in ('cash', 'bank') then raise exception 'طريقة دفع غير معروفة'; end if;
  if amt <= 0 then raise exception 'المبلغ يجب أن يكون أكبر من صفر'; end if;
  if not is_store_member(sid) then raise exception 'ليس لديك صلاحية' using errcode = '42501'; end if;
  select coalesce(nullif(upper(currency), ''), 'AED') into base_cur from stores where id = sid;
  if cur = '' then cur := base_cur; end if;
  fx := cur <> base_cur;
  if fx then
    if rate is null or rate <= 0 then raise exception 'أدخل سعر صرف % مقابل %', cur, base_cur; end if;
    base_amt := round(amt / rate, 2);
    fxnote := ' (' || trim(to_char(amt, 'FM999,999,999,990.00')) || ' ' || cur || ' بسعر ' || trim(to_char(rate, 'FM999,999,990.####')) || ')';
  else
    base_amt := amt;
  end if;
  select id into me from staff where user_id = auth.uid() and store_id = sid limit 1;

  if party = 'customer' then
    select id, store_id, name into c from customers where id = pid and store_id in (select org_store_ids(sid));
    if c is null then raise exception 'اختر الزبون'; end if;
    if not (has_permission('edit_customers', sid) or has_permission('manage_daily_cashbox', sid)) then raise exception 'ليس لديك صلاحية سندات الزبائن' using errcode = '42501'; end if;
    note := coalesce(descr, case when kind = 'in' then 'دفعة من العميل' else 'صرف للعميل' end) || fxnote;
    insert into cash_movements (store_id, box, direction, amount, description, created_by, fx_amount, fx_currency)
      values (sid, case when method = 'bank' then 'bank' else 'main' end, kind, base_amt,
              case when kind = 'in' then 'دفعة من العميل ' else 'صرف للعميل ' end || c.name || case when method = 'bank' then ' (تحويل/بطاقة)' else '' end,
              me, case when fx then amt end, case when fx then cur end) returning id into cm;
    if method = 'cash' and daily then
      insert into daily_cash_log (store_id, operation_type, direction, amount, currency, notes, created_by, cash_movement_id)
        values (sid, case when kind = 'in' then 'دفعة من عميل' else 'صرف لعميل' end, kind, amt, cur, c.name || ' — ' || note, me, cm);
    end if;
    insert into customer_debts (store_id, customer_id, movement_type, cash_amount, gold_grams_24k, notes, source, created_by, cash_movement_id)
      values (sid, c.id, case when kind = 'in' then 'debt_decrease' else 'debt_increase' end, base_amt, 0, note,
              case when kind = 'in' then 'payment' else 'cash_out' end, me, cm);

  elsif party = 'trader' then
    select id, store_id, name into t from traders where id = pid and store_id in (select org_store_ids(sid));
    if t is null then raise exception 'اختر التاجر'; end if;
    if not has_permission('edit_traders', sid) then raise exception 'ليس لديك صلاحية تعديل حسابات التجار' using errcode = '42501'; end if;
    note := coalesce(descr, case when kind = 'out' then 'صرف كاش للتاجر' else 'قبض كاش من التاجر' end) || fxnote;
    insert into trader_movements (store_id, trader_id, movement_type, weight_grams, karat, gold_24k_equivalent, fab_fee_amount, source, notes, created_by)
      values (sid, t.id, case when kind = 'out' then 'debt_decrease' else 'debt_increase' end, 0, null, 0, base_amt,
              case when kind = 'out' then 'cash_out' else 'cash_in' end, note, me) returning id into mid;
    insert into cash_movements (store_id, box, direction, amount, description, created_by, trader_movement_id, fx_amount, fx_currency)
      values (sid, case when method = 'bank' then 'bank' else 'main' end, kind, base_amt,
              case when kind = 'out' then 'صرف كاش للتاجر ' else 'قبض كاش من التاجر ' end || t.name, me, mid,
              case when fx then amt end, case when fx then cur end) returning id into cm;
    if method = 'cash' and daily then
      insert into daily_cash_log (store_id, operation_type, direction, amount, currency, notes, created_by, cash_movement_id)
        values (sid, case when kind = 'out' then 'صرف كاش لتاجر' else 'قبض كاش من تاجر' end, kind, amt, cur, t.name || ' — ' || note, me, cm);
    end if;

  elsif party = 'expense' then
    if kind <> 'out' then raise exception 'المصروف يكون سند صرف فقط'; end if;
    if not gm_can_expense(sid) then raise exception 'ليس لديك صلاحية تسجيل المصاريف' using errcode = '42501'; end if;
    select id, name into cat from expense_categories where id = nullif(p->>'category_id', '')::uuid and store_id = sid;
    if cat is null then raise exception 'اختر نوع المصروف'; end if;
    insert into expense_entries (store_id, category_id, amount, description, created_by)
      values (sid, cat.id, base_amt, coalesce(descr, cat.name) || fxnote, me) returning id into eid;
    insert into cash_movements (store_id, box, direction, amount, description, created_by, fx_amount, fx_currency)
      values (sid, case when method = 'bank' then 'bank' else 'main' end, 'out', base_amt, 'مصروف ' || cat.name || coalesce(': ' || descr, '') || fxnote,
              me, case when fx then amt end, case when fx then cur end) returning id into cm;
    update expense_entries set cash_movement_id = cm where id = eid;
    if method = 'cash' and daily then
      insert into daily_cash_log (store_id, operation_type, direction, amount, currency, notes, created_by, cash_movement_id)
        values (sid, 'مصروف: ' || cat.name, 'out', amt, cur, coalesce(descr, '') || fxnote, me, cm);
    end if;
  else
    raise exception 'اختر الطرف: زبون أو تاجر أو مصروف';
  end if;
  return jsonb_build_object('ok', true, 'cash_movement_id', cm, 'base_amount', base_amt, 'base_currency', base_cur);
end $$;


--
-- Name: check_head_office_in_org(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_head_office_in_org() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
begin
  if new.head_office_store_id is not null
       and not exists (select 1 from stores where id = new.head_office_store_id and organization_id = new.id) then
           raise exception 'المكتب الرئيسي يجب أن يكون أحد فروع نفس المنشأة';
             end if;
               return new;
               end $$;


--
-- Name: check_staff_limit(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_staff_limit(p_store_id uuid) RETURNS TABLE(current_count integer, included_count integer, extra_price numeric, upgrade_threshold integer, plan_key text)
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public'
    AS $$
declare
  v_plan_id uuid;
begin
  select plan_id into v_plan_id from subscriptions where store_id = p_store_id limit 1;
  return query
  select public.get_effective_staff_count(p_store_id), p.included_staff, p.extra_staff_price, p.staff_upgrade_threshold, p.key
  from plans p where p.id = v_plan_id;
end;
$$;


--
-- Name: close_fiscal_year(uuid, integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.close_fiscal_year(target_store_id uuid, target_year integer, notes text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  actor_staff_id uuid;
  is_owner boolean;
  yr_start timestamptz := make_timestamptz(target_year, 1, 1, 0, 0, 0, 'UTC');
  yr_end timestamptz := make_timestamptz(target_year + 1, 1, 1, 0, 0, 0, 'UTC');
  v_total_sales numeric := 0;
  v_total_returns numeric := 0;
  v_total_output_tax numeric := 0;
  v_total_input_tax numeric := 0;
  store_vat_rate numeric;
begin
  select id, (role = 'owner') into actor_staff_id, is_owner
  from public.staff where user_id = auth.uid() and store_id = target_store_id limit 1;

  if not coalesce(is_owner, false) then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if exists (select 1 from public.fiscal_year_closures where store_id = target_store_id and fiscal_year = target_year) then
    raise exception 'ALREADY_CLOSED';
  end if;

  select vat_rate into store_vat_rate from public.stores where id = target_store_id;
  store_vat_rate := coalesce(store_vat_rate, 0);

  select coalesce(sum(total_amount), 0) into v_total_sales
    from public.invoices
    where store_id = target_store_id and type = 'sale' and status <> 'cancelled'
      and created_at >= yr_start and created_at < yr_end;

  select coalesce(sum(total_amount), 0) into v_total_returns
    from public.invoices
    where store_id = target_store_id and type = 'return'
      and created_at >= yr_start and created_at < yr_end;

  select coalesce(sum(total_amount - total_amount / (1 + store_vat_rate / 100.0)), 0) into v_total_output_tax
    from public.invoices
    where store_id = target_store_id and type = 'sale' and status <> 'cancelled'
      and created_at >= yr_start and created_at < yr_end;

  select coalesce(sum(vat_amount), 0) into v_total_input_tax
    from public.invoices
    where store_id = target_store_id and type in ('buyTrader', 'buyRetail') and status <> 'cancelled'
      and created_at >= yr_start and created_at < yr_end;

  insert into public.fiscal_year_closures (
    store_id, fiscal_year, total_sales, total_returns, total_profit,
    total_output_tax, total_input_tax, notes, closed_by
  ) values (
    target_store_id, target_year, v_total_sales, v_total_returns, 0,
    v_total_output_tax, v_total_input_tax, notes, actor_staff_id
  );
end;
$$;


--
-- Name: consume_diamond_stock_lot(uuid, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.consume_diamond_stock_lot(target_lot_id uuid, amount numeric) RETURNS numeric
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  new_remaining numeric;
  lot_store_id uuid;
begin
  select store_id into lot_store_id from diamond_stock_lots where id = target_lot_id;
  if lot_store_id is null then
    raise exception 'LOT_NOT_FOUND';
  end if;
  if not is_store_member(lot_store_id) then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if amount <= 0 then
    raise exception 'INVALID_AMOUNT';
  end if;

  update diamond_stock_lots
    set remaining_carat = remaining_carat - amount
    where id = target_lot_id and remaining_carat >= amount
    returning remaining_carat into new_remaining;

  if new_remaining is null then
    raise exception 'INSUFFICIENT_STOCK';
  end if;

  return new_remaining;
end;
$$;


--
-- Name: consume_gold_stock_lot(uuid, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.consume_gold_stock_lot(target_lot_id uuid, amount numeric) RETURNS numeric
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  new_remaining numeric;
  lot_store_id uuid;
begin
  select store_id into lot_store_id from gold_stock_lots where id = target_lot_id;
  if lot_store_id is null then
    raise exception 'LOT_NOT_FOUND';
  end if;
  if not is_store_member(lot_store_id) then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if amount <= 0 then
    raise exception 'INVALID_AMOUNT';
  end if;

  update gold_stock_lots
    set weight_grams_remaining = weight_grams_remaining - amount
    where id = target_lot_id and weight_grams_remaining >= amount
    returning weight_grams_remaining into new_remaining;

  if new_remaining is null then
    raise exception 'INSUFFICIENT_STOCK';
  end if;

  return new_remaining;
end;
$$;


--
-- Name: consume_gold_stock_lot_pooled(uuid, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.consume_gold_stock_lot_pooled(target_lot_id uuid, weight_amount numeric, fee_amount numeric) RETURNS TABLE(new_weight_remaining numeric, new_fee_remaining numeric)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  lot_store_id uuid;
  lot_fab_remaining numeric;
begin
  select store_id, fabrication_pool_remaining into lot_store_id, lot_fab_remaining
    from gold_stock_lots where id = target_lot_id;

  if lot_store_id is null then
    raise exception 'LOT_NOT_FOUND';
  end if;
  if not is_store_member(lot_store_id) then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if weight_amount <= 0 then
    raise exception 'INVALID_AMOUNT';
  end if;
  if fee_amount < 0 then
    raise exception 'INVALID_AMOUNT';
  end if;
  if lot_fab_remaining is null then
    raise exception 'NOT_A_POOLED_LOT';
  end if;

  update gold_stock_lots
    set weight_grams_remaining = weight_grams_remaining - weight_amount,
        fabrication_pool_remaining = fabrication_pool_remaining - fee_amount
    where id = target_lot_id
      and weight_grams_remaining >= weight_amount
      and fabrication_pool_remaining >= fee_amount
    returning weight_grams_remaining, fabrication_pool_remaining
    into new_weight_remaining, new_fee_remaining;

  if new_weight_remaining is null then
    raise exception 'INSUFFICIENT_STOCK';
  end if;

  return next;
end;
$$;


--
-- Name: create_branch(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_branch(p_from_store uuid, p_name text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
                 declare
                   org uuid;
                     me record;
                       src record;
                         new_id uuid;
                           nm text := btrim(coalesce(p_name, ''));
                           begin
                             if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
                               select organization_id into org from stores where id = p_from_store;
                                 if org is null or not is_org_owner(org) then
                                     raise exception 'إضافة فرع متاحة لمالك المنشأة فقط' using errcode = '42501';
                                       end if;
                                         if nm = '' then raise exception 'اكتب اسم الفرع'; end if;
                                           if exists (select 1 from stores where organization_id = org and lower(btrim(name)) = lower(nm)) then
                                               raise exception 'يوجد فرع بنفس الاسم في هذه المنشأة';
                                                 end if;
                                                   select * into me from staff where store_id = p_from_store and user_id = auth.uid() limit 1;
                                                     select * into src from stores where id = p_from_store;

                                                       -- settings only: address, phone, licence, branch code and emirate, devices and counters start fresh
                                                         insert into stores (name, organization_id, currency, vat_rate, country, gold_price_source, invoice_numbering_mode,
                                                               invoice_print_frame, invoice_print_shape, diamonds_enabled, einvoice_disabled,
                                                                     piece_barcode_prefix_gold, piece_barcode_prefix_diamond, piece_barcode_seq_width_gold, piece_barcode_seq_width_diamond,
                                                                           secondary_currency, secondary_currency_rate, secondary_currency_rate_updated_at, rfid_enabled, auto_capture_photo_enabled,
                                                                                 last_gold_ounce_price, last_gold_ounce_rate, fab_rate_retail, fab_rate_wholesale, fab_rate_wholesale2,
                                                                                       label_mc_multiplier, label_mc_addend, zebra_label_width_mm, zebra_label_height_mm, zebra_label_dpi,
                                                                                             zebra_label_x_offset_mm, zebra_label_y_offset_mm, zebra_barcode_height_mm, zebra_label_rotate_180, zebra_darkness,
                                                                                                   zebra_field_spacing_mm, zebra_barcode_module_width, allow_biometric_login, debt_alert_days, debt_alert_customers,
                                                                                                         debt_alert_traders, terms_accepted_at, terms_accepted_version)
                                                                                                           values (nm, org, src.currency, src.vat_rate, src.country, src.gold_price_source, src.invoice_numbering_mode,
                                                                                                                 src.invoice_print_frame, src.invoice_print_shape, src.diamonds_enabled, src.einvoice_disabled,
                                                                                                                       src.piece_barcode_prefix_gold, src.piece_barcode_prefix_diamond, src.piece_barcode_seq_width_gold, src.piece_barcode_seq_width_diamond,
                                                                                                                             src.secondary_currency, src.secondary_currency_rate, src.secondary_currency_rate_updated_at, src.rfid_enabled, src.auto_capture_photo_enabled,
                                                                                                                                   src.last_gold_ounce_price, src.last_gold_ounce_rate, src.fab_rate_retail, src.fab_rate_wholesale, src.fab_rate_wholesale2,
                                                                                                                                         src.label_mc_multiplier, src.label_mc_addend, src.zebra_label_width_mm, src.zebra_label_height_mm, src.zebra_label_dpi,
                                                                                                                                               src.zebra_label_x_offset_mm, src.zebra_label_y_offset_mm, src.zebra_barcode_height_mm, src.zebra_label_rotate_180, src.zebra_darkness,
                                                                                                                                                     src.zebra_field_spacing_mm, src.zebra_barcode_module_width, src.allow_biometric_login, src.debt_alert_days, src.debt_alert_customers,
                                                                                                                                                           src.debt_alert_traders, src.terms_accepted_at, src.terms_accepted_version)
                                                                                                                                                             returning id into new_id;

                                                                                                                                                               insert into gold_prices (store_id, karat, price_per_gram, mode)
                                                                                                                                                                   select new_id, karat, price_per_gram, mode from gold_prices where store_id = p_from_store;

                                                                                                                                                                     -- same plan and end date as the organization's primary store
                                                                                                                                                                       insert into subscriptions (store_id, plan_id, status, trial_end, current_period_end, grace_period_days)
                                                                                                                                                                           select new_id, s.plan_id, s.status, s.trial_end, s.current_period_end, s.grace_period_days
                                                                                                                                                                               from subscriptions s join organizations o on o.primary_store_id = s.store_id
                                                                                                                                                                                   where o.id = org limit 1;

                                                                                                                                                                                     insert into staff (user_id, store_id, full_name, role, permissions, contact_phone, whatsapp_phone)
                                                                                                                                                                                         values (auth.uid(), new_id, coalesce(me.full_name, split_part((select email from auth.users where id = auth.uid()), '@', 1)),
                                                                                                                                                                                                     'owner', me.permissions, me.contact_phone, me.whatsapp_phone);

                                                                                                                                                                                                       insert into audit_log (store_id, staff_id, action_type, description)
                                                                                                                                                                                                           values (p_from_store, me.id, 'branch_created', 'إضافة فرع جديد: ' || nm);

                                                                                                                                                                                                             return new_id;
                                                                                                                                                                                                             end $$;


--
-- Name: create_customer_deposit(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_customer_deposit(p jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare c record; me uuid; amt numeric := round(coalesce(nullif(p->>'amount', '')::numeric, 0), 2);
        meth text := coalesce(nullif(p->>'method', ''), 'cash'); num text; dep_id uuid; cm uuid;
                to_box boolean := coalesce((p->>'to_cashbox')::boolean, true);
                begin
                  select id, coalesce(nullif(p->>'store_id', '')::uuid, store_id) as store_id, store_id as home_store, name into c from customers where id = (p->>'customer_id')::uuid;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               if c is not null and c.store_id not in (select org_store_ids(c.home_store)) then raise exception 'العميل ليس من هذه المنشأة'; end if;
                    if c is null then raise exception 'اختر العميل'; end if;
                      if not (has_permission('edit_customers', c.store_id) or has_permission('manage_daily_cashbox', c.store_id)) then
                          raise exception 'ليس لديك صلاحية تسجيل العربون' using errcode = '42501';
                            end if;
                              if amt <= 0 then raise exception 'المبلغ يجب أن يكون أكبر من صفر'; end if;
                                if meth not in ('cash', 'bank') then raise exception 'طريقة دفع غير معروفة'; end if;
                                  select id into me from staff where user_id = auth.uid() and store_id = c.store_id limit 1;

                                    perform pg_advisory_xact_lock(hashtext('deposit:' || c.store_id));
                                      select 'DEP-' || lpad((coalesce(max(nullif(regexp_replace(deposit_number, '\D', '', 'g'), '')::int), 0) + 1)::text, 6, '0')
                                          into num from customer_deposits where store_id = c.store_id;

                                            insert into customer_deposits (store_id, deposit_number, customer_id, amount, method, items, notes, created_by, in_cashbox)
                                                values (c.store_id, num, c.id, amt, meth, coalesce(p->'items', '[]'::jsonb), nullif(trim(p->>'notes'), ''), me, to_box)
                                                    returning id into dep_id;
                                                      if to_box then
                                                          insert into cash_movements (store_id, box, direction, amount, description, created_by)
                                                                values (c.store_id, case when meth = 'bank' then 'bank' else 'main' end, 'in', amt, 'عربون ' || num || ' من ' || c.name, me)
                                                                      returning id into cm;
                                                                          if meth = 'cash' then
                                                                                insert into daily_cash_log (store_id, operation_type, direction, amount, notes, created_by, cash_movement_id)
                                                                                        values (c.store_id, 'عربون', 'in', amt, 'عربون ' || num || ' — ' || c.name, me, cm);
                                                                                            end if;
                                                                                              end if;
                                                                                                insert into customer_debts (store_id, customer_id, movement_type, cash_amount, gold_grams_24k, notes, source, created_by)
                                                                                                    values (c.store_id, c.id, 'debt_decrease', amt, 0, 'عربون ' || num, 'deposit', me);
                                                                                                      update pieces set status = 'reserved', reserved_customer_id = c.id
                                                                                                          where store_id = c.store_id and status = 'available'
                                                                                                                and barcode in (select nullif(trim(x->>'barcode'), '') from jsonb_array_elements(coalesce(p->'items', '[]'::jsonb)) x);
                                                                                                                  return jsonb_build_object('id', dep_id, 'deposit_number', num);
                                                                                                                  end $$;


--
-- Name: currency_usd_peg(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.currency_usd_peg(cur text) RETURNS numeric
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public'
    AS $$
  select case upper(coalesce(cur,''))
    when 'USD' then 1 when 'AED' then 3.6725 when 'SAR' then 3.75 when 'QAR' then 3.64
    when 'BHD' then 0.376 when 'OMR' then 0.3845 when 'JOD' then 0.709 else null end
$$;


--
-- Name: current_store_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.current_store_id() RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select store_id from public.staff where user_id = auth.uid() limit 1;
$$;


--
-- Name: customer_cash_out(uuid, numeric, text, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.customer_cash_out(p_customer uuid, p_amount numeric, p_method text DEFAULT 'cash'::text, p_notes text DEFAULT NULL::text, p_store uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
                                                                                                                                                                                                                                                                                                                                                                                                                         declare c record; st uuid; me uuid; amt numeric := round(coalesce(p_amount, 0), 2); cm uuid; note text;
                                                                                                                                                                                                                                                                                                                                                                                                                         begin
                                                                                                                                                                                                                                                                                                                                                                                                                           select id, store_id, name into c from customers where id = p_customer;
                                                                                                                                                                                                                                                                                                                                                                                                                             if c is null then raise exception 'العميل غير موجود'; end if;
                                                                                                                                                                                                                                                                                                                                                                                                                               st := coalesce(p_store, c.store_id);
                                                                                                                                                                                                                                                                                                                                                                                                                                 if st not in (select org_store_ids(c.store_id)) then raise exception 'العميل ليس من هذه المنشأة'; end if;
                                                                                                                                                                                                                                                                                                                                                                                                                                   if not (has_permission('edit_customers', st) or has_permission('manage_daily_cashbox', st)) then
                                                                                                                                                                                                                                                                                                                                                                                                                                       raise exception 'ليس لديك صلاحية صرف مبالغ للعملاء' using errcode = '42501';
                                                                                                                                                                                                                                                                                                                                                                                                                                         end if;
                                                                                                                                                                                                                                                                                                                                                                                                                                           if amt <= 0 then raise exception 'المبلغ يجب أن يكون أكبر من صفر'; end if;
                                                                                                                                                                                                                                                                                                                                                                                                                                             if coalesce(p_method, 'cash') not in ('cash', 'bank') then raise exception 'طريقة دفع غير معروفة'; end if;
                                                                                                                                                                                                                                                                                                                                                                                                                                               select id into me from staff where user_id = auth.uid() and store_id = st limit 1;
                                                                                                                                                                                                                                                                                                                                                                                                                                                 note := coalesce(nullif(trim(p_notes), ''), 'صرف للعميل');
                                                                                                                                                                                                                                                                                                                                                                                                                                                   insert into cash_movements (store_id, box, direction, amount, description, created_by)
                                                                                                                                                                                                                                                                                                                                                                                                                                                       values (st, case when p_method = 'bank' then 'bank' else 'main' end, 'out', amt,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                   'صرف للعميل ' || c.name || case when p_method = 'bank' then ' (تحويل/بطاقة)' else '' end, me)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                       returning id into cm;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                         if coalesce(p_method, 'cash') = 'cash' then
                                                                                                                                                                                                                                                                                                                                                                                                                                                                             insert into daily_cash_log (store_id, operation_type, direction, amount, notes, created_by, cash_movement_id)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   values (st, 'صرف لعميل', 'out', amt, c.name || ' — ' || note, me, cm);
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     end if;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       insert into customer_debts (store_id, customer_id, movement_type, cash_amount, gold_grams_24k, notes, source, created_by, cash_movement_id)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           values (st, c.id, 'debt_increase', amt, 0, note, 'cash_out', me, cm);
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             return jsonb_build_object('ok', true);
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             end $$;


--
-- Name: customer_credit(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.customer_credit(sid uuid, cust uuid) RETURNS numeric
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
                     select round(greatest(0, -coalesce(sum(case when movement_type = 'debt_increase' then cash_amount else -cash_amount end), 0)), 2)
                       from customer_debts where store_id in (select org_store_ids(sid)) and customer_id = cust;
                       $$;


--
-- Name: customer_debt_discount(uuid, numeric, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.customer_debt_discount(p_customer uuid, p_amount numeric, p_notes text DEFAULT NULL::text, p_store uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             declare c record; st uuid; me uuid; amt numeric := round(coalesce(p_amount, 0), 2); owed numeric;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             begin
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               select id, store_id, name into c from customers where id = p_customer;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 if c is null then raise exception 'العميل غير موجود'; end if;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   st := coalesce(p_store, c.store_id);
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     if st not in (select org_store_ids(c.store_id)) then raise exception 'العميل ليس من هذه المنشأة'; end if;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       if not has_permission('edit_customers', st) then
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           raise exception 'ليس لديك صلاحية تسجيل خصم على دين العميل' using errcode = '42501';
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             end if;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               if amt <= 0 then raise exception 'المبلغ يجب أن يكون أكبر من صفر'; end if;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 -- the customer's whole debt across the organization
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   select coalesce(sum(case when movement_type = 'debt_increase' then cash_amount else -cash_amount end), 0) into owed
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       from customer_debts where customer_id = c.id and store_id in (select org_store_ids(st));
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         if amt > round(owed, 2) + 0.009 then raise exception 'الخصم (%) أكبر من دين العميل (%)', amt, round(owed, 2); end if;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           select id into me from staff where user_id = auth.uid() and store_id = st limit 1;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             -- Balance-only: no cash moves. Settles the oldest open invoices like a payment.
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               insert into customer_debts (store_id, customer_id, movement_type, cash_amount, gold_grams_24k, notes, source, created_by)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   values (st, c.id, 'debt_decrease', amt, 0, coalesce(nullif(trim(p_notes), ''), 'خصم على الدين'), 'discount', me);
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     return jsonb_build_object('ok', true);
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     end $$;


--
-- Name: customer_debt_discount_update(uuid, numeric, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.customer_debt_discount_update(p_id uuid, p_amount numeric, p_notes text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare d record; amt numeric := round(coalesce(p_amount, 0), 2); owed numeric;
begin
  select * into d from customer_debts where id = p_id and source = 'discount';
  if d is null then raise exception 'الخصم غير موجود'; end if;
  if not has_permission('edit_customers', d.store_id) then
    raise exception 'ليس لديك صلاحية تعديل خصم دين العميل' using errcode = '42501';
  end if;
  if amt < 0 then raise exception 'المبلغ غير صحيح'; end if;
  if amt = 0 then
    delete from customer_debts where id = p_id;
  else
    select coalesce(sum(case when movement_type = 'debt_increase' then cash_amount else -cash_amount end), 0) into owed
      from customer_debts where customer_id = d.customer_id and store_id = d.store_id and id <> p_id;
    if amt > round(owed, 2) + 0.009 then raise exception 'الخصم (%) أكبر من دين العميل (%)', amt, round(owed, 2); end if;
    update customer_debts set cash_amount = amt, notes = coalesce(nullif(trim(p_notes), ''), 'خصم على الدين') where id = p_id;
  end if;
  perform gm_allocate_customer_credit(d.store_id, d.customer_id);
  perform gm_unallocate_customer_credit(d.store_id, d.customer_id);
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: customer_deposit_remaining(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.customer_deposit_remaining(sid uuid) RETURNS TABLE(deposit_id uuid, remaining numeric)
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
                         with cred as (
                             select customer_id, greatest(0, -sum(case when movement_type = 'debt_increase' then cash_amount else -cash_amount end)) c
                                 from customer_debts where store_id in (select org_store_ids(sid)) group by customer_id),
                                   d as (
                                       select dp.id, dp.store_id, dp.amount, coalesce(cr.c, 0) c,
                                                  sum(dp.amount) over (partition by dp.customer_id order by dp.created_at desc, dp.id) run
                                                      from customer_deposits dp left join cred cr on cr.customer_id = dp.customer_id
                                                          where dp.store_id in (select org_store_ids(sid)) and dp.status = 'active')
                                                            select id, round(least(amount, greatest(0, c - (run - amount))), 2) from d where store_id = sid;
                                                            $$;


--
-- Name: customer_payment_update(uuid, numeric, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.customer_payment_update(p_id uuid, p_amount numeric, p_notes text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare d record; c record; m record; amt numeric := round(coalesce(p_amount, 0), 2); note text; ratio numeric := 1;
begin
  select * into d from customer_debts where id = p_id and source in ('payment', 'cash_out');
  if d is null then raise exception 'الحركة غير موجودة'; end if;
  if not has_permission('edit_customers', d.store_id) then
    raise exception 'ليس لديك صلاحية تعديل دفعات العملاء' using errcode = '42501';
  end if;
  if amt < 0 then raise exception 'المبلغ غير صحيح'; end if;
  select name into c from customers where id = d.customer_id;
  if amt = 0 then
    delete from customer_debts where id = p_id;
    if d.cash_movement_id is not null then delete from cash_movements where id = d.cash_movement_id; end if; -- daily row cascades
  else
    note := coalesce(nullif(trim(p_notes), ''), case when d.source = 'cash_out' then 'صرف للعميل' else 'دفعة من العميل' end);
    update customer_debts set cash_amount = amt, notes = note where id = p_id;
    if d.cash_movement_id is not null then
      select * into m from cash_movements where id = d.cash_movement_id;
      if m.fx_currency is not null and m.amount > 0 then ratio := m.fx_amount / m.amount; end if;
      update cash_movements set amount = amt, fx_amount = case when fx_currency is not null then round(amt * ratio, 2) end where id = d.cash_movement_id;
      update daily_cash_log set amount = round(amt * ratio, 2), notes = c.name || ' — ' || note where cash_movement_id = d.cash_movement_id;
    end if;
  end if;
  perform gm_allocate_customer_credit(d.store_id, d.customer_id);
  perform gm_unallocate_customer_credit(d.store_id, d.customer_id);
  return jsonb_build_object('ok', true, 'linked', d.cash_movement_id is not null);
end $$;


--
-- Name: delete_expense(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_expense(p_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
                                                                                                                                                                                                                                                                       declare e record;
                                                                                                                                                                                                                                                                       begin
                                                                                                                                                                                                                                                                         select * into e from expense_entries where id = p_id;
                                                                                                                                                                                                                                                                           if e is null then raise exception 'المصروف غير موجود'; end if;
                                                                                                                                                                                                                                                                             if not gm_can_expense(e.store_id) or not is_store_member(e.store_id) then raise exception 'ليس لديك صلاحية حذف المصاريف' using errcode = '42501'; end if;
                                                                                                                                                                                                                                                                               if exists (select 1 from inventory_gifts where expense_entry_id = p_id) then raise exception 'هذا مصروف هدية — احذفه بإرجاع الهدية إلى المخزن'; end if;
                                                                                                                                                                                                                                                                                 update gold_stock_lots l set weight_grams_remaining = round(l.weight_grams_remaining + r.grams, 3)
                                                                                                                                                                                                                                                                                     from repair_gold_lines r where r.expense_entry_id = p_id and r.lot_id = l.id;
                                                                                                                                                                                                                                                                                       delete from repair_gold_lines where expense_entry_id = p_id;
                                                                                                                                                                                                                                                                                         delete from expense_entries where id = p_id;
                                                                                                                                                                                                                                                                                           if e.cash_movement_id is not null then delete from cash_movements where id = e.cash_movement_id; end if; -- its daily-box row goes with it
                                                                                                                                                                                                                                                                                             return jsonb_build_object('ok', true);
                                                                                                                                                                                                                                                                                             end $$;


--
-- Name: delete_expense_category(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_expense_category(p_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare c record;
begin
  select * into c from expense_categories where id = p_id;
  if c is null then return; end if;
  if not gm_can_expense(c.store_id) then raise exception 'ليس لديك صلاحية' using errcode = '42501'; end if;
  if c.name = 'هدايا' then raise exception 'لا يمكن حذف نوع الهدايا'; end if;
  if exists (select 1 from expense_entries where category_id = p_id) then
    raise exception 'لا يمكن حذف نوع عليه مصاريف مسجّلة — يمكنك تغيير اسمه';
  end if;
  delete from expense_categories where id = p_id;
end $$;


--
-- Name: delete_last_sale_invoice(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_last_sale_invoice(target_invoice_id uuid) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
                                                                                                                                                                                   declare
                                                                                                                                                                                     inv record;
                                                                                                                                                                                       st record;
                                                                                                                                                                                         inv_seq integer;
                                                                                                                                                                                           inv_year integer;
                                                                                                                                                                                             actor uuid;
                                                                                                                                                                                               parts text[];
                                                                                                                                                                                               begin
                                                                                                                                                                                                 select * into inv from public.invoices where id = target_invoice_id for update;
                                                                                                                                                                                                   if inv is null then raise exception 'الفاتورة غير موجودة'; end if;

                                                                                                                                                                                                     if not exists (select 1 from public.staff where user_id = auth.uid() and store_id = inv.store_id and role = 'owner') then
                                                                                                                                                                                                         raise exception 'حذف الفواتير متاح للمالك فقط' using errcode = '42501';
                                                                                                                                                                                                           end if;
                                                                                                                                                                                                             if inv.type <> 'sale' then raise exception 'الحذف متاح لفواتير المبيعات فقط'; end if;
                                                                                                                                                                                                               if exists (select 1 from public.invoices where related_invoice_id = inv.id) then
                                                                                                                                                                                                                   raise exception 'عليها فاتورة مرتجع، ولا يمكن حذفها';
                                                                                                                                                                                                                     end if;
                                                                                                                                                                                                                       if exists (select 1 from public.invoice_items where invoice_id = inv.id and diamond_stock_lot_id is not null) then
                                                                                                                                                                                                                           raise exception 'فيها ماس من رصيد جملة — استخدم الإلغاء بدل الحذف';
                                                                                                                                                                                                                             end if;

                                                                                                                                                                                                                               -- number format [CODE-]PREFIX-YYYY-NNNNNN; must be the last one issued
                                                                                                                                                                                                                                 parts := regexp_match(inv.invoice_number, '-([0-9]{4})-([0-9]+)$');
                                                                                                                                                                                                                                   inv_year := parts[1]::integer;
                                                                                                                                                                                                                                     inv_seq  := parts[2]::integer;
                                                                                                                                                                                                                                       select next_invoice_seq, next_invoice_seq_year into st from public.stores where id = inv.store_id for update;
                                                                                                                                                                                                                                         if inv_seq is null or inv_year is distinct from st.next_invoice_seq_year or inv_seq <> st.next_invoice_seq - 1 then
                                                                                                                                                                                                                                             raise exception 'يمكن حذف آخر فاتورة فقط (لتجنّب حدوث فراغ في الترقيم). يمكنك إلغاء هذه الفاتورة بدلاً من حذفها.';
                                                                                                                                                                                                                                               end if;

                                                                                                                                                                                                                                                 select id into actor from public.staff where user_id = auth.uid() and store_id = inv.store_id limit 1;

                                                                                                                                                                                                                                                   -- pieces back to stock
                                                                                                                                                                                                                                                     update public.pieces set status = 'available'
                                                                                                                                                                                                                                                        where status = 'sold' and id in (select piece_id from public.invoice_items where invoice_id = inv.id and piece_id is not null);
                                                                                                                                                                                                                                                          delete from public.piece_movements
                                                                                                                                                                                                                                                             where store_id = inv.store_id and event_type = 'sold' and note = 'بيع بفاتورة ' || inv.invoice_number
                                                                                                                                                                                                                                                                  and piece_id in (select piece_id from public.invoice_items where invoice_id = inv.id and piece_id is not null);
                                                                                                                                                                                                                                                                    update public.diamond_pieces set status = 'available'
                                                                                                                                                                                                                                                                       where status = 'sold' and id in (select diamond_piece_id from public.invoice_items where invoice_id = inv.id and diamond_piece_id is not null);

                                                                                                                                                                                                                                                                         -- bulk gold sold from lots goes back to the lot (weight, and pooled fee)
                                                                                                                                                                                                                                                                           update public.gold_stock_lots l
                                                                                                                                                                                                                                                                                set weight_grams_remaining = l.weight_grams_remaining + x.w,
                                                                                                                                                                                                                                                                                         fabrication_pool_remaining = case when l.fabrication_pool_remaining is null then null
                                                                                                                                                                                                                                                                                                                                    else l.fabrication_pool_remaining + x.f end
                                                                                                                                                                                                                                                                                                                                        from (select gold_stock_lot_id, sum(coalesce(weight_grams, 0)) w, sum(coalesce(fabrication_fee, 0)) f
                                                                                                                                                                                                                                                                                                                                                    from public.invoice_items where invoice_id = inv.id and gold_stock_lot_id is not null
                                                                                                                                                                                                                                                                                                                                                               group by gold_stock_lot_id) x
                                                                                                                                                                                                                                                                                                                                                                  where l.id = x.gold_stock_lot_id;

                                                                                                                                                                                                                                                                                                                                                                    -- money / debt movements created by (or reversing) this invoice
                                                                                                                                                                                                                                                                                                                                                                      delete from public.cash_movements where invoice_id = inv.id;
                                                                                                                                                                                                                                                                                                                                                                        delete from public.customer_debts where invoice_id = inv.id;
                                                                                                                                                                                                                                                                                                                                                                          delete from public.trader_movements where invoice_id = inv.id;

                                                                                                                                                                                                                                                                                                                                                                            delete from public.invoices where id = inv.id; -- invoice_items cascade

                                                                                                                                                                                                                                                                                                                                                                              update public.stores set next_invoice_seq = inv_seq where id = inv.store_id;

                                                                                                                                                                                                                                                                                                                                                                                insert into public.audit_log (store_id, staff_id, action_type, description)
                                                                                                                                                                                                                                                                                                                                                                                  values (inv.store_id, actor, 'invoice_deleted',
                                                                                                                                                                                                                                                                                                                                                                                            'حذف فاتورة مبيعات ' || inv.invoice_number || ' بقيمة ' || coalesce(inv.total_amount, 0) || ' — الرقم رجع متاح للفاتورة الجاية');

                                                                                                                                                                                                                                                                                                                                                                                              return inv.invoice_number;
                                                                                                                                                                                                                                                                                                                                                                                              end;
                                                                                                                                                                                                                                                                                                                                                                                              $_$;


--
-- Name: ensure_store_organization(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ensure_store_organization() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
                                     declare new_org uuid;
                                     begin
                                       insert into organizations (name, primary_store_id, country) values (new.name, new.id, new.country)
                                           returning id into new_org;
                                             update stores set organization_id = new_org where id = new.id;
                                               return null;
                                               end $$;


--
-- Name: fill_currency_from_store(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fill_currency_from_store() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if new.currency is null or new.currency = '' then
    select coalesce(nullif(upper(currency), ''), 'AED') into new.currency from public.stores where id = new.store_id;
    new.currency := coalesce(new.currency, 'AED');
  end if;
  return new;
end;
$$;


--
-- Name: find_my_pending_invites(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.find_my_pending_invites() RETURNS TABLE(store_id uuid, store_name text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  uid uuid := auth.uid();
  user_email text;
begin
  if uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  select email into user_email from auth.users where id = uid;
  if user_email is null then
    raise exception 'NO_EMAIL';
  end if;

  -- Always scoped to the CALLER's own verified email (auth.uid() ->
  -- auth.users.email), never a client-supplied value -- so this can only
  -- ever reveal invites belonging to whoever is actually authenticated,
  -- unlike the old public search_companies which exposed every company
  -- name to anyone, authenticated or not.
  return query
    select si.store_id, s.name
    from public.store_invites si
    join public.stores s on s.id = si.store_id
    where lower(si.email) = lower(user_email) and si.status = 'pending';
end;
$$;


--
-- Name: get_branch_count(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_branch_count(p_organization_id uuid) RETURNS integer
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
  select count(*)::int from stores where organization_id = p_organization_id;
$$;


--
-- Name: get_effective_staff_count(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_effective_staff_count(p_store_id uuid) RETURNS integer
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
  select count(*)::int from staff where store_id = p_store_id and user_id is not null;
$$;


--
-- Name: get_invoice_receipt(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_invoice_receipt(p_id uuid) RETURNS TABLE(invoice_number text, invoice_type text, status text, payment_method text, vat_amount numeric, total_amount numeric, created_at timestamp with time zone, store_name text, store_logo_url text, store_address text, store_phone text, store_email text, vat_rate numeric, tax_number text, currency text, secondary_currency text, secondary_currency_rate numeric, customer_name text, customer_phone text, items jsonb)
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
                                                                                 select inv.invoice_number, inv.type, inv.status, inv.payment_method, inv.vat_amount, inv.total_amount, inv.created_at,
                                                                                     s.name, o.logo_url, s.address, s.phone, s.email, s.vat_rate, o.tax_number,
                                                                                         s.currency, s.secondary_currency, s.secondary_currency_rate,
                                                                                             c.name, c.phone,
                                                                                                 coalesce((
                                                                                                       select jsonb_agg(jsonb_build_object(
                                                                                                               'description', ii.description, 'description_en', ii.description_en, 'karat', ii.karat,
                                                                                                                       'weight_grams', ii.weight_grams, 'line_total', ii.line_total, 'quantity', 1) order by ii.id)
                                                                                                                             from invoice_items ii where ii.invoice_id = inv.id
                                                                                                                                 ), '[]'::jsonb)
                                                                                                                                   from invoices inv
                                                                                                                                     join stores s on s.id = inv.store_id
                                                                                                                                       left join organizations o on o.id = s.organization_id
                                                                                                                                         left join customers c on c.id = inv.customer_id
                                                                                                                                           where inv.id = p_id and inv.status != 'cancelled';
                                                                                                                                           $$;


--
-- Name: get_repair_receipt(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_repair_receipt(p_id uuid) RETURNS TABLE(ticket_number text, piece_description text, problem_description text, intake_photo_url text, ready_photo_url text, status text, received_at timestamp with time zone, ready_at timestamp with time zone, store_name text, store_logo_url text, store_address text, store_phone text, received_by_name text, invoice_print_frame text, invoice_print_shape text, estimated_cost numeric, actual_cost numeric, vat_rate numeric, tax_number text)
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
                                                                                                                                                   select rt.ticket_number, rt.piece_description, rt.problem_description, rt.intake_photo_url, rt.ready_photo_url,
                                                                                                                                                       rt.status, rt.received_at, rt.ready_at,
                                                                                                                                                           s.name, o.logo_url, s.address, s.phone, st.full_name, s.invoice_print_frame, s.invoice_print_shape,
                                                                                                                                                               rt.estimated_cost, rt.actual_cost, s.vat_rate, o.tax_number
                                                                                                                                                                 from repair_tickets rt
                                                                                                                                                                   join stores s on s.id = rt.store_id
                                                                                                                                                                     left join organizations o on o.id = s.organization_id
                                                                                                                                                                       left join staff st on st.id = rt.received_by
                                                                                                                                                                         where rt.id = p_id;
                                                                                                                                                                         $$;


--
-- Name: get_subscription_status(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_subscription_status(p_store_id uuid) RETURNS text
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public'
    AS $$
declare
  v_sub subscriptions%rowtype;
begin
  select * into v_sub from subscriptions where store_id = p_store_id limit 1;
  if v_sub.id is null then return 'none'; end if;
  if v_sub.status = 'canceled' then return 'canceled'; end if;
  if v_sub.status = 'trialing' then
    if v_sub.trial_end is not null and now() > v_sub.trial_end then return 'expired'; end if;
    return 'trialing';
  end if;
  if v_sub.current_period_end is not null then
    if now() > v_sub.current_period_end + (v_sub.grace_period_days || ' days')::interval then return 'expired'; end if;
    if now() > v_sub.current_period_end then return 'grace'; end if;
  end if;
  return coalesce(v_sub.status, 'active');
end;
$$;


--
-- Name: gift_out_piece(uuid, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gift_out_piece(target_piece_id uuid, p_recipient text, p_reason text DEFAULT NULL::text, p_notes text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  pc record; actor uuid; gp numeric; w numeric; gold numeric; fab numeric; cat uuid; exp_id uuid; gift_id uuid;
begin
  select * into pc from public.pieces where id = target_piece_id for update;
  if pc is null then raise exception 'القطعة غير موجودة'; end if;
  if not public.has_permission('give_gifts', pc.store_id) then
    raise exception 'ليس لديك صلاحية إخراج قطع كهدايا' using errcode = '42501';
  end if;
  if pc.status not in ('available', 'in_box') then raise exception 'القطعة غير متاحة في المخزن (حالتها: %)', pc.status; end if;
  if coalesce(trim(p_recipient), '') = '' then raise exception 'اكتب اسم الشخص الذي سيستلم الهدية'; end if;

  select id into actor from public.staff where user_id = auth.uid() and store_id = pc.store_id limit 1;
  select price_per_gram into gp from public.gold_prices where store_id = pc.store_id and karat = pc.karat;
  w := coalesce(pc.accounting_weight_grams, pc.weight_grams, 0);
  gold := round(w * coalesce(gp, 0), 2);
  fab := round(w * coalesce(pc.cost_fabrication_per_gram, 0), 2);

  select id into cat from public.expense_categories where store_id = pc.store_id and name = 'هدايا' limit 1;
  if cat is null then
    insert into public.expense_categories (store_id, name) values (pc.store_id, 'هدايا') returning id into cat;
  end if;
  if gold + fab > 0 then
    insert into public.expense_entries (store_id, category_id, amount, description, created_by)
    values (pc.store_id, cat, gold + fab,
            'هدية: ' || coalesce(pc.barcode, '') || ' (' || w || 'غ عيار ' || pc.karat || ') — إلى ' || trim(p_recipient)
              || coalesce(' — ' || nullif(trim(p_reason), ''), ''), actor)
    returning id into exp_id;
  end if;
  insert into public.inventory_gifts (store_id, piece_id, barcode, karat, weight_grams, accounting_weight_grams,
    gold_price_per_gram, gold_cost, fabrication_cost, total_cost, recipient, reason, notes, expense_entry_id, created_by)
  values (pc.store_id, pc.id, pc.barcode, pc.karat, pc.weight_grams, w, gp, gold, fab, gold + fab,
    trim(p_recipient), nullif(trim(p_reason), ''), nullif(trim(p_notes), ''), exp_id, actor)
  returning id into gift_id;
  update public.pieces set status = 'gifted' where id = pc.id;
  insert into public.piece_movements (store_id, piece_id, event_type, note, created_by)
  values (pc.store_id, pc.id, 'gifted', 'إخراج كهدية إلى ' || trim(p_recipient), actor);
  return gift_id;
end;
$$;


--
-- Name: give_scrap_to_trader(uuid, integer, numeric, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.give_scrap_to_trader(p_trader uuid, p_karat integer, p_weight numeric, p_notes text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare t record; me uuid; w numeric := round(coalesce(p_weight, 0), 3); left_w numeric; take numeric;
        cost numeric := 0; lot record; avail numeric; mid uuid;
begin
  select id, gm_acting_store(store_id) as store_id, name into t from traders where id = p_trader;
  if t is null then raise exception 'التاجر غير موجود'; end if;
  if not has_permission('edit_traders', t.store_id) then raise exception 'ليس لديك صلاحية تعديل حسابات التجار' using errcode = '42501'; end if;
  if w <= 0 then raise exception 'أدخل الوزن'; end if;
  select coalesce(sum(weight_grams_remaining), 0) into avail from gold_stock_lots
   where store_id = t.store_id and box_name = 'كسر ' || p_karat and weight_grams_remaining > 0;
  if w > avail + 0.0005 then raise exception 'الوزن أكبر من الموجود في صندوق كسر % (% غ)', p_karat, round(avail, 3); end if;
  select id into me from staff where user_id = auth.uid() and store_id = t.store_id limit 1;

  insert into trader_movements (store_id, trader_id, movement_type, weight_grams, accounting_weight_grams, karat,
      gold_24k_equivalent, fab_fee_amount, source, notes, created_by)
    values (t.store_id, t.id, 'debt_decrease', w, w, p_karat, round(w * p_karat / 24.0, 3), 0, 'scrap_given', '', me)
    returning id into mid;

  left_w := w;
  for lot in select l.id, l.weight_grams_remaining rem,
                    coalesce((select sum(ii.line_total) / nullif(sum(ii.weight_grams), 0) from invoice_items ii join invoices iv on iv.id = ii.invoice_id
                               where ii.gold_stock_lot_id = l.id and iv.type = 'buyRetail'), 0) per_g
               from gold_stock_lots l
              where l.store_id = t.store_id and l.box_name = 'كسر ' || p_karat and l.weight_grams_remaining > 0
              order by l.created_at, l.id for update of l
  loop
    exit when left_w <= 0.0005;
    take := least(lot.rem, left_w);
    update gold_stock_lots set weight_grams_remaining = round(weight_grams_remaining - take, 3) where id = lot.id;
    insert into trader_scrap_draws (store_id, movement_id, lot_id, grams) values (t.store_id, mid, lot.id, round(take, 3));
    cost := cost + take * lot.per_g;
    left_w := left_w - take;
  end loop;
  cost := round(cost, 2);

  update trader_movements set notes = format('إخراج كسر عيار %s بالكلفة: %s غ (كلفته %s)', p_karat, w, cost)
      || coalesce(' — ' || nullif(trim(p_notes), ''), '') where id = mid;
  return jsonb_build_object('id', mid, 'cost', cost);
end $$;


--
-- Name: gm_acting_store(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gm_acting_store(home uuid) RETURNS uuid
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare h uuid;
begin
  begin
      h := nullif(current_setting('request.headers', true)::json ->> 'x-gm-store', '')::uuid;
        exception when others then h := null;
          end;
            if h is not null and h <> home and h in (select org_store_ids(home)) then return h; end if;
              return home;
              end $$;


--
-- Name: gm_allocate_customer_credit(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gm_allocate_customer_credit(sid uuid, cust uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
                                                            declare owed numeric; open_rem numeric; credit numeric; r record; a numeric; me uuid;
                                                            begin
                                                              if cust is null then return; end if;
                                                                select coalesce(sum(case when movement_type = 'debt_increase' then cash_amount else -cash_amount end), 0)
                                                                    into owed from customer_debts where store_id in (select org_store_ids(sid)) and customer_id = cust;
                                                                      select coalesce(sum(total_amount - coalesce(amount_paid, 0)), 0) into open_rem
                                                                          from invoices where store_id in (select org_store_ids(sid)) and customer_id = cust and type = 'sale' and status <> 'cancelled'
                                                                               and total_amount - coalesce(amount_paid, 0) > 0.009;
                                                                                 credit := round(open_rem - owed, 2);
                                                                                   if credit <= 0.009 then return; end if;
                                                                                     select id into me from staff where user_id = auth.uid() and store_id = sid limit 1;
                                                                                       for r in select id, store_id, invoice_number, total_amount - coalesce(amount_paid, 0) rem
                                                                                                    from invoices where store_id in (select org_store_ids(sid)) and customer_id = cust and type = 'sale' and status <> 'cancelled'
                                                                                                                  and total_amount - coalesce(amount_paid, 0) > 0.009
                                                                                                                              order by created_at, invoice_number for update
                                                                                                                                loop
                                                                                                                                    exit when credit <= 0.009;
                                                                                                                                        a := least(credit, r.rem);
                                                                                                                                            insert into customer_debts (store_id, customer_id, invoice_id, movement_type, cash_amount, gold_grams_24k, notes, source, created_by) values
                                                                                                                                                  (r.store_id, cust, r.id, 'debt_decrease', a, 0, 'دفعة مخصّصة للفاتورة ' || r.invoice_number, 'allocation', me),
                                                                                                                                                        (r.store_id, cust, null, 'debt_increase', a, 0, 'تخصيص دفعة للفاتورة ' || r.invoice_number, 'allocation', me);
                                                                                                                                                            update invoices set amount_paid = coalesce(amount_paid, 0) + a,
                                                                                                                                                                                    status = case when total_amount - coalesce(amount_paid, 0) - a <= 0.009 then 'paid' else status end
                                                                                                                                                                                         where id = r.id;
                                                                                                                                                                                             credit := credit - a;
                                                                                                                                                                                               end loop;
                                                                                                                                                                                               end $$;


--
-- Name: gm_can_expense(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gm_can_expense(sid uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select has_permission('manage_daily_cashbox', sid) or has_permission('view_profit_report', sid)
$$;


--
-- Name: gm_cash_log_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gm_cash_log_guard() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
declare
  today date := (now() at time zone 'Asia/Dubai')::date;
  st uuid := coalesce(new.store_id, old.store_id);
  od date; nd date;
begin
  if current_user <> 'authenticated' or auth.uid() is null then return coalesce(new, old); end if;
  if tg_op <> 'INSERT' then
    od := (old.created_at at time zone 'Asia/Dubai')::date;
    if tg_op = 'UPDATE' and (to_jsonb(new) - 'link_group') = (to_jsonb(old) - 'link_group') then return new; end if;
    if od < today and not public.has_permission('edit_past_cash', st) then
      raise exception 'ليس لديك صلاحية تعديل أو حذف حركات الأيام السابقة' using errcode = '42501';
    end if;
    if public.gm_fiscal_closed(st, od) then
      raise exception 'السنة المالية % مقفلة', extract(year from od)::int using errcode = '42501';
    end if;
    if tg_op = 'DELETE' then return old; end if;
    if new.created_at is not distinct from old.created_at then return new; end if;
  end if;
  nd := (new.created_at at time zone 'Asia/Dubai')::date;
  if nd < today and not public.has_permission('backdate_entries', st) then
    raise exception 'ليس لديك صلاحية تسجيل حركة بتاريخ سابق' using errcode = '42501';
  end if;
  if nd > today then raise exception 'لا يمكن تسجيل حركة بتاريخ لاحق' using errcode = '22008'; end if;
  if public.gm_fiscal_closed(st, nd) then
    raise exception 'السنة المالية % مقفلة — لا يمكن التسجيل بتاريخ فيها', extract(year from nd)::int using errcode = '42501';
  end if;
  return new;
end $$;


--
-- Name: gm_daily_label(text, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gm_daily_label(p_op text, p_notes text, p_cm uuid, OUT op text, OUT notes text) RETURNS record
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
-- Daily cash box wording: title = what happened + who ("دفعة من أحمد الخياط"),
-- second line = only what the title doesn't already say (note, amount in another currency, invoice no.).
declare nm text; rest text; inv record;
begin
  op := p_op; notes := p_notes;
  if p_op in ('دفعة من عميل', 'صرف لعميل', 'قبض كاش من تاجر', 'صرف كاش لتاجر') and position(' — ' in coalesce(p_notes, '')) > 0 then
    nm := split_part(p_notes, ' — ', 1);
    rest := substr(p_notes, length(nm) + 4);
    rest := regexp_replace(rest, '^\s*(دفعة من العميل|صرف للعميل|قبض كاش من التاجر|صرف كاش للتاجر)\s*', '');
    op := case p_op when 'دفعة من عميل' then 'دفعة من ' when 'قبض كاش من تاجر' then 'قبض من ' else 'صرف إلى ' end || nm;
    notes := nullif(trim(rest), '');
  elsif p_op in ('فاتورة بيع', 'فاتورة شراء') and p_cm is not null then
    select i.type, coalesce(c.name, t.name, nullif(i.counterparty_name, '')) as who into inv
      from cash_movements m join invoices i on i.id = m.invoice_id
      left join customers c on c.id = i.customer_id left join traders t on t.id = i.trader_id
     where m.id = p_cm;
    if p_op = 'فاتورة بيع' then
      op := 'مبيعات' || coalesce(' لـ ' || inv.who, '');
      notes := regexp_replace(regexp_replace(coalesce(p_notes, ''), '^تحصيل فاتورة بيع ', ''), 'لفاتورة بيع ', '');
    else
      op := 'مشتريات' || coalesce(' من ' || inv.who, '');
      notes := regexp_replace(coalesce(p_notes, ''), '^دفع فاتورة شراء ', '');
    end if;
    notes := nullif(trim(notes), '');
  end if;
end $$;


--
-- Name: gm_deposit_sale_to_daily(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gm_deposit_sale_to_daily(p_invoice uuid, p_customer uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare inv record; a numeric; take numeric; d record; used numeric; g text; me uuid; cur text; row_id uuid; covered numeric := 0;
begin
  select i.id, i.store_id, i.invoice_number, i.type, coalesce(c.name, '') cname into inv
    from invoices i left join customers c on c.id = i.customer_id where i.id = p_invoice;
  if inv.id is null or inv.type <> 'sale' then return; end if;
  select coalesce(sum(cash_amount), 0) into a from customer_debts
   where invoice_id = p_invoice and source = 'allocation' and movement_type = 'debt_decrease' and entered_at = now();
  if a <= 0.009 then return; end if;
  select coalesce(nullif(upper(currency), ''), 'AED') into cur from stores where id = inv.store_id;
  select id into me from staff where user_id = auth.uid() and store_id = inv.store_id limit 1;
  g := 'dep_' || substr(replace(p_invoice::text, '-', ''), 1, 12);
  for d in select id, deposit_number, amount, created_at from customer_deposits
            where customer_id = p_customer and status = 'active' and method = 'cash' and in_cashbox
              and store_id in (select org_store_ids(inv.store_id))
            order by created_at, deposit_number loop
    exit when a <= 0.009;
    select coalesce(sum(amount), 0) into used from daily_cash_log
     where operation_type = 'عربون سابق' and direction = 'out' and store_id in (select org_store_ids(inv.store_id))
       and notes like d.deposit_number || ' بتاريخ ' || to_char(d.created_at at time zone 'Asia/Dubai', 'DD/MM/YYYY') || ' %';
    take := round(least(a, d.amount - used), 2);
    continue when take <= 0.009;
    insert into daily_cash_log (store_id, operation_type, direction, amount, currency, notes, created_by, link_group)
    values (inv.store_id, 'عربون سابق', 'out', take, cur,
            d.deposit_number || ' بتاريخ ' || to_char(d.created_at at time zone 'Asia/Dubai', 'DD/MM/YYYY') || ' — ' || inv.cname || ' · فاتورة ' || inv.invoice_number,
            me, g);
    a := a - take; covered := covered + take;
  end loop;
  if covered <= 0.009 then return; end if;
  select l.id into row_id from daily_cash_log l join cash_movements m on m.id = l.cash_movement_id
   where m.invoice_id = p_invoice and not coalesce(m.edit_delta, false) and l.direction = 'in' and upper(l.currency) = cur
   order by l.created_at limit 1;
  if row_id is not null then
    update daily_cash_log set amount = round(amount + covered, 2), link_group = g,
           notes = nullif(trim(coalesce(notes, '') || ' · منها ' || to_char(covered, 'FM999,999,990.00') || ' من عربون سابق'), '')
     where id = row_id;
  else
    insert into daily_cash_log (store_id, operation_type, direction, amount, currency, notes, created_by, link_group)
    values (inv.store_id, 'مبيعات لـ ' || inv.cname, 'in', round(covered, 2), cur,
            inv.invoice_number || ' — مدفوعة من عربون سابق', me, g);
  end if;
end $$;


--
-- Name: gm_draw_for_piece(uuid, uuid, text, uuid, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gm_draw_for_piece(p_piece uuid, p_store uuid, p_box text, p_lot uuid, p_grams numeric) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare left_g numeric := round(p_grams, 3); r record; a numeric; avail numeric;
begin
  if left_g <= 0 then return; end if;
  select coalesce(sum(weight_grams_remaining), 0) into avail from gold_stock_lots
   where store_id = p_store and weight_grams_remaining > 0
     and (case when p_box is not null then box_name = p_box else id = p_lot end);
  if avail + 0.0005 < left_g then
    raise exception 'الوزن المطلوب (% غ) أكبر من المتوفر في % (% غ)', left_g, coalesce(p_box, 'الدفعة'), round(avail, 2);
  end if;
  for r in select id, weight_grams_remaining from gold_stock_lots
            where store_id = p_store and weight_grams_remaining > 0
              and (case when p_box is not null then box_name = p_box else id = p_lot end)
            order by created_at, id for update
  loop
    exit when left_g <= 0.0005;
    a := least(left_g, r.weight_grams_remaining);
    update gold_stock_lots set weight_grams_remaining = weight_grams_remaining - a where id = r.id;
    insert into piece_lot_draws (store_id, piece_id, lot_id, grams) values (p_store, p_piece, r.id, a);
    left_g := left_g - a;
  end loop;
end $$;


--
-- Name: gm_fiscal_closed(uuid, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gm_fiscal_closed(p_store uuid, p_day date) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (select 1 from fiscal_year_closures
                 where store_id = p_store and fiscal_year = extract(year from p_day)::int);
$$;


--
-- Name: gm_invoice_daily_rewrite(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gm_invoice_daily_rewrite(p_invoice uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
                                                                                                                                                                                                                             declare inv record; keep record; r record; first boolean := true; net numeric; dep numeric; cur text; first_cm uuid;
                                                                                                                                                                                                                             begin
                                                                                                                                                                                                                               select i.id, i.store_id, i.invoice_number, i.type, i.status, i.pay_breakdown, i.pay_currency, i.pay_fx_rate, coalesce(c.name, '') cname
                                                                                                                                                                                                                                   into inv from invoices i left join customers c on c.id = i.customer_id where i.id = p_invoice;
                                                                                                                                                                                                                                     if inv.id is null or inv.type <> 'sale' or inv.status = 'cancelled' then return; end if;
                                                                                                                                                                                                                                       if auth.uid() is not null and not has_permission('edit_invoice', inv.store_id) then
                                                                                                                                                                                                                                           raise exception 'ليس لديك صلاحية تعديل الفواتير' using errcode = '42501';
                                                                                                                                                                                                                                             end if;
                                                                                                                                                                                                                                               select id into first_cm from cash_movements where invoice_id = p_invoice and direction = 'in' order by created_at limit 1;
                                                                                                                                                                                                                                                 -- the invoice's first row (its sale day) stays and is rewritten; its other rows go
                                                                                                                                                                                                                                                   select l.id, l.created_at, l.created_by into keep from daily_cash_log l
                                                                                                                                                                                                                                                      where l.direction = 'in' and (l.cash_movement_id in (select id from cash_movements where invoice_id = p_invoice) or l.bank_invoice_id = p_invoice)
                                                                                                                                                                                                                                                         order by l.created_at, l.id limit 1;
                                                                                                                                                                                                                                                           delete from daily_cash_log l
                                                                                                                                                                                                                                                              where (l.cash_movement_id in (select id from cash_movements where invoice_id = p_invoice) or l.bank_invoice_id = p_invoice)
                                                                                                                                                                                                                                                                   and l.id is distinct from keep.id;
                                                                                                                                                                                                                                                                     if inv.pay_breakdown is not null then
                                                                                                                                                                                                                                                                         -- several currencies: one row per currency, cash parts only
                                                                                                                                                                                                                                                                             for r in select upper(b->>'currency') c, round(sum((b->>'amount')::numeric), 2) a from jsonb_array_elements(inv.pay_breakdown) b
                                                                                                                                                                                                                                                                                           where b->>'method' = 'cash' and (b->>'amount')::numeric > 0 group by 1 order by 1 loop
                                                                                                                                                                                                                                                                                                 if first and keep.id is not null then
                                                                                                                                                                                                                                                                                                         update daily_cash_log set amount = r.a, currency = r.c, cash_movement_id = first_cm, bank_invoice_id = null where id = keep.id;
                                                                                                                                                                                                                                                                                                               else
                                                                                                                                                                                                                                                                                                                       insert into daily_cash_log (store_id, operation_type, direction, amount, currency, notes, created_by, created_at, cash_movement_id, bank_invoice_id)
                                                                                                                                                                                                                                                                                                                               values (inv.store_id, 'مبيعات لـ ' || inv.cname, 'in', r.a, r.c, inv.invoice_number, keep.created_by, coalesce(keep.created_at, now()),
                                                                                                                                                                                                                                                                                                                                               case when first then first_cm end, case when first then null else p_invoice end);
                                                                                                                                                                                                                                                                                                                                                     end if;
                                                                                                                                                                                                                                                                                                                                                           first := false;
                                                                                                                                                                                                                                                                                                                                                               end loop;
                                                                                                                                                                                                                                                                                                                                                                   if first and keep.id is not null then delete from daily_cash_log where id = keep.id; end if;
                                                                                                                                                                                                                                                                                                                                                                       return;
                                                                                                                                                                                                                                                                                                                                                                         end if;
                                                                                                                                                                                                                                                                                                                                                                           -- one currency: what the invoice brought into the main box (+ an earlier deposit used on it);
                                                                                                                                                                                                                                                                                                                                                                             -- the card/transfer part is then taken out by sync_invoice_bank_part as on a new sale
                                                                                                                                                                                                                                                                                                                                                                               select coalesce(sum(case when direction = 'in' then amount else -amount end), 0) into net from cash_movements where invoice_id = p_invoice;
                                                                                                                                                                                                                                                                                                                                                                                 select coalesce(sum(amount), 0) into dep from daily_cash_log
                                                                                                                                                                                                                                                                                                                                                                                    where operation_type = 'عربون سابق' and link_group = 'dep_' || substr(replace(p_invoice::text, '-', ''), 1, 12);
                                                                                                                                                                                                                                                                                                                                                                                      net := round(net + dep, 2);
                                                                                                                                                                                                                                                                                                                                                                                        if inv.pay_currency is not null and inv.pay_fx_rate > 0 then net := round(net * inv.pay_fx_rate, 2); cur := upper(inv.pay_currency);
                                                                                                                                                                                                                                                                                                                                                                                          else select coalesce(nullif(upper(currency), ''), 'AED') into cur from stores where id = inv.store_id; end if;
                                                                                                                                                                                                                                                                                                                                                                                            if net <= 0.009 then
                                                                                                                                                                                                                                                                                                                                                                                                if keep.id is not null then delete from daily_cash_log where id = keep.id; end if;
                                                                                                                                                                                                                                                                                                                                                                                                    return;
                                                                                                                                                                                                                                                                                                                                                                                                      end if;
                                                                                                                                                                                                                                                                                                                                                                                                        if keep.id is not null then
                                                                                                                                                                                                                                                                                                                                                                                                            update daily_cash_log set amount = net, currency = cur, cash_movement_id = first_cm, bank_invoice_id = null where id = keep.id;
                                                                                                                                                                                                                                                                                                                                                                                                              else
                                                                                                                                                                                                                                                                                                                                                                                                                  insert into daily_cash_log (store_id, operation_type, direction, amount, currency, notes, created_by, cash_movement_id)
                                                                                                                                                                                                                                                                                                                                                                                                                      values (inv.store_id, 'مبيعات لـ ' || inv.cname, 'in', net, cur, inv.invoice_number, null, first_cm);
                                                                                                                                                                                                                                                                                                                                                                                                                        end if;
                                                                                                                                                                                                                                                                                                                                                                                                                          perform sync_invoice_bank_part(p_invoice);
                                                                                                                                                                                                                                                                                                                                                                                                                          end $$;


--
-- Name: gm_op_date(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gm_op_date() RETURNS date
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public'
    AS $_$
declare h text; d date; today date := (now() at time zone 'Asia/Dubai')::date;
begin
  h := nullif(current_setting('request.headers', true), '')::json->>'x-gm-op-date';
  if h is null or h !~ '^\d{4}-\d{2}-\d{2}$' then return null; end if;
  begin d := h::date; exception when others then return null; end;
  if d >= today or d < today - 3650 then return null; end if;
  return d;
end $_$;


--
-- Name: gm_op_date_stamp(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gm_op_date_stamp() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
declare d date := public.gm_op_date();
begin
  new.entered_at := now();
  if d is not null then
    if auth.uid() is not null and not public.has_permission('backdate_entries', new.store_id) then
      raise exception 'ليس لديك صلاحية تسجيل عملية بتاريخ سابق' using errcode = '42501';
    end if;
    if public.gm_fiscal_closed(new.store_id, d) then
      raise exception 'السنة المالية % مقفلة — لا يمكن التسجيل بتاريخ فيها', extract(year from d)::int using errcode = '42501';
    end if;
    new.created_at := (d + (now() at time zone 'Asia/Dubai')::time) at time zone 'Asia/Dubai';
  end if;
  return new;
end $$;


--
-- Name: gm_pre_request(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gm_pre_request() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if coalesce(auth.role(), '') <> 'authenticated' then return; end if;
  if coalesce(current_setting('request.path', true), '') = '/rpc/gm_session_ok' then return; end if;
  if not public.gm_session_ok() then
    raise sqlstate 'PT403' using message = '2FA_REQUIRED', hint = 'أدخل رمز التحقق المرسل إلى بريدك الإلكتروني';
  end if;
end $$;


--
-- Name: gm_return_draws(uuid, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gm_return_draws(p_piece uuid, p_grams numeric) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare left_g numeric := round(p_grams, 3); r record; a numeric;
begin
  for r in select id, lot_id, grams from piece_lot_draws where piece_id = p_piece order by created_at desc, id desc loop
    exit when left_g <= 0.0005;
    a := least(left_g, r.grams);
    update gold_stock_lots set weight_grams_remaining = weight_grams_remaining + a where id = r.lot_id;
    if r.grams - a <= 0.0005 then delete from piece_lot_draws where id = r.id;
    else update piece_lot_draws set grams = grams - a where id = r.id; end if;
    left_g := left_g - a;
  end loop;
end $$;


--
-- Name: gm_sale_debt_to_daily(uuid, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gm_sale_debt_to_daily(p_invoice uuid, p_amount numeric) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare inv record; used numeric; debt numeric; cur text; amt numeric; me uuid; g text;
begin
  select i.id, i.store_id, i.invoice_number, i.type, i.pay_currency, i.pay_fx_rate, coalesce(c.name, '') cname into inv
    from invoices i left join customers c on c.id = i.customer_id where i.id = p_invoice;
  if inv.id is null or inv.type <> 'sale' then return; end if;
  select coalesce(sum(cash_amount), 0) into used from customer_debts
   where invoice_id = p_invoice and source = 'allocation' and movement_type = 'debt_decrease' and entered_at = now();
  debt := round(p_amount - used, 2);
  if debt <= 0.009 then return; end if;
  if inv.pay_currency is not null and inv.pay_fx_rate > 0 then
    amt := round(debt * inv.pay_fx_rate, 2); cur := upper(inv.pay_currency);
  else
    amt := debt; select coalesce(nullif(upper(currency), ''), 'AED') into cur from stores where id = inv.store_id;
  end if;
  select id into me from staff where user_id = auth.uid() and store_id = inv.store_id limit 1;
  g := 'debt_' || substr(replace(p_invoice::text, '-', ''), 1, 12);
  insert into daily_cash_log (store_id, operation_type, direction, amount, currency, notes, created_by, link_group)
  values (inv.store_id, 'مبيعات لـ ' || inv.cname, 'in', amt, cur, inv.invoice_number || ' — بالدين', me, g),
         (inv.store_id, 'دين على ' || inv.cname, 'out', amt, cur, inv.invoice_number, me, g);
end $$;


--
-- Name: gm_scrap_price_at_purchase(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gm_scrap_price_at_purchase() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare st uuid; typ text; pr numeric;
begin
  if new.gold_stock_lot_id is null or new.gold_price_per_gram is not null or new.karat is null then return new; end if;
  select store_id, type into st, typ from invoices where id = new.invoice_id;
  if typ is distinct from 'buyRetail' then return new; end if;
  select price_per_gram into pr from gold_prices where store_id = st and karat = new.karat;
  if pr is null then
    select price_per_gram * new.karat / 24.0 into pr from gold_prices where store_id = st and karat = 24;
  end if;
  new.gold_price_per_gram := round(pr, 2);
  return new;
end $$;


--
-- Name: gm_scrap_return_unrecorded(uuid, integer, numeric, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gm_scrap_return_unrecorded(p_store uuid, p_karat integer, p_grams numeric, p_note text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare left_g numeric := round(p_grams, 3); r record; a numeric;
begin
  for r in select id, weight_grams_total - weight_grams_remaining room from gold_stock_lots
            where store_id = p_store and box_name = 'كسر ' || p_karat and weight_grams_remaining < weight_grams_total
            order by created_at desc, id desc for update loop
    exit when left_g <= 0.0005;
    a := least(left_g, r.room);
    update gold_stock_lots set weight_grams_remaining = round(weight_grams_remaining + a, 3) where id = r.id;
    left_g := left_g - a;
  end loop;
  if left_g > 0.0005 then
    insert into gold_stock_lots (store_id, karat, box_name, weight_grams_total, weight_grams_remaining, notes)
      values (p_store, p_karat, 'كسر ' || p_karat, round(left_g, 3), round(left_g, 3), p_note);
  end if;
end $$;


--
-- Name: gm_seller_stamp(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gm_seller_stamp() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
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
end $_$;


--
-- Name: gm_session_ok(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gm_session_ok() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select auth.uid() is null
    or coalesce((select bool_or(a->>'method' <> 'password') from jsonb_array_elements(coalesce(auth.jwt()->'amr', '[]'::jsonb)) a), true)
    or exists (select 1 from auth.users u where u.id = auth.uid() and u.email like '%@staff.goldmind.app')
    or exists (select 1 from public.login_2fa l where l.session_id = nullif(auth.jwt()->>'session_id', '')::uuid
                 and l.user_id = auth.uid() and l.verified_at is not null);
$$;


--
-- Name: gm_staff_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gm_staff_guard() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
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
  if tg_op = 'UPDATE' and old.role = 'owner' then raise exception 'لا يمكن تعديل حساب المالك' using errcode = '42501'; end if;
  for k in select key from jsonb_each_text(coalesce(new.permissions, '{}'::jsonb)) where value = 'true' loop
    if coalesce(me.permissions ->> k, '') <> 'true'
       and (tg_op = 'INSERT' or coalesce(old.permissions ->> k, '') <> 'true') then
      raise exception 'لا يمكنك منح صلاحية لا تملكها (%)', k using errcode = '42501';
    end if;
  end loop;
  return new;
end $$;


--
-- Name: gm_stock_in_rescrap(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gm_stock_in_rescrap(p_voucher uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare v record; fab_bal numeric; aw_bal numeric; avg_fab numeric; loss numeric := 0; sfab numeric; l record;
        txt text[] := '{}'; cat_id uuid; eid uuid; dsc text;
begin
  select sv.*, pt.name party_name into v from stock_vouchers sv join stock_parties pt on pt.id = sv.party_id where sv.id = p_voucher;
  if v is null or not exists (select 1 from stock_voucher_lines where voucher_id = p_voucher and piece_id is null and barcode like 'كسر %') then return; end if;
  select coalesce(sum(case l2.direction when 'out' then 1 else -1 end * l2.fab_per_gram * l2.accounting_weight_grams), 0),
         coalesce(sum(case l2.direction when 'out' then 1 else -1 end * l2.accounting_weight_grams), 0)
    into fab_bal, aw_bal
    from stock_voucher_lines l2 join stock_vouchers v2 on v2.id = l2.voucher_id
   where l2.party_id = v.party_id and v2.created_at <= v.created_at
     and not (l2.voucher_id = p_voucher and l2.piece_id is null and l2.barcode like 'كسر %');
  avg_fab := case when aw_bal > 0.0005 and fab_bal > 0 then fab_bal / aw_bal else 0 end;
  for l in select * from stock_voucher_lines where voucher_id = p_voucher and piece_id is null and barcode like 'كسر %' order by id loop
    sfab := round(least(avg_fab, greatest(fab_bal - loss, 0) / l.weight_grams), 4);
    update stock_voucher_lines set fab_per_gram = sfab,
           cost_value = round(l.weight_grams * (coalesce(l.gold_price_per_gram, 0) + sfab), 2) where id = l.id;
    loss := loss + l.weight_grams * sfab;
    txt := txt || (trim(to_char(l.weight_grams, 'FM999990.000')) || ' غ لصندوق كسر ' || l.karat);
  end loop;
  loss := round(loss, 2);
  dsc := 'خسارة مصنعية — ' || array_to_string(txt, '، ') || ' من ' || v.party_name
         || ' (متوسط المصنعية ' || trim(to_char(round(avg_fab, 2), 'FM999,999,990.00')) || ' للغرام) — السند ' || v.voucher_number;
  select id into cat_id from expense_categories where store_id = v.store_id and name = 'خسارة مصنعية' limit 1;
  if cat_id is not null then
    select id into eid from expense_entries where store_id = v.store_id and category_id = cat_id
       and (description like '%— السند ' || v.voucher_number or description like '%— السند ' || v.voucher_number || ' (%')
     order by created_at limit 1;
  end if;
  if eid is not null then
    update expense_entries set amount = loss, description = dsc || case when loss = 0 then ' (لا خسارة بعد التعديل)' else '' end where id = eid;
  elsif loss > 0 then
    if cat_id is null then insert into expense_categories (store_id, name) values (v.store_id, 'خسارة مصنعية') returning id into cat_id; end if;
    insert into expense_entries (store_id, category_id, amount, description, created_by)
    values (v.store_id, cat_id, loss, dsc, (select id from staff where user_id = auth.uid() and store_id = v.store_id limit 1));
  end if;
end $$;


--
-- Name: gm_tm_snapshot(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gm_tm_snapshot() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if new.source = 'stock_given' then
    if new.piece_acc_weight is null and new.piece_id is not null then
      select coalesce(accounting_weight_grams, weight_grams) into new.piece_acc_weight from pieces where id = new.piece_id;
    end if;
    if new.gold_price_24k is null then
      select price_per_gram into new.gold_price_24k from gold_prices where store_id = new.store_id and karat = 24 limit 1;
    end if;
  end if;
  return new;
end $$;


--
-- Name: gm_unallocate_customer_credit(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gm_unallocate_customer_credit(sid uuid, cust uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
                                                                                                                                                                                               declare owed numeric; open_rem numeric; deficit numeric; r record; a numeric; me uuid;
                                                                                                                                                                                               begin
                                                                                                                                                                                                 select coalesce(sum(case when movement_type = 'debt_increase' then cash_amount else -cash_amount end), 0)
                                                                                                                                                                                                     into owed from customer_debts where store_id in (select org_store_ids(sid)) and customer_id = cust;
                                                                                                                                                                                                       select coalesce(sum(total_amount - coalesce(amount_paid, 0)), 0) into open_rem
                                                                                                                                                                                                           from invoices where store_id in (select org_store_ids(sid)) and customer_id = cust and type = 'sale' and status <> 'cancelled'
                                                                                                                                                                                                                and total_amount - coalesce(amount_paid, 0) > 0.009;
                                                                                                                                                                                                                  deficit := round(owed - open_rem, 2);
                                                                                                                                                                                                                    if deficit <= 0.009 then return; end if;
                                                                                                                                                                                                                      select id into me from staff where user_id = auth.uid() and store_id = sid limit 1;
                                                                                                                                                                                                                        for r in select d.invoice_id, i.store_id, i.invoice_number, sum(case when d.movement_type = 'debt_decrease' then d.cash_amount else -d.cash_amount end) alloc, max(d.created_at) last_at
                                                                                                                                                                                                                                     from customer_debts d join invoices i on i.id = d.invoice_id
                                                                                                                                                                                                                                                 where d.store_id in (select org_store_ids(sid)) and d.customer_id = cust and d.source = 'allocation' and i.status <> 'cancelled'
                                                                                                                                                                                                                                                             group by d.invoice_id, i.store_id, i.invoice_number
                                                                                                                                                                                                                                                                        having sum(case when d.movement_type = 'debt_decrease' then d.cash_amount else -d.cash_amount end) > 0.009
                                                                                                                                                                                                                                                                                    order by max(d.created_at) desc
                                                                                                                                                                                                                                                                                      loop
                                                                                                                                                                                                                                                                                          exit when deficit <= 0.009;
                                                                                                                                                                                                                                                                                              a := least(deficit, r.alloc);
                                                                                                                                                                                                                                                                                                  insert into customer_debts (store_id, customer_id, invoice_id, movement_type, cash_amount, gold_grams_24k, notes, source, created_by) values
                                                                                                                                                                                                                                                                                                        (r.store_id, cust, r.invoice_id, 'debt_increase', a, 0, 'إلغاء تخصيص للفاتورة ' || r.invoice_number, 'allocation', me),
                                                                                                                                                                                                                                                                                                              (r.store_id, cust, null, 'debt_decrease', a, 0, 'إلغاء تخصيص للفاتورة ' || r.invoice_number, 'allocation', me);
                                                                                                                                                                                                                                                                                                                  update invoices set amount_paid = greatest(coalesce(amount_paid, 0) - a, 0),
                                                                                                                                                                                                                                                                                                                                          status = case when status = 'paid' then 'unpaid' else status end
                                                                                                                                                                                                                                                                                                                                               where id = r.invoice_id;
                                                                                                                                                                                                                                                                                                                                                   deficit := deficit - a;
                                                                                                                                                                                                                                                                                                                                                     end loop;
                                                                                                                                                                                                                                                                                                                                                     end $$;


--
-- Name: gold_implied_usd_ounce(numeric, integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gold_implied_usd_ounce(price_per_gram numeric, karat integer, cur text) RETURNS numeric
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public'
    AS $$
  select case when currency_usd_peg(cur) is null or karat is null or karat <= 0 or price_per_gram is null then null
    else price_per_gram * 24.0 / karat * 31.1034768 / currency_usd_peg(cur) end
$$;


--
-- Name: gold_price_problem(uuid, integer, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gold_price_problem(sid uuid, karat integer, price numeric) RETURNS text
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare cur text; implied numeric; ref numeric; lo numeric; hi numeric;
begin
  select upper(currency) into cur from stores where id = sid;
  implied := gold_implied_usd_ounce(price, karat, cur);
  if implied is null then return null; end if;
  ref := gold_reference_usd_ounce(sid);
  if ref is not null then lo := ref * 0.6; hi := ref * 1.6; else lo := 1500; hi := 12000; end if;
  if implied < lo or implied > hi then
    return format('سعر غرام عيار %s (%s %s) لا يتناسب مع عملة المحل %s، إذ يصبح سعر الأونصة %s دولاراً. غالباً حُسب السعر بعملة أخرى.',
      karat, round(price, 2), cur, cur, round(implied));
  end if;
  return null;
end $$;


--
-- Name: gold_prices_currency_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gold_prices_currency_guard() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare msg text;
begin
  msg := gold_price_problem(new.store_id, new.karat, new.price_per_gram);
  if msg is not null then raise exception '%', msg using errcode = 'P0001'; end if;
  return new;
end $$;


--
-- Name: gold_reference_usd_ounce(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gold_reference_usd_ounce(exclude_store uuid) RETURNS numeric
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select percentile_cont(0.5) within group (order by gold_implied_usd_ounce(g.price_per_gram, g.karat, s.currency))
  from gold_prices g join stores s on s.id = g.store_id
  where g.store_id <> exclude_store and g.updated_at > now() - interval '45 days'
    and gold_implied_usd_ounce(g.price_per_gram, g.karat, s.currency) is not null
$$;


--
-- Name: has_permission(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.has_permission(perm text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select coalesce(
    (select role = 'owner' or (permissions ->> perm) = 'true'
     from public.staff where id = auth.uid()),
    false
  );
$$;


--
-- Name: has_permission(text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.has_permission(perm text, target_store_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select coalesce(
    (select role = 'owner' or (permissions ->> perm) = 'true'
     from public.staff where user_id = auth.uid() and store_id = target_store_id),
    false
  );
$$;


--
-- Name: invoices_currency_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.invoices_currency_guard() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare scur text;
begin
  select upper(coalesce(nullif(currency,''),'AED')) into scur from stores where id = new.store_id;
  if new.currency is null or new.currency = '' then new.currency := scur; end if;
  if upper(new.currency) <> scur then
    raise exception 'عملة الفاتورة (%) غير عملة المحل (%)', new.currency, scur using errcode = 'P0001';
  end if;
  return new;
end $$;


--
-- Name: is_org_owner(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_org_owner(p_org uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
                                     select exists (
                                         select 1 from staff st join organizations o on o.primary_store_id = st.store_id
                                             where o.id = p_org and st.user_id = auth.uid() and st.role = 'owner');
                                             $$;


--
-- Name: is_platform_admin(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_platform_admin() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (select 1 from public.platform_admins where id = auth.uid());
$$;


--
-- Name: is_store_member(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_store_member(target_store_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (
    select 1 from public.staff
    where user_id = auth.uid() and store_id = target_store_id
  );
$$;


--
-- Name: join_company_by_invite(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.join_company_by_invite(target_store_id uuid) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  uid uuid := auth.uid();
  user_email text;
  inv record;
begin
  if uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if exists (select 1 from public.staff where user_id = uid and store_id = target_store_id) then
    raise exception 'ALREADY_MEMBER';
  end if;

  select email into user_email from auth.users where id = uid;
  if user_email is null then
    raise exception 'NO_EMAIL';
  end if;

  select * into inv from public.store_invites
  where store_id = target_store_id
    and lower(email) = lower(user_email)
    and status = 'pending'
  limit 1;

  if inv.id is null then
    raise exception 'NOT_INVITED';
  end if;

  insert into public.staff (id, user_id, store_id, full_name, role, permissions, whatsapp_phone)
  values (gen_random_uuid(), uid, target_store_id, split_part(user_email, '@', 1), inv.role, inv.permissions, inv.whatsapp_phone);

  update public.store_invites set status = 'accepted', accepted_at = now() where id = inv.id;

  return true;
end;
$$;


--
-- Name: log_audit_event(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.log_audit_event() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  store_id_val uuid;
  actor_staff_id uuid;
  action_label text;
  description_val text;
  inv_type_label text;
begin
  if tg_op = 'DELETE' then
    store_id_val := old.store_id;
  else
    store_id_val := new.store_id;
  end if;

  select id into actor_staff_id
  from public.staff
  where user_id = auth.uid() and store_id = store_id_val
  limit 1;

  action_label := tg_table_name || '_' || lower(tg_op);

  if tg_table_name = 'invoices' then
    inv_type_label := case coalesce(new.type, old.type)
      when 'sale' then 'فاتورة بيع'
      when 'sell' then 'فاتورة بيع'
      when 'buyRetail' then 'فاتورة شراء من عميل'
      when 'buyTrader' then 'فاتورة شراء من تاجر'
      when 'traderPay' then 'سند دفع لتاجر'
      else 'فاتورة'
    end;
    description_val := case tg_op
      when 'INSERT' then inv_type_label || ' رقم ' || coalesce(new.invoice_number, '') || ' بقيمة ' || coalesce(new.total_amount::text, '0')
      when 'DELETE' then 'حذف ' || inv_type_label || ' رقم ' || coalesce(old.invoice_number, '')
      else 'تعديل ' || inv_type_label || ' رقم ' || coalesce(new.invoice_number, '') || ' بقيمة ' || coalesce(new.total_amount::text, '0')
    end;
  elsif tg_table_name = 'pieces' then
    description_val := case tg_op
      when 'INSERT' then 'إضافة قطعة بباركود ' || coalesce(new.barcode, 'بدون باركود')
      when 'DELETE' then 'حذف قطعة بباركود ' || coalesce(old.barcode, 'بدون باركود')
      else 'تعديل قطعة بباركود ' || coalesce(new.barcode, 'بدون باركود')
    end;
  elsif tg_table_name = 'customers' then
    description_val := case tg_op
      when 'INSERT' then 'إضافة عميل: ' || coalesce(new.name, '')
      when 'DELETE' then 'حذف عميل: ' || coalesce(old.name, '')
      else 'تعديل عميل: ' || coalesce(new.name, '')
    end;
  elsif tg_table_name = 'cash_movements' then
    description_val := case tg_op
      when 'INSERT' then 'حركة صندوق: ' || coalesce(new.direction, '') || ' ' || coalesce(new.amount::text, '')
      else 'تعديل حركة صندوق'
    end;
  else
    description_val := action_label;
  end if;

  begin
    insert into public.audit_log (store_id, staff_id, action_type, description)
    values (store_id_val, actor_staff_id, action_label, description_val);
  exception when foreign_key_violation then
    -- The parent store is being deleted in this same transaction (e.g. a
    -- full company deletion) — nothing to log against anymore, skip.
    null;
  end;

  return coalesce(new, old);
end;
$$;


--
-- Name: login_email_for(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.login_email_for(p_username text, p_password text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $_$
declare v_ip text; v_user text := 'u:' || lower(trim(coalesce(p_username, ''))); v_email text; v_hash text;
begin
  if length(coalesce(p_password, '')) = 0 or length(v_user) < 5 then return null; end if;
    v_ip := split_part(coalesce((current_setting('request.headers', true)::json ->> 'x-forwarded-for'), 'unknown'), ',', 1);
      if (select count(*) from lookup_username_attempts where caller_ip = v_ip and attempted_at > now() - interval '60 seconds') >= 5
           or (select count(*) from lookup_username_attempts where caller_ip = v_user and attempted_at > now() - interval '5 minutes') >= 10
                or (select count(*) from lookup_username_attempts where attempted_at > now() - interval '60 seconds') >= 120 then
                    raise exception 'RATE_LIMITED' using errcode = '42901';
                      end if;
                        insert into lookup_username_attempts (caller_ip) values (v_ip), (v_user);
                          delete from lookup_username_attempts where attempted_at < now() - interval '10 minutes';
                            select u.email::text, u.encrypted_password into v_email, v_hash
                                from user_profiles up join auth.users u on u.id = up.id
                                   where lower(up.username) = lower(trim(p_username)) limit 1;
                                     if v_hash is null or v_hash = '' then
                                         perform crypt(p_password, '$2a$10$abcdefghijklmnopqrstuuJ7xJ0hX5d2h5e4lV0YbQyH3n7m1QW2e');
                                             return null;
                                               end if;
                                                 if crypt(p_password, v_hash) = v_hash then return v_email; end if;
                                                   return null;
                                                   end $_$;


--
-- Name: lookup_email_by_username(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.lookup_email_by_username(p_username text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
-- Kept only for older app builds. Returns just the internal staff login address
-- (…@staff.goldmind.app), never a real email; new pages use login_email_for().
declare v_ip text; v_email text;
begin
  v_ip := split_part(coalesce((current_setting('request.headers', true)::json ->> 'x-forwarded-for'), 'unknown'), ',', 1);
  if (select count(*) from public.lookup_username_attempts where caller_ip = v_ip and attempted_at > now() - interval '60 seconds') >= 5
     or (select count(*) from public.lookup_username_attempts where attempted_at > now() - interval '60 seconds') >= 60 then
    raise exception 'RATE_LIMITED' using errcode = '42901';
  end if;
  insert into public.lookup_username_attempts (caller_ip) values (v_ip);
  select u.email::text into v_email from public.user_profiles up join auth.users u on u.id = up.id
   where lower(up.username) = lower(trim(p_username)) limit 1;
  if v_email like '%@staff.goldmind.app' then return v_email; end if;
  return null;
end $$;


--
-- Name: mirror_invoice_cash_to_daily(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mirror_invoice_cash_to_daily() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
 declare inv record; r record; first boolean := true; full_base numeric; amt numeric; cur text; note text; op text;
 begin
   if new.invoice_id is null then return new; end if;
     -- a change of payment currencies: gm_invoice_daily_rewrite() sets the invoice's rows
       if coalesce(new.description, '') like 'تعديل عملات الدفع%' then return new; end if;
         select id, type, payment_method, pay_breakdown, pay_currency, pay_fx_rate into inv from public.invoices where id = new.invoice_id;
           if inv is null then return new; end if;
             if inv.payment_method not in ('cash', 'bank', 'mixed') or new.amount <= 0 then return new; end if;
               op := case inv.type when 'sale' then 'فاتورة بيع' when 'return' then 'مرتجع مبيعات' else 'فاتورة شراء' end;
                 if new.edit_delta then
                     amt := case when new.fx_currency is not null and new.fx_amount > 0 then new.fx_amount
                                     when inv.pay_currency is not null and inv.pay_fx_rate > 0 then new.amount * inv.pay_fx_rate else new.amount end;
                                         cur := coalesce(upper(new.fx_currency), case when inv.pay_currency is not null and inv.pay_fx_rate > 0 then inv.pay_currency end, new.currency);
                                             select l.id, l.direction, l.amount into r from daily_cash_log l join cash_movements m on m.id = l.cash_movement_id
                                                  where m.invoice_id = inv.id and not m.edit_delta and upper(l.currency) = upper(cur)
                                                       order by l.created_at limit 1;
                                                           if r.id is not null then
                                                                 full_base := round(r.amount + case when new.direction = r.direction then amt else -amt end, 2);
                                                                       if full_base > 0 then
                                                                               update daily_cash_log set amount = full_base where id = r.id;
                                                                                       perform public.sync_invoice_bank_part(new.invoice_id);
                                                                                               return new;
                                                                                                     end if;
                                                                                                         end if;
                                                                                                           end if;
                                                                                                             if new.fx_currency is null and inv.pay_breakdown is not null then
                                                                                                                 select sum((b->>'amount')::numeric / (b->>'rate')::numeric) into full_base from jsonb_array_elements(inv.pay_breakdown) b;
                                                                                                                     if abs(new.amount - full_base) < 0.05 then
                                                                                                                           for r in select upper(b->>'currency') c, sum((b->>'amount')::numeric) a from jsonb_array_elements(inv.pay_breakdown) b
                                                                                                                                           where b->>'method' = 'cash' and (b->>'amount')::numeric > 0 group by 1 order by 1 loop
                                                                                                                                                   insert into public.daily_cash_log (store_id, operation_type, direction, amount, currency, notes, created_by, cash_movement_id, bank_invoice_id)
                                                                                                                                                           values (new.store_id, op, new.direction, round(r.a, 2), r.c, new.description, new.created_by,
                                                                                                                                                                           case when first then new.id end, case when first then null else inv.id end);
                                                                                                                                                                                   first := false;
                                                                                                                                                                                         end loop;
                                                                                                                                                                                               return new;
                                                                                                                                                                                                   end if;
                                                                                                                                                                                                     end if;
                                                                                                                                                                                                       amt := round(new.amount, 2); cur := new.currency; note := new.description;
                                                                                                                                                                                                         if new.fx_currency is not null and new.fx_amount > 0 then
                                                                                                                                                                                                             amt := round(new.fx_amount, 2); cur := upper(new.fx_currency);
                                                                                                                                                                                                               elsif inv.pay_currency is not null and inv.pay_fx_rate > 0 and upper(inv.pay_currency) <> upper(coalesce(new.currency, '')) then
                                                                                                                                                                                                                   amt := round(new.amount * inv.pay_fx_rate, 2); cur := inv.pay_currency;
                                                                                                                                                                                                                     end if;
                                                                                                                                                                                                                       insert into public.daily_cash_log (store_id, operation_type, direction, amount, currency, notes, created_by, cash_movement_id)
                                                                                                                                                                                                                         values (new.store_id, op, new.direction, amt, cur, note, new.created_by, new.id);
                                                                                                                                                                                                                           perform public.sync_invoice_bank_part(new.invoice_id);
                                                                                                                                                                                                                             return new;
                                                                                                                                                                                                                             end $$;


--
-- Name: my_stores(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.my_stores() RETURNS TABLE(store_id uuid, store_name text, role text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select s.store_id, coalesce(nullif(btrim(st.display_name), ''), st.name), s.role
    from public.staff s
      join public.stores st on st.id = s.store_id
        where s.user_id = auth.uid()
          order by 2;
          $$;


--
-- Name: next_invoice_number(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.next_invoice_number(target_store_id uuid, prefix text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
declare
  pfx text := $2;  -- the parameter name clashes with invoice_number_counters.prefix
    seq integer;
      yr integer := extract(year from now())::integer;
        stored_year integer;
          code text;
          begin
            if not public.is_store_member(target_store_id) then
                raise exception 'NOT_AUTHORIZED';
                  end if;
                    if pfx is null or pfx !~ '^[A-Z]{2,6}$' then
                        raise exception 'INVALID_PREFIX';
                          end if;

                            if pfx = 'INV' then
                                select next_invoice_seq_year, branch_code into stored_year, code from public.stores where id = target_store_id for update;
                                    if stored_year is null or stored_year <> yr then
                                          update public.stores set next_invoice_seq = 2, next_invoice_seq_year = yr where id = target_store_id;
                                                seq := 1;
                                                    else
                                                          update public.stores set next_invoice_seq = next_invoice_seq + 1
                                                                 where id = target_store_id returning next_invoice_seq - 1 into seq;
                                                                     end if;
                                                                       else
                                                                           select branch_code into code from public.stores where id = target_store_id;
                                                                               insert into public.invoice_number_counters as c (store_id, prefix, year, next_seq)
                                                                                   values (target_store_id, pfx, yr,
                                                                                               coalesce((select max((regexp_match(i.invoice_number, '-([0-9]+)$'))[1]::integer)
                                                                                                                       from public.invoices i
                                                                                                                                              where i.store_id = target_store_id
                                                                                                                                                                       and i.invoice_number ~ ('^([A-Z]{2,5}-)?' || pfx || '-' || yr || '-[0-9]+$')), 0) + 2)
                                                                                                                                                                           on conflict on constraint invoice_number_counters_pkey do update set next_seq = c.next_seq + 1
                                                                                                                                                                               returning c.next_seq - 1 into seq;
                                                                                                                                                                                 end if;

                                                                                                                                                                                   return coalesce(code || '-', '') || pfx || '-' || yr::text || '-' || lpad(seq::text, 6, '0');
                                                                                                                                                                                   end;
                                                                                                                                                                                   $_$;


--
-- Name: next_piece_barcode(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.next_piece_barcode(target_store_id uuid, category text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
                                                                                                                                                                      $$;


--
-- Name: next_repair_number(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.next_repair_number(p_store_id uuid) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  seq integer;
  yr text := to_char(now(), 'YYYY');
BEGIN
  IF NOT public.is_store_member(p_store_id) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  UPDATE stores SET next_repair_seq = COALESCE(next_repair_seq,1) + 1
    WHERE id = p_store_id
    RETURNING next_repair_seq - 1 INTO seq;

  RETURN 'REP-' || yr || '-' || lpad(seq::text, 6, '0');
END;
$$;


--
-- Name: org_branches(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.org_branches(sid uuid) RETURNS TABLE(id uuid, name text, can_open_invoices boolean)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
      select b.id, coalesce(nullif(btrim(b.display_name), ''), b.name),
               b.id = sid or has_permission('view_branch_invoices', b.id) or org_can(b.id, 'view_branch_invoices')
                 from stores b where b.id in (select org_store_ids(sid)) and is_store_member(sid)
                   order by b.created_at;
                   $$;


--
-- Name: org_can(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.org_can(p_store uuid, perm text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (
      select 1 from stores a join stores b on b.organization_id = a.organization_id
          where a.id = p_store and has_permission(perm, b.id));
          $$;


--
-- Name: org_store_ids(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.org_store_ids(sid uuid) RETURNS SETOF uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select b.id from stores a join stores b on b.organization_id = a.organization_id where a.id = sid
    union select sid;
    $$;


--
-- Name: post_purchase_invoice(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.post_purchase_invoice(p jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  sid uuid := nullif(p->>'store_id','')::uuid;
  ref uuid := nullif(p->>'client_ref','')::uuid;
  typ text := p->>'type';
  pm text := p->>'payment_method';
  tid uuid := nullif(p->>'trader_id','')::uuid;
  sid_type text := nullif(p->>'seller_id_type','');
  photos jsonb := case when jsonb_typeof(p->'bulk_photos') = 'array' and jsonb_array_length(p->'bulk_photos') > 0 then p->'bulk_photos' end;
  me uuid; inv_id uuid; inv_no text; ex record;
  it jsonb; mode text; price numeric; w numeric; k int; fee numeric; fee_vat numeric; carat numeric; ppc numeric;
  has_gold boolean;
  total numeric := 0; fab_total numeric := 0; vat_total numeric := 0;
  new_id uuid; bc text; chk numeric; codes jsonb := '[]';
begin
  if sid is null then raise exception 'المحل غير محدد'; end if;
  if not has_permission('create_invoice', sid) then
    raise exception 'ليس لديك صلاحية إنشاء فاتورة شراء' using errcode = '42501';
  end if;
  if ref is not null then
    select id, invoice_number into ex from invoices where client_ref = ref and store_id = sid;
    if found then return jsonb_build_object('id', ex.id, 'invoice_number', ex.invoice_number, 'duplicate', true); end if;
  end if;
  if typ is null or typ not in ('buyTrader', 'buyRetail') then raise exception 'نوع فاتورة الشراء غير معروف'; end if;
  if pm is null or pm not in ('cash', 'credit') then raise exception 'طريقة دفع غير معروفة'; end if;
  if typ = 'buyTrader' then
    if tid is null or not exists (select 1 from traders where id = tid and store_id in (select org_store_ids(sid))) then
      raise exception 'الرجاء اختيار تاجر من نفس المحل';
    end if;
  else
    tid := null;
  end if;
  if sid_type is not null and sid_type not in ('emirates_id', 'passport', 'other') then
    raise exception 'نوع مستند الهوية غير معروف';
  end if;
  if jsonb_typeof(p->'items') is distinct from 'array' or jsonb_array_length(p->'items') = 0 then
    raise exception 'الفاتورة فارغة — أضف قطعة واحدة على الأقل';
  end if;
  select id into me from staff where user_id = auth.uid() and store_id = sid limit 1;

  for it in select * from jsonb_array_elements(p->'items') loop
    mode := coalesce(it->>'mode', 'piece');
    if mode not in ('piece', 'bulk', 'diamond', 'diamond_bulk') then raise exception 'نوع سطر غير معروف: %', mode; end if;
    price := round(coalesce(nullif(it->>'price','')::numeric, 0), 2);
    fee := round(coalesce(nullif(it->>'fab_fee','')::numeric, 0), 2);
    fee_vat := case when typ = 'buyTrader' then round(coalesce(nullif(it->>'fab_fee_vat','')::numeric, 0), 2) else 0 end;
    if price < 0 or fee < 0 or fee_vat < 0 then raise exception 'مبلغ سالب بأحد السطور'; end if;
    if mode in ('piece', 'bulk') then
      w := nullif(it->>'weight','')::numeric; k := nullif(it->>'karat','')::int;
      if w is null or w <= 0 then raise exception 'وزن غير صحيح بأحد السطور'; end if;
      if k is null or k < 1 or k > 24 then raise exception 'عيار غير صحيح بأحد السطور'; end if;
    elsif mode = 'diamond' then
      carat := nullif(it->>'diamond_carat','')::numeric;
      if carat is null or carat <= 0 then raise exception 'وزن الماس غير صحيح'; end if;
      if coalesce((it->>'has_gold')::boolean, false) then
        w := nullif(it->>'gold_weight','')::numeric; k := nullif(it->>'gold_karat','')::int;
        if w is null or w <= 0 or k is null or k < 1 or k > 24 then raise exception 'وزن أو عيار ذهب قطعة الماس غير صحيح'; end if;
      end if;
    else
      carat := nullif(it->>'diamond_carat','')::numeric;
      if carat is null or carat <= 0 then raise exception 'قيراط صندوق الماس غير صحيح'; end if;
    end if;
    total := total + price;
    fab_total := fab_total + fee;
    vat_total := vat_total + fee_vat;
  end loop;
  total := round(total, 2);

  inv_no := next_invoice_number(sid, 'PINV');
  insert into invoices (store_id, invoice_number, type, trader_id, counterparty_name, seller_id_type, seller_id_number,
      payment_method, fabrication_fees, vat_amount, total_amount, amount_paid, status, attachment_url, bulk_photos,
      created_by, client_ref)
    values (sid, inv_no, typ, tid,
      case when typ = 'buyRetail' then nullif(trim(p->>'counterparty_name'), '') end,
      case when typ = 'buyRetail' then sid_type end,
      case when typ = 'buyRetail' then nullif(trim(p->>'seller_id_number'), '') end,
      pm, fab_total, case when typ = 'buyTrader' then vat_total else 0 end, total,
      case when pm = 'cash' then total else 0 end, case when pm = 'cash' then 'paid' else 'unpaid' end,
      nullif(p->>'attachment_url', ''), photos, me, ref)
    returning id into inv_id;

  for it in select * from jsonb_array_elements(p->'items') loop
    mode := coalesce(it->>'mode', 'piece');
    price := round(coalesce(nullif(it->>'price','')::numeric, 0), 2);
    fee := round(coalesce(nullif(it->>'fab_fee','')::numeric, 0), 2);
    fee_vat := case when typ = 'buyTrader' then round(coalesce(nullif(it->>'fab_fee_vat','')::numeric, 0), 2) else 0 end;
    w := nullif(it->>'weight','')::numeric; k := nullif(it->>'karat','')::int;

    if mode = 'piece' then
      bc := next_piece_barcode(sid, 'gold');
      insert into pieces (store_id, barcode, weight_grams, karat, description_ar, status, created_by, box_name, cost_fabrication_per_gram, purchase_cost)
        values (sid, bc, w, k, it->>'description', 'available', me, coalesce(nullif(trim(it->>'box_name'), ''), 'قطع ذهبية'),
          case when typ = 'buyTrader' and w > 0 then round(fee / w, 2) end,
          case when pm = 'cash' and price > 0 then price end) returning id into new_id;
      codes := codes || to_jsonb(bc);
      insert into invoice_items (invoice_id, piece_id, barcode, karat, weight_grams, accounting_weight_grams,
          fabrication_fee, fabrication_fee_vat, line_total, description)
        values (inv_id, new_id, bc, k, w, w, fee, fee_vat, price, it->>'description');

    elsif mode = 'bulk' then
      insert into gold_stock_lots (store_id, karat, weight_grams_total, weight_grams_remaining, cost_fabrication_per_gram,
          trader_id, source_invoice_id, notes, box_name, created_by)
        values (sid, k, w, w, coalesce(nullif(it->>'fab_per_gram','')::numeric, 0), tid, inv_id, it->>'description',
          case when typ = 'buyRetail' then 'كسر ' || k end, me)
        returning id into new_id;
      insert into invoice_items (invoice_id, gold_stock_lot_id, karat, weight_grams, accounting_weight_grams,
          fabrication_fee, fabrication_fee_vat, line_total, description)
        values (inv_id, new_id, k, w, w, fee, fee_vat, price, it->>'description');

    elsif mode = 'diamond_bulk' then
      carat := nullif(it->>'diamond_carat','')::numeric;
      ppc := nullif(it->>'diamond_price_per_carat','')::numeric;
      insert into diamond_stock_lots (store_id, box_name, total_carat, remaining_carat, price_per_carat, trader_id,
          source_invoice_id, notes, created_by)
        values (sid, nullif(trim(it->>'box_name'), ''), carat, carat, ppc, tid, inv_id, it->>'description', me)
        returning id into new_id;
      insert into invoice_items (invoice_id, diamond_stock_lot_id, fabrication_fee, line_total, description)
        values (inv_id, new_id, 0, price, it->>'description');

    else
      has_gold := coalesce((it->>'has_gold')::boolean, false);
      w := case when has_gold then nullif(it->>'gold_weight','')::numeric end;
      k := case when has_gold then nullif(it->>'gold_karat','')::int end;
      bc := next_piece_barcode(sid, 'diamond');
      insert into diamond_pieces (store_id, barcode, has_gold, gold_weight_grams, gold_karat, gold_cost_fabrication_per_gram,
          diamond_carat, diamond_price_per_carat, shape, clarity, cut, color, certificate_lab, certificate_number,
          description_ar, status, created_by, box_name)
        values (sid, bc, has_gold, w, k, nullif(it->>'gold_fab_cost','')::numeric,
          nullif(it->>'diamond_carat','')::numeric, nullif(it->>'diamond_price_per_carat','')::numeric,
          nullif(it->>'shape',''), nullif(it->>'clarity',''), nullif(it->>'cut',''), nullif(it->>'color',''),
          nullif(it->>'cert_lab',''), nullif(it->>'cert_number',''), it->>'description', 'available', me,
          coalesce(nullif(trim(it->>'box_name'), ''), 'قطع ألماسية'))
        returning id into new_id;
      codes := codes || to_jsonb(bc);
      insert into invoice_items (invoice_id, diamond_piece_id, barcode, karat, weight_grams, accounting_weight_grams,
          fabrication_fee, line_total, description)
        values (inv_id, new_id, bc, k, w, w, 0, price, it->>'description');
    end if;

    if pm = 'credit' and typ = 'buyTrader' then
      insert into trader_movements (store_id, trader_id, invoice_id, movement_type, weight_grams, karat,
          gold_24k_equivalent, fab_fee_amount, notes, created_by)
        values (sid, tid, inv_id, 'debt_increase',
          case when mode in ('piece', 'bulk', 'diamond') then w end,
          case when mode in ('piece', 'bulk', 'diamond') then k end,
          case when mode in ('piece', 'bulk', 'diamond') and w is not null and k is not null then round(w * k / 24.0, 3) else 0 end,
          case when mode in ('diamond', 'diamond_bulk') then price else round(fee + fee_vat, 2) end,
          coalesce(nullif(it->>'description', ''), 'فاتورة شراء ' || inv_no), me);
    end if;
  end loop;

  if pm = 'cash' and total > 0 then
    insert into cash_movements (store_id, box, direction, amount, description, created_by, invoice_id)
      values (sid, 'main', 'out', total, 'دفع فاتورة شراء ' || inv_no, me, inv_id);
  end if;

  select coalesce(sum(line_total), 0) into chk from invoice_items where invoice_id = inv_id;
  if abs(chk - total) > 0.01 then raise exception 'فحص محاسبي فشل: مجموع السطور % ≠ الإجمالي %', chk, total; end if;

  return jsonb_build_object('id', inv_id, 'invoice_number', inv_no, 'total', total, 'duplicate', false, 'barcodes', codes);
exception when unique_violation then
  if ref is not null then
    select id, invoice_number into ex from invoices where client_ref = ref and store_id = sid;
    if found then return jsonb_build_object('id', ex.id, 'invoice_number', ex.invoice_number, 'duplicate', true); end if;
  end if;
  raise;
end $$;


--
-- Name: post_sale_exchange(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.post_sale_exchange(p jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  sid uuid := nullif(p->>'store_id', '')::uuid;
  orig uuid := nullif(p->>'original_invoice_id', '')::uuid;
  ref uuid := nullif(p->>'client_ref', '')::uuid;
  dir text := coalesce(nullif(p->>'diff_dir', ''), 'none');
  meth text := coalesce(nullif(p->>'diff_method', ''), 'cash');
  amt numeric := round(coalesce(nullif(p->>'diff_amount', '')::numeric, 0), 2);
  paid_amt numeric := round(coalesce(nullif(p->>'paid_amount', '')::numeric, 0), 2);
  cur text := upper(coalesce(nullif(p->>'diff_currency', ''), ''));
  rate numeric := nullif(p->>'diff_rate', '')::numeric;
  o record; ex record; pc record; it record;
  me uuid; base_cur text; fx boolean := false; base_diff numeric := 0; paid_base numeric := 0;
  ret_total numeric; new_total numeric; total numeric;
  n_ret int; n_new int; n_found int; wsum numeric; acc numeric := 0; k int := 0; price numeric;
  inv_id uuid; inv_no text; pm text; old_codes text; new_codes text; gp numeric; bd jsonb;
begin
  if sid is null then raise exception 'المحل غير محدد'; end if;
  if not has_permission('create_invoice', sid) then raise exception 'ليس لديك صلاحية التبديل' using errcode = '42501'; end if;
  if ref is not null then
    select id, invoice_number into ex from invoices where client_ref = ref and store_id = sid;
    if found then return jsonb_build_object('id', ex.id, 'invoice_number', ex.invoice_number, 'duplicate', true); end if;
  end if;
  select * into o from invoices where id = orig and store_id = sid for update;
  if not found or o.type <> 'sale' then raise exception 'فاتورة البيع الأصلية غير موجودة'; end if;
  if o.status = 'cancelled' then raise exception 'الفاتورة الأصلية ملغاة'; end if;
  if o.customer_id is null then raise exception 'الفاتورة بدون زبون — اختر الزبون بتعديل الفاتورة أولاً'; end if;
  if dir not in ('in', 'out', 'none') then raise exception 'اتجاه الفرق غير معروف'; end if;
  if meth not in ('cash', 'bank', 'account', 'partial') or (meth = 'partial' and dir <> 'in') then raise exception 'طريقة دفع الفرق غير معروفة'; end if;
  select id into me from staff where user_id = auth.uid() and store_id = sid limit 1;

  select count(*), round(sum(line_total), 2), string_agg(coalesce(barcode, description, '—'), '، ')
    into n_ret, ret_total, old_codes
    from invoice_items ii
   where ii.invoice_id = orig and ii.piece_id is not null and ii.line_total > 0
     and ii.id in (select x::uuid from jsonb_array_elements_text(coalesce(p->'item_ids', '[]'::jsonb)) x)
     and not exists (select 1 from invoice_items r join invoices ri on ri.id = r.invoice_id
                      where r.returned_item_id = ii.id and ri.status <> 'cancelled')
     and not exists (select 1 from invoice_items r join invoices ri on ri.id = r.invoice_id
                      where ri.related_invoice_id = orig and ri.type = 'return' and ri.status <> 'cancelled' and r.piece_id = ii.piece_id);
  if n_ret = 0 or n_ret <> (select count(distinct x) from jsonb_array_elements_text(coalesce(p->'item_ids', '[]'::jsonb)) x) then
    raise exception 'القطعة الراجعة غير صحيحة أو رجعت من قبل من هذه الفاتورة';
  end if;

  select coalesce(nullif(upper(currency), ''), 'AED') into base_cur from stores where id = sid;
  if dir = 'none' then amt := 0; end if;
  if amt < 0 or paid_amt < 0 then raise exception 'مبلغ غير صحيح'; end if;
  if dir <> 'none' and amt = 0 then raise exception 'اكتب مبلغ الفرق'; end if;
  if amt > 0 then
    if cur = '' then cur := base_cur; end if;
    fx := cur <> base_cur;
    if fx and (rate is null or rate <= 0) then raise exception 'أدخل سعر صرف % مقابل %', cur, base_cur; end if;
    base_diff := case when fx then round(amt / rate, 2) else amt end;
  end if;
  total := case dir when 'in' then base_diff when 'out' then -base_diff else 0 end;
  new_total := round(ret_total + total, 2);
  if new_total < 0 then raise exception 'الفرق أكبر من قيمة القطع الراجعة'; end if;
  if meth = 'partial' then
    if paid_amt <= 0 or paid_amt >= amt then raise exception 'المدفوع الآن يجب أن يكون أقل من الفرق وأكبر من صفر'; end if;
    paid_base := case when fx then round(paid_amt / rate, 2) else paid_amt end;
  end if;

  select count(*) into n_new from (select distinct x from jsonb_array_elements_text(coalesce(p->'new_piece_ids', '[]'::jsonb)) x) s;
  if n_new = 0 then raise exception 'أضف القطعة الجديدة'; end if;
  select count(*), sum(coalesce(accounting_weight_grams, weight_grams, 0)), string_agg(barcode, '، ')
    into n_found, wsum, new_codes
    from pieces where store_id = sid and status = 'available'
     and id in (select x::uuid from jsonb_array_elements_text(p->'new_piece_ids') x);
  if n_found <> n_new then raise exception 'إحدى القطع الجديدة غير متوفرة للبيع'; end if;

  pm := case when dir = 'out' or meth = 'account' then 'credit' when meth = 'partial' then 'mixed' when dir = 'none' then 'cash' else meth end;
  inv_no := next_invoice_number(sid, 'INV');
  insert into invoices (store_id, invoice_number, type, customer_id, payment_method, cash_paid_amount, bank_paid_amount,
      gold_value, fabrication_fees, vat_amount, total_amount, amount_paid, status, created_by, client_ref, related_invoice_id, is_exchange)
    values (sid, inv_no, 'sale', o.customer_id, pm,
      case when pm = 'mixed' then paid_base end, case when pm = 'mixed' then 0 end,
      0, 0, 0, total,
      case pm when 'credit' then 0 when 'mixed' then paid_base else total end,
      case when pm = 'credit' and total > 0.009 then 'unpaid' when pm = 'mixed' then 'unpaid' else 'paid' end,
      me, ref, orig, true)
    returning id into inv_id;
  if fx and dir = 'in' and meth in ('cash', 'bank', 'partial') then
    bd := jsonb_build_array(jsonb_build_object('currency', cur, 'amount', case when meth = 'partial' then paid_amt else amt end,
                                               'rate', rate, 'method', case when meth = 'bank' then 'bank' else 'cash' end));
    update invoices set pay_breakdown = bd where id = inv_id;
  end if;

  for it in select * from invoice_items where invoice_id = orig and id in (select x::uuid from jsonb_array_elements_text(p->'item_ids') x) loop
    insert into invoice_items (invoice_id, piece_id, barcode, karat, weight_grams, accounting_weight_grams, fabrication_fee,
        line_total, description, description_en, item_photo_url, gold_price_per_gram, returned_item_id)
      values (inv_id, it.piece_id, it.barcode, it.karat, it.weight_grams, it.accounting_weight_grams, 0,
        -it.line_total, it.description, it.description_en, it.item_photo_url, it.gold_price_per_gram, it.id);
    update pieces set status = 'available' where id = it.piece_id and store_id = sid;
    insert into piece_movements (store_id, piece_id, event_type, note, created_by)
      values (sid, it.piece_id, 'returned', 'رجعت بتبديل بفاتورة ' || inv_no || ' (من الفاتورة ' || o.invoice_number || ') — بدلها ' || new_codes, me);
  end loop;
  for pc in select * from pieces where store_id = sid and id in (select x::uuid from jsonb_array_elements_text(p->'new_piece_ids') x) order by barcode for update loop
    k := k + 1;
    price := case when k = n_new then round(new_total - acc, 2)
                  when coalesce(wsum, 0) > 0 then round(new_total * coalesce(pc.accounting_weight_grams, pc.weight_grams, 0) / wsum, 2)
                  else round(new_total / n_new, 2) end;
    acc := acc + price;
    select price_per_gram into gp from gold_prices where store_id = sid and karat = pc.karat;
    insert into invoice_items (invoice_id, piece_id, barcode, karat, weight_grams, accounting_weight_grams, fabrication_fee,
        line_total, description, description_en, gold_price_per_gram)
      values (inv_id, pc.id, pc.barcode, pc.karat, pc.weight_grams, coalesce(pc.accounting_weight_grams, pc.weight_grams), 0,
        price, coalesce(pc.description_ar, pc.piece_type, 'قطعة'), pc.description_en, gp);
    update pieces set status = 'sold' where id = pc.id;
    insert into piece_movements (store_id, piece_id, event_type, note, created_by)
      values (sid, pc.id, 'sold', 'بيع بفاتورة ' || inv_no || ' — تبديل بدل ' || old_codes || ' (فاتورة ' || o.invoice_number || ')', me);
  end loop;

  if dir = 'in' and meth in ('cash', 'bank') then
    insert into cash_movements (store_id, box, direction, amount, description, created_by, invoice_id)
      values (sid, 'main', 'in', total, 'فرق تبديل بفاتورة ' || inv_no, me, inv_id);
  elsif dir = 'in' and meth = 'partial' then
    insert into cash_movements (store_id, box, direction, amount, description, created_by, invoice_id)
      values (sid, 'main', 'in', paid_base, 'فرق تبديل (جزء) بفاتورة ' || inv_no, me, inv_id);
    insert into customer_debts (store_id, customer_id, invoice_id, movement_type, cash_amount, gold_grams_24k, notes, created_by)
      values (sid, o.customer_id, inv_id, 'debt_increase', round(total - paid_base, 2), 0, 'باقي فرق تبديل بفاتورة ' || inv_no, me);
  elsif dir = 'in' and meth = 'account' then
    insert into customer_debts (store_id, customer_id, invoice_id, movement_type, cash_amount, gold_grams_24k, notes, created_by)
      values (sid, o.customer_id, inv_id, 'debt_increase', total, 0, 'فرق تبديل بفاتورة ' || inv_no, me);
  elsif dir = 'out' then
    insert into customer_debts (store_id, customer_id, invoice_id, movement_type, cash_amount, gold_grams_24k, notes, created_by)
      values (sid, o.customer_id, inv_id, 'debt_decrease', -total, 0, 'فرق تبديل لصالح الزبون بفاتورة ' || inv_no, me);
    if meth in ('cash', 'bank') then
      perform cash_voucher(jsonb_build_object('store_id', sid, 'kind', 'out', 'party', 'customer', 'party_id', o.customer_id,
        'amount', amt, 'currency', cur, 'fx_rate', rate, 'method', meth, 'notes', 'رد فرق تبديل بفاتورة ' || inv_no));
    end if;
  end if;

  if abs((select coalesce(sum(line_total), 0) from invoice_items where invoice_id = inv_id) - total) > 0.01 then
    raise exception 'فحص محاسبي فشل: مجموع السطور ≠ الفرق';
  end if;
  return jsonb_build_object('id', inv_id, 'invoice_number', inv_no, 'total', total, 'returned_total', ret_total, 'new_total', new_total, 'duplicate', false);
end $$;


--
-- Name: post_sale_invoice(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.post_sale_invoice(p jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
            declare
              sid uuid := nullif(p->>'store_id','')::uuid;
                ref uuid := nullif(p->>'client_ref','')::uuid;
                  pm text := p->>'payment_method';
                    cust uuid := nullif(p->>'customer_id','')::uuid;
                      allow_low boolean := coalesce((p->>'confirm_low_price')::boolean, false);
                        cash_amt numeric := round(coalesce(nullif(p->>'cash_paid','')::numeric, 0), 2);
                          bank_amt numeric := round(coalesce(nullif(p->>'bank_paid','')::numeric, 0), 2);
                            sold_at timestamptz := coalesce(nullif(p->>'sold_at','')::timestamptz, now());
                              me uuid; inv_id uuid; inv_no text; ex record;
                                it jsonb; mode text; price numeric; total numeric := 0; paid numeric; remaining numeric := 0;
                                  pc record; dp record; lot record;
                                    k int; w numeric; aw numeric; gp numeric; lows text := '';
                                      lines jsonb := '[]'::jsonb;
                                        chk numeric;
                                        begin
                                          if sid is null then raise exception 'المحل غير محدد'; end if;
                                            if not has_permission('create_invoice', sid) then
                                                raise exception 'ليس لديك صلاحية إنشاء فاتورة بيع' using errcode = '42501';
                                                  end if;
                                                    if ref is not null then
                                                        select id, invoice_number into ex from invoices where client_ref = ref and store_id = sid;
                                                            if found then return jsonb_build_object('id', ex.id, 'invoice_number', ex.invoice_number, 'duplicate', true); end if;
                                                              end if;
                                                                if pm is null or pm not in ('cash','bank','credit','mixed') then raise exception 'طريقة دفع غير معروفة'; end if;
                                                                  -- a customer added on the sale screen while offline is created with the sale
                                                                    if cust is null and nullif(trim(p->'new_customer'->>'name'), '') is not null then
                                                                        select id into cust from customers where store_id in (select org_store_ids(sid)) and name = trim(p->'new_customer'->>'name')
                                                                              and coalesce(phone, '') = coalesce(nullif(trim(p->'new_customer'->>'phone'), ''), '') limit 1;
                                                                                end if;
                                                                                  if cust is null and nullif(trim(p->'new_customer'->>'name'), '') is not null then
                                                                                      insert into customers (store_id, name, phone) values (sid, trim(p->'new_customer'->>'name'), nullif(trim(p->'new_customer'->>'phone'), ''))
                                                                                          returning id into cust;
                                                                                            end if;
                                                                                              if cust is null or not exists (select 1 from customers where id = cust and store_id in (select org_store_ids(sid))) then
                                                                                                  raise exception 'الرجاء اختيار عميل من نفس المحل';
                                                                                                    end if;
                                                                                                      if jsonb_typeof(p->'items') <> 'array' or jsonb_array_length(p->'items') = 0 then
                                                                                                          raise exception 'الفاتورة فاضية — ضيف قطعة وحدة على الأقل';
                                                                                                            end if;
                                                                                                              -- offline sales keep their real time, but never in the future or older than 14 days
                                                                                                                if sold_at > now() + interval '5 minutes' or sold_at < now() - interval '14 days' then sold_at := now(); end if;
                                                                                                                  select id into me from staff where user_id = auth.uid() and store_id = sid limit 1;

                                                                                                                    -- 1) validate + lock every line, build the rows to insert
                                                                                                                      for it in select * from jsonb_array_elements(p->'items') loop
                                                                                                                          mode := coalesce(it->>'mode', 'manual');
                                                                                                                              price := round((it->>'price')::numeric, 2);
                                                                                                                                  if price is null or price < 0 then raise exception 'سعر غير صحيح بأحد السطور'; end if;
                                                                                                                                      if coalesce(nullif(it->>'manual_fab_fee','')::numeric, 0) < 0 then raise exception 'المصنعية لا تكون بالسالب'; end if;
                                                                                                                                          k := nullif(it->>'karat','')::int; w := nullif(it->>'weight','')::numeric; aw := coalesce(nullif(it->>'accounting_weight','')::numeric, w);

                                                                                                                                              if mode = 'diamond' then
                                                                                                                                                    select * into dp from diamond_pieces where id = (it->>'diamond_piece_id')::uuid and store_id = sid for update;
                                                                                                                                                          if not found then raise exception 'قطعة الماس غير موجودة'; end if;
                                                                                                                                                                if dp.status <> 'available' then raise exception 'القطعة % غير متاحة للبيع (حالتها: %)', coalesce(dp.barcode, dp.id::text), dp.status; end if;
                                                                                                                                                                      if lines @> jsonb_build_array(jsonb_build_object('diamond_piece_id', dp.id::text)) then raise exception 'القطعة % مكررة بنفس الفاتورة', coalesce(dp.barcode, dp.id::text); end if;
                                                                                                                                                                            k := case when dp.has_gold then dp.gold_karat end;
                                                                                                                                                                                  w := case when dp.has_gold then dp.gold_weight_grams end; aw := w;
                                                                                                                                                                                      elsif it ? 'piece_id' and nullif(it->>'piece_id','') is not null then
                                                                                                                                                                                            select * into pc from pieces where id = (it->>'piece_id')::uuid and store_id = sid for update;
                                                                                                                                                                                                  if not found then raise exception 'القطعة غير موجودة بهالمحل'; end if;
                                                                                                                                                                                                        if pc.status <> 'available' then raise exception 'القطعة % غير متاحة للبيع (حالتها: %)', pc.barcode, pc.status; end if;
                                                                                                                                                                                                              if lines @> jsonb_build_array(jsonb_build_object('piece_id', pc.id::text)) then raise exception 'القطعة % مكررة بنفس الفاتورة', pc.barcode; end if;
                                                                                                                                                                                                                    k := pc.karat; w := pc.weight_grams; aw := coalesce(pc.accounting_weight_grams, pc.weight_grams);
                                                                                                                                                                                                                        end if;
                                                                                                                                                                                                                            if mode = 'stock' then
                                                                                                                                                                                                                                  select * into lot from gold_stock_lots where id = (it->>'lot_id')::uuid and store_id = sid;
                                                                                                                                                                                                                                        if not found then raise exception 'رصيد الجملة غير موجود'; end if;
                                                                                                                                                                                                                                            end if;

                                                                                                                                                                                                                                                gp := case when k is null then null else (select price_per_gram from gold_prices where store_id = sid and karat = k) end;
                                                                                                                                                                                                                                                    -- currency-mistake guard: a gold line sold under half its gold value
                                                                                                                                                                                                                                                        if gp is not null and aw is not null and aw > 0 and price < gp * aw * 0.5 then
                                                                                                                                                                                                                                                              lows := lows || format(E'\n• %s: %s بدل قيمة ذهب تقريبية %s', coalesce(it->>'barcode', it->>'description', k || 'K'), price, round(gp * aw, 2));
                                                                                                                                                                                                                                                                  end if;
                                                                                                                                                                                                                                                                      total := total + price;
                                                                                                                                                                                                                                                                          lines := lines || jsonb_build_object(
                                                                                                                                                                                                                                                                                'piece_id', case when mode <> 'diamond' then nullif(it->>'piece_id','') end,
                                                                                                                                                                                                                                                                                      'diamond_piece_id', case when mode = 'diamond' then it->>'diamond_piece_id' end,
                                                                                                                                                                                                                                                                                            'lot_id', case when mode = 'stock' then it->>'lot_id' end,
                                                                                                                                                                                                                                                                                                  'is_pooled', coalesce((it->>'is_pooled')::boolean, false),
                                                                                                                                                                                                                                                                                                        'fee', case when mode = 'diamond' or nullif(it->>'piece_id','') is not null then 0
                                                                                                                                                                                                                                                                                                                          else coalesce(nullif(it->>'manual_fab_fee','')::numeric, 0) end,
                                                                                                                                                                                                                                                                                                                                'barcode', it->>'barcode', 'karat', k, 'weight', w, 'aw', aw, 'price', price, 'gp', gp,
                                                                                                                                                                                                                                                                                                                                      'description', it->>'description', 'description_en', it->>'description_en', 'photo', it->>'photo_url');
                                                                                                                                                                                                                                                                                                                                        end loop;

                                                                                                                                                                                                                                                                                                                                          if lows <> '' and not allow_low then
                                                                                                                                                                                                                                                                                                                                              raise exception 'LOW_PRICE:%', lows using errcode = 'P0001';
                                                                                                                                                                                                                                                                                                                                                end if;

                                                                                                                                                                                                                                                                                                                                                  total := round(total, 2);
                                                                                                                                                                                                                                                                                                                                                    if pm = 'mixed' then
                                                                                                                                                                                                                                                                                                                                                        if cash_amt < 0 or bank_amt < 0 then raise exception 'مبلغ دفع غير صحيح'; end if;
                                                                                                                                                                                                                                                                                                                                                            if cash_amt + bank_amt > total + 0.01 then raise exception 'المبلغ المدفوع أكبر من إجمالي الفاتورة'; end if;
                                                                                                                                                                                                                                                                                                                                                                remaining := greatest(0, total - cash_amt - bank_amt);
                                                                                                                                                                                                                                                                                                                                                                    paid := cash_amt + bank_amt;
                                                                                                                                                                                                                                                                                                                                                                      else
                                                                                                                                                                                                                                                                                                                                                                          paid := case when pm = 'credit' then 0 else total end;
                                                                                                                                                                                                                                                                                                                                                                              remaining := case when pm = 'credit' then total else 0 end;
                                                                                                                                                                                                                                                                                                                                                                                end if;

                                                                                                                                                                                                                                                                                                                                                                                  -- 2) write everything
                                                                                                                                                                                                                                                                                                                                                                                    inv_no := next_invoice_number(sid, 'INV');
                                                                                                                                                                                                                                                                                                                                                                                      insert into invoices (store_id, invoice_number, type, customer_id, payment_method, cash_paid_amount, bank_paid_amount,
                                                                                                                                                                                                                                                                                                                                                                                            gold_value, fabrication_fees, vat_amount, total_amount, amount_paid, status, created_by, created_at, client_ref)
                                                                                                                                                                                                                                                                                                                                                                                                values (sid, inv_no, 'sale', cust, pm, case when pm = 'mixed' then cash_amt end, case when pm = 'mixed' then bank_amt end,
                                                                                                                                                                                                                                                                                                                                                                                                      0, 0, 0, total, paid, case when remaining > 0.01 then 'unpaid' else 'paid' end, me, sold_at, ref)
                                                                                                                                                                                                                                                                                                                                                                                                          returning id into inv_id;

                                                                                                                                                                                                                                                                                                                                                                                                            -- paid in several currencies: [{currency, amount, rate (per 1 shop currency), method cash|bank}]
                                                                                                                                                                                                                                                                                                                                                                                                              if jsonb_typeof(p->'pay_breakdown') = 'array' and jsonb_array_length(p->'pay_breakdown') > 0 then
                                                                                                                                                                                                                                                                                                                                                                                                                  if pm = 'credit' then raise exception 'الدين لا يُقسّم على عملات'; end if;
                                                                                                                                                                                                                                                                                                                                                                                                                      if abs(coalesce((select sum((b->>'amount')::numeric / (b->>'rate')::numeric) from jsonb_array_elements(p->'pay_breakdown') b where b->>'method' = 'cash'), 0) - case pm when 'cash' then total when 'mixed' then cash_amt else 0 end) > 0.05
                                                                                                                                                                                                                                                                                                                                                                                                                             or abs(coalesce((select sum((b->>'amount')::numeric / (b->>'rate')::numeric) from jsonb_array_elements(p->'pay_breakdown') b where b->>'method' = 'bank'), 0) - case pm when 'bank' then total when 'mixed' then bank_amt else 0 end) > 0.05 then
                                                                                                                                                                                                                                                                                                                                                                                                                                   raise exception 'مبالغ العملات لا تطابق المدفوع';
                                                                                                                                                                                                                                                                                                                                                                                                                                       end if;
                                                                                                                                                                                                                                                                                                                                                                                                                                           update invoices set pay_breakdown = p->'pay_breakdown' where id = inv_id;
                                                                                                                                                                                                                                                                                                                                                                                                                                             end if;
                                                                                                                                                                                                                                                                                                                                                                                                                                               if nullif(upper(p->>'pay_currency'), '') is not null and (p->>'pay_fx_rate')::numeric > 0 then
                                                                                                                                                                                                                                                                                                                                                                                                                                                   update invoices set pay_currency = upper(p->>'pay_currency'), pay_fx_rate = (p->>'pay_fx_rate')::numeric where id = inv_id;
                                                                                                                                                                                                                                                                                                                                                                                                                                                     end if;

                                                                                                                                                                                                                                                                                                                                                                                                                                                       insert into invoice_items (invoice_id, piece_id, diamond_piece_id, gold_stock_lot_id, barcode, karat, weight_grams,
                                                                                                                                                                                                                                                                                                                                                                                                                                                             accounting_weight_grams, fabrication_fee, line_total, description, description_en, item_photo_url, gold_price_per_gram)
                                                                                                                                                                                                                                                                                                                                                                                                                                                               select inv_id, (l->>'piece_id')::uuid, (l->>'diamond_piece_id')::uuid, (l->>'lot_id')::uuid, l->>'barcode', (l->>'karat')::int,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                     (l->>'weight')::numeric, (l->>'aw')::numeric, (l->>'fee')::numeric, (l->>'price')::numeric, l->>'description',
                                                                                                                                                                                                                                                                                                                                                                                                                                                                           l->>'description_en', l->>'photo', (l->>'gp')::numeric
                                                                                                                                                                                                                                                                                                                                                                                                                                                                             from jsonb_array_elements(lines) l;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                               update pieces set status = 'sold' where id in (select (l->>'piece_id')::uuid from jsonb_array_elements(lines) l where l->>'piece_id' is not null);
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 insert into piece_movements (store_id, piece_id, event_type, note, created_by)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     select sid, (l->>'piece_id')::uuid, 'sold', 'بيع بفاتورة ' || inv_no, me from jsonb_array_elements(lines) l where l->>'piece_id' is not null;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       update diamond_pieces set status = 'sold' where id in (select (l->>'diamond_piece_id')::uuid from jsonb_array_elements(lines) l where l->>'diamond_piece_id' is not null);

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         for it in select * from jsonb_array_elements(lines) l where l->>'lot_id' is not null loop
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             if (it->>'is_pooled')::boolean then
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   perform consume_gold_stock_lot_pooled((it->>'lot_id')::uuid, (it->>'weight')::numeric, (it->>'fee')::numeric);
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       else
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             perform consume_gold_stock_lot((it->>'lot_id')::uuid, (it->>'weight')::numeric);
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 end if;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   end loop;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     if paid > 0 then
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         insert into cash_movements (store_id, box, direction, amount, description, created_by, invoice_id, created_at)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             values (sid, 'main', 'in', paid,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   case when pm = 'mixed' then format('تحصيل جزئي لفاتورة بيع %s (%s)', inv_no, concat_ws(' + ', case when cash_amt > 0 then cash_amt || ' نقداً' end, case when bank_amt > 0 then bank_amt || ' فيزا/بنك' end))
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              else 'تحصيل فاتورة بيع ' || inv_no end, me, inv_id, sold_at);
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                end if;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  if remaining > 0.01 then
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      insert into customer_debts (store_id, customer_id, invoice_id, movement_type, cash_amount, gold_grams_24k, notes, created_by)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          values (sid, cust, inv_id, 'debt_increase', remaining, 0,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                case when pm = 'credit' then 'فاتورة بيع ' || inv_no else format('متبقي فاتورة بيع %s (دُفع %s من %s)', inv_no, paid, total) end, me);
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  end if;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    -- 3) self-check before commit: lines = total, paid + debt = total
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      select coalesce(sum(line_total), 0) into chk from invoice_items where invoice_id = inv_id;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        if abs(chk - total) > 0.01 then raise exception 'فحص محاسبي فشل: مجموع السطور % ≠ الإجمالي %', chk, total; end if;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          if abs(paid + remaining - total) > 0.01 then raise exception 'فحص محاسبي فشل: المدفوع + الدين ≠ الإجمالي'; end if;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            return jsonb_build_object('id', inv_id, 'invoice_number', inv_no, 'total', total, 'duplicate', false);
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            exception when unique_violation then
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              if ref is not null then
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  select id, invoice_number into ex from invoices where client_ref = ref and store_id = sid;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      if found then return jsonb_build_object('id', ex.id, 'invoice_number', ex.invoice_number, 'duplicate', true); end if;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        end if;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          raise;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          end $$;


--
-- Name: post_sales_return(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.post_sales_return(p jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  sid uuid := nullif(p->>'store_id','')::uuid;
  ref uuid := nullif(p->>'client_ref','')::uuid;
  orig uuid := nullif(p->>'original_invoice_id','')::uuid;
  rm text := p->>'refund_method';
  reason text := nullif(trim(p->>'reason'), '');
  o record; ex record; lr record;
  ids uuid[]; me uuid; inv_id uuid; inv_no text;
  total numeric; chk numeric; sold numeric; back numeric; note text;
begin
  if sid is null then raise exception 'المحل غير محدد'; end if;
  if not (has_permission('create_invoice', sid) or has_permission('delete_invoice', sid)) then
    raise exception 'ليس لديك صلاحية تسجيل مرتجع' using errcode = '42501';
  end if;
  if ref is not null then
    select id, invoice_number into ex from invoices where client_ref = ref and store_id = sid;
    if found then return jsonb_build_object('id', ex.id, 'invoice_number', ex.invoice_number, 'duplicate', true); end if;
  end if;
  if rm is null or rm not in ('cash', 'bank', 'debt_reduce') then raise exception 'طريقة رد غير معروفة'; end if;

  select * into o from invoices where id = orig and store_id = sid for update;
  if not found then raise exception 'الفاتورة الأصلية غير موجودة'; end if;
  if o.type <> 'sale' then raise exception 'يمكن إرجاع فواتير البيع فقط'; end if;
  if o.status = 'cancelled' then raise exception 'الفاتورة الأصلية ملغاة'; end if;
  if rm = 'debt_reduce' and o.customer_id is null then raise exception 'لا يوجد عميل لتخفيض دينه'; end if;

  select array_agg(distinct x::uuid) into ids from jsonb_array_elements_text(coalesce(p->'item_ids', '[]'::jsonb)) x;
  if ids is null or cardinality(ids) = 0 then raise exception 'اختر قطعة واحدة على الأقل للإرجاع'; end if;
  if exists (select 1 from unnest(ids) i where not exists (select 1 from invoice_items where id = i and invoice_id = orig)) then
    raise exception 'أحد السطور المختارة ليس من الفاتورة الأصلية';
  end if;
  if exists (
    select 1 from invoice_items s
      join invoice_items r on (r.piece_id = s.piece_id or r.diamond_piece_id = s.diamond_piece_id)
      join invoices ri on ri.id = r.invoice_id
     where s.id = any(ids) and ri.related_invoice_id = orig and ri.type = 'return' and ri.status <> 'cancelled') then
    raise exception 'بعض القطع المختارة أُرجعت مسبقاً'; end if;
  if exists (select 1 from invoice_items where id = any(ids) and (line_total < 0 or returned_item_id is not null))
     or exists (select 1 from invoice_items r join invoices ri on ri.id = r.invoice_id where r.returned_item_id = any(ids) and ri.status <> 'cancelled') then
    raise exception 'بعض القطع المختارة رجعت بتبديل';
  end if;
  for lr in select gold_stock_lot_id lid, sum(coalesce(weight_grams, 0)) w
              from invoice_items where id = any(ids) and gold_stock_lot_id is not null group by 1 loop
    select coalesce(sum(weight_grams), 0) into sold from invoice_items where invoice_id = orig and gold_stock_lot_id = lr.lid;
    select coalesce(sum(r.weight_grams), 0) into back from invoice_items r join invoices ri on ri.id = r.invoice_id
     where ri.related_invoice_id = orig and ri.type = 'return' and ri.status <> 'cancelled' and r.gold_stock_lot_id = lr.lid;
    if back + lr.w > sold + 0.0005 then raise exception 'وزن المرتجع من رصيد الجملة أكبر من الوزن المباع'; end if;
  end loop;

  select round(sum(line_total), 2) into total from invoice_items where id = any(ids);
  select id into me from staff where user_id = auth.uid() and store_id = sid limit 1;
  inv_no := next_invoice_number(sid, 'RET');
  note := 'مرتجع ' || inv_no || ' لفاتورة ' || o.invoice_number || coalesce(' — ' || reason, '');

  insert into invoices (store_id, invoice_number, type, related_invoice_id, customer_id, payment_method,
      total_amount, amount_paid, status, created_by, client_ref)
    values (sid, inv_no, 'return', orig, o.customer_id, case when rm = 'debt_reduce' then 'credit' else rm end,
      total, total, 'paid', me, ref)
    returning id into inv_id;

  insert into invoice_items (invoice_id, piece_id, gold_stock_lot_id, diamond_piece_id, barcode, karat, weight_grams,
      accounting_weight_grams, fabrication_fee, line_total, description, description_en, gold_price_per_gram, item_photo_url)
    select inv_id, piece_id, gold_stock_lot_id, diamond_piece_id, barcode, karat, weight_grams,
      accounting_weight_grams, 0, line_total, description, description_en, gold_price_per_gram, item_photo_url
      from invoice_items where id = any(ids);

  update pieces set status = 'available'
   where status = 'sold' and store_id = sid and id in (select piece_id from invoice_items where id = any(ids) and piece_id is not null);
  insert into piece_movements (store_id, piece_id, event_type, note, created_by)
    select sid, piece_id, 'returned', note, me from invoice_items where id = any(ids) and piece_id is not null;
  update diamond_pieces set status = 'available'
   where status = 'sold' and store_id = sid and id in (select diamond_piece_id from invoice_items where id = any(ids) and diamond_piece_id is not null);
  update gold_stock_lots l
     set weight_grams_remaining = l.weight_grams_remaining + x.w,
         fabrication_pool_remaining = case when l.fabrication_pool_remaining is null then null
                                           else l.fabrication_pool_remaining + x.f end
    from (select gold_stock_lot_id, sum(coalesce(weight_grams, 0)) w, sum(coalesce(fabrication_fee, 0)) f
            from invoice_items where id = any(ids) and gold_stock_lot_id is not null group by gold_stock_lot_id) x
   where l.id = x.gold_stock_lot_id and l.store_id = sid;

  if rm = 'debt_reduce' then
    insert into customer_debts (store_id, customer_id, invoice_id, movement_type, cash_amount, gold_grams_24k, notes, created_by)
      values (sid, o.customer_id, inv_id, 'debt_decrease', total, 0, note, me);
  elsif total > 0 then
    insert into cash_movements (store_id, box, direction, amount, description, created_by, invoice_id)
      values (sid, 'main', 'out', total, 'رد مبلغ ' || note, me, inv_id);
  end if;

  select coalesce(sum(line_total), 0) into chk from invoice_items where invoice_id = inv_id;
  if abs(chk - total) > 0.01 then raise exception 'فحص محاسبي فشل: مجموع سطور المرتجع % ≠ %', chk, total; end if;

  return jsonb_build_object('id', inv_id, 'invoice_number', inv_no, 'total', total, 'duplicate', false);
exception when unique_violation then
  if ref is not null then
    select id, invoice_number into ex from invoices where client_ref = ref and store_id = sid;
    if found then return jsonb_build_object('id', ex.id, 'invoice_number', ex.invoice_number, 'duplicate', true); end if;
  end if;
  raise;
end $$;


--
-- Name: production_take(uuid, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.production_take(p_piece uuid, p_box text DEFAULT NULL::text, p_lot uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare pc record;
begin
  select id, store_id, weight_grams into pc from pieces where id = p_piece;
  if pc is null then raise exception 'القطعة غير موجودة'; end if;
  if not has_permission('add_piece', pc.store_id) then raise exception 'ليس لديك صلاحية الإنتاج' using errcode = '42501'; end if;
  if p_box is null and p_lot is null then raise exception 'حدّد الصندوق أو الدفعة'; end if;
  if exists (select 1 from piece_lot_draws where piece_id = p_piece) then raise exception 'القطعة مسحوبة من الكسر مسبقاً'; end if;
  perform gm_draw_for_piece(p_piece, pc.store_id, p_box, p_lot, pc.weight_grams);
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: receive_branch_transfer(uuid, text[], uuid[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receive_branch_transfer(p_transfer uuid, p_barcodes text[] DEFAULT NULL::text[], p_items uuid[] DEFAULT NULL::uuid[]) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
                                                                                                                                                                                                                                                                                                                                                                       declare tr record; it record; me uuid; got int := 0; left_n int; cm uuid;
                                                                                                                                                                                                                                                                                                                                                                       begin
                                                                                                                                                                                                                                                                                                                                                                         select * into tr from branch_transfers where id = p_transfer for update;
                                                                                                                                                                                                                                                                                                                                                                           if tr is null then raise exception 'سند النقل غير موجود'; end if;
                                                                                                                                                                                                                                                                                                                                                                             if not (has_permission('stock_transfers', tr.to_store_id) or has_permission('add_piece', tr.to_store_id)) then
                                                                                                                                                                                                                                                                                                                                                                                 raise exception 'ليس لديك صلاحية استلام البضاعة في هذا الفرع' using errcode = '42501';
                                                                                                                                                                                                                                                                                                                                                                                   end if;
                                                                                                                                                                                                                                                                                                                                                                                     if tr.status <> 'in_transit' then raise exception 'هذا السند ليس بالطريق (حالته: %)', tr.status; end if;
                                                                                                                                                                                                                                                                                                                                                                                       select id into me from staff where user_id = auth.uid() and store_id = tr.to_store_id limit 1;

                                                                                                                                                                                                                                                                                                                                                                                         for it in select * from branch_transfer_items
                                                                                                                                                                                                                                                                                                                                                                                                      where transfer_id = tr.id and received_at is null
                                                                                                                                                                                                                                                                                                                                                                                                                     and ((p_barcodes is null and p_items is null)
                                                                                                                                                                                                                                                                                                                                                                                                                                         or barcode = any(coalesce(p_barcodes, array[]::text[]))
                                                                                                                                                                                                                                                                                                                                                                                                                                                             or id = any(coalesce(p_items, array[]::uuid[]))) for update
                                                                                                                                                                                                                                                                                                                                                                                                                                                               loop
                                                                                                                                                                                                                                                                                                                                                                                                                                                                   if it.kind = 'scrap' then
                                                                                                                                                                                                                                                                                                                                                                                                                                                                         insert into gold_stock_lots (store_id, karat, weight_grams_total, weight_grams_remaining, cost_fabrication_per_gram, notes, created_by, box_name)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 values (tr.to_store_id, it.karat, it.weight_grams, it.weight_grams, it.fab_per_gram, 'استلام كسر من فرع آخر بسند ' || tr.transfer_number, me, it.box_name);
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     elsif it.kind = 'cash' then
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           insert into cash_movements (store_id, box, direction, amount, description, created_by)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   values (tr.to_store_id, it.cash_box, 'in', it.amount, 'استلام نقد من فرع آخر بسند ' || tr.transfer_number, me) returning id into cm;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         if it.cash_box = 'main' then
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 insert into daily_cash_log (store_id, operation_type, direction, amount, notes, created_by, cash_movement_id)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           values (tr.to_store_id, 'استلام نقد من فرع آخر', 'in', it.amount, 'سند ' || tr.transfer_number, me, cm);
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 end if;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     elsif it.piece_id is not null then
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           update pieces set store_id = tr.to_store_id, status = 'available' where id = it.piece_id and status = 'in_transit';
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 insert into piece_movements (store_id, piece_id, event_type, note, created_by)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         values (tr.to_store_id, it.piece_id, 'transfer_in', 'استلام من فرع آخر بسند ' || tr.transfer_number, me);
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             elsif it.diamond_piece_id is not null then
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   if exists (select 1 from diamond_pieces where store_id = tr.to_store_id and barcode = it.barcode and id <> it.diamond_piece_id) then
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           raise exception 'يوجد في هذا الفرع قطعة ألماس أخرى بنفس الباركود %', it.barcode;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 end if;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       update diamond_pieces set store_id = tr.to_store_id, status = 'available' where id = it.diamond_piece_id and status = 'in_transit';
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           end if;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               update branch_transfer_items set received_at = now(), received_by = me where id = it.id;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   got := got + 1;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     end loop;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       if (p_barcodes is not null or p_items is not null) and got = 0 then
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           raise exception 'غير موجود في هذا السند أو استُلم من قبل';
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             end if;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               select count(*) into left_n from branch_transfer_items where transfer_id = tr.id and received_at is null;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 if left_n = 0 then
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     update branch_transfers set status = 'received', received_by = me, received_at = now() where id = tr.id;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       end if;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         return jsonb_build_object('received', got, 'remaining', left_n);
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         end $$;


--
-- Name: record_customer_payment(uuid, numeric, text, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.record_customer_payment(p_customer uuid, p_amount numeric, p_method text DEFAULT 'cash'::text, p_notes text DEFAULT NULL::text, p_store uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
                                                                                                                                                                                                                                                                                                                                                     declare c record; st uuid; me uuid; amt numeric := round(coalesce(p_amount, 0), 2); cm uuid; note text;
                                                                                                                                                                                                                                                                                                                                                     begin
                                                                                                                                                                                                                                                                                                                                                       select id, store_id, name into c from customers where id = p_customer;
                                                                                                                                                                                                                                                                                                                                                         if c is null then raise exception 'العميل غير موجود'; end if;
                                                                                                                                                                                                                                                                                                                                                           st := coalesce(p_store, c.store_id);
                                                                                                                                                                                                                                                                                                                                                             if st not in (select org_store_ids(c.store_id)) then raise exception 'العميل ليس من هذه المنشأة'; end if;
                                                                                                                                                                                                                                                                                                                                                               if not (has_permission('edit_customers', st) or has_permission('manage_daily_cashbox', st)) then
                                                                                                                                                                                                                                                                                                                                                                   raise exception 'ليس لديك صلاحية تسجيل دفعات العملاء' using errcode = '42501';
                                                                                                                                                                                                                                                                                                                                                                     end if;
                                                                                                                                                                                                                                                                                                                                                                       if amt <= 0 then raise exception 'المبلغ يجب أن يكون أكبر من صفر'; end if;
                                                                                                                                                                                                                                                                                                                                                                         if coalesce(p_method, 'cash') not in ('cash', 'bank') then raise exception 'طريقة دفع غير معروفة'; end if;
                                                                                                                                                                                                                                                                                                                                                                           select id into me from staff where user_id = auth.uid() and store_id = st limit 1;
                                                                                                                                                                                                                                                                                                                                                                             note := coalesce(nullif(trim(p_notes), ''), 'دفعة من العميل');
                                                                                                                                                                                                                                                                                                                                                                               insert into cash_movements (store_id, box, direction, amount, description, created_by)
                                                                                                                                                                                                                                                                                                                                                                                   values (st, case when p_method = 'bank' then 'bank' else 'main' end, 'in', amt,
                                                                                                                                                                                                                                                                                                                                                                                               'دفعة من العميل ' || c.name || case when p_method = 'bank' then ' (تحويل/بطاقة)' else '' end, me)
                                                                                                                                                                                                                                                                                                                                                                                                   returning id into cm;
                                                                                                                                                                                                                                                                                                                                                                                                     if coalesce(p_method, 'cash') = 'cash' then
                                                                                                                                                                                                                                                                                                                                                                                                         insert into daily_cash_log (store_id, operation_type, direction, amount, notes, created_by, cash_movement_id)
                                                                                                                                                                                                                                                                                                                                                                                                               values (st, 'دفعة من عميل', 'in', amt, c.name || ' — ' || note, me, cm);
                                                                                                                                                                                                                                                                                                                                                                                                                 end if;
                                                                                                                                                                                                                                                                                                                                                                                                                   insert into customer_debts (store_id, customer_id, movement_type, cash_amount, gold_grams_24k, notes, source, created_by, cash_movement_id)
                                                                                                                                                                                                                                                                                                                                                                                                                       values (st, c.id, 'debt_decrease', amt, 0, note, 'payment', me, cm);
                                                                                                                                                                                                                                                                                                                                                                                                                         return jsonb_build_object('ok', true);
                                                                                                                                                                                                                                                                                                                                                                                                                         end $$;


--
-- Name: record_expense(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.record_expense(p jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare sid uuid := (p->>'store_id')::uuid; me uuid; cat record; amt numeric := round(coalesce(nullif(p->>'amount', '')::numeric, 0), 2);
        eid uuid; cm uuid; descr text := nullif(trim(p->>'description'), '');
        cur text := upper(coalesce(nullif(p->>'currency', ''), '')); rate numeric := nullif(p->>'fx_rate', '')::numeric;
        base_cur text; fx boolean; base_amt numeric; fxnote text := '';
begin
  if not gm_can_expense(sid) or not is_store_member(sid) then raise exception 'ليس لديك صلاحية تسجيل المصاريف' using errcode = '42501'; end if;
  select id, name into cat from expense_categories where id = (p->>'category_id')::uuid and store_id = sid;
  if cat is null then raise exception 'اختر نوع المصروف'; end if;
  if amt <= 0 then raise exception 'المبلغ يجب أن يكون أكبر من صفر'; end if;
  select coalesce(nullif(upper(currency), ''), 'AED') into base_cur from stores where id = sid;
  if cur = '' then cur := base_cur; end if;
  fx := cur <> base_cur;
  if fx then
    if rate is null or rate <= 0 then raise exception 'أدخل سعر صرف % مقابل %', cur, base_cur; end if;
    base_amt := round(amt / rate, 2);
    fxnote := ' (' || trim(to_char(amt, 'FM999,999,999,990.##')) || ' ' || cur || ')';
  else
    base_amt := amt;
  end if;
  select id into me from staff where user_id = auth.uid() and store_id = sid limit 1;
  insert into expense_entries (store_id, category_id, amount, description, attachment_url, created_by, fx_amount, fx_currency)
    values (sid, cat.id, base_amt, coalesce(descr, cat.name), nullif(p->>'attachment_url', ''), me,
            case when fx then amt end, case when fx then cur end) returning id into eid;
  insert into cash_movements (store_id, box, direction, amount, description, created_by, fx_amount, fx_currency)
    values (sid, 'main', 'out', base_amt, 'مصروف ' || cat.name || coalesce(': ' || descr, '') || fxnote, me,
            case when fx then amt end, case when fx then cur end) returning id into cm;
  update expense_entries set cash_movement_id = cm where id = eid;
  if coalesce((p->>'from_daily_cashbox')::boolean, true) then
    insert into daily_cash_log (store_id, operation_type, direction, amount, currency, notes, created_by, cash_movement_id)
      values (sid, 'مصروف: ' || cat.name, 'out', amt, cur, descr, me, cm);
  end if;
  return eid;
end $$;


--
-- Name: record_repair_gold(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.record_repair_gold(p jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
                declare sid uuid := (p->>'store_id')::uuid;
                        kt int := (p->>'karat')::int;
                                w numeric := round(coalesce(nullif(p->>'grams', '')::numeric, 0), 3);
                                        left_w numeric := w; take numeric; avail numeric; total_cost numeric := 0; today_price numeric := 0;
                                                lot record; cat_id uuid; me uuid; eid uuid; lines text := ''; head text;
                                                        descr text := nullif(trim(p->>'description'), '');
                                                        begin
                                                          if not gm_can_expense(sid) or not is_store_member(sid) then raise exception 'ليس لديك صلاحية تسجيل المصاريف' using errcode = '42501'; end if;
                                                            if kt not in (18, 21, 22, 24) then raise exception 'اختر العيار'; end if;
                                                              if w <= 0 then raise exception 'أدخل الغرامات'; end if;
                                                                select coalesce(sum(weight_grams_remaining), 0) into avail from gold_stock_lots
                                                                   where store_id = sid and box_name = 'كسر ' || kt and weight_grams_remaining > 0;
                                                                     if w > avail + 0.0005 then raise exception 'الوزن أكبر من الموجود في صندوق كسر % (% غ)', kt, round(avail, 3); end if;

                                                                       select price_per_gram into today_price from gold_prices where store_id = sid and karat = kt limit 1;
                                                                         select id into cat_id from expense_categories where store_id = sid and name = 'تصاليح ذهب' limit 1;
                                                                           if cat_id is null then cat_id := save_expense_category(sid, 'تصاليح ذهب'); end if;
                                                                             select id into me from staff where user_id = auth.uid() and store_id = sid limit 1;

                                                                               insert into expense_entries (store_id, category_id, amount, description, created_by)
                                                                                   values (sid, cat_id, 0, 'تصليح ذهب', me) returning id into eid;

                                                                                     for lot in select l.id, l.weight_grams_remaining rem, l.created_at ld,
                                                                                                         coalesce((select sum(ii.line_total) / nullif(sum(ii.weight_grams), 0) from invoice_items ii join invoices iv on iv.id = ii.invoice_id
                                                                                                                                        where ii.gold_stock_lot_id = l.id and iv.type = 'buyRetail'), 0) per_g
                                                                                                                                                       from gold_stock_lots l
                                                                                                                                                                     where l.store_id = sid and l.box_name = 'كسر ' || kt and l.weight_grams_remaining > 0
                                                                                                                                                                                   order by l.created_at, l.id for update of l
                                                                                                                                                                                     loop
                                                                                                                                                                                         exit when left_w <= 0.0005;
                                                                                                                                                                                             take := least(lot.rem, left_w);
                                                                                                                                                                                                 update gold_stock_lots set weight_grams_remaining = round(weight_grams_remaining - take, 3) where id = lot.id;
                                                                                                                                                                                                     insert into repair_gold_lines (expense_entry_id, lot_id, karat, grams, cost, lot_date)
                                                                                                                                                                                                           values (eid, lot.id, kt, take, round(take * lot.per_g, 2), lot.ld);
                                                                                                                                                                                                               total_cost := total_cost + take * lot.per_g;
                                                                                                                                                                                                                   lines := lines || E'\n• ' || to_char(lot.ld at time zone 'Asia/Dubai', 'DD/MM/YYYY') || ': '
                                                                                                                                                                                                                                || trim(to_char(take, 'FM999990.000')) || ' غ — كلفة ' || trim(to_char(round(take * lot.per_g, 2), 'FM999,999,990.00'));
                                                                                                                                                                                                                                    left_w := left_w - take;
                                                                                                                                                                                                                                      end loop;

                                                                                                                                                                                                                                        head := format('تصليح ذهب عيار %s: %s غ — قيمتها بسعر اليوم %s', kt, trim(to_char(w, 'FM999990.000')),
                                                                                                                                                                                                                                                         trim(to_char(round(w * coalesce(today_price, 0), 2), 'FM999,999,990.00')))
                                                                                                                                                                                                                                                                   || coalesce(' — ' || descr, '');
                                                                                                                                                                                                                                                                     update expense_entries set amount = round(total_cost, 2), description = head || lines where id = eid;
                                                                                                                                                                                                                                                                       return eid;
                                                                                                                                                                                                                                                                       end $$;


--
-- Name: record_subscription_payment(uuid, integer, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.record_subscription_payment(p_store_id uuid, p_months integer, p_payment_ref text DEFAULT NULL::text, p_plan_id uuid DEFAULT NULL::uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_sub subscriptions%rowtype;
  v_base timestamptz;
begin
  if not exists (select 1 from platform_admins where user_id = auth.uid()) then
    raise exception 'unauthorized';
  end if;

  select * into v_sub from subscriptions where store_id = p_store_id limit 1;
  if v_sub.id is null then raise exception 'no subscription found for store'; end if;

  v_base := greatest(coalesce(v_sub.current_period_end, now()), now());
  update subscriptions set
    status = 'active',
    plan_id = coalesce(p_plan_id, plan_id),
    current_period_end = v_base + (p_months || ' months')::interval,
    payment_ref = coalesce(p_payment_ref, payment_ref),
    deactivated_at = null,
    updated_at = now()
  where id = v_sub.id;

  insert into audit_log (store_id, action_type, description)
  values (p_store_id, 'subscription_payment_recorded', 'تسجيل دفعة اشتراك يدوياً: ' || p_months || ' شهر' || coalesce(' - مرجع: ' || p_payment_ref, ''));
end;
$$;


--
-- Name: refund_customer_deposit(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.refund_customer_deposit(p_deposit uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
                                                                                                                  declare d record; me uuid; cm uuid; left_amt numeric;
                                                                                                                  begin
                                                                                                                    select dp.*, cu.name cname into d from customer_deposits dp join customers cu on cu.id = dp.customer_id where dp.id = p_deposit for update of dp;
                                                                                                                      if d is null then raise exception 'العربون غير موجود'; end if;
                                                                                                                        if not (has_permission('edit_customers', d.store_id) or has_permission('manage_daily_cashbox', d.store_id)) then
                                                                                                                            raise exception 'ليس لديك صلاحية' using errcode = '42501';
                                                                                                                              end if;
                                                                                                                                if d.status <> 'active' then raise exception 'هذا العربون مُسترجَع مسبقاً'; end if;
                                                                                                                                  select remaining into left_amt from customer_deposit_remaining(d.store_id) where deposit_id = d.id;
                                                                                                                                    if coalesce(left_amt, 0) < d.amount - 0.009 then
                                                                                                                                        raise exception 'هذا العربون استُخدم (كلياً أو جزئياً) في فاتورة، فلا يمكن استرجاعه كاملاً. لإعادة ما تبقّى للزبون استخدم «صرف للزبون» من صفحة حسابه.';
                                                                                                                                          end if;
                                                                                                                                            select id into me from staff where user_id = auth.uid() and store_id = d.store_id limit 1;
                                                                                                                                              update customer_deposits set status = 'refunded', refunded_at = now() where id = d.id;
                                                                                                                                                update pieces set status = 'available', reserved_customer_id = null
                                                                                                                                                    where store_id = d.store_id and status = 'reserved' and reserved_customer_id = d.customer_id
                                                                                                                                                          and barcode in (select nullif(trim(x->>'barcode'), '') from jsonb_array_elements(coalesce(d.items, '[]'::jsonb)) x);
                                                                                                                                                            if d.in_cashbox then
                                                                                                                                                                insert into cash_movements (store_id, box, direction, amount, description, created_by)
                                                                                                                                                                      values (d.store_id, case when d.method = 'bank' then 'bank' else 'main' end, 'out', d.amount, 'استرجاع عربون ' || d.deposit_number || ' إلى ' || d.cname, me)
                                                                                                                                                                            returning id into cm;
                                                                                                                                                                                if d.method = 'cash' then
                                                                                                                                                                                      insert into daily_cash_log (store_id, operation_type, direction, amount, notes, created_by, cash_movement_id)
                                                                                                                                                                                              values (d.store_id, 'استرجاع عربون', 'out', d.amount, d.deposit_number || ' — ' || d.cname, me, cm);
                                                                                                                                                                                                  end if;
                                                                                                                                                                                                    end if;
                                                                                                                                                                                                      insert into customer_debts (store_id, customer_id, movement_type, cash_amount, gold_grams_24k, notes, source, created_by)
                                                                                                                                                                                                          values (d.store_id, d.customer_id, 'debt_increase', d.amount, 0, 'استرجاع عربون ' || d.deposit_number, 'deposit_refund', me);
                                                                                                                                                                                                          end $$;


--
-- Name: regenerate_piece_barcode(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.regenerate_piece_barcode(p_piece_id uuid) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
                declare
                  p record;
                    new_bc text;
                      tries int := 0;
                      begin
                        select * into p from public.pieces where id = p_piece_id for update;
                          if not found then raise exception 'PIECE_NOT_FOUND'; end if;
                            if not public.has_permission('edit_piece', p.store_id) then raise exception 'NOT_AUTHORIZED'; end if;
                              if p.barcode is null then raise exception 'NO_BARCODE'; end if;

                                -- next number from the store's sequence; skip any number already used or cancelled
                                  loop
                                      new_bc := public.next_piece_barcode(p.store_id, 'gold');
                                          tries := tries + 1;
                                              exit when not exists (select 1 from public.pieces where barcode = new_bc)
                                                        and not exists (select 1 from public.piece_barcode_history where old_barcode = new_bc);
                                                            if tries >= 20 then raise exception 'BARCODE_COLLISION'; end if;
                                                              end loop;

                                                                insert into public.piece_barcode_history (store_id, piece_id, old_barcode, new_barcode, changed_by)
                                                                  values (p.store_id, p.id, p.barcode, new_bc, auth.uid());

                                                                    -- the chip still holds the old EPC until it is programmed again
                                                                      update public.pieces set barcode = new_bc, rfid_epc = null, rfid_encoded_at = null where id = p.id;
                                                                        return new_bc;
                                                                        end $$;


--
-- Name: register_new_company(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.register_new_company(company_name text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  new_store_id uuid;
  uid uuid := auth.uid();
  user_email text;
begin
  if uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if exists (select 1 from public.staff where user_id = uid) then
    raise exception 'ALREADY_HAS_COMPANY';
  end if;
  if company_name is null or length(trim(company_name)) = 0 then
    raise exception 'COMPANY_NAME_REQUIRED';
  end if;

  select email into user_email from auth.users where id = uid;

  insert into public.stores (name) values (trim(company_name)) returning id into new_store_id;

  insert into public.staff (id, user_id, store_id, full_name, role, permissions)
  values (
    gen_random_uuid(), uid, new_store_id, split_part(coalesce(user_email, ''), '@', 1), 'owner',
    jsonb_build_object(
      'view_inventory', true, 'add_piece', true, 'edit_piece', true, 'delete_piece', true,
      'view_customers', true, 'add_customers', true, 'edit_customers', true,
      'view_traders', true, 'add_traders', true, 'edit_traders', true,
      'view_invoices', true, 'create_invoice', true, 'delete_invoice', true,
      'view_reports', true, 'view_profit_report', true, 'edit_settings', true,
      'manage_staff', true, 'manage_gold_price', true, 'manage_subscription', true
    )
  );

  insert into public.subscriptions (store_id, plan_id, status, trial_end)
  select new_store_id, p.id, 'trialing', now() + interval '30 days'
  from public.plans p where p.key = 'pro';

  return new_store_id;
end;
$$;


--
-- Name: register_new_company(text, boolean, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.register_new_company(company_name text, terms_accepted boolean DEFAULT false, terms_version text DEFAULT '1.0'::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  new_store_id uuid;
  uid uuid := auth.uid();
  user_email text;
begin
  if uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if company_name is null or length(trim(company_name)) = 0 then
    raise exception 'COMPANY_NAME_REQUIRED';
  end if;
  if not terms_accepted then
    raise exception 'TERMS_NOT_ACCEPTED';
  end if;
  if exists (
    select 1 from public.staff s
    join public.stores st on st.id = s.store_id
    where s.user_id = uid and lower(trim(st.name)) = lower(trim(company_name))
  ) then
    raise exception 'ALREADY_HAS_THIS_COMPANY';
  end if;

  select email into user_email from auth.users where id = uid;

  insert into public.stores (name, terms_accepted_at, terms_accepted_version)
  values (trim(company_name), now(), terms_version)
  returning id into new_store_id;

  insert into public.staff (id, user_id, store_id, full_name, role, permissions)
  values (
    gen_random_uuid(), uid, new_store_id, split_part(coalesce(user_email, ''), '@', 1), 'owner',
    jsonb_build_object(
      'view_inventory', true, 'add_piece', true, 'edit_piece', true, 'delete_piece', true,
      'view_customers', true, 'add_customers', true, 'edit_customers', true,
      'view_traders', true, 'add_traders', true, 'edit_traders', true,
      'view_invoices', true, 'create_invoice', true, 'edit_invoice', true, 'delete_invoice', true,
      'view_reports', true, 'view_profit_report', true, 'edit_settings', true,
      'manage_staff', true, 'manage_gold_price', true, 'manage_subscription', true,
      'contact_support', true, 'view_repairs', true, 'add_repair', true, 'edit_repair', true
    )
  );

  insert into public.subscriptions (store_id, plan_id, status, trial_end)
  select new_store_id, p.id, 'trialing', now() + interval '30 days'
  from public.plans p where p.key = 'pro';

  return new_store_id;
end;
$$;


--
-- Name: replace_piece_chip(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.replace_piece_chip(p_piece_id uuid, p_old_epc text, p_new_epc text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
                declare
                  p record;
                  begin
                    select * into p from public.pieces where id = p_piece_id for update;
                      if not found then raise exception 'PIECE_NOT_FOUND'; end if;
                        if not public.has_permission('edit_piece', p.store_id) then raise exception 'NOT_AUTHORIZED'; end if;
                          if p_new_epc is null or p_new_epc !~ '^[0-9A-F]{24}$' then raise exception 'INVALID_EPC'; end if;
                            if exists (select 1 from public.pieces where rfid_epc = p_new_epc and id <> p.id)
                                 or exists (select 1 from public.piece_chip_history where old_epc = p_new_epc) then
                                     raise exception 'EPC_IN_USE';
                                       end if;

                                         insert into public.piece_chip_history (store_id, piece_id, old_epc, new_epc, changed_by)
                                           values (p.store_id, p.id, p_old_epc, p_new_epc, auth.uid());

                                             update public.pieces set rfid_epc = p_new_epc, rfid_encoded_at = now() where id = p.id;
                                               return p_new_epc;
                                               end $_$;


--
-- Name: reset_invoice_sequence(uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reset_invoice_sequence(target_store_id uuid, new_seq integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if not public.has_permission('edit_settings', target_store_id) then
    raise exception 'NOT_AUTHORIZED';
  end if;

  if new_seq < 1 then
    raise exception 'INVALID_SEQUENCE';
  end if;

  update public.stores
    set next_invoice_seq = new_seq,
        next_invoice_seq_year = extract(year from now())::integer
    where id = target_store_id;
end;
$$;


--
-- Name: reset_piece_barcode_sequence(uuid, text, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reset_piece_barcode_sequence(target_store_id uuid, category text, new_seq bigint) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
                                                                                                                                                                      begin
                                                                                                                                                                        perform reset_piece_barcode_sequence(target_store_id, category, new_seq, null::smallint,
                                                                                                                                                                            (select case when category = 'diamond' then piece_barcode_prefix_diamond else piece_barcode_prefix_gold end
                                                                                                                                                                                   from stores where id = barcode_counter_store(target_store_id)));
                                                                                                                                                                                   end;
                                                                                                                                                                                   $$;


--
-- Name: reset_piece_barcode_sequence(uuid, text, bigint, smallint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reset_piece_barcode_sequence(target_store_id uuid, category text, new_seq bigint, seq_width smallint DEFAULT NULL::smallint) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
                                                                                                                                                                                   begin
                                                                                                                                                                                     perform reset_piece_barcode_sequence(target_store_id, category, new_seq, seq_width,
                                                                                                                                                                                         (select case when category = 'diamond' then piece_barcode_prefix_diamond else piece_barcode_prefix_gold end
                                                                                                                                                                                                from stores where id = barcode_counter_store(target_store_id)));
                                                                                                                                                                                                end;
                                                                                                                                                                                                $$;


--
-- Name: reset_piece_barcode_sequence(uuid, text, bigint, smallint, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reset_piece_barcode_sequence(target_store_id uuid, category text, new_seq bigint, seq_width smallint DEFAULT NULL::smallint, new_prefix text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
                                                                                                                                                                                                                                                                                                  $$;


--
-- Name: restore_invoice(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.restore_invoice(target_invoice_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  inv record;
  actor_staff_id uuid;
  restored_status text;
begin
  select * into inv from public.invoices where id = target_invoice_id;
  if inv is null then raise exception 'INVOICE_NOT_FOUND'; end if;
  if not public.has_permission('delete_invoice', inv.store_id) then raise exception 'NOT_AUTHORIZED'; end if;
  if inv.status != 'cancelled' then raise exception 'NOT_CANCELLED'; end if;

  select id into actor_staff_id from public.staff where user_id = auth.uid() and store_id = inv.store_id limit 1;

  restored_status := case when inv.total_amount - coalesce(inv.amount_paid, 0) <= 0.009 then 'paid' else 'unpaid' end;
  update public.invoices set status = restored_status where id = target_invoice_id;

  if inv.type = 'sale' then
    update public.pieces set status = 'sold'
    where id in (select piece_id from public.invoice_items where invoice_id = target_invoice_id and piece_id is not null and returned_item_id is null);
    update public.pieces set status = 'available'
    where id in (select piece_id from public.invoice_items where invoice_id = target_invoice_id and piece_id is not null and returned_item_id is not null);
  elsif inv.type in ('buyTrader', 'buyRetail') then
    update public.pieces set status = 'available'
    where id in (select piece_id from public.invoice_items where invoice_id = target_invoice_id and piece_id is not null);
  end if;

  insert into public.cash_movements (store_id, box, direction, amount, currency, fx_amount, fx_currency, description, created_by, invoice_id)
  select store_id, box, direction, amount, currency, fx_amount, fx_currency, 'استعادة فاتورة ' || inv.invoice_number, actor_staff_id, target_invoice_id
  from public.cash_movements where invoice_id = target_invoice_id
    and coalesce(description, '') not like 'إلغاء فاتورة%' and coalesce(description, '') not like 'استعادة فاتورة%';

  insert into public.customer_debts (store_id, customer_id, invoice_id, movement_type, cash_amount, gold_grams_24k, notes, created_by)
  select store_id, customer_id, invoice_id, movement_type, cash_amount, gold_grams_24k, 'استعادة فاتورة ' || inv.invoice_number, actor_staff_id
  from public.customer_debts where invoice_id = target_invoice_id
    and coalesce(notes, '') not like 'إلغاء فاتورة%' and coalesce(notes, '') not like 'استعادة فاتورة%';

  insert into public.trader_movements (store_id, trader_id, invoice_id, movement_type, weight_grams, karat, gold_24k_equivalent, fab_fee_amount, notes)
  select store_id, trader_id, invoice_id, movement_type, weight_grams, karat, gold_24k_equivalent, fab_fee_amount, 'استعادة فاتورة ' || inv.invoice_number
  from public.trader_movements where invoice_id = target_invoice_id
    and coalesce(notes, '') not like 'إلغاء فاتورة%' and coalesce(notes, '') not like 'استعادة فاتورة%';
end;
$$;


--
-- Name: revert_gift(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.revert_gift(target_gift_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare g record; actor uuid;
begin
  select * into g from public.inventory_gifts where id = target_gift_id for update;
  if g is null then raise exception 'السجل غير موجود'; end if;
  if not public.has_permission('give_gifts', g.store_id) then
    raise exception 'ليس لديك صلاحية' using errcode = '42501';
  end if;
  if g.status <> 'active' then raise exception 'هذه الهدية أُعيدت مسبقاً'; end if;
  select id into actor from public.staff where user_id = auth.uid() and store_id = g.store_id limit 1;

  update public.pieces set status = 'available' where id = g.piece_id and status = 'gifted';
  if g.expense_entry_id is not null then delete from public.expense_entries where id = g.expense_entry_id; end if;
  update public.inventory_gifts set status = 'reverted', reverted_at = now(), expense_entry_id = null where id = g.id;
  insert into public.piece_movements (store_id, piece_id, event_type, note, created_by)
  values (g.store_id, g.piece_id, 'gift_reverted', 'رجوع هدية للمخزن (كانت إلى ' || g.recipient || ')', actor);
end;
$$;


--
-- Name: rfid_device_done(text, uuid, boolean, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rfid_device_done(p_key text, p_job uuid, p_ok boolean, p_msg text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare st uuid; j record;
begin
  select id into st from stores where rfid_device_key is not null and length(p_key) >= 12 and rfid_device_key = upper(trim(p_key));
  if st is null then raise exception 'رمز الربط غير صحيح'; end if;
  select * into j from rfid_write_jobs where id = p_job and store_id = st and status in ('pending','working');
  if j.id is null then return; end if;
  update rfid_write_jobs set status = case when p_ok then 'done' else 'failed' end, message = left(p_msg, 300), done_at = now() where id = j.id;
  if p_ok then update pieces set rfid_epc = j.epc, rfid_encoded_at = now() where id = j.piece_id and store_id = st; end if;
end $$;


--
-- Name: rfid_device_hello(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rfid_device_hello(p_key text) RETURNS jsonb
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select jsonb_build_object('store', name, 'prefix', upper(substr(replace(id::text, '-', ''), 1, 8)))
    from stores where rfid_device_key is not null and length(p_key) >= 12 and rfid_device_key = upper(trim(p_key));
$$;


--
-- Name: rfid_device_key_reset(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rfid_device_key_reset(p_store uuid) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare k text;
begin
  if not has_permission('edit_piece', p_store) then raise exception 'ليس لديك صلاحية' using errcode = '42501'; end if;
  k := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));
  update stores set rfid_device_key = k where id = p_store;
  return k;
end $$;


--
-- Name: rfid_device_next(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rfid_device_next(p_key text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare st uuid; j record;
begin
  select id into st from stores where rfid_device_key is not null and length(p_key) >= 12 and rfid_device_key = upper(trim(p_key));
  if st is null then raise exception 'رمز الربط غير صحيح'; end if;
  update rfid_write_jobs set status = 'cancelled', message = 'انتهت المهلة'
   where store_id = st and status in ('pending','working') and created_at < now() - interval '5 minutes';
  select * into j from rfid_write_jobs where store_id = st and status = 'pending' order by created_at limit 1 for update skip locked;
  if j.id is null then return null; end if;
  update rfid_write_jobs set status = 'working' where id = j.id;
  return jsonb_build_object('id', j.id, 'barcode', j.barcode, 'epc', j.epc);
end $$;


--
-- Name: sale_invoice_change_customer(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sale_invoice_change_customer(p_invoice uuid, p_customer uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare inv record; newc record; oldname text; rem numeric; me uuid; alloc numeric;
begin
  select * into inv from invoices where id = p_invoice for update;
  if inv is null then raise exception 'الفاتورة غير موجودة'; end if;
  if not has_permission('edit_invoice', inv.store_id) then raise exception 'ليس لديك صلاحية تعديل الفواتير' using errcode = '42501'; end if;
  if inv.type <> 'sale' or inv.status = 'cancelled' then raise exception 'يمكن تغيير الزبون لفواتير البيع غير الملغاة فقط'; end if;
  select id, name into newc from customers where id = p_customer and store_id in (select org_store_ids(inv.store_id));
  if newc is null then raise exception 'الزبون غير موجود'; end if;
  if inv.customer_id = newc.id then return; end if;
  select name into oldname from customers where id = inv.customer_id;
  select id into me from staff where user_id = auth.uid() and store_id = inv.store_id limit 1;
  -- the old customer's later payments that were applied to this invoice go back to him as credit
  if inv.customer_id is not null then
    select coalesce(sum(case when movement_type = 'debt_decrease' then cash_amount else -cash_amount end), 0) into alloc
      from customer_debts where invoice_id = inv.id and customer_id = inv.customer_id and source = 'allocation';
    if alloc > 0.009 then
      insert into customer_debts (store_id, customer_id, invoice_id, movement_type, cash_amount, gold_grams_24k, notes, source, created_by) values
        (inv.store_id, inv.customer_id, inv.id, 'debt_increase', alloc, 0, 'إلغاء تخصيص للفاتورة ' || inv.invoice_number || ' (نُقلت إلى ' || newc.name || ')', 'allocation', me),
        (inv.store_id, inv.customer_id, null, 'debt_decrease', alloc, 0, 'إلغاء تخصيص للفاتورة ' || inv.invoice_number || ' (نُقلت إلى ' || newc.name || ')', 'allocation', me);
      update invoices set amount_paid = greatest(coalesce(amount_paid, 0) - alloc, 0), status = case when status = 'paid' then 'unpaid' else status end
       where id = inv.id returning * into inv;
    end if;
  end if;
  rem := round(inv.total_amount - coalesce(inv.amount_paid, 0), 2);
  update invoices set customer_id = newc.id where id = inv.id;
  if rem > 0.009 and inv.customer_id is not null then
    insert into customer_debts (store_id, customer_id, invoice_id, movement_type, cash_amount, gold_grams_24k, notes, source, created_by)
    values (inv.store_id, inv.customer_id, inv.id, 'debt_decrease', rem, 0, 'نقل دين الفاتورة ' || inv.invoice_number || ' إلى ' || newc.name, 'invoice_edit', me);
  end if;
  if rem > 0.009 then
    insert into customer_debts (store_id, customer_id, invoice_id, movement_type, cash_amount, gold_grams_24k, notes, source, created_by)
    values (inv.store_id, newc.id, inv.id, 'debt_increase', rem, 0, 'دين الفاتورة ' || inv.invoice_number || ' منقول من ' || coalesce(oldname, 'زبون سابق'), 'invoice_edit', me);
  end if;
  if inv.customer_id is not null then perform gm_allocate_customer_credit(inv.store_id, inv.customer_id); end if;
  perform gm_allocate_customer_credit(inv.store_id, newc.id);
end $$;


--
-- Name: save_expense_category(uuid, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.save_expense_category(p_store uuid, p_name text, p_id uuid DEFAULT NULL::uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare nm text := nullif(trim(p_name), ''); rid uuid;
begin
  if not gm_can_expense(p_store) or not is_store_member(p_store) then raise exception 'ليس لديك صلاحية' using errcode = '42501'; end if;
  if nm is null then raise exception 'اكتب اسم نوع المصروف'; end if;
  if exists (select 1 from expense_categories where store_id = p_store and name = nm and id is distinct from p_id) then
    raise exception 'هذا النوع موجود مسبقاً';
  end if;
  if p_id is null then
    insert into expense_categories (store_id, name) values (p_store, nm) returning id into rid;
  else
    if (select name from expense_categories where id = p_id and store_id = p_store) = 'هدايا' then raise exception 'لا يمكن تغيير اسم نوع الهدايا'; end if;
    update expense_categories set name = nm where id = p_id and store_id = p_store returning id into rid;
  end if;
  return rid;
end $$;


--
-- Name: seed_default_zebra_label_fields(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.seed_default_zebra_label_fields() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  insert into zebra_label_fields (store_id, column_num, row_order, content_type, font_size) values
    (new.id, 1, 1, 'weight', 20),
    (new.id, 1, 2, 'karat', 20),
    (new.id, 1, 3, 'mc', 20),
    (new.id, 1, 10, 'description', 20),
    (new.id, 1, 11, 'barcode_number', 20),
    (new.id, 1, 12, 'barcode_graphic', 5),
    (new.id, 1, 13, 'company_name', 20);
  return new;
end;
$$;


--
-- Name: send_branch_transfer(uuid, uuid, text[], text, jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.send_branch_transfer(p_from uuid, p_to uuid, p_barcodes text[] DEFAULT NULL::text[], p_notes text DEFAULT NULL::text, p_scrap jsonb DEFAULT NULL::jsonb, p_cash jsonb DEFAULT NULL::jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
                                            declare org uuid; me uuid; tid uuid; num text; bc text; pc record; dp record; n int := 0;
                                              s jsonb; k int; w numeric; left_w numeric; take numeric; lot record; draws jsonb; fab_sum numeric; box text;
                                                amt numeric; cbox text; cm uuid; cur_from text; cur_to text;
                                                begin
                                                  if not has_permission('stock_transfers', p_from) then
                                                      raise exception 'ليس لديك صلاحية نقل البضاعة بين الفروع' using errcode = '42501';
                                                        end if;
                                                          if p_to is null or p_to = p_from or p_to not in (select org_store_ids(p_from)) then
                                                              raise exception 'اختر فرعاً آخر من نفس المنشأة';
                                                                end if;
                                                                  select organization_id, upper(currency) into org, cur_from from stores where id = p_from;
                                                                    select upper(currency) into cur_to from stores where id = p_to;
                                                                      select id into me from staff where user_id = auth.uid() and store_id = p_from limit 1;

                                                                        perform pg_advisory_xact_lock(hashtext('branch_transfer:' || coalesce(org, p_from)::text));
                                                                          select 'TRF-' || lpad((coalesce(max(nullif(regexp_replace(transfer_number, '\D', '', 'g'), '')::int), 0) + 1)::text, 6, '0')
                                                                              into num from branch_transfers where coalesce(organization_id, from_store_id) = coalesce(org, p_from);
                                                                                insert into branch_transfers (organization_id, from_store_id, to_store_id, transfer_number, notes, created_by)
                                                                                    values (org, p_from, p_to, num, nullif(trim(p_notes), ''), me) returning id into tid;

                                                                                      -- pieces
                                                                                        foreach bc in array coalesce(p_barcodes, array[]::text[]) loop
                                                                                            bc := nullif(trim(bc), '');
                                                                                                continue when bc is null;
                                                                                                    select * into pc from pieces where store_id = p_from and barcode = bc for update;
                                                                                                        if found then
                                                                                                              if pc.status <> 'available' then raise exception 'القطعة % غير متاحة للنقل (حالتها: %)', bc, pc.status; end if;
                                                                                                                    update pieces set status = 'in_transit' where id = pc.id;
                                                                                                                          insert into branch_transfer_items (transfer_id, kind, piece_id, barcode, description, karat, weight_grams, photo_url)
                                                                                                                                  values (tid, 'piece', pc.id, pc.barcode, coalesce(pc.description_ar, pc.piece_type), pc.karat, pc.weight_grams, pc.photo_url);
                                                                                                                                        insert into piece_movements (store_id, piece_id, event_type, note, created_by)
                                                                                                                                                values (p_from, pc.id, 'transfer_out', 'نقل إلى فرع آخر بسند ' || num, me);
                                                                                                                                                    else
                                                                                                                                                          select * into dp from diamond_pieces where store_id = p_from and barcode = bc for update;
                                                                                                                                                                if not found then raise exception 'القطعة % غير موجودة في هذا الفرع', bc; end if;
                                                                                                                                                                      if dp.status <> 'available' then raise exception 'القطعة % غير متاحة للنقل (حالتها: %)', bc, dp.status; end if;
                                                                                                                                                                            update diamond_pieces set status = 'in_transit' where id = dp.id;
                                                                                                                                                                                  insert into branch_transfer_items (transfer_id, kind, diamond_piece_id, barcode, description, karat, weight_grams, photo_url)
                                                                                                                                                                                          values (tid, 'piece', dp.id, dp.barcode, dp.description_ar, dp.gold_karat, dp.gold_weight_grams, dp.photo_url);
                                                                                                                                                                                              end if;
                                                                                                                                                                                                  n := n + 1;
                                                                                                                                                                                                    end loop;

                                                                                                                                                                                                      -- scrap: [{karat, weight}] from «كسر <karat>», oldest lot first
                                                                                                                                                                                                        for s in select * from jsonb_array_elements(coalesce(p_scrap, '[]'::jsonb)) loop
                                                                                                                                                                                                            k := (s->>'karat')::int; w := round((s->>'weight')::numeric, 3);
                                                                                                                                                                                                                if k is null or w is null or w <= 0 then raise exception 'وزن كسر غير صحيح'; end if;
                                                                                                                                                                                                                    box := 'كسر ' || k; left_w := w; draws := '[]'::jsonb; fab_sum := 0;
                                                                                                                                                                                                                        for lot in select * from gold_stock_lots where store_id = p_from and box_name = box and weight_grams_remaining > 0
                                                                                                                                                                                                                                       order by created_at, id for update loop
                                                                                                                                                                                                                                             exit when left_w <= 0;
                                                                                                                                                                                                                                                   take := least(left_w, lot.weight_grams_remaining);
                                                                                                                                                                                                                                                         update gold_stock_lots set weight_grams_remaining = weight_grams_remaining - take where id = lot.id;
                                                                                                                                                                                                                                                               draws := draws || jsonb_build_object('lot_id', lot.id, 'w', take);
                                                                                                                                                                                                                                                                     fab_sum := fab_sum + take * coalesce(lot.cost_fabrication_per_gram, 0);
                                                                                                                                                                                                                                                                           left_w := left_w - take;
                                                                                                                                                                                                                                                                               end loop;
                                                                                                                                                                                                                                                                                   if left_w > 0.0005 then raise exception 'المتوفر في صندوق % أقل من %غ', box, w; end if;
                                                                                                                                                                                                                                                                                       insert into branch_transfer_items (transfer_id, kind, description, karat, weight_grams, box_name, fab_per_gram, lot_draws)
                                                                                                                                                                                                                                                                                             values (tid, 'scrap', box, k, w, box, round(fab_sum / w, 4), draws);
                                                                                                                                                                                                                                                                                                 n := n + 1;
                                                                                                                                                                                                                                                                                                   end loop;

                                                                                                                                                                                                                                                                                                     -- cash: {amount, box: main|bank}
                                                                                                                                                                                                                                                                                                       if p_cash is not null and coalesce((p_cash->>'amount')::numeric, 0) > 0 then
                                                                                                                                                                                                                                                                                                           amt := round((p_cash->>'amount')::numeric, 2);
                                                                                                                                                                                                                                                                                                               cbox := case when p_cash->>'box' = 'bank' then 'bank' else 'main' end;
                                                                                                                                                                                                                                                                                                                   if cur_from is distinct from cur_to then raise exception 'لا يمكن نقل النقد بين فرعين بعملتين مختلفتين'; end if;
                                                                                                                                                                                                                                                                                                                       insert into cash_movements (store_id, box, direction, amount, description, created_by)
                                                                                                                                                                                                                                                                                                                             values (p_from, cbox, 'out', amt, 'نقل نقد إلى فرع آخر بسند ' || num, me) returning id into cm;
                                                                                                                                                                                                                                                                                                                                 if cbox = 'main' then
                                                                                                                                                                                                                                                                                                                                       insert into daily_cash_log (store_id, operation_type, direction, amount, notes, created_by, cash_movement_id)
                                                                                                                                                                                                                                                                                                                                               values (p_from, 'نقل نقد لفرع آخر', 'out', amt, 'سند ' || num, me, cm);
                                                                                                                                                                                                                                                                                                                                                   end if;
                                                                                                                                                                                                                                                                                                                                                       insert into branch_transfer_items (transfer_id, kind, description, amount, cash_box)
                                                                                                                                                                                                                                                                                                                                                             values (tid, 'cash', case when cbox = 'bank' then 'نقد (بنك)' else 'نقد' end, amt, cbox);
                                                                                                                                                                                                                                                                                                                                                                 n := n + 1;
                                                                                                                                                                                                                                                                                                                                                                   end if;

                                                                                                                                                                                                                                                                                                                                                                     if n = 0 then raise exception 'أضف قطعة أو كسراً أو نقداً'; end if;
                                                                                                                                                                                                                                                                                                                                                                       return jsonb_build_object('id', tid, 'transfer_number', num, 'items', n);
                                                                                                                                                                                                                                                                                                                                                                       end $$;


--
-- Name: set_branch_own_gold_price(uuid, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_branch_own_gold_price(p_store uuid, p_own boolean) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
                                                                                                                                                  $$;


--
-- Name: set_gold_ounce_price(uuid, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_gold_ounce_price(target_store_id uuid, ounce numeric, rate numeric) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
                                                                                              $$;


--
-- Name: set_piece_weights(uuid, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_piece_weights(p_piece uuid, p_weight numeric, p_acc numeric) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare pc record; me uuid; cut numeric;
begin
  select id, store_id, barcode, karat, weight_grams into pc from pieces where id = p_piece for update;
    if pc is null then raise exception 'القطعة غير موجودة'; end if;
      if not has_permission('edit_sale_weights', pc.store_id) then
          raise exception 'ليس لديك صلاحية تعديل أوزان القطع' using errcode = '42501';
            end if;
              if p_weight is null or p_weight <= 0 then raise exception 'الوزن القائم يجب أن يكون أكبر من صفر'; end if;
                if p_acc is null or p_acc <= 0 then raise exception 'الوزن المحاسبي يجب أن يكون أكبر من صفر'; end if;

                  cut := round(coalesce(pc.weight_grams, 0) - p_weight, 3);
                    if cut > 0 then
                        if pc.karat is null then raise exception 'القطعة بدون عيار، ما بنقدر نضيف الفرق لصندوق الكسر'; end if;
                            select id into me from staff where user_id = auth.uid() and store_id = pc.store_id limit 1;
                                insert into gold_stock_lots (store_id, karat, weight_grams_total, weight_grams_remaining, cost_fabrication_per_gram,
                                        notes, box_name, created_by)
                                              values (pc.store_id, pc.karat, cut, cut, 0, 'من تقصير القطعة ' || pc.barcode, 'كسر ' || pc.karat, me);
                                                end if;

                                                  update pieces set weight_grams = round(p_weight, 3), accounting_weight_grams = round(p_acc, 3) where id = pc.id;
                                                  end $$;


--
-- Name: set_voucher_date(uuid, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_voucher_date(p_cash_movement uuid, p_date date) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  cm record;
  today date := (now() at time zone 'Asia/Dubai')::date;
  new_ts timestamptz;
begin
  select * into cm from cash_movements where id = p_cash_movement;
  if cm is null then raise exception 'السند غير موجود'; end if;
  if cm.invoice_id is not null then raise exception 'هذه الحركة من فاتورة — عدّل تاريخ الفاتورة من صفحتها'; end if;
  if p_date is null or p_date > today or p_date < today - 3650 then raise exception 'اختر تاريخاً سابقاً أو اليوم'; end if;
  if not is_store_member(cm.store_id) then raise exception 'ليس لديك صلاحية' using errcode = '42501'; end if;
  if cm.trader_movement_id is not null and not has_permission('edit_traders', cm.store_id) then
    raise exception 'ليس لديك صلاحية تعديل حسابات التجار' using errcode = '42501';
  end if;
  if exists (select 1 from customer_debts where cash_movement_id = cm.id) and not has_permission('edit_customers', cm.store_id) then
    raise exception 'ليس لديك صلاحية تعديل حسابات الزبائن' using errcode = '42501';
  end if;
  if exists (select 1 from expense_entries where cash_movement_id = cm.id) and not gm_can_expense(cm.store_id) then
    raise exception 'ليس لديك صلاحية تعديل المصاريف' using errcode = '42501';
  end if;

  new_ts := (p_date + (cm.created_at at time zone 'Asia/Dubai')::time) at time zone 'Asia/Dubai';
  update cash_movements set created_at = new_ts where id = cm.id;
  update daily_cash_log set created_at = new_ts where cash_movement_id = cm.id;
  update customer_debts set created_at = new_ts where cash_movement_id = cm.id;
  update expense_entries set created_at = new_ts where cash_movement_id = cm.id;
  if cm.trader_movement_id is not null then
    update trader_movements set created_at = new_ts where id = cm.trader_movement_id;
  end if;
end $$;


--
-- Name: staff_heartbeat(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.staff_heartbeat(p_store uuid, p_page text DEFAULT NULL::text) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  insert into public.staff_presence (staff_id, store_id, last_seen_at, last_page)
  select s.id, s.store_id, now(), left(p_page, 80)
  from public.staff s
  where s.user_id = auth.uid() and s.store_id = p_store
  on conflict (staff_id) do update
    set last_seen_at = excluded.last_seen_at, last_page = excluded.last_page;
$$;


--
-- Name: stock_in_from_party(uuid, uuid[], jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.stock_in_from_party(target_party_id uuid, return_piece_ids uuid[], new_lines jsonb, p_notes text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  pt record; actor uuid; vid uuid; num text; pc record; ln jsonb; gp numeric;
  k int; wt numeric; aw numeric; fab numeric; bc text; newid uuid; cnt int := 0;
begin
  select * into pt from public.stock_parties where id = target_party_id;
  if pt is null then raise exception 'الجهة غير موجودة'; end if;
  if not public.has_permission('stock_transfers', pt.store_id) then
    raise exception 'ليس لديك صلاحية إخراج/إدخال البضاعة' using errcode = '42501';
  end if;
  select id into actor from public.staff where user_id = auth.uid() and store_id = pt.store_id limit 1;

  perform 1 from public.stores where id = pt.store_id for update;
  num := 'IN-' || lpad((select count(*) + 1 from public.stock_vouchers where store_id = pt.store_id and direction = 'in')::text, 5, '0');
  insert into public.stock_vouchers (store_id, party_id, direction, voucher_number, notes, created_by)
  values (pt.store_id, pt.id, 'in', num, nullif(trim(p_notes), ''), actor) returning id into vid;

  -- 1) same pieces returning unchanged
  for pc in select * from public.pieces where id = any(coalesce(return_piece_ids, '{}')) for update loop
    if pc.store_id <> pt.store_id then raise exception 'قطعة تابعة لشركة أخرى'; end if;
    if pc.status not in ('in_box', 'at_intermediary') then raise exception 'القطعة % ليست لدى جهة (حالتها: %)', pc.barcode, pc.status; end if;
    select price_per_gram into gp from public.gold_prices where store_id = pc.store_id and karat = pc.karat;
    aw := coalesce(pc.accounting_weight_grams, pc.weight_grams, 0);
    insert into public.stock_voucher_lines (voucher_id, store_id, party_id, direction, piece_id, barcode, karat,
      weight_grams, accounting_weight_grams, fab_per_gram, gold_price_per_gram, cost_value)
    values (vid, pc.store_id, pt.id, 'in', pc.id, pc.barcode, pc.karat, pc.weight_grams, aw,
      coalesce(pc.cost_fabrication_per_gram, 0), gp, round(aw * (coalesce(gp, 0) + coalesce(pc.cost_fabrication_per_gram, 0)), 2));
    update public.pieces set status = 'available' where id = pc.id;
    insert into public.piece_movements (store_id, piece_id, event_type, note, created_by)
    values (pc.store_id, pc.id, 'stock_in', 'رجوع بالسند ' || num || ' من ' || pt.name, actor);
    cnt := cnt + 1;
  end loop;

  -- 2) new pieces (e.g. the result of splitting / modifying)
  for ln in select * from jsonb_array_elements(coalesce(new_lines, '[]'::jsonb)) loop
    k := (ln->>'karat')::int;
    wt := (ln->>'weight')::numeric;
    aw := coalesce(nullif(ln->>'acc_weight', '')::numeric, wt);
    fab := coalesce(nullif(ln->>'fab_per_gram', '')::numeric, 0);
    if k not in (18, 21, 22, 24) then raise exception 'عيار غير صحيح'; end if;
    if wt is null or wt <= 0 or aw <= 0 or fab < 0 then raise exception 'وزن أو مصنعية غير صحيحة'; end if;
    bc := public.next_piece_barcode(pt.store_id, 'gold');
    insert into public.pieces (store_id, barcode, photo_url, weight_grams, accounting_weight_grams, karat, color, status,
      created_by, cost_fabrication_per_gram, description_ar, piece_type, category1, category2)
    values (pt.store_id, bc, nullif(ln->>'photo_url', ''), wt, aw, k, coalesce(nullif(ln->>'color', ''), 'Gold'), 'available',
      actor, fab, nullif(ln->>'description_ar', ''), nullif(ln->>'piece_type', ''), nullif(ln->>'category1', ''), nullif(ln->>'category2', ''))
    returning id into newid;
    select price_per_gram into gp from public.gold_prices where store_id = pt.store_id and karat = k;
    insert into public.stock_voucher_lines (voucher_id, store_id, party_id, direction, piece_id, barcode, karat,
      weight_grams, accounting_weight_grams, fab_per_gram, gold_price_per_gram, cost_value)
    values (vid, pt.store_id, pt.id, 'in', newid, bc, k, wt, aw, fab, gp, round(aw * (coalesce(gp, 0) + fab), 2));
    insert into public.piece_movements (store_id, piece_id, event_type, note, created_by)
    values (pt.store_id, newid, 'stock_in', 'قطعة جديدة بالسند ' || num || ' من ' || pt.name, actor);
    cnt := cnt + 1;
  end loop;

  if cnt = 0 then raise exception 'لا توجد أي قطعة في السند'; end if;
  return vid;
end;
$$;


--
-- Name: stock_in_from_party(uuid, uuid[], jsonb, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.stock_in_from_party(target_party_id uuid, return_piece_ids uuid[], new_lines jsonb, p_notes text, p_return_box text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  pt record; actor uuid; vid uuid; num text; pc record; ln jsonb; gp numeric;
  k int; wt numeric; aw numeric; fab numeric; bc text; newid uuid; cnt int := 0; rbox text := nullif(trim(p_return_box), '');
begin
  select * into pt from public.stock_parties where id = target_party_id;
  if pt is null then raise exception 'الجهة غير موجودة'; end if;
  if not public.has_permission('stock_transfers', pt.store_id) then
    raise exception 'ليس لديك صلاحية إخراج/إدخال البضاعة' using errcode = '42501';
  end if;
  select id into actor from public.staff where user_id = auth.uid() and store_id = pt.store_id limit 1;

  perform 1 from public.stores where id = pt.store_id for update;
  num := 'IN-' || lpad((select count(*) + 1 from public.stock_vouchers where store_id = pt.store_id and direction = 'in')::text, 5, '0');
  insert into public.stock_vouchers (store_id, party_id, direction, voucher_number, notes, created_by)
  values (pt.store_id, pt.id, 'in', num, nullif(trim(p_notes), ''), actor) returning id into vid;

  for pc in select * from public.pieces where id = any(coalesce(return_piece_ids, '{}')) for update loop
    if pc.store_id <> pt.store_id then raise exception 'قطعة تابعة لشركة أخرى'; end if;
    if pc.status not in ('in_box', 'at_intermediary') then raise exception 'القطعة % ليست لدى جهة (حالتها: %)', pc.barcode, pc.status; end if;
    select price_per_gram into gp from public.gold_prices where store_id = pc.store_id and karat = pc.karat;
    aw := coalesce(pc.accounting_weight_grams, pc.weight_grams, 0);
    insert into public.stock_voucher_lines (voucher_id, store_id, party_id, direction, piece_id, barcode, karat,
      weight_grams, accounting_weight_grams, fab_per_gram, gold_price_per_gram, cost_value)
    values (vid, pc.store_id, pt.id, 'in', pc.id, pc.barcode, pc.karat, pc.weight_grams, aw,
      coalesce(pc.cost_fabrication_per_gram, 0), gp, round(aw * (coalesce(gp, 0) + coalesce(pc.cost_fabrication_per_gram, 0)), 2));
    update public.pieces set status = 'available', box_name = coalesce(rbox, box_name) where id = pc.id;
    insert into public.piece_movements (store_id, piece_id, event_type, note, created_by)
    values (pc.store_id, pc.id, 'stock_in', 'رجوع بالسند ' || num || ' من ' || pt.name || coalesce(' إلى صندوق ' || rbox, ''), actor);
    cnt := cnt + 1;
  end loop;

  for ln in select * from jsonb_array_elements(coalesce(new_lines, '[]'::jsonb)) loop
    k := (ln->>'karat')::int;
    wt := (ln->>'weight')::numeric;
    aw := coalesce(nullif(ln->>'acc_weight', '')::numeric, wt);
    fab := coalesce(nullif(ln->>'fab_per_gram', '')::numeric, 0);
    if k not in (18, 21, 22, 24) then raise exception 'عيار غير صحيح'; end if;
    if wt is null or wt <= 0 or aw <= 0 or fab < 0 then raise exception 'وزن أو مصنعية غير صحيحة'; end if;
    if nullif(trim(ln->>'box_name'), '') is null then raise exception 'اختر الصندوق لكل قطعة جديدة'; end if;
    bc := public.next_piece_barcode(pt.store_id, 'gold');
    insert into public.pieces (store_id, barcode, photo_url, weight_grams, accounting_weight_grams, karat, color, status,
      created_by, cost_fabrication_per_gram, description_ar, piece_type, category1, category2, box_name)
    values (pt.store_id, bc, nullif(ln->>'photo_url', ''), wt, aw, k, coalesce(nullif(ln->>'color', ''), 'Gold'), 'available',
      actor, fab, nullif(ln->>'description_ar', ''), nullif(ln->>'piece_type', ''), nullif(ln->>'category1', ''), nullif(ln->>'category2', ''),
      trim(ln->>'box_name'))
    returning id into newid;
    select price_per_gram into gp from public.gold_prices where store_id = pt.store_id and karat = k;
    insert into public.stock_voucher_lines (voucher_id, store_id, party_id, direction, piece_id, barcode, karat,
      weight_grams, accounting_weight_grams, fab_per_gram, gold_price_per_gram, cost_value)
    values (vid, pt.store_id, pt.id, 'in', newid, bc, k, wt, aw, fab, gp, round(aw * (coalesce(gp, 0) + fab), 2));
    insert into public.piece_movements (store_id, piece_id, event_type, note, created_by)
    values (pt.store_id, newid, 'stock_in', 'قطعة جديدة بالسند ' || num || ' من ' || pt.name, actor);
    cnt := cnt + 1;
  end loop;

  if cnt = 0 then raise exception 'لا توجد أي قطعة في السند'; end if;
  return vid;
end;
$$;


--
-- Name: stock_in_from_party(uuid, uuid[], jsonb, text, text, uuid[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.stock_in_from_party(target_party_id uuid, return_piece_ids uuid[], new_lines jsonb, p_notes text, p_return_box text, p_source_piece_ids uuid[]) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  pt record; actor uuid; vid uuid; num text; pc record; ln jsonb; gp numeric;
  k int; wt numeric; aw numeric; fab numeric; bc text; newid uuid; cnt int := 0; rbox text := nullif(trim(p_return_box), '');
  src_codes text; new_codes text[] := '{}';
  src_fab numeric := 0; loss numeric := 0; scrap_txt text[] := '{}'; cat_id uuid;
  fab_bal numeric; aw_bal numeric; held_ids uuid[]; sfab numeric;
begin
  select * into pt from public.stock_parties where id = target_party_id;
  if pt is null then raise exception 'الجهة غير موجودة'; end if;
  if not public.has_permission('stock_transfers', pt.store_id) then
    raise exception 'ليس لديك صلاحية إخراج/إدخال البضاعة' using errcode = '42501';
  end if;
  select id into actor from public.staff where user_id = auth.uid() and store_id = pt.store_id limit 1;

  select array_agg(p.id), string_agg(p.barcode, '، ' order by p.barcode) into held_ids, src_codes
    from public.pieces p
   where p.store_id = pt.store_id and p.status = 'at_intermediary' and not (p.id = any(coalesce(return_piece_ids, '{}')))
     and (select l.direction from public.stock_voucher_lines l join public.stock_vouchers v on v.id = l.voucher_id
           where l.piece_id = p.id and l.party_id = pt.id order by v.created_at desc limit 1) = 'out';

  perform 1 from public.stores where id = pt.store_id for update;
  num := 'IN-' || lpad((select count(*) + 1 from public.stock_vouchers where store_id = pt.store_id and direction = 'in')::text, 5, '0');
  insert into public.stock_vouchers (store_id, party_id, direction, voucher_number, notes, created_by)
  values (pt.store_id, pt.id, 'in', num, nullif(trim(p_notes), ''), actor) returning id into vid;

  for pc in select * from public.pieces where id = any(coalesce(return_piece_ids, '{}')) for update loop
    if pc.store_id <> pt.store_id then raise exception 'قطعة تابعة لشركة أخرى'; end if;
    if pc.status not in ('in_box', 'at_intermediary') then raise exception 'القطعة % ليست لدى جهة (حالتها: %)', pc.barcode, pc.status; end if;
    select price_per_gram into gp from public.gold_prices where store_id = pc.store_id and karat = pc.karat;
    aw := coalesce(pc.accounting_weight_grams, pc.weight_grams, 0);
    insert into public.stock_voucher_lines (voucher_id, store_id, party_id, direction, piece_id, barcode, karat,
      weight_grams, accounting_weight_grams, fab_per_gram, gold_price_per_gram, cost_value)
    values (vid, pc.store_id, pt.id, 'in', pc.id, pc.barcode, pc.karat, pc.weight_grams, aw,
      coalesce(pc.cost_fabrication_per_gram, 0), gp, round(aw * (coalesce(gp, 0) + coalesce(pc.cost_fabrication_per_gram, 0)), 2));
    update public.pieces set status = 'available', box_name = coalesce(rbox, box_name) where id = pc.id;
    insert into public.piece_movements (store_id, piece_id, event_type, note, created_by)
    values (pc.store_id, pc.id, 'stock_in', 'رجوع بالسند ' || num || ' من ' || pt.name || coalesce(' إلى صندوق ' || rbox, ''), actor);
    cnt := cnt + 1;
  end loop;

  for ln in select * from jsonb_array_elements(coalesce(new_lines, '[]'::jsonb)) loop
    k := (ln->>'karat')::int;
    wt := (ln->>'weight')::numeric;
    continue when coalesce((ln->>'to_scrap')::boolean, false);
    aw := coalesce(nullif(ln->>'acc_weight', '')::numeric, wt);
    fab := coalesce(nullif(ln->>'fab_per_gram', '')::numeric, 0);
    if k not in (18, 21, 22, 24) then raise exception 'عيار غير صحيح'; end if;
    if wt is null or wt <= 0 or aw <= 0 or fab < 0 then raise exception 'وزن أو مصنعية غير صحيحة'; end if;
    if nullif(trim(ln->>'box_name'), '') is null then raise exception 'اختر الصندوق لكل قطعة جديدة'; end if;
    bc := public.next_piece_barcode(pt.store_id, 'gold');
    insert into public.pieces (store_id, barcode, photo_url, weight_grams, accounting_weight_grams, karat, color, status,
      created_by, cost_fabrication_per_gram, description_ar, piece_type, category1, category2, box_name)
    values (pt.store_id, bc, nullif(ln->>'photo_url', ''), wt, aw, k, coalesce(nullif(ln->>'color', ''), 'Gold'), 'available',
      actor, fab, nullif(ln->>'description_ar', ''), nullif(ln->>'piece_type', ''), nullif(ln->>'category1', ''), nullif(ln->>'category2', ''),
      trim(ln->>'box_name'))
    returning id into newid;
    select price_per_gram into gp from public.gold_prices where store_id = pt.store_id and karat = k;
    insert into public.stock_voucher_lines (voucher_id, store_id, party_id, direction, piece_id, barcode, karat,
      weight_grams, accounting_weight_grams, fab_per_gram, gold_price_per_gram, cost_value)
    values (vid, pt.store_id, pt.id, 'in', newid, bc, k, wt, aw, fab, gp, round(aw * (coalesce(gp, 0) + fab), 2));
    insert into public.piece_movements (store_id, piece_id, event_type, note, created_by)
    values (pt.store_id, newid, 'stock_in', 'قطعة جديدة بالسند ' || num || ' من ' || pt.name, actor);
    new_codes := new_codes || bc;
    cnt := cnt + 1;
  end loop;

  select coalesce(sum(case l.direction when 'out' then 1 else -1 end * l.fab_per_gram * l.accounting_weight_grams), 0),
         coalesce(sum(case l.direction when 'out' then 1 else -1 end * l.accounting_weight_grams), 0)
    into fab_bal, aw_bal from public.stock_voucher_lines l where l.party_id = pt.id;
  src_fab := case when aw_bal > 0.0005 and fab_bal > 0 then fab_bal / aw_bal else 0 end;

  for ln in select * from jsonb_array_elements(coalesce(new_lines, '[]'::jsonb)) loop
    k := (ln->>'karat')::int;
    wt := (ln->>'weight')::numeric;
    continue when not coalesce((ln->>'to_scrap')::boolean, false);
    if k not in (18, 21, 22, 24) then raise exception 'عيار غير صحيح'; end if;
    if wt is null or wt <= 0 then raise exception 'وزن غير صحيح'; end if;
    wt := round(wt, 3);
    insert into public.gold_stock_lots (store_id, karat, box_name, weight_grams_total, weight_grams_remaining, cost_fabrication_per_gram, notes, created_by)
    values (pt.store_id, k, 'كسر ' || k, wt, wt, 0, 'من سند الإدخال ' || num || ' — ' || pt.name, actor);
    select price_per_gram into gp from public.gold_prices where store_id = pt.store_id and karat = k;
    sfab := round(least(src_fab, greatest(fab_bal - loss, 0) / wt), 4);
    insert into public.stock_voucher_lines (voucher_id, store_id, party_id, direction, piece_id, barcode, karat,
      weight_grams, accounting_weight_grams, fab_per_gram, gold_price_per_gram, cost_value)
    values (vid, pt.store_id, pt.id, 'in', null, 'كسر ' || k, k, wt, wt, sfab, gp, round(wt * (coalesce(gp, 0) + sfab), 2));
    loss := loss + wt * sfab;
    scrap_txt := scrap_txt || (trim(to_char(wt, 'FM999990.000')) || ' غ لصندوق كسر ' || k);
    cnt := cnt + 1;
  end loop;

  if cnt = 0 then raise exception 'لا توجد أي قطعة في السند'; end if;

  loss := round(loss, 2);
  if loss > 0 then
    select id into cat_id from public.expense_categories where store_id = pt.store_id and name = 'خسارة مصنعية' limit 1;
    if cat_id is null then insert into public.expense_categories (store_id, name) values (pt.store_id, 'خسارة مصنعية') returning id into cat_id; end if;
    insert into public.expense_entries (store_id, category_id, amount, description, created_by)
    values (pt.store_id, cat_id, loss, 'خسارة مصنعية — ' || array_to_string(scrap_txt, '، ') || ' من ' || pt.name
            || ' (متوسط المصنعية ' || trim(to_char(round(src_fab, 2), 'FM999,999,990.00')) || ' للغرام) — السند ' || num, actor);
  end if;

  if (array_length(new_codes, 1) is not null or array_length(scrap_txt, 1) is not null) and held_ids is not null then
    update public.pieces set status = 'reworked' where id = any(held_ids);
    insert into public.piece_movements (store_id, piece_id, event_type, note, created_by)
    select pt.store_id, p.id, 'reworked', 'حُوّلت في ' || pt.name || ' — السند ' || num || ': ' || array_to_string(new_codes || scrap_txt, '، '), actor
      from public.pieces p where p.id = any(held_ids);
  end if;
  return vid;
end;
$$;


--
-- Name: stock_in_piece_update(uuid, numeric, numeric, numeric, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.stock_in_piece_update(p_line uuid, p_weight numeric, p_acc numeric, p_fab numeric, p_description text, p_box text, p_photo_url text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare l record; pc record; gp numeric; actor uuid; aw numeric; ch text[] := '{}';
begin
  select * into l from stock_voucher_lines where id = p_line for update;
  if l is null or l.direction <> 'in' or l.piece_id is null then raise exception 'السطر غير موجود أو ليس قطعة مُدخلة'; end if;
  if not has_permission('stock_transfers', l.store_id) then raise exception 'ليس لديك صلاحية إخراج/إدخال البضاعة' using errcode = '42501'; end if;
  select * into pc from pieces where id = l.piece_id for update;
  if pc.status <> 'available' then raise exception 'القطعة % لم تعد في المخزن (حالتها: %)', pc.barcode, pc.status; end if;
  if p_weight is null or p_weight <= 0 then raise exception 'الوزن القائم يجب أن يكون أكبر من صفر'; end if;
  aw := coalesce(nullif(p_acc, 0), p_weight);
  if aw <= 0 or coalesce(p_fab, 0) < 0 then raise exception 'وزن أو مصنعية غير صحيحة'; end if;
  if nullif(trim(p_box), '') is null then raise exception 'اختر الصندوق'; end if;
  select id into actor from staff where user_id = auth.uid() and store_id = l.store_id limit 1;

  if round(p_weight, 3) <> pc.weight_grams then ch := ch || ('القائم ' || pc.weight_grams || ' ← ' || round(p_weight, 3)); end if;
  if round(aw, 3) <> coalesce(pc.accounting_weight_grams, pc.weight_grams) then ch := ch || ('المحاسبي ' || coalesce(pc.accounting_weight_grams, pc.weight_grams) || ' ← ' || round(aw, 3)); end if;
  if coalesce(p_fab, 0) <> coalesce(pc.cost_fabrication_per_gram, 0) then ch := ch || ('المصنعية ' || coalesce(pc.cost_fabrication_per_gram, 0) || ' ← ' || coalesce(p_fab, 0)); end if;
  if trim(p_box) is distinct from pc.box_name then ch := ch || ('الصندوق ' || coalesce(pc.box_name, '—') || ' ← ' || trim(p_box)); end if;
  if nullif(trim(p_description), '') is distinct from pc.description_ar then ch := ch || 'الوصف'::text; end if;
  if nullif(p_photo_url, '') is not null then ch := ch || 'الصورة'::text; end if;
  if array_length(ch, 1) is null then return; end if;

  update pieces set weight_grams = round(p_weight, 3), accounting_weight_grams = round(aw, 3),
         cost_fabrication_per_gram = coalesce(p_fab, 0), box_name = trim(p_box),
         description_ar = nullif(trim(p_description), ''), photo_url = coalesce(nullif(p_photo_url, ''), photo_url)
   where id = pc.id;
  gp := coalesce(l.gold_price_per_gram, 0);
  update stock_voucher_lines set weight_grams = round(p_weight, 3), accounting_weight_grams = round(aw, 3),
         fab_per_gram = coalesce(p_fab, 0), cost_value = round(aw * (gp + coalesce(p_fab, 0)), 2)
   where id = l.id;
  insert into piece_movements (store_id, piece_id, event_type, note, created_by)
  values (l.store_id, pc.id, 'edited', 'تعديل من سند الإدخال: ' || array_to_string(ch, '، '), actor);
  perform gm_stock_in_rescrap(l.voucher_id);
end $$;


--
-- Name: stock_out_to_party(uuid, uuid[], text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.stock_out_to_party(target_party_id uuid, piece_ids uuid[], p_notes text DEFAULT NULL::text, p_recipient text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  pt record; actor uuid; vid uuid; num text; pc record; gp numeric; w numeric; n int := 0;
begin
  select * into pt from public.stock_parties where id = target_party_id;
  if pt is null then raise exception 'الجهة غير موجودة'; end if;
  if not public.has_permission('stock_transfers', pt.store_id) then
    raise exception 'ليس لديك صلاحية إخراج/إدخال البضاعة' using errcode = '42501';
  end if;
  if pt.kind = 'gift' and not public.has_permission('give_gifts', pt.store_id) then
    raise exception 'ليس لديك صلاحية إخراج قطع كهدايا' using errcode = '42501';
  end if;
  if piece_ids is null or array_length(piece_ids, 1) is null then raise exception 'اختار قطعة واحدة على الأقل'; end if;
  select id into actor from public.staff where user_id = auth.uid() and store_id = pt.store_id limit 1;

  perform 1 from public.stores where id = pt.store_id for update; -- serialize numbering
  num := 'OUT-' || lpad((select count(*) + 1 from public.stock_vouchers where store_id = pt.store_id and direction = 'out')::text, 5, '0');
  insert into public.stock_vouchers (store_id, party_id, direction, voucher_number, notes, created_by)
  values (pt.store_id, pt.id, 'out', num,
          nullif(trim(concat_ws(' — ', case when pt.kind = 'gift' then 'إلى: ' || coalesce(nullif(trim(p_recipient), ''), pt.name) end, nullif(trim(p_notes), ''))), ''),
          actor) returning id into vid;

  for pc in select * from public.pieces where id = any(piece_ids) for update loop
    if pc.store_id <> pt.store_id then raise exception 'قطعة تابعة لشركة أخرى'; end if;
    if pc.status not in ('available', 'in_box') or (pt.kind <> 'gift' and pc.status <> 'available') then
      raise exception 'القطعة % غير متاحة في المخزن (حالتها: %)', pc.barcode, pc.status;
    end if;
    select price_per_gram into gp from public.gold_prices where store_id = pc.store_id and karat = pc.karat;
    w := coalesce(pc.accounting_weight_grams, pc.weight_grams, 0);
    insert into public.stock_voucher_lines (voucher_id, store_id, party_id, direction, piece_id, barcode, karat,
      weight_grams, accounting_weight_grams, fab_per_gram, gold_price_per_gram, cost_value)
    values (vid, pc.store_id, pt.id, 'out', pc.id, pc.barcode, pc.karat, pc.weight_grams, w,
      coalesce(pc.cost_fabrication_per_gram, 0), gp, round(w * (coalesce(gp, 0) + coalesce(pc.cost_fabrication_per_gram, 0)), 2));
    if pt.kind = 'gift' then
      -- expense + gift record + status 'gifted' + movement, in one go
      perform public.gift_out_piece(pc.id, coalesce(nullif(trim(p_recipient), ''), pt.name), nullif(trim(p_notes), ''), 'سند ' || num);
    else
      update public.pieces set status = case pt.kind when 'box' then 'in_box' else 'at_intermediary' end where id = pc.id;
      insert into public.piece_movements (store_id, piece_id, event_type, note, created_by)
      values (pc.store_id, pc.id, 'stock_out', 'إخراج بالسند ' || num || ' إلى ' || pt.name, actor);
    end if;
    n := n + 1;
  end loop;
  if n <> array_length(piece_ids, 1) then raise exception 'بعض القطع غير موجودة'; end if;
  return vid;
end;
$$;


--
-- Name: store_legal(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.store_legal(p_store_id uuid) RETURNS TABLE(organization_id uuid, organization_name text, legal_name text, tax_number text, country text, logo_url text, commercial_registration_number text, legal_registration_id_type text, emirate_code text, peppol_endpoint_id text)
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
                                                   select s.organization_id, o.name, o.legal_name, o.tax_number, coalesce(o.country, s.country), o.logo_url,
                                                            o.commercial_registration_number, o.legal_registration_id_type,
                                                                     coalesce(s.branch_emirate_code, o.emirate_code), o.peppol_endpoint_id
                                                                       from stores s left join organizations o on o.id = s.organization_id
                                                                         where s.id = p_store_id;
                                                                         $$;


--
-- Name: stores_currency_convert_gold(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.stores_currency_convert_gold() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare f numeric;
begin
  if upper(coalesce(new.currency,'')) = upper(coalesce(old.currency,'')) then return null; end if;
  f := currency_usd_peg(new.currency) / currency_usd_peg(old.currency);
  if f is null then return null; end if;  -- unknown currency: leave prices, health check will flag
  update public.gold_prices set price_per_gram = round(price_per_gram * f, 2), updated_at = now() where store_id = new.id;
  return null;
end $$;


--
-- Name: stores_currency_usd_reprice(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.stores_currency_usd_reprice() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if upper(coalesce(new.currency,'')) <> upper(coalesce(old.currency,''))
     and currency_usd_peg(new.currency) is not null and new.last_gold_ounce_price is not null then
    new.last_gold_ounce_rate := currency_usd_peg(new.currency);
  end if;
  return new;
end $$;


--
-- Name: sync_invoice_bank_part(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_invoice_bank_part(p_invoice uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare inv record; bank numeric; d numeric; b numeric; target numeric; diff numeric; cm record; rate numeric;
begin
  select id, store_id, invoice_number, status, payment_method, amount_paid, bank_paid_amount, pay_breakdown, pay_currency, pay_fx_rate into inv from invoices where id = p_invoice;
  if inv is null or inv.pay_breakdown is not null then return; end if; -- multi-currency: handled per currency in the mirror
  rate := case when inv.pay_currency is not null and inv.pay_fx_rate > 0 then inv.pay_fx_rate else 1 end;
  bank := rate * case
    when inv.status = 'cancelled' then 0
    when inv.payment_method = 'bank' then coalesce(inv.amount_paid, 0)
    when inv.payment_method = 'mixed' then coalesce(inv.bank_paid_amount, 0)
    else 0 end;
  select coalesce(sum(case when l.direction='in' then l.amount else -l.amount end), 0) into d
    from daily_cash_log l join cash_movements m on m.id = l.cash_movement_id where m.invoice_id = p_invoice;
  select coalesce(sum(case when direction='in' then amount else -amount end), 0) into b
    from daily_cash_log where bank_invoice_id = p_invoice;
  target := case when abs(d) < 0.01 then 0 else -sign(d) * least(round(bank, 2), abs(d)) end;
  diff := round(target - b, 2);
  if abs(diff) < 0.01 then return; end if;
  select currency, created_by into cm from cash_movements where invoice_id = p_invoice order by created_at desc limit 1;
  insert into daily_cash_log (store_id, operation_type, direction, amount, currency, notes, created_by, bank_invoice_id)
  values (inv.store_id, 'فيزا / تحويل بنكي', case when diff < 0 then 'out' else 'in' end, abs(diff),
          coalesce(inv.pay_currency, cm.currency, (select currency from stores where id = inv.store_id)),
          inv.invoice_number || case when (diff < 0) = (d >= 0) then ' — الجزء المدفوع فيزا/تحويل لا يدخل الدرج' else ' — تصحيح جزء الفيزا/التحويل' end,
          cm.created_by, p_invoice);
end $$;


--
-- Name: sync_staff_to_hr_employee(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_staff_to_hr_employee() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if not exists (select 1 from hr_employees where linked_staff_id = new.id) then
    insert into hr_employees (store_id, name, phone, job_title, linked_staff_id, created_by)
    values (new.store_id, new.full_name, coalesce(new.contact_phone, new.whatsapp_phone), new.role, new.id, new.id);
  end if;
  return new;
end;
$$;


--
-- Name: sync_store_country_to_org(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_store_country_to_org() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
                               begin
                                 update organizations set country = new.country where id = new.organization_id and primary_store_id = new.id;
                                   return null;
                                   end $$;


--
-- Name: trader_cash_move(uuid, text, numeric, text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trader_cash_move(p_trader uuid, p_direction text, p_amount numeric, p_notes text DEFAULT NULL::text, p_daily boolean DEFAULT true) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare t record; me uuid; amt numeric := round(coalesce(p_amount, 0), 2); mid uuid; cm uuid; note text;
begin
  select id, gm_acting_store(store_id) as store_id, name into t from traders where id = p_trader;
  if t is null then raise exception 'التاجر غير موجود'; end if;
  if not has_permission('edit_traders', t.store_id) then raise exception 'ليس لديك صلاحية تعديل حسابات التجار' using errcode = '42501'; end if;
  if p_direction not in ('out', 'in') then raise exception 'اتجاه غير معروف'; end if;
  if amt <= 0 then raise exception 'المبلغ يجب أن يكون أكبر من صفر'; end if;
  select id into me from staff where user_id = auth.uid() and store_id = t.store_id limit 1;
  note := coalesce(nullif(trim(p_notes), ''), case when p_direction = 'out' then 'صرف كاش للتاجر' else 'قبض كاش من التاجر' end);

  insert into trader_movements (store_id, trader_id, movement_type, weight_grams, karat, gold_24k_equivalent, fab_fee_amount, source, notes, created_by)
    values (t.store_id, t.id, case when p_direction = 'out' then 'debt_decrease' else 'debt_increase' end, 0, null, 0, amt,
            case when p_direction = 'out' then 'cash_out' else 'cash_in' end, note, me)
    returning id into mid;
  insert into cash_movements (store_id, box, direction, amount, description, created_by, trader_movement_id)
    values (t.store_id, 'main', p_direction, amt,
            case when p_direction = 'out' then 'صرف كاش للتاجر ' else 'قبض كاش من التاجر ' end || t.name, me, mid)
    returning id into cm;
  if coalesce(p_daily, true) then
    insert into daily_cash_log (store_id, operation_type, direction, amount, notes, created_by, cash_movement_id)
      values (t.store_id, case when p_direction = 'out' then 'صرف كاش لتاجر' else 'قبض كاش من تاجر' end, p_direction, amt, t.name || ' — ' || note, me, cm);
  end if;
  return mid;
end $$;


--
-- Name: trader_discount(uuid, text, numeric, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trader_discount(p_trader uuid, p_for text, p_amount numeric, p_notes text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
-- Discount on the cash balance with a trader. No money moves.
--  for = 'trader': in the trader's favour (he owes less / we owe him more) → shop profit goes down
--  for = 'shop'  : in the shop's favour  (he owes more / we owe him less) → shop profit goes up
declare t record; me uuid; amt numeric := round(coalesce(p_amount, 0), 2); mid uuid;
begin
  select id, gm_acting_store(store_id) as store_id, name into t from traders where id = p_trader;
  if t is null then raise exception 'التاجر غير موجود'; end if;
  if not has_permission('edit_traders', t.store_id) then raise exception 'ليس لديك صلاحية تعديل حسابات التجار' using errcode = '42501'; end if;
  if p_for not in ('trader', 'shop') then raise exception 'اختر لصالح من الخصم'; end if;
  if amt <= 0 then raise exception 'المبلغ يجب أن يكون أكبر من صفر'; end if;
  select id into me from staff where user_id = auth.uid() and store_id = t.store_id limit 1;
  insert into trader_movements (store_id, trader_id, movement_type, weight_grams, karat, gold_24k_equivalent, fab_fee_amount, source, notes, created_by)
    values (t.store_id, t.id, case when p_for = 'trader' then 'debt_increase' else 'debt_decrease' end, 0, null, 0, amt, 'discount',
            coalesce(nullif(trim(p_notes), ''), case when p_for = 'trader' then 'خصم لصالح التاجر' else 'خصم لصالح المحل' end), me)
    returning id into mid;
  return mid;
end $$;


--
-- Name: trader_gold_to_cash(uuid, numeric, integer, numeric, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trader_gold_to_cash(p_trader uuid, p_weight numeric, p_karat integer, p_price numeric, p_direction text, p_notes text DEFAULT NULL::text) RETURNS numeric
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare t record; me uuid; w numeric := round(coalesce(p_weight, 0), 3); pr numeric := coalesce(p_price, 0);
        k int := coalesce(p_karat, 24); g24 numeric; cash numeric; note text; ref text := gen_random_uuid()::text;
begin
  select id, gm_acting_store(store_id) as store_id, name into t from traders where id = p_trader;
  if t is null then raise exception 'التاجر غير موجود'; end if;
  if not has_permission('edit_traders', t.store_id) then raise exception 'ليس لديك صلاحية تعديل حسابات التجار' using errcode = '42501'; end if;
  if p_direction not in ('we_owe_gold', 'they_owe_gold') then raise exception 'اتجاه غير معروف'; end if;
  if w <= 0 or pr <= 0 then raise exception 'أدخل الوزن وسعر الغرام'; end if;
  if k not in (18, 21, 22, 24) then raise exception 'عيار غير معروف'; end if;
  select id into me from staff where user_id = auth.uid() and store_id = t.store_id limit 1;
  g24 := round(w * k / 24.0, 3);
  cash := round(w * pr, 2);
  note := format('تسكير عملات: %s غ عيار %s × %s = %s', w, k, pr, cash) || coalesce(' — ' || nullif(trim(p_notes), ''), '');
  insert into trader_movements (store_id, trader_id, movement_type, weight_grams, karat, gold_24k_equivalent, fab_fee_amount, source, notes, batch_ref, created_by) values
    (t.store_id, t.id, case when p_direction = 'we_owe_gold' then 'debt_decrease' else 'debt_increase' end, w, k, g24, 0, 'gold_to_cash', note, ref, me),
    (t.store_id, t.id, case when p_direction = 'we_owe_gold' then 'debt_increase' else 'debt_decrease' end, 0, null, 0, cash, 'gold_to_cash', note, ref, me);
  return cash;
end $$;


--
-- Name: trader_receive_stock(uuid, jsonb, numeric, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trader_receive_stock(p_trader uuid, p_lines jsonb, p_vat_rate numeric DEFAULT 0, p_batch_ref text DEFAULT NULL::text, p_notes text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare t record; me uuid; ln jsonb; k int; wt numeric; aw numeric; fab numeric; kind text; bc text; pid uuid; lid uuid;
        bid uuid := case when jsonb_array_length(coalesce(p_lines, '[]')) > 1 then gen_random_uuid() end;
        codes jsonb := '[]'; vat numeric := coalesce(p_vat_rate, 0);
begin
  select id, gm_acting_store(store_id) as store_id, name into t from traders where id = p_trader;
  if t is null then raise exception 'التاجر غير موجود'; end if;
  if not has_permission('edit_traders', t.store_id) then raise exception 'ليس لديك صلاحية تعديل حسابات التجار' using errcode = '42501'; end if;
  if jsonb_array_length(coalesce(p_lines, '[]')) = 0 then raise exception 'أضف سطراً واحداً على الأقل'; end if;
  select id into me from staff where user_id = auth.uid() and store_id = t.store_id limit 1;

  for ln in select * from jsonb_array_elements(p_lines) loop
    k := (ln->>'karat')::int; wt := (ln->>'weight')::numeric;
    aw := coalesce(nullif(ln->>'acc_weight', '')::numeric, wt); fab := coalesce(nullif(ln->>'fab_per_gram', '')::numeric, 0);
    kind := coalesce(ln->>'kind', 'piece');
    if k not in (18, 21, 22, 24) then raise exception 'عيار غير صحيح'; end if;
    if wt is null or wt <= 0 or aw <= 0 or fab < 0 then raise exception 'وزن أو مصنعية غير صحيحة'; end if;
    pid := null; lid := null;
    if kind = 'piece' then
      if nullif(trim(ln->>'box_name'), '') is null then raise exception 'اختر الصندوق لكل قطعة'; end if;
      bc := next_piece_barcode(t.store_id, 'gold');
      insert into pieces (store_id, barcode, weight_grams, accounting_weight_grams, karat, color, status, created_by,
        cost_fabrication_per_gram, description_ar, box_name)
      values (t.store_id, bc, wt, aw, k, 'Gold', 'available', me, fab, nullif(trim(ln->>'description_ar'), ''), trim(ln->>'box_name'))
      returning id into pid;
      insert into piece_movements (store_id, piece_id, event_type, note, created_by)
      values (t.store_id, pid, 'stock_in', 'استلام من التاجر ' || t.name, me);
      codes := codes || to_jsonb(bc);
    elsif kind = 'bulk' then
      insert into gold_stock_lots (store_id, karat, weight_grams_total, weight_grams_remaining, cost_fabrication_per_gram, trader_id, notes, created_by, box_name)
      values (t.store_id, k, wt, wt, fab, t.id, 'استلام بالجملة من التاجر ' || t.name, me, nullif(trim(ln->>'box_name'), ''))
      returning id into lid;
    else raise exception 'نوع سطر غير معروف';
    end if;
    insert into trader_movements (store_id, trader_id, movement_type, weight_grams, karat, gold_24k_equivalent, accounting_weight_grams,
      fab_fee_per_gram, fab_fee_amount, source, batch_id, batch_ref, notes, created_by, piece_id, gold_stock_lot_id)
    values (t.store_id, t.id, 'debt_increase', wt, k, round(aw * k / 24.0, 3), aw, fab, round(aw * fab * (1 + vat / 100), 2),
      'stock_received', bid, nullif(trim(p_batch_ref), ''),
      coalesce(nullif(trim(p_notes), ''), 'استلام بضاعة من التاجر') || case when bc is not null and kind = 'piece' then ' — باركود ' || bc else ' — وزن بالجملة' end,
      me, pid, lid);
  end loop;
  return jsonb_build_object('barcodes', codes);
end $$;


--
-- Name: trader_return_piece(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trader_return_piece(p_movement uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
 declare m record; me uuid; bc text;
 begin
   select * into m from trader_movements where id = p_movement and source = 'stock_given' and piece_id is not null;
     if m is null then raise exception 'القطعة غير موجودة في حساب التاجر'; end if;
       if not has_permission('edit_traders', m.store_id) then raise exception 'ليس لديك صلاحية تعديل حسابات التجار' using errcode = '42501'; end if;
         select id into me from staff where user_id = auth.uid() and store_id = m.store_id limit 1;
           delete from trader_movements where id = m.id;
             update pieces set status = 'available' where id = m.piece_id and status = 'given_to_trader' returning barcode into bc;
               insert into piece_movements (store_id, piece_id, event_type, note, created_by)
                   values (m.store_id, m.piece_id, 'returned_from_trader', 'مرتجع من التاجر — رجعت إلى المخزن', me);
                     return jsonb_build_object('ok', true, 'barcode', bc);
                     end $$;


--
-- Name: trg_cash_movement_deleted_bank_sync(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_cash_movement_deleted_bank_sync() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if old.invoice_id is not null then perform public.sync_invoice_bank_part(old.invoice_id); end if;
  return old;
end $$;


--
-- Name: trg_cash_movement_updated_daily_sync(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_cash_movement_updated_daily_sync() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if new.invoice_id is not null then return new; end if;
  update daily_cash_log
     set amount = round(coalesce(case when new.fx_currency is not null and new.fx_amount > 0 then new.fx_amount end, new.amount), 2),
         direction = new.direction
   where cash_movement_id = new.id
     and (amount <> round(coalesce(case when new.fx_currency is not null and new.fx_amount > 0 then new.fx_amount end, new.amount), 2)
          or direction <> new.direction);
  return new;
end $$;


--
-- Name: trg_customer_debts_allocate(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_customer_debts_allocate() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  perform gm_allocate_customer_credit(new.store_id, new.customer_id);
  if new.movement_type = 'debt_increase' and new.invoice_id is not null then
    perform gm_deposit_sale_to_daily(new.invoice_id, new.customer_id);
    if new.source is null then perform gm_sale_debt_to_daily(new.invoice_id, new.cash_amount); end if;
  end if;
  return null;
end $$;


--
-- Name: trg_daily_label(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_daily_label() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare r record;
begin
  select * into r from gm_daily_label(new.operation_type, new.notes, new.cash_movement_id);
  new.operation_type := r.op; new.notes := r.notes;
  return new;
end $$;


--
-- Name: trg_invoice_bank_part_sync(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_invoice_bank_part_sync() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if new.payment_method is distinct from old.payment_method or new.amount_paid is distinct from old.amount_paid
     or new.status is distinct from old.status
     or new.cash_paid_amount is distinct from old.cash_paid_amount or new.bank_paid_amount is distinct from old.bank_paid_amount then
    perform public.sync_invoice_bank_part(new.id);
  end if;
  return new;
end $$;


--
-- Name: trg_invoice_status_piece_log(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_invoice_status_piece_log() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare sid uuid := (select id from staff where user_id = auth.uid() and store_id = new.store_id limit 1);
begin
  if new.type not in ('sale', 'buyTrader', 'buyRetail') then return new; end if;
  if new.status = 'cancelled' and old.status is distinct from 'cancelled' then
    insert into piece_movements (store_id, piece_id, event_type, note, created_by)
    select new.store_id, ii.piece_id, 'status_changed',
           'إلغاء الفاتورة ' || new.invoice_number || case when new.type = 'sale' then ' — عادت القطعة متوفرة' else '' end, sid
      from invoice_items ii where ii.invoice_id = new.id and ii.piece_id is not null;
  elsif old.status = 'cancelled' and new.status is distinct from 'cancelled' then
    insert into piece_movements (store_id, piece_id, event_type, note, created_by)
    select new.store_id, ii.piece_id, case when new.type = 'sale' then 'sold' else 'restored' end,
           'استعادة الفاتورة ' || new.invoice_number, sid
      from invoice_items ii where ii.invoice_id = new.id and ii.piece_id is not null;
  end if;
  return new;
end $$;


--
-- Name: trg_piece_draws_delete(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_piece_draws_delete() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  perform gm_return_draws(old.id, (select coalesce(sum(grams), 0) from piece_lot_draws where piece_id = old.id));
  return old;
end $$;


--
-- Name: trg_piece_draws_weight(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_piece_draws_weight() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
declare d record; diff numeric;
begin
  diff := round(coalesce(new.weight_grams, 0) - coalesce(old.weight_grams, 0), 3);
  if abs(diff) < 0.0005 then return new; end if;
  select l.box_name, l.id lot_id into d from piece_lot_draws w join gold_stock_lots l on l.id = w.lot_id
   where w.piece_id = new.id order by w.created_at limit 1;
  if d is null then return new; end if;
  if diff > 0 then
    perform gm_draw_for_piece(new.id, new.store_id, case when d.box_name ~ '^كسر [0-9]+$' then d.box_name end, d.lot_id, diff);
  else
    perform gm_return_draws(new.id, -diff);
  end if;
  return new;
end $_$;


--
-- Name: trg_scrap_given_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_scrap_given_guard() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare d record; n int := 0;
begin
  if tg_op = 'UPDATE' then
    if new.weight_grams is distinct from old.weight_grams or new.karat is distinct from old.karat then
      raise exception 'لا يمكن تعديل وزن إخراج الكسر — احذف الحركة (يرجع الوزن لصندوق الكسر) ثم أخرجه من جديد';
    end if;
    return new;
  end if;
  for d in select lot_id, grams from trader_scrap_draws where movement_id = old.id loop
    update gold_stock_lots set weight_grams_remaining = round(weight_grams_remaining + d.grams, 3) where id = d.lot_id;
    n := n + 1;
  end loop;
  if n = 0 and coalesce(old.weight_grams, 0) > 0 then
    perform gm_scrap_return_unrecorded(old.store_id, old.karat, old.weight_grams, 'أُرجع من حذف إخراج كسر لتاجر');
  end if;
  return old;
end $$;


--
-- Name: trg_settlement_lot_sync(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_settlement_lot_sync() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare lt record;
begin
  if tg_op = 'UPDATE' and new.weight_grams is not distinct from old.weight_grams and new.karat is not distinct from old.karat
     and new.gold_24k_equivalent is not distinct from old.gold_24k_equivalent then
    return new;
  end if;
  for lt in select * from gold_stock_lots where trader_movement_id = old.id for update loop
    if lt.weight_grams_remaining <> lt.weight_grams_total then
      raise exception 'الذهب المستلم بهذه التسوية استُعمل من المستودع (إنتاج أو بيع) — لا يمكن تعديله أو حذفه. عدّل الحساب بتسوية جديدة.';
    end if;
    if tg_op = 'UPDATE' then
      update gold_stock_lots set
        weight_grams_total = round(coalesce(new.gold_24k_equivalent, 0) * 24 / lt.karat, 3),
        weight_grams_remaining = round(coalesce(new.gold_24k_equivalent, 0) * 24 / lt.karat, 3)
       where id = lt.id;
    else
      update gold_stock_lots set weight_grams_remaining = 0,
        notes = coalesce(notes, '') || ' — أُلغي بإلغاء التسوية'
       where id = lt.id;
    end if;
  end loop;
  return case when tg_op = 'UPDATE' then new else old end;
end $$;


--
-- Name: trg_trader_received_sync(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_trader_received_sync() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare pc record; lt record; aw numeric := coalesce(new.accounting_weight_grams, new.weight_grams);
begin
  if new.weight_grams is not distinct from old.weight_grams and new.karat is not distinct from old.karat
     and new.accounting_weight_grams is not distinct from old.accounting_weight_grams
     and new.fab_fee_per_gram is not distinct from old.fab_fee_per_gram then return new; end if;
  if new.piece_id is not null then
    select * into pc from pieces where id = new.piece_id for update;
    if pc.id is not null then
      if pc.status <> 'available' then raise exception 'القطعة % لم تعد متوفرة (بيعت أو خرجت) — لا يمكن تعديل وزنها. عدّل الحساب بتسوية.', pc.barcode; end if;
      update pieces set weight_grams = new.weight_grams, accounting_weight_grams = aw, karat = new.karat,
        cost_fabrication_per_gram = coalesce(new.fab_fee_per_gram, cost_fabrication_per_gram) where id = pc.id;
    end if;
  end if;
  if new.gold_stock_lot_id is not null then
    select * into lt from gold_stock_lots where id = new.gold_stock_lot_id for update;
    if lt.id is not null then
      if lt.weight_grams_remaining <> lt.weight_grams_total then raise exception 'الوزن بالجملة استُعمل (بيع أو إنتاج) — لا يمكن تعديله. عدّل الحساب بتسوية.'; end if;
      update gold_stock_lots set weight_grams_total = new.weight_grams, weight_grams_remaining = new.weight_grams, karat = new.karat,
        cost_fabrication_per_gram = coalesce(new.fab_fee_per_gram, cost_fabrication_per_gram) where id = lt.id;
    end if;
  end if;
  return new;
end $$;


--
-- Name: update_expense(uuid, uuid, numeric, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_expense(p_id uuid, p_category uuid, p_amount numeric, p_description text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare e record; cat record; amt numeric := round(coalesce(p_amount, 0), 2); descr text := nullif(trim(p_description), '');
begin
  select * into e from expense_entries where id = p_id;
  if e is null then raise exception 'المصروف غير موجود'; end if;
  if not gm_can_expense(e.store_id) or not is_store_member(e.store_id) then raise exception 'ليس لديك صلاحية تعديل المصاريف' using errcode = '42501'; end if;
  if exists (select 1 from inventory_gifts where expense_entry_id = p_id) then raise exception 'هذا مصروف هدية — عدّله بإرجاع الهدية إلى المخزن'; end if;
  select id, name into cat from expense_categories where id = p_category and store_id = e.store_id;
  if cat is null then raise exception 'اختر نوع المصروف'; end if;
  if amt <= 0 then raise exception 'المبلغ يجب أن يكون أكبر من صفر'; end if;
  update expense_entries set category_id = cat.id, amount = amt, description = coalesce(descr, cat.name) where id = p_id;
  if e.cash_movement_id is not null then
    update cash_movements set amount = amt, description = 'مصروف ' || cat.name || coalesce(': ' || descr, '') where id = e.cash_movement_id;
    update daily_cash_log set amount = amt, operation_type = 'مصروف: ' || cat.name, notes = descr where cash_movement_id = e.cash_movement_id;
  end if;
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: update_expense_fx(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_expense_fx(p jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare e record; cat record; amt numeric := round(coalesce(nullif(p->>'amount', '')::numeric, 0), 2);
        descr text := nullif(trim(p->>'description'), ''); cur text := upper(coalesce(nullif(p->>'currency', ''), ''));
        rate numeric := nullif(p->>'fx_rate', '')::numeric; base_cur text; fx boolean; base_amt numeric; fxnote text := '';
begin
  select * into e from expense_entries where id = (p->>'id')::uuid;
  if e is null then raise exception 'المصروف غير موجود'; end if;
  if not gm_can_expense(e.store_id) or not is_store_member(e.store_id) then raise exception 'ليس لديك صلاحية تعديل المصاريف' using errcode = '42501'; end if;
  if exists (select 1 from inventory_gifts where expense_entry_id = e.id) then raise exception 'هذا مصروف هدية — عدّله بإرجاع الهدية إلى المخزن'; end if;
  select id, name into cat from expense_categories where id = (p->>'category_id')::uuid and store_id = e.store_id;
  if cat is null then raise exception 'اختر نوع المصروف'; end if;
  if amt <= 0 then raise exception 'المبلغ يجب أن يكون أكبر من صفر'; end if;
  select coalesce(nullif(upper(currency), ''), 'AED') into base_cur from stores where id = e.store_id;
  if cur = '' then cur := base_cur; end if;
  fx := cur <> base_cur;
  if fx then
    if rate is null or rate <= 0 then raise exception 'أدخل سعر صرف % مقابل %', cur, base_cur; end if;
    base_amt := round(amt / rate, 2);
    fxnote := ' (' || trim(to_char(amt, 'FM999,999,999,990.##')) || ' ' || cur || ')';
  else base_amt := amt; end if;
  update expense_entries set category_id = cat.id, amount = base_amt, description = coalesce(descr, cat.name),
         fx_amount = case when fx then amt end, fx_currency = case when fx then cur end where id = e.id;
  if e.cash_movement_id is not null then
    update cash_movements set amount = base_amt, description = 'مصروف ' || cat.name || coalesce(': ' || descr, '') || fxnote,
           fx_amount = case when fx then amt end, fx_currency = case when fx then cur end where id = e.cash_movement_id;
    update daily_cash_log set amount = amt, currency = cur, operation_type = 'مصروف: ' || cat.name, notes = descr where cash_movement_id = e.cash_movement_id;
  end if;
  return jsonb_build_object('ok', true);
end $$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: _backup_20260927_intake_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public._backup_20260927_intake_batches (
    id uuid,
    store_id uuid,
    source_type text,
    source_lot_id uuid,
    notes text,
    created_by uuid,
    created_at timestamp with time zone
);


--
-- Name: _backup_20260927_piece_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public._backup_20260927_piece_batches (
    piece_id uuid,
    intake_batch_id uuid
);


--
-- Name: audit_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_log (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid,
    staff_id uuid,
    action_type text NOT NULL,
    description text,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: auth_device_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auth_device_keys (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    secret_hash text NOT NULL,
    device_name text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_used_at timestamp with time zone
);

ALTER TABLE ONLY public.auth_device_keys FORCE ROW LEVEL SECURITY;


--
-- Name: auth_passkeys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auth_passkeys (
    id text NOT NULL,
    user_id uuid NOT NULL,
    public_key text NOT NULL,
    counter bigint DEFAULT 0 NOT NULL,
    transports text[],
    device_name text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_used_at timestamp with time zone
);

ALTER TABLE ONLY public.auth_passkeys FORCE ROW LEVEL SECURITY;


--
-- Name: auth_webauthn_challenges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auth_webauthn_challenges (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    challenge text NOT NULL,
    user_id uuid,
    kind text NOT NULL,
    expires_at timestamp with time zone DEFAULT (now() + '00:05:00'::interval) NOT NULL,
    CONSTRAINT auth_webauthn_challenges_kind_check CHECK ((kind = ANY (ARRAY['register'::text, 'login'::text])))
);

ALTER TABLE ONLY public.auth_webauthn_challenges FORCE ROW LEVEL SECURITY;


--
-- Name: branch_transfer_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.branch_transfer_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    transfer_id uuid NOT NULL,
    piece_id uuid,
    diamond_piece_id uuid,
    barcode text,
    description text,
    karat integer,
    weight_grams numeric,
    photo_url text,
    received_at timestamp with time zone,
    received_by uuid,
    kind text DEFAULT 'piece'::text NOT NULL,
    amount numeric,
    cash_box text,
    box_name text,
    fab_per_gram numeric,
    lot_draws jsonb,
    CONSTRAINT branch_transfer_items_kind_check CHECK ((kind = ANY (ARRAY['piece'::text, 'scrap'::text, 'cash'::text])))
);


--
-- Name: branch_transfers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.branch_transfers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid,
    from_store_id uuid NOT NULL,
    to_store_id uuid NOT NULL,
    transfer_number text NOT NULL,
    status text DEFAULT 'in_transit'::text NOT NULL,
    notes text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    received_by uuid,
    received_at timestamp with time zone,
    CONSTRAINT branch_transfers_status_check CHECK ((status = ANY (ARRAY['in_transit'::text, 'received'::text, 'cancelled'::text])))
);


--
-- Name: cash_movements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cash_movements (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid,
    invoice_id uuid,
    direction text NOT NULL,
    amount numeric(12,2) NOT NULL,
    box text DEFAULT 'main'::text,
    description text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now(),
    currency text,
    trader_movement_id uuid,
    fx_amount numeric,
    fx_currency text,
    edit_delta boolean DEFAULT false NOT NULL,
    entered_at timestamp with time zone DEFAULT now()
);


--
-- Name: client_errors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.client_errors (
    id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    user_id uuid DEFAULT auth.uid(),
    store_id uuid,
    page text,
    message text NOT NULL,
    source text,
    line integer,
    stack text,
    user_agent text,
    app_version text,
    CONSTRAINT client_errors_app_version_check CHECK ((char_length(app_version) <= 50)),
    CONSTRAINT client_errors_message_check CHECK ((char_length(message) <= 1000)),
    CONSTRAINT client_errors_page_check CHECK ((char_length(page) <= 200)),
    CONSTRAINT client_errors_source_check CHECK ((char_length(source) <= 300)),
    CONSTRAINT client_errors_stack_check CHECK ((char_length(stack) <= 4000)),
    CONSTRAINT client_errors_user_agent_check CHECK ((char_length(user_agent) <= 300))
);


--
-- Name: client_errors_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.client_errors ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.client_errors_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: company_kyc_documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.company_kyc_documents (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    owner_type text NOT NULL,
    owner_id uuid NOT NULL,
    file_url text NOT NULL,
    file_name text,
    uploaded_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    document_category text DEFAULT 'kyc'::text NOT NULL,
    CONSTRAINT company_kyc_documents_owner_type_check CHECK ((owner_type = ANY (ARRAY['customer'::text, 'trader'::text, 'invoice'::text])))
);


--
-- Name: company_register_attempts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.company_register_attempts (
    id bigint NOT NULL,
    caller_ip text NOT NULL,
    attempted_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: company_register_attempts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.company_register_attempts ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.company_register_attempts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: company_search_attempts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.company_search_attempts (
    id bigint NOT NULL,
    caller_ip text NOT NULL,
    attempted_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: company_search_attempts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.company_search_attempts ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.company_search_attempts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: customer_debts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer_debts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid,
    customer_id uuid,
    invoice_id uuid,
    gold_grams_24k numeric(10,3) DEFAULT 0,
    cash_amount numeric(12,2) DEFAULT 0,
    status text DEFAULT 'active'::text,
    created_at timestamp with time zone DEFAULT now(),
    movement_type text,
    notes text,
    created_by uuid,
    source text,
    currency text,
    cash_movement_id uuid,
    entered_at timestamp with time zone DEFAULT now()
);


--
-- Name: COLUMN customer_debts.movement_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.customer_debts.movement_type IS 'debt_increase (credit sale) or debt_decrease (customer payment/settlement), mirroring trader_movements design.';


--
-- Name: customer_deposits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer_deposits (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    deposit_number text NOT NULL,
    customer_id uuid NOT NULL,
    amount numeric NOT NULL,
    currency text,
    method text DEFAULT 'cash'::text NOT NULL,
    items jsonb DEFAULT '[]'::jsonb NOT NULL,
    notes text,
    status text DEFAULT 'active'::text NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    refunded_at timestamp with time zone,
    in_cashbox boolean DEFAULT true NOT NULL,
    CONSTRAINT customer_deposits_amount_check CHECK ((amount > (0)::numeric)),
    CONSTRAINT customer_deposits_status_check CHECK ((status = ANY (ARRAY['active'::text, 'refunded'::text])))
);


--
-- Name: customer_phones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer_phones (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    phone text NOT NULL,
    phone_country_code text,
    label text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: customers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid,
    name text NOT NULL,
    phone text,
    created_at timestamp with time zone DEFAULT now(),
    is_company boolean DEFAULT false NOT NULL,
    legal_name text,
    tax_number text,
    address text,
    email text,
    phone_country_code text,
    nationality text,
    date_of_birth date,
    id_type text,
    id_number text,
    id_expiry_date date,
    occupation text,
    source_of_funds text,
    trade_license_number text,
    business_activity text,
    ubo_name text,
    ubo_id_number text,
    ubo_ownership_percent numeric,
    authorized_signatory_name text,
    authorized_signatory_id_number text,
    kyc_declaration_accepted boolean DEFAULT false,
    kyc_completed_at timestamp with time zone
);


--
-- Name: daily_cash_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.daily_cash_log (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    operation_type text NOT NULL,
    direction text NOT NULL,
    amount numeric NOT NULL,
    currency text NOT NULL,
    notes text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    link_group text,
    cash_movement_id uuid,
    bank_part boolean DEFAULT false NOT NULL,
    bank_invoice_id uuid,
    entered_at timestamp with time zone DEFAULT now(),
    CONSTRAINT daily_cash_log_amount_check CHECK ((amount > (0)::numeric)),
    CONSTRAINT daily_cash_log_direction_check CHECK ((direction = ANY (ARRAY['in'::text, 'out'::text])))
);


--
-- Name: TABLE daily_cash_log; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.daily_cash_log IS 'Simple free-text manual drawer journal (separate from the real accounting ledger in cash_movements/invoices). Balance rolls forward day to day per currency as a running total. Never feeds monthly/annual/tax reports.';


--
-- Name: COLUMN daily_cash_log.link_group; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.daily_cash_log.link_group IS 'Free-text tag the user sets to visually link related in/out entries (e.g. same customer/deal) with a matching background color in the UI — not a foreign key, purely a display grouping label.';


--
-- Name: diamond_pieces; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.diamond_pieces (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    barcode text,
    photo_url text,
    has_gold boolean DEFAULT false NOT NULL,
    gold_weight_grams numeric,
    gold_karat integer,
    gold_cost_fabrication_per_gram numeric,
    diamond_carat numeric NOT NULL,
    diamond_price_per_carat numeric NOT NULL,
    suggested_sale_price numeric,
    description_ar text,
    description_en text,
    status text DEFAULT 'available'::text NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    clarity text,
    shape text,
    cut text,
    color text,
    certificate_lab text,
    certificate_number text,
    box_name text,
    diamond_stock_lot_id uuid,
    secondary_stones_cost numeric
);


--
-- Name: COLUMN diamond_pieces.box_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.diamond_pieces.box_name IS 'User-chosen destination label (e.g. "قطع ألماسية") -- purely organizational.';


--
-- Name: diamond_stock_lots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.diamond_stock_lots (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    box_name text,
    total_carat numeric NOT NULL,
    remaining_carat numeric NOT NULL,
    price_per_carat numeric,
    trader_id uuid,
    source_invoice_id uuid,
    notes text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: expense_categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.expense_categories (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid,
    name text NOT NULL
);


--
-- Name: expense_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.expense_entries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid,
    category_id uuid,
    amount numeric(12,2) NOT NULL,
    description text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now(),
    attachment_url text,
    cash_movement_id uuid,
    fx_amount numeric,
    fx_currency text
);


--
-- Name: fiscal_year_closures; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fiscal_year_closures (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    fiscal_year integer NOT NULL,
    total_sales numeric DEFAULT 0 NOT NULL,
    total_returns numeric DEFAULT 0 NOT NULL,
    total_profit numeric DEFAULT 0 NOT NULL,
    total_output_tax numeric DEFAULT 0 NOT NULL,
    total_input_tax numeric DEFAULT 0 NOT NULL,
    notes text,
    closed_by uuid,
    closed_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: gift_cost_adjust_20261006; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gift_cost_adjust_20261006 (
    gift_id uuid,
    old_fab numeric,
    old_total numeric,
    expense_entry_id uuid,
    old_amount numeric(12,2)
);


--
-- Name: gold_prices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gold_prices (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid,
    karat integer NOT NULL,
    price_per_gram numeric NOT NULL,
    mode text DEFAULT 'manual'::text NOT NULL,
    updated_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: gold_stock_lots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gold_stock_lots (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    karat integer NOT NULL,
    weight_grams_total numeric NOT NULL,
    weight_grams_remaining numeric NOT NULL,
    cost_fabrication_per_gram numeric DEFAULT 0 NOT NULL,
    trader_id uuid,
    source_invoice_id uuid,
    notes text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    fabrication_pool_total numeric,
    fabrication_pool_remaining numeric,
    box_name text,
    trader_movement_id uuid,
    CONSTRAINT gold_stock_lots_remaining_check CHECK (((weight_grams_remaining >= (0)::numeric) AND (weight_grams_remaining <= weight_grams_total)))
);


--
-- Name: COLUMN gold_stock_lots.box_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.gold_stock_lots.box_name IS 'User-chosen label for this bulk lot (e.g. "ذهب مشغول", "ذهب كسر 18") -- purely organizational, no business logic depends on it.';


--
-- Name: hr_employees; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hr_employees (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    name text NOT NULL,
    phone text,
    job_title text,
    department text,
    hire_date date,
    annual_leave_days numeric DEFAULT 30 NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    linked_staff_id uuid,
    notes text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: hr_leave_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hr_leave_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    leave_type text DEFAULT 'annual'::text NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    days_count numeric NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    reason text,
    approved_by uuid,
    approved_at timestamp with time zone,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: inventory_count_expected; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventory_count_expected (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    count_id uuid NOT NULL,
    piece_id uuid NOT NULL,
    piece_source text NOT NULL,
    match_value text NOT NULL,
    barcode text,
    description_ar text,
    karat integer,
    weight_grams numeric,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT inventory_count_expected_piece_source_check CHECK ((piece_source = ANY (ARRAY['gold'::text, 'diamond'::text])))
);

ALTER TABLE ONLY public.inventory_count_expected FORCE ROW LEVEL SECURITY;


--
-- Name: inventory_count_scans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventory_count_scans (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    count_id uuid NOT NULL,
    rfid_epc text NOT NULL,
    piece_id uuid,
    match_status text DEFAULT 'matched'::text NOT NULL,
    scanned_at timestamp with time zone DEFAULT now() NOT NULL,
    scanned_by uuid,
    piece_source text,
    scan_method text,
    CONSTRAINT inventory_count_scans_match_status_check CHECK ((match_status = ANY (ARRAY['matched'::text, 'unexpected'::text, 'duplicate'::text, 'cancelled'::text])))
);


--
-- Name: inventory_counts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventory_counts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    status text DEFAULT 'in_progress'::text NOT NULL,
    started_by uuid,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    notes text,
    expected_piece_count integer,
    scanned_piece_count integer DEFAULT 0 NOT NULL,
    matched_count integer DEFAULT 0 NOT NULL,
    missing_count integer DEFAULT 0 NOT NULL,
    unexpected_count integer DEFAULT 0 NOT NULL,
    method text,
    scope text[],
    posted_at timestamp with time zone,
    posted_by uuid,
    CONSTRAINT inventory_counts_status_check CHECK ((status = ANY (ARRAY['in_progress'::text, 'completed'::text, 'posted'::text, 'cancelled'::text])))
);


--
-- Name: inventory_gifts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventory_gifts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    piece_id uuid NOT NULL,
    barcode text,
    karat integer,
    weight_grams numeric,
    accounting_weight_grams numeric,
    gold_price_per_gram numeric,
    gold_cost numeric DEFAULT 0 NOT NULL,
    fabrication_cost numeric DEFAULT 0 NOT NULL,
    total_cost numeric DEFAULT 0 NOT NULL,
    recipient text NOT NULL,
    reason text,
    notes text,
    expense_entry_id uuid,
    status text DEFAULT 'active'::text NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    reverted_at timestamp with time zone,
    CONSTRAINT inventory_gifts_status_check CHECK ((status = ANY (ARRAY['active'::text, 'reverted'::text])))
);

ALTER TABLE ONLY public.inventory_gifts FORCE ROW LEVEL SECURITY;


--
-- Name: invoice_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invoice_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    invoice_id uuid,
    piece_id uuid,
    barcode text,
    karat integer,
    weight_grams numeric(10,3),
    fabrication_fee numeric(12,2) DEFAULT 0,
    line_total numeric(12,2) DEFAULT 0,
    description text,
    gold_price_per_gram numeric,
    description_en text,
    accounting_weight_grams numeric,
    gold_stock_lot_id uuid,
    item_photo_url text,
    diamond_piece_id uuid,
    fabrication_fee_vat numeric,
    diamond_stock_lot_id uuid,
    returned_item_id uuid
);


--
-- Name: COLUMN invoice_items.gold_price_per_gram; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoice_items.gold_price_per_gram IS 'Gold market price per gram (for this item''s karat) at the moment the invoice was created, snapshotted from gold_prices so profit reports stay historically accurate regardless of later price changes.';


--
-- Name: COLUMN invoice_items.accounting_weight_grams; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoice_items.accounting_weight_grams IS 'Snapshot of the piece''s accounting weight at the moment of sale, used for profit calculations instead of weight_grams (which is the actual/gross weight shown on the invoice).';


--
-- Name: COLUMN invoice_items.fabrication_fee_vat; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoice_items.fabrication_fee_vat IS 'VAT amount on this line''s fabrication_fee (buyTrader purchases only) — lets invoice-print-ar.html show a real per-item Making/VAT breakdown instead of only an invoice-level total.';


--
-- Name: COLUMN invoice_items.diamond_stock_lot_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoice_items.diamond_stock_lot_id IS 'Links this line to the diamond_stock_lots row it created, when the cart item was a bulk diamond-lot purchase (mode diamond_bulk).';


--
-- Name: invoice_number_counters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invoice_number_counters (
    store_id uuid NOT NULL,
    prefix text NOT NULL,
    year integer NOT NULL,
    next_seq integer NOT NULL
);


--
-- Name: invoices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invoices (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid,
    invoice_number text NOT NULL,
    type text DEFAULT 'sell'::text NOT NULL,
    customer_id uuid,
    trader_id uuid,
    payment_method text DEFAULT 'cash'::text,
    gold_value numeric(12,2) DEFAULT 0,
    fabrication_fees numeric(12,2) DEFAULT 0,
    vat_amount numeric(12,2) DEFAULT 0,
    total_amount numeric(12,2) DEFAULT 0,
    amount_paid numeric(12,2) DEFAULT 0,
    status text DEFAULT 'confirmed'::text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now(),
    counterparty_name text,
    attachment_url text,
    related_invoice_id uuid,
    cash_paid_amount numeric,
    bank_paid_amount numeric,
    einvoice_uuid uuid,
    einvoice_xml text,
    einvoice_status text DEFAULT 'not_generated'::text NOT NULL,
    currency text,
    bulk_photos jsonb,
    client_ref uuid,
    seller_id_type text,
    seller_id_number text,
    pay_currency text,
    pay_fx_rate numeric,
    pay_breakdown jsonb,
    is_exchange boolean DEFAULT false NOT NULL,
    salesperson_id uuid,
    CONSTRAINT invoices_seller_id_type_check CHECK (((seller_id_type IS NULL) OR (seller_id_type = ANY (ARRAY['emirates_id'::text, 'passport'::text, 'other'::text]))))
);


--
-- Name: COLUMN invoices.related_invoice_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.related_invoice_id IS 'For type=return invoices: the original sale invoice being returned against. The original invoice is never modified.';


--
-- Name: COLUMN invoices.bulk_photos; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.bulk_photos IS 'Optional array of photo URLs attached to a bulk/trader purchase invoice (e.g. photos of the received gold lot). Shown only on that invoice''s printed voucher.';


--
-- Name: COLUMN invoices.seller_id_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.invoices.seller_id_type IS 'Purchase from an individual: seller document type (emirates_id / passport / other). Photos live in company_kyc_documents (owner_type=invoice).';


--
-- Name: kyc_screenings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.kyc_screenings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    owner_type text NOT NULL,
    owner_id uuid NOT NULL,
    screened_at timestamp with time zone DEFAULT now() NOT NULL,
    screened_by uuid,
    result text DEFAULT 'clear'::text NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: login_2fa; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.login_2fa (
    session_id uuid NOT NULL,
    user_id uuid NOT NULL,
    code_hash text,
    expires_at timestamp with time zone,
    attempts integer DEFAULT 0 NOT NULL,
    sent_count integer DEFAULT 0 NOT NULL,
    last_sent_at timestamp with time zone,
    verified_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: lookup_username_attempts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lookup_username_attempts (
    id bigint NOT NULL,
    caller_ip text NOT NULL,
    attempted_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: lookup_username_attempts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.lookup_username_attempts ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.lookup_username_attempts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: organizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organizations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    primary_store_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    legal_name text,
    tax_number text,
    country text,
    logo_url text,
    commercial_registration_number text,
    legal_registration_id_type text,
    emirate_code text,
    peppol_endpoint_id text,
    head_office_store_id uuid
);

ALTER TABLE ONLY public.organizations FORCE ROW LEVEL SECURITY;


--
-- Name: payroll_payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payroll_payments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    staff_id uuid NOT NULL,
    pay_period text NOT NULL,
    base_salary numeric DEFAULT 0 NOT NULL,
    bonus numeric DEFAULT 0 NOT NULL,
    deduction numeric DEFAULT 0 NOT NULL,
    net_amount numeric DEFAULT 0 NOT NULL,
    notes text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE payroll_payments; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.payroll_payments IS 'Actual salary payment log (base + bonus - deduction = net), one row per payment run; mirrored into expense_entries + cash_movements at insert time by the app';


--
-- Name: piece_barcode_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.piece_barcode_history (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    piece_id uuid,
    old_barcode text NOT NULL,
    new_barcode text NOT NULL,
    changed_by uuid,
    changed_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: piece_chip_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.piece_chip_history (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    piece_id uuid,
    old_epc text NOT NULL,
    new_epc text NOT NULL,
    changed_by uuid,
    changed_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: piece_classification_options; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.piece_classification_options (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    field_key text NOT NULL,
    value text NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    value_en text,
    CONSTRAINT piece_classification_options_field_key_check CHECK ((field_key = ANY (ARRAY['type'::text, 'category1'::text, 'category2'::text])))
);


--
-- Name: piece_cost_adjust_20261006; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.piece_cost_adjust_20261006 (
    piece_id uuid,
    old_cost numeric,
    at_time timestamp with time zone
);


--
-- Name: piece_intake_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.piece_intake_batches (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    source_type text NOT NULL,
    source_lot_id uuid,
    notes text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT piece_intake_batches_source_type_check CHECK ((source_type = ANY (ARRAY['manual'::text, 'production'::text, 'opening'::text])))
);


--
-- Name: piece_lot_draws; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.piece_lot_draws (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    piece_id uuid NOT NULL,
    lot_id uuid NOT NULL,
    grams numeric NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT piece_lot_draws_grams_check CHECK ((grams > (0)::numeric))
);


--
-- Name: piece_movements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.piece_movements (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    piece_id uuid NOT NULL,
    event_type text NOT NULL,
    note text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    entered_at timestamp with time zone DEFAULT now()
);


--
-- Name: pieces; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pieces (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid,
    barcode text,
    photo_url text,
    weight_grams numeric(10,3) NOT NULL,
    karat integer NOT NULL,
    color text DEFAULT 'Gold'::text,
    status text DEFAULT 'in_stock'::text NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now(),
    cost_fabrication_per_gram numeric,
    description_ar text,
    description_en text,
    accounting_weight_grams numeric,
    piece_type text,
    category1 text,
    category2 text,
    rfid_epc text,
    rfid_encoded_at timestamp with time zone,
    rfid_last_seen_at timestamp with time zone,
    box_name text,
    intake_batch_id uuid,
    accent_diamond_carat numeric,
    accent_diamond_price_per_carat numeric,
    center_stone_carat numeric,
    center_stone_price_per_carat numeric,
    purchase_cost numeric,
    zircon_carat numeric,
    reserved_customer_id uuid,
    CONSTRAINT pieces_karat_check CHECK ((karat = ANY (ARRAY[18, 21, 22, 24]))),
    CONSTRAINT pieces_zircon_carat_check CHECK (((zircon_carat IS NULL) OR (zircon_carat >= (0)::numeric)))
);


--
-- Name: COLUMN pieces.accounting_weight_grams; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.pieces.accounting_weight_grams IS 'Billable/accounting gold weight, may differ from the piece''s actual weight_grams when stones are set and deducted. Falls back to weight_grams when null.';


--
-- Name: COLUMN pieces.rfid_epc; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.pieces.rfid_epc IS 'RFID tag EPC (hex), written by Zebra ZD621R at issuance time alongside the printed barcode. Null = piece has no RFID tag (legacy or barcode-only).';


--
-- Name: COLUMN pieces.rfid_last_seen_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.pieces.rfid_last_seen_at IS 'Updated whenever this EPC is scanned during a warehouse inventory count session.';


--
-- Name: COLUMN pieces.box_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.pieces.box_name IS 'User-chosen destination label a produced/added piece was filed under (e.g. "قطع مجوهرات") -- purely organizational.';


--
-- Name: COLUMN pieces.zircon_carat; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.pieces.zircon_carat IS 'Zircon (cubic zirconia) weight in grams; label symbol Z.';


--
-- Name: plans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plans (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    key text NOT NULL,
    name_ar text NOT NULL,
    name_en text NOT NULL,
    price_monthly numeric DEFAULT 0 NOT NULL,
    price_yearly numeric DEFAULT 0 NOT NULL,
    max_staff integer,
    features jsonb DEFAULT '{}'::jsonb NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    currency text DEFAULT 'USD'::text NOT NULL,
    included_staff integer,
    extra_staff_price numeric,
    staff_upgrade_threshold integer,
    included_branches integer DEFAULT 1,
    extra_branch_price numeric,
    max_branches integer,
    next_plan_key text,
    is_custom boolean DEFAULT false NOT NULL,
    prices jsonb DEFAULT '{}'::jsonb NOT NULL,
    einvoice_monthly_quota integer,
    highlights_ar text[]
);


--
-- Name: COLUMN plans.prices; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.plans.prices IS 'Per-currency price list: {"USD":{yearly,extra_staff_yearly,einvoice_addon_monthly,einvoice_overage}}. Yearly only, paid upfront; refundable within 14 days of subscribing.';


--
-- Name: COLUMN plans.einvoice_monthly_quota; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.plans.einvoice_monthly_quota IS 'E-invoices per month included once e-invoicing launches. NULL + einvoice_addon price = paid add-on.';


--
-- Name: platform_admins; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_admins (
    id uuid NOT NULL,
    email text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: repair_gold_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.repair_gold_lines (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    expense_entry_id uuid NOT NULL,
    lot_id uuid NOT NULL,
    karat integer NOT NULL,
    grams numeric NOT NULL,
    cost numeric DEFAULT 0 NOT NULL,
    lot_date timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT repair_gold_lines_grams_check CHECK ((grams > (0)::numeric))
);


--
-- Name: repair_tickets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.repair_tickets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    ticket_number text,
    customer_id uuid,
    customer_name text,
    customer_phone text,
    piece_description text,
    problem_description text,
    intake_photo_url text,
    ready_photo_url text,
    estimated_cost numeric,
    actual_cost numeric,
    deposit_amount numeric DEFAULT 0,
    status text DEFAULT 'received'::text NOT NULL,
    received_at timestamp with time zone DEFAULT now(),
    received_by uuid,
    expected_ready_at date,
    ready_at timestamp with time zone,
    delivered_at timestamp with time zone,
    delivered_by uuid,
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT repair_tickets_status_check CHECK ((status = ANY (ARRAY['received'::text, 'in_progress'::text, 'ready'::text, 'delivered'::text, 'cancelled'::text])))
);


--
-- Name: rfid_write_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rfid_write_jobs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    piece_id uuid NOT NULL,
    barcode text NOT NULL,
    epc text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    message text,
    created_by uuid DEFAULT auth.uid(),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    done_at timestamp with time zone,
    CONSTRAINT rfid_write_jobs_epc_check CHECK ((epc ~ '^[0-9A-F]{24}$'::text)),
    CONSTRAINT rfid_write_jobs_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'working'::text, 'done'::text, 'failed'::text, 'cancelled'::text])))
);


--
-- Name: staff; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.staff (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid,
    full_name text NOT NULL,
    role text DEFAULT 'staff'::text NOT NULL,
    can_sell boolean DEFAULT true,
    can_manage_inventory boolean DEFAULT false,
    can_view_reports boolean DEFAULT false,
    can_delete boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now(),
    permissions jsonb DEFAULT '{}'::jsonb NOT NULL,
    user_id uuid,
    whatsapp_phone text,
    contact_phone text
);


--
-- Name: COLUMN staff.whatsapp_phone; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.staff.whatsapp_phone IS 'Optional WhatsApp number (with country code, digits only) used for the free manual "send daily report via WhatsApp" click-to-chat feature. Recipients are staff with view_reports=true and this set.';


--
-- Name: staff_presence; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.staff_presence (
    staff_id uuid NOT NULL,
    store_id uuid NOT NULL,
    last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
    last_page text
);


--
-- Name: staff_salaries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.staff_salaries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    staff_id uuid NOT NULL,
    monthly_salary numeric DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid
);


--
-- Name: TABLE staff_salaries; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.staff_salaries IS 'Confidential reference monthly salary per staff member — separate from staff table because staff has an open colleague-read RLS policy';


--
-- Name: stock_parties; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stock_parties (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    name text NOT NULL,
    kind text NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT stock_parties_kind_check CHECK ((kind = ANY (ARRAY['intermediary'::text, 'gift'::text])))
);

ALTER TABLE ONLY public.stock_parties FORCE ROW LEVEL SECURITY;


--
-- Name: stock_voucher_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stock_voucher_lines (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    voucher_id uuid NOT NULL,
    store_id uuid NOT NULL,
    party_id uuid NOT NULL,
    direction text NOT NULL,
    piece_id uuid,
    barcode text,
    karat integer NOT NULL,
    weight_grams numeric DEFAULT 0 NOT NULL,
    accounting_weight_grams numeric DEFAULT 0 NOT NULL,
    fab_per_gram numeric DEFAULT 0 NOT NULL,
    gold_price_per_gram numeric,
    cost_value numeric DEFAULT 0 NOT NULL,
    CONSTRAINT stock_voucher_lines_direction_check CHECK ((direction = ANY (ARRAY['out'::text, 'in'::text])))
);

ALTER TABLE ONLY public.stock_voucher_lines FORCE ROW LEVEL SECURITY;


--
-- Name: stock_vouchers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stock_vouchers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    party_id uuid NOT NULL,
    direction text NOT NULL,
    voucher_number text NOT NULL,
    notes text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT stock_vouchers_direction_check CHECK ((direction = ANY (ARRAY['out'::text, 'in'::text])))
);

ALTER TABLE ONLY public.stock_vouchers FORCE ROW LEVEL SECURITY;


--
-- Name: store_invites; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.store_invites (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    email text NOT NULL,
    permissions jsonb DEFAULT '{}'::jsonb NOT NULL,
    role text DEFAULT 'staff'::text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    invited_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    accepted_at timestamp with time zone,
    whatsapp_phone text,
    CONSTRAINT store_invites_role_check CHECK ((role = ANY (ARRAY['staff'::text, 'owner'::text]))),
    CONSTRAINT store_invites_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'accepted'::text, 'revoked'::text])))
);


--
-- Name: stores; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stores (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text DEFAULT 'Al-Fares Gold Shop'::text NOT NULL,
    currency text DEFAULT 'AED'::text NOT NULL,
    gold_price_source text DEFAULT 'Live Market'::text,
    invoice_prefix text DEFAULT 'INV'::text,
    next_invoice_number integer DEFAULT 1,
    vat_rate numeric(5,2) DEFAULT 5.00,
    created_at timestamp with time zone DEFAULT now(),
    address text,
    phone text,
    email text,
    manager_name text,
    contact_person_name text,
    license_number text,
    social_instagram text,
    social_facebook text,
    social_whatsapp text,
    country text,
    invoice_numbering_mode text DEFAULT 'auto'::text NOT NULL,
    terms_accepted_at timestamp with time zone,
    terms_accepted_version text,
    next_invoice_seq integer DEFAULT 1 NOT NULL,
    next_invoice_seq_year integer,
    next_repair_seq integer DEFAULT 1,
    invoice_print_frame text DEFAULT 'classic'::text NOT NULL,
    invoice_print_shape text DEFAULT 'soft'::text NOT NULL,
    website_url text,
    social_tiktok text,
    social_snapchat text,
    diamonds_enabled boolean DEFAULT false NOT NULL,
    organization_id uuid,
    einvoice_disabled boolean DEFAULT false NOT NULL,
    piece_barcode_prefix_gold text DEFAULT 'G'::text,
    piece_barcode_prefix_diamond text DEFAULT 'D'::text,
    next_piece_seq_gold bigint DEFAULT 1 NOT NULL,
    next_piece_seq_diamond bigint DEFAULT 1 NOT NULL,
    secondary_currency text,
    secondary_currency_rate numeric,
    secondary_currency_rate_updated_at timestamp with time zone,
    rfid_enabled boolean DEFAULT false NOT NULL,
    last_gold_ounce_price numeric,
    last_gold_ounce_rate numeric,
    auto_capture_photo_enabled boolean DEFAULT false NOT NULL,
    fab_rate_retail numeric,
    fab_rate_wholesale numeric,
    fab_rate_wholesale2 numeric,
    label_mc_multiplier numeric DEFAULT 1 NOT NULL,
    label_mc_addend numeric DEFAULT 0 NOT NULL,
    zebra_label_width_mm numeric DEFAULT 60 NOT NULL,
    zebra_label_height_mm numeric DEFAULT 30 NOT NULL,
    zebra_label_dpi integer DEFAULT 203 NOT NULL,
    zebra_label_x_offset_mm numeric DEFAULT '-20'::integer NOT NULL,
    zebra_barcode_height_mm numeric DEFAULT 3 NOT NULL,
    zebra_label_rotate_180 boolean DEFAULT true NOT NULL,
    zebra_darkness integer DEFAULT 15 NOT NULL,
    zebra_field_spacing_mm numeric DEFAULT 0.62 NOT NULL,
    zebra_label_y_offset_mm numeric DEFAULT 4.5 NOT NULL,
    piece_barcode_seq_width_gold smallint,
    piece_barcode_seq_width_diamond smallint,
    zebra_barcode_module_width numeric DEFAULT 1 NOT NULL,
    address_en text,
    allow_biometric_login boolean DEFAULT true NOT NULL,
    rfid_device_key text,
    branch_emirate_code text,
    debt_alert_days integer DEFAULT 15 NOT NULL,
    debt_alert_customers boolean DEFAULT true NOT NULL,
    debt_alert_traders boolean DEFAULT false NOT NULL,
    display_name text,
    branch_code text,
    own_gold_price boolean DEFAULT false NOT NULL,
    CONSTRAINT invoice_print_frame_check CHECK ((invoice_print_frame = ANY (ARRAY['classic'::text, 'gold'::text, 'double'::text, 'dashed'::text, 'none'::text]))),
    CONSTRAINT invoice_print_shape_check CHECK ((invoice_print_shape = ANY (ARRAY['square'::text, 'soft'::text, 'round'::text]))),
    CONSTRAINT stores_branch_code_format CHECK (((branch_code IS NULL) OR (branch_code ~ '^[A-Z]{2,5}$'::text))),
    CONSTRAINT stores_debt_alert_days_check CHECK (((debt_alert_days >= 1) AND (debt_alert_days <= 365)))
);


--
-- Name: COLUMN stores.secondary_currency; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.stores.secondary_currency IS 'Optional secondary currency code shown alongside base currency (display-only conversion, not stored per-transaction)';


--
-- Name: COLUMN stores.secondary_currency_rate; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.stores.secondary_currency_rate IS 'How many units of secondary_currency equal 1 unit of stores.currency (base). Set manually by owner from settings.';


--
-- Name: COLUMN stores.auto_capture_photo_enabled; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.stores.auto_capture_photo_enabled IS 'When true, inventory-add / stock-production pages auto-trigger a desktop webcam capture as soon as a piece gets a barcode number (or a new production row is started), instead of waiting for a manual tap on the photo box.';


--
-- Name: COLUMN stores.fab_rate_retail; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.stores.fab_rate_retail IS 'Suggested fabrication fee per gram for retail (مفرق) sales — used to pre-fill (not force) the sale price at new-sale-ar.html.';


--
-- Name: COLUMN stores.fab_rate_wholesale; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.stores.fab_rate_wholesale IS 'Suggested fabrication fee per gram for wholesale (جملة) sales.';


--
-- Name: COLUMN stores.fab_rate_wholesale2; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.stores.fab_rate_wholesale2 IS 'Suggested fabrication fee per gram for super-wholesale (جملة الجملة) sales.';


--
-- Name: COLUMN stores.allow_biometric_login; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.stores.allow_biometric_login IS 'Owner switch: employees may log in with fingerprint/Face ID (turn off for shared shop devices). Owners are always allowed.';


--
-- Name: subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subscriptions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    plan_id uuid NOT NULL,
    status text DEFAULT 'trialing'::text NOT NULL,
    trial_end timestamp with time zone,
    current_period_end timestamp with time zone,
    payment_provider text,
    payment_ref text,
    gateway_status text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    grace_period_days integer DEFAULT 7 NOT NULL,
    pending_upgrade_plan_id uuid,
    last_auto_upgrade_at timestamp with time zone,
    deactivated_at timestamp with time zone,
    CONSTRAINT subscriptions_status_check CHECK ((status = ANY (ARRAY['trialing'::text, 'active'::text, 'past_due'::text, 'canceled'::text])))
);


--
-- Name: support_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.support_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    created_by uuid,
    subject text NOT NULL,
    message text NOT NULL,
    status text DEFAULT 'open'::text NOT NULL,
    admin_reply text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    preferred_language text DEFAULT 'ar'::text,
    CONSTRAINT support_requests_status_check CHECK ((status = ANY (ARRAY['open'::text, 'in_progress'::text, 'resolved'::text])))
);


--
-- Name: trader_movements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trader_movements (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid,
    trader_id uuid,
    invoice_id uuid,
    movement_type text NOT NULL,
    weight_grams numeric(10,3) DEFAULT 0,
    karat integer,
    gold_24k_equivalent numeric(10,3) DEFAULT 0,
    fab_fee_amount numeric(12,2) DEFAULT 0,
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    accounting_weight_grams numeric,
    fab_fee_per_gram numeric,
    source text DEFAULT 'settlement'::text NOT NULL,
    currency text,
    created_by uuid,
    piece_id uuid,
    batch_id uuid,
    batch_ref text,
    cost_fab_per_gram numeric,
    sale_cost numeric,
    gold_stock_lot_id uuid,
    piece_acc_weight numeric,
    gold_price_24k numeric,
    entered_at timestamp with time zone DEFAULT now(),
    CONSTRAINT trader_movements_source_check CHECK ((source = ANY (ARRAY['settlement'::text, 'stock_given'::text, 'stock_received'::text, 'opening_balance'::text, 'cash_out'::text, 'cash_in'::text, 'gold_to_cash'::text, 'scrap_given'::text, 'discount'::text])))
);


--
-- Name: COLUMN trader_movements.accounting_weight_grams; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.trader_movements.accounting_weight_grams IS 'وزن المحاسبة عند إعطاء بضاعة للتاجر (source=stock_given)؛ قد يختلف عن weight_grams (الوزن القائم/الفعلي)';


--
-- Name: COLUMN trader_movements.fab_fee_per_gram; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.trader_movements.fab_fee_per_gram IS 'أجرة المصنعية للغرام الواحد وقت تسليم البضاعة للتاجر، محسوبة على وزن المحاسبة';


--
-- Name: COLUMN trader_movements.source; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.trader_movements.source IS 'settlement = تسوية/دفعة يدوية عادية، stock_given = تسليم بضاعة للتاجر (وزن قائم/محاسبة + مصنعية)';


--
-- Name: COLUMN trader_movements.piece_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.trader_movements.piece_id IS 'Links a stock_given/stock_received trader movement to the specific inventoried piece it came from (barcode-driven give-stock flow in ledger-ar.html). Null for older free-typed movements and for non-stock movements (settlement/opening_balance).';


--
-- Name: COLUMN trader_movements.batch_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.trader_movements.batch_id IS 'Groups multiple trader_movements rows created together as one multi-line voucher (e.g. a wholesale purchase invoice with several weight/rate lines) so the ledger UI can render + edit + delete them as a single card. Null for single-line movements.';


--
-- Name: COLUMN trader_movements.batch_ref; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.trader_movements.batch_ref IS 'Optional free-text reference for a batch (e.g. the trader''s own invoice number), shown as the batch card header.';


--
-- Name: COLUMN trader_movements.cost_fab_per_gram; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.trader_movements.cost_fab_per_gram IS 'Our own making cost per gram for goods given to a trader by weight (no piece) — used for wholesale profit';


--
-- Name: trader_scrap_draws; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trader_scrap_draws (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    movement_id uuid NOT NULL,
    lot_id uuid NOT NULL,
    grams numeric NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT trader_scrap_draws_grams_check CHECK ((grams > (0)::numeric))
);


--
-- Name: traders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.traders (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid,
    name text NOT NULL,
    phone text,
    created_at timestamp with time zone DEFAULT now(),
    notes text,
    is_company boolean DEFAULT false NOT NULL,
    legal_name text,
    tax_number text,
    address text,
    email text,
    phone_country_code text,
    nationality text,
    date_of_birth date,
    id_type text,
    id_number text,
    id_expiry_date date,
    occupation text,
    source_of_funds text,
    trade_license_number text,
    business_activity text,
    ubo_name text,
    ubo_id_number text,
    ubo_ownership_percent numeric,
    authorized_signatory_name text,
    authorized_signatory_id_number text,
    kyc_declaration_accepted boolean DEFAULT false,
    kyc_completed_at timestamp with time zone,
    weight_basis text DEFAULT 'accounting'::text NOT NULL,
    CONSTRAINT traders_weight_basis_chk CHECK ((weight_basis = ANY (ARRAY['accounting'::text, 'gross'::text])))
);


--
-- Name: user_profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_profiles (
    id uuid NOT NULL,
    username text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    privacy_accepted_at timestamp with time zone,
    home_prefs jsonb,
    CONSTRAINT user_profiles_username_format CHECK (((username IS NULL) OR (username ~ '^[a-zA-Z0-9_\.]{3,30}$'::text)))
);


--
-- Name: zebra_label_fields; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.zebra_label_fields (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    column_num smallint NOT NULL,
    row_order smallint NOT NULL,
    content_type text NOT NULL,
    custom_text text,
    font_size smallint DEFAULT 20 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    x_offset_mm numeric DEFAULT 0 NOT NULL,
    CONSTRAINT zebra_label_fields_column_num_check CHECK ((column_num = ANY (ARRAY[1, 2]))),
    CONSTRAINT zebra_label_fields_content_type_check CHECK ((content_type = ANY (ARRAY['barcode_number'::text, 'barcode_graphic'::text, 'company_name'::text, 'weight'::text, 'karat'::text, 'mc'::text, 'description'::text, 'custom_text'::text, 'blank_line'::text, 'diamond_carat'::text, 'zircon_carat'::text])))
);


--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (id);


--
-- Name: auth_device_keys auth_device_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_device_keys
    ADD CONSTRAINT auth_device_keys_pkey PRIMARY KEY (id);


--
-- Name: auth_passkeys auth_passkeys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_passkeys
    ADD CONSTRAINT auth_passkeys_pkey PRIMARY KEY (id);


--
-- Name: auth_webauthn_challenges auth_webauthn_challenges_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_webauthn_challenges
    ADD CONSTRAINT auth_webauthn_challenges_pkey PRIMARY KEY (id);


--
-- Name: branch_transfer_items branch_transfer_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branch_transfer_items
    ADD CONSTRAINT branch_transfer_items_pkey PRIMARY KEY (id);


--
-- Name: branch_transfers branch_transfers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branch_transfers
    ADD CONSTRAINT branch_transfers_pkey PRIMARY KEY (id);


--
-- Name: cash_movements cash_movements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_movements
    ADD CONSTRAINT cash_movements_pkey PRIMARY KEY (id);


--
-- Name: client_errors client_errors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_errors
    ADD CONSTRAINT client_errors_pkey PRIMARY KEY (id);


--
-- Name: company_kyc_documents company_kyc_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_kyc_documents
    ADD CONSTRAINT company_kyc_documents_pkey PRIMARY KEY (id);


--
-- Name: company_register_attempts company_register_attempts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_register_attempts
    ADD CONSTRAINT company_register_attempts_pkey PRIMARY KEY (id);


--
-- Name: company_search_attempts company_search_attempts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_search_attempts
    ADD CONSTRAINT company_search_attempts_pkey PRIMARY KEY (id);


--
-- Name: customer_debts customer_debts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_debts
    ADD CONSTRAINT customer_debts_pkey PRIMARY KEY (id);


--
-- Name: customer_deposits customer_deposits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_deposits
    ADD CONSTRAINT customer_deposits_pkey PRIMARY KEY (id);


--
-- Name: customer_deposits customer_deposits_store_id_deposit_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_deposits
    ADD CONSTRAINT customer_deposits_store_id_deposit_number_key UNIQUE (store_id, deposit_number);


--
-- Name: customer_phones customer_phones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_phones
    ADD CONSTRAINT customer_phones_pkey PRIMARY KEY (id);


--
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (id);


--
-- Name: daily_cash_log daily_cash_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_cash_log
    ADD CONSTRAINT daily_cash_log_pkey PRIMARY KEY (id);


--
-- Name: diamond_pieces diamond_pieces_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.diamond_pieces
    ADD CONSTRAINT diamond_pieces_pkey PRIMARY KEY (id);


--
-- Name: diamond_stock_lots diamond_stock_lots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.diamond_stock_lots
    ADD CONSTRAINT diamond_stock_lots_pkey PRIMARY KEY (id);


--
-- Name: expense_categories expense_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expense_categories
    ADD CONSTRAINT expense_categories_pkey PRIMARY KEY (id);


--
-- Name: expense_entries expense_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expense_entries
    ADD CONSTRAINT expense_entries_pkey PRIMARY KEY (id);


--
-- Name: fiscal_year_closures fiscal_year_closures_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fiscal_year_closures
    ADD CONSTRAINT fiscal_year_closures_pkey PRIMARY KEY (id);


--
-- Name: fiscal_year_closures fiscal_year_closures_store_id_fiscal_year_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fiscal_year_closures
    ADD CONSTRAINT fiscal_year_closures_store_id_fiscal_year_key UNIQUE (store_id, fiscal_year);


--
-- Name: gold_prices gold_prices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gold_prices
    ADD CONSTRAINT gold_prices_pkey PRIMARY KEY (id);


--
-- Name: gold_prices gold_prices_store_id_karat_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gold_prices
    ADD CONSTRAINT gold_prices_store_id_karat_key UNIQUE (store_id, karat);


--
-- Name: gold_stock_lots gold_stock_lots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gold_stock_lots
    ADD CONSTRAINT gold_stock_lots_pkey PRIMARY KEY (id);


--
-- Name: hr_employees hr_employees_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hr_employees
    ADD CONSTRAINT hr_employees_pkey PRIMARY KEY (id);


--
-- Name: hr_leave_requests hr_leave_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hr_leave_requests
    ADD CONSTRAINT hr_leave_requests_pkey PRIMARY KEY (id);


--
-- Name: inventory_count_expected inventory_count_expected_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_count_expected
    ADD CONSTRAINT inventory_count_expected_pkey PRIMARY KEY (id);


--
-- Name: inventory_count_scans inventory_count_scans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_count_scans
    ADD CONSTRAINT inventory_count_scans_pkey PRIMARY KEY (id);


--
-- Name: inventory_counts inventory_counts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_counts
    ADD CONSTRAINT inventory_counts_pkey PRIMARY KEY (id);


--
-- Name: inventory_gifts inventory_gifts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_gifts
    ADD CONSTRAINT inventory_gifts_pkey PRIMARY KEY (id);


--
-- Name: invoice_items invoice_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_items
    ADD CONSTRAINT invoice_items_pkey PRIMARY KEY (id);


--
-- Name: invoice_number_counters invoice_number_counters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_number_counters
    ADD CONSTRAINT invoice_number_counters_pkey PRIMARY KEY (store_id, prefix, year);


--
-- Name: invoices invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_pkey PRIMARY KEY (id);


--
-- Name: kyc_screenings kyc_screenings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kyc_screenings
    ADD CONSTRAINT kyc_screenings_pkey PRIMARY KEY (id);


--
-- Name: login_2fa login_2fa_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.login_2fa
    ADD CONSTRAINT login_2fa_pkey PRIMARY KEY (session_id);


--
-- Name: lookup_username_attempts lookup_username_attempts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lookup_username_attempts
    ADD CONSTRAINT lookup_username_attempts_pkey PRIMARY KEY (id);


--
-- Name: organizations organizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (id);


--
-- Name: payroll_payments payroll_payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_payments
    ADD CONSTRAINT payroll_payments_pkey PRIMARY KEY (id);


--
-- Name: piece_barcode_history piece_barcode_history_old_barcode_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.piece_barcode_history
    ADD CONSTRAINT piece_barcode_history_old_barcode_key UNIQUE (old_barcode);


--
-- Name: piece_barcode_history piece_barcode_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.piece_barcode_history
    ADD CONSTRAINT piece_barcode_history_pkey PRIMARY KEY (id);


--
-- Name: piece_chip_history piece_chip_history_old_epc_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.piece_chip_history
    ADD CONSTRAINT piece_chip_history_old_epc_key UNIQUE (old_epc);


--
-- Name: piece_chip_history piece_chip_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.piece_chip_history
    ADD CONSTRAINT piece_chip_history_pkey PRIMARY KEY (id);


--
-- Name: piece_classification_options piece_classification_options_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.piece_classification_options
    ADD CONSTRAINT piece_classification_options_pkey PRIMARY KEY (id);


--
-- Name: piece_classification_options piece_classification_options_store_id_field_key_value_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.piece_classification_options
    ADD CONSTRAINT piece_classification_options_store_id_field_key_value_key UNIQUE (store_id, field_key, value);


--
-- Name: piece_intake_batches piece_intake_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.piece_intake_batches
    ADD CONSTRAINT piece_intake_batches_pkey PRIMARY KEY (id);


--
-- Name: piece_lot_draws piece_lot_draws_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.piece_lot_draws
    ADD CONSTRAINT piece_lot_draws_pkey PRIMARY KEY (id);


--
-- Name: piece_movements piece_movements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.piece_movements
    ADD CONSTRAINT piece_movements_pkey PRIMARY KEY (id);


--
-- Name: pieces pieces_barcode_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pieces
    ADD CONSTRAINT pieces_barcode_key UNIQUE (barcode);


--
-- Name: pieces pieces_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pieces
    ADD CONSTRAINT pieces_pkey PRIMARY KEY (id);


--
-- Name: plans plans_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plans
    ADD CONSTRAINT plans_key_key UNIQUE (key);


--
-- Name: plans plans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plans
    ADD CONSTRAINT plans_pkey PRIMARY KEY (id);


--
-- Name: platform_admins platform_admins_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_admins
    ADD CONSTRAINT platform_admins_pkey PRIMARY KEY (id);


--
-- Name: repair_gold_lines repair_gold_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.repair_gold_lines
    ADD CONSTRAINT repair_gold_lines_pkey PRIMARY KEY (id);


--
-- Name: repair_tickets repair_tickets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.repair_tickets
    ADD CONSTRAINT repair_tickets_pkey PRIMARY KEY (id);


--
-- Name: rfid_write_jobs rfid_write_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rfid_write_jobs
    ADD CONSTRAINT rfid_write_jobs_pkey PRIMARY KEY (id);


--
-- Name: staff staff_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff
    ADD CONSTRAINT staff_pkey PRIMARY KEY (id);


--
-- Name: staff_presence staff_presence_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_presence
    ADD CONSTRAINT staff_presence_pkey PRIMARY KEY (staff_id);


--
-- Name: staff_salaries staff_salaries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_salaries
    ADD CONSTRAINT staff_salaries_pkey PRIMARY KEY (id);


--
-- Name: staff_salaries staff_salaries_store_id_staff_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_salaries
    ADD CONSTRAINT staff_salaries_store_id_staff_id_key UNIQUE (store_id, staff_id);


--
-- Name: staff staff_user_store_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff
    ADD CONSTRAINT staff_user_store_unique UNIQUE (user_id, store_id);


--
-- Name: stock_parties stock_parties_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_parties
    ADD CONSTRAINT stock_parties_pkey PRIMARY KEY (id);


--
-- Name: stock_parties stock_parties_store_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_parties
    ADD CONSTRAINT stock_parties_store_id_name_key UNIQUE (store_id, name);


--
-- Name: stock_voucher_lines stock_voucher_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_voucher_lines
    ADD CONSTRAINT stock_voucher_lines_pkey PRIMARY KEY (id);


--
-- Name: stock_vouchers stock_vouchers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_vouchers
    ADD CONSTRAINT stock_vouchers_pkey PRIMARY KEY (id);


--
-- Name: store_invites store_invites_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_invites
    ADD CONSTRAINT store_invites_pkey PRIMARY KEY (id);


--
-- Name: stores stores_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stores
    ADD CONSTRAINT stores_pkey PRIMARY KEY (id);


--
-- Name: subscriptions subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_pkey PRIMARY KEY (id);


--
-- Name: support_requests support_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.support_requests
    ADD CONSTRAINT support_requests_pkey PRIMARY KEY (id);


--
-- Name: trader_movements trader_movements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trader_movements
    ADD CONSTRAINT trader_movements_pkey PRIMARY KEY (id);


--
-- Name: trader_scrap_draws trader_scrap_draws_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trader_scrap_draws
    ADD CONSTRAINT trader_scrap_draws_pkey PRIMARY KEY (id);


--
-- Name: traders traders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.traders
    ADD CONSTRAINT traders_pkey PRIMARY KEY (id);


--
-- Name: user_profiles user_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_profiles
    ADD CONSTRAINT user_profiles_pkey PRIMARY KEY (id);


--
-- Name: user_profiles user_profiles_username_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_profiles
    ADD CONSTRAINT user_profiles_username_key UNIQUE (username);


--
-- Name: zebra_label_fields zebra_label_fields_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.zebra_label_fields
    ADD CONSTRAINT zebra_label_fields_pkey PRIMARY KEY (id);


--
-- Name: audit_log_staff_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_staff_id_fk_idx ON public.audit_log USING btree (staff_id);


--
-- Name: audit_log_store_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_store_id_fk_idx ON public.audit_log USING btree (store_id);


--
-- Name: auth_device_keys_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_device_keys_user_idx ON public.auth_device_keys USING btree (user_id);


--
-- Name: auth_passkeys_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_passkeys_user_idx ON public.auth_passkeys USING btree (user_id);


--
-- Name: auth_webauthn_challenges_user_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_webauthn_challenges_user_id_fk_idx ON public.auth_webauthn_challenges USING btree (user_id);


--
-- Name: branch_transfer_items_transfer_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX branch_transfer_items_transfer_idx ON public.branch_transfer_items USING btree (transfer_id);


--
-- Name: branch_transfers_from_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX branch_transfers_from_idx ON public.branch_transfers USING btree (from_store_id, created_at DESC);


--
-- Name: branch_transfers_to_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX branch_transfers_to_idx ON public.branch_transfers USING btree (to_store_id, status);


--
-- Name: cash_movements_created_by_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cash_movements_created_by_fk_idx ON public.cash_movements USING btree (created_by);


--
-- Name: cash_movements_invoice_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cash_movements_invoice_id_fk_idx ON public.cash_movements USING btree (invoice_id);


--
-- Name: cash_movements_store_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cash_movements_store_id_fk_idx ON public.cash_movements USING btree (store_id);


--
-- Name: client_errors_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX client_errors_created_at_idx ON public.client_errors USING btree (created_at DESC);


--
-- Name: client_errors_store_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX client_errors_store_id_idx ON public.client_errors USING btree (store_id);


--
-- Name: company_kyc_documents_store_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX company_kyc_documents_store_id_fk_idx ON public.company_kyc_documents USING btree (store_id);


--
-- Name: company_kyc_documents_uploaded_by_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX company_kyc_documents_uploaded_by_fk_idx ON public.company_kyc_documents USING btree (uploaded_by);


--
-- Name: company_register_attempts_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX company_register_attempts_at_idx ON public.company_register_attempts USING btree (attempted_at);


--
-- Name: customer_debts_cash_movement_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX customer_debts_cash_movement_id_fk_idx ON public.customer_debts USING btree (cash_movement_id);


--
-- Name: customer_debts_created_by_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX customer_debts_created_by_fk_idx ON public.customer_debts USING btree (created_by);


--
-- Name: customer_debts_customer_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX customer_debts_customer_id_fk_idx ON public.customer_debts USING btree (customer_id);


--
-- Name: customer_debts_invoice_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX customer_debts_invoice_id_fk_idx ON public.customer_debts USING btree (invoice_id);


--
-- Name: customer_debts_store_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX customer_debts_store_id_fk_idx ON public.customer_debts USING btree (store_id);


--
-- Name: customer_deposits_created_by_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX customer_deposits_created_by_fk_idx ON public.customer_deposits USING btree (created_by);


--
-- Name: customer_deposits_customer_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX customer_deposits_customer_id_fk_idx ON public.customer_deposits USING btree (customer_id);


--
-- Name: customer_deposits_store_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX customer_deposits_store_idx ON public.customer_deposits USING btree (store_id, created_at DESC);


--
-- Name: customers_store_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX customers_store_id_fk_idx ON public.customers USING btree (store_id);


--
-- Name: daily_cash_log_bank_invoice_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX daily_cash_log_bank_invoice_idx ON public.daily_cash_log USING btree (bank_invoice_id) WHERE (bank_invoice_id IS NOT NULL);


--
-- Name: daily_cash_log_cash_movement_uidx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX daily_cash_log_cash_movement_uidx ON public.daily_cash_log USING btree (cash_movement_id) WHERE (cash_movement_id IS NOT NULL);


--
-- Name: daily_cash_log_created_by_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX daily_cash_log_created_by_fk_idx ON public.daily_cash_log USING btree (created_by);


--
-- Name: daily_cash_log_store_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX daily_cash_log_store_id_fk_idx ON public.daily_cash_log USING btree (store_id);


--
-- Name: diamond_pieces_created_by_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX diamond_pieces_created_by_fk_idx ON public.diamond_pieces USING btree (created_by);


--
-- Name: diamond_pieces_diamond_stock_lot_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX diamond_pieces_diamond_stock_lot_id_fk_idx ON public.diamond_pieces USING btree (diamond_stock_lot_id);


--
-- Name: diamond_stock_lots_source_invoice_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX diamond_stock_lots_source_invoice_id_fk_idx ON public.diamond_stock_lots USING btree (source_invoice_id);


--
-- Name: diamond_stock_lots_store_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX diamond_stock_lots_store_id_fk_idx ON public.diamond_stock_lots USING btree (store_id);


--
-- Name: diamond_stock_lots_trader_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX diamond_stock_lots_trader_id_fk_idx ON public.diamond_stock_lots USING btree (trader_id);


--
-- Name: expense_categories_store_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX expense_categories_store_id_fk_idx ON public.expense_categories USING btree (store_id);


--
-- Name: expense_entries_cash_movement_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX expense_entries_cash_movement_id_fk_idx ON public.expense_entries USING btree (cash_movement_id);


--
-- Name: expense_entries_category_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX expense_entries_category_id_fk_idx ON public.expense_entries USING btree (category_id);


--
-- Name: expense_entries_created_by_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX expense_entries_created_by_fk_idx ON public.expense_entries USING btree (created_by);


--
-- Name: expense_entries_store_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX expense_entries_store_id_fk_idx ON public.expense_entries USING btree (store_id);


--
-- Name: fiscal_year_closures_closed_by_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX fiscal_year_closures_closed_by_fk_idx ON public.fiscal_year_closures USING btree (closed_by);


--
-- Name: gold_stock_lots_created_by_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX gold_stock_lots_created_by_fk_idx ON public.gold_stock_lots USING btree (created_by);


--
-- Name: gold_stock_lots_source_invoice_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX gold_stock_lots_source_invoice_id_fk_idx ON public.gold_stock_lots USING btree (source_invoice_id);


--
-- Name: gold_stock_lots_trader_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX gold_stock_lots_trader_id_fk_idx ON public.gold_stock_lots USING btree (trader_id);


--
-- Name: gold_stock_lots_trader_movement_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX gold_stock_lots_trader_movement_id_idx ON public.gold_stock_lots USING btree (trader_movement_id);


--
-- Name: hr_employees_linked_staff_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hr_employees_linked_staff_id_fk_idx ON public.hr_employees USING btree (linked_staff_id);


--
-- Name: hr_employees_store_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hr_employees_store_id_fk_idx ON public.hr_employees USING btree (store_id);


--
-- Name: hr_leave_requests_employee_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hr_leave_requests_employee_id_fk_idx ON public.hr_leave_requests USING btree (employee_id);


--
-- Name: hr_leave_requests_store_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hr_leave_requests_store_id_fk_idx ON public.hr_leave_requests USING btree (store_id);


--
-- Name: idx_cash_movements_trader_movement_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cash_movements_trader_movement_id ON public.cash_movements USING btree (trader_movement_id) WHERE (trader_movement_id IS NOT NULL);


--
-- Name: idx_customer_phones_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customer_phones_customer_id ON public.customer_phones USING btree (customer_id);


--
-- Name: idx_customer_phones_store_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customer_phones_store_id ON public.customer_phones USING btree (store_id);


--
-- Name: idx_diamond_pieces_store_barcode; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_diamond_pieces_store_barcode ON public.diamond_pieces USING btree (store_id, barcode) WHERE (barcode IS NOT NULL);


--
-- Name: idx_diamond_pieces_store_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_diamond_pieces_store_status ON public.diamond_pieces USING btree (store_id, status);


--
-- Name: idx_gold_stock_lots_store_karat; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gold_stock_lots_store_karat ON public.gold_stock_lots USING btree (store_id, karat);


--
-- Name: idx_inventory_count_expected_count_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_count_expected_count_id ON public.inventory_count_expected USING btree (count_id);


--
-- Name: idx_inventory_count_expected_match_value; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_count_expected_match_value ON public.inventory_count_expected USING btree (count_id, match_value);


--
-- Name: idx_inventory_count_scans_count_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_count_scans_count_id ON public.inventory_count_scans USING btree (count_id);


--
-- Name: idx_inventory_count_scans_epc; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_count_scans_epc ON public.inventory_count_scans USING btree (rfid_epc);


--
-- Name: idx_lookup_username_attempts_ip_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lookup_username_attempts_ip_time ON public.lookup_username_attempts USING btree (caller_ip, attempted_at);


--
-- Name: idx_payroll_payments_store_staff; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payroll_payments_store_staff ON public.payroll_payments USING btree (store_id, staff_id, pay_period);


--
-- Name: idx_piece_movements_piece; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_piece_movements_piece ON public.piece_movements USING btree (piece_id, created_at DESC);


--
-- Name: idx_pieces_rfid_epc; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pieces_rfid_epc ON public.pieces USING btree (rfid_epc) WHERE (rfid_epc IS NOT NULL);


--
-- Name: idx_trader_movements_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trader_movements_batch_id ON public.trader_movements USING btree (batch_id) WHERE (batch_id IS NOT NULL);


--
-- Name: inventory_count_expected_store_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX inventory_count_expected_store_id_fk_idx ON public.inventory_count_expected USING btree (store_id);


--
-- Name: inventory_count_scans_count_value_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX inventory_count_scans_count_value_uniq ON public.inventory_count_scans USING btree (count_id, rfid_epc);


--
-- Name: inventory_count_scans_piece_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX inventory_count_scans_piece_id_fk_idx ON public.inventory_count_scans USING btree (piece_id);


--
-- Name: inventory_count_scans_scanned_by_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX inventory_count_scans_scanned_by_fk_idx ON public.inventory_count_scans USING btree (scanned_by);


--
-- Name: inventory_count_scans_store_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX inventory_count_scans_store_id_fk_idx ON public.inventory_count_scans USING btree (store_id);


--
-- Name: inventory_counts_started_by_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX inventory_counts_started_by_fk_idx ON public.inventory_counts USING btree (started_by);


--
-- Name: inventory_counts_store_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX inventory_counts_store_id_fk_idx ON public.inventory_counts USING btree (store_id);


--
-- Name: inventory_gifts_created_by_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX inventory_gifts_created_by_fk_idx ON public.inventory_gifts USING btree (created_by);


--
-- Name: inventory_gifts_expense_entry_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX inventory_gifts_expense_entry_id_fk_idx ON public.inventory_gifts USING btree (expense_entry_id);


--
-- Name: inventory_gifts_piece_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX inventory_gifts_piece_id_fk_idx ON public.inventory_gifts USING btree (piece_id);


--
-- Name: inventory_gifts_store_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX inventory_gifts_store_idx ON public.inventory_gifts USING btree (store_id, created_at DESC);


--
-- Name: invoice_items_diamond_piece_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX invoice_items_diamond_piece_id_fk_idx ON public.invoice_items USING btree (diamond_piece_id);


--
-- Name: invoice_items_diamond_stock_lot_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX invoice_items_diamond_stock_lot_id_fk_idx ON public.invoice_items USING btree (diamond_stock_lot_id);


--
-- Name: invoice_items_gold_stock_lot_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX invoice_items_gold_stock_lot_id_fk_idx ON public.invoice_items USING btree (gold_stock_lot_id);


--
-- Name: invoice_items_invoice_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX invoice_items_invoice_id_fk_idx ON public.invoice_items USING btree (invoice_id);


--
-- Name: invoice_items_piece_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX invoice_items_piece_id_fk_idx ON public.invoice_items USING btree (piece_id);


--
-- Name: invoice_items_returned_item_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX invoice_items_returned_item_idx ON public.invoice_items USING btree (returned_item_id) WHERE (returned_item_id IS NOT NULL);


--
-- Name: invoices_client_ref_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX invoices_client_ref_key ON public.invoices USING btree (client_ref) WHERE (client_ref IS NOT NULL);


--
-- Name: invoices_created_by_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX invoices_created_by_fk_idx ON public.invoices USING btree (created_by);


--
-- Name: invoices_customer_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX invoices_customer_id_fk_idx ON public.invoices USING btree (customer_id);


--
-- Name: invoices_related_invoice_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX invoices_related_invoice_id_fk_idx ON public.invoices USING btree (related_invoice_id);


--
-- Name: invoices_store_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX invoices_store_id_fk_idx ON public.invoices USING btree (store_id);


--
-- Name: invoices_store_salesperson_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX invoices_store_salesperson_created_idx ON public.invoices USING btree (store_id, salesperson_id, created_at);


--
-- Name: invoices_trader_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX invoices_trader_id_fk_idx ON public.invoices USING btree (trader_id);


--
-- Name: kyc_screenings_store_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX kyc_screenings_store_id_fk_idx ON public.kyc_screenings USING btree (store_id);


--
-- Name: login_2fa_user_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX login_2fa_user_id_idx ON public.login_2fa USING btree (user_id);


--
-- Name: organizations_primary_store_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX organizations_primary_store_id_fk_idx ON public.organizations USING btree (primary_store_id);


--
-- Name: payroll_payments_created_by_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payroll_payments_created_by_fk_idx ON public.payroll_payments USING btree (created_by);


--
-- Name: payroll_payments_staff_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payroll_payments_staff_id_fk_idx ON public.payroll_payments USING btree (staff_id);


--
-- Name: piece_barcode_history_store_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX piece_barcode_history_store_idx ON public.piece_barcode_history USING btree (store_id);


--
-- Name: piece_chip_history_store_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX piece_chip_history_store_idx ON public.piece_chip_history USING btree (store_id);


--
-- Name: piece_classification_options_created_by_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX piece_classification_options_created_by_fk_idx ON public.piece_classification_options USING btree (created_by);


--
-- Name: piece_intake_batches_source_lot_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX piece_intake_batches_source_lot_id_fk_idx ON public.piece_intake_batches USING btree (source_lot_id);


--
-- Name: piece_intake_batches_store_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX piece_intake_batches_store_idx ON public.piece_intake_batches USING btree (store_id, created_at DESC);


--
-- Name: piece_lot_draws_lot_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX piece_lot_draws_lot_id_fk_idx ON public.piece_lot_draws USING btree (lot_id);


--
-- Name: piece_lot_draws_piece_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX piece_lot_draws_piece_idx ON public.piece_lot_draws USING btree (piece_id);


--
-- Name: piece_lot_draws_store_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX piece_lot_draws_store_id_fk_idx ON public.piece_lot_draws USING btree (store_id);


--
-- Name: piece_movements_created_by_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX piece_movements_created_by_fk_idx ON public.piece_movements USING btree (created_by);


--
-- Name: piece_movements_store_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX piece_movements_store_id_fk_idx ON public.piece_movements USING btree (store_id);


--
-- Name: pieces_created_by_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pieces_created_by_fk_idx ON public.pieces USING btree (created_by);


--
-- Name: pieces_intake_batch_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pieces_intake_batch_idx ON public.pieces USING btree (intake_batch_id);


--
-- Name: pieces_rfid_epc_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX pieces_rfid_epc_unique ON public.pieces USING btree (rfid_epc) WHERE (rfid_epc IS NOT NULL);


--
-- Name: pieces_store_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pieces_store_id_fk_idx ON public.pieces USING btree (store_id);


--
-- Name: repair_gold_lines_expense_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX repair_gold_lines_expense_idx ON public.repair_gold_lines USING btree (expense_entry_id);


--
-- Name: repair_gold_lines_lot_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX repair_gold_lines_lot_idx ON public.repair_gold_lines USING btree (lot_id);


--
-- Name: repair_tickets_customer_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX repair_tickets_customer_id_fk_idx ON public.repair_tickets USING btree (customer_id);


--
-- Name: repair_tickets_delivered_by_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX repair_tickets_delivered_by_fk_idx ON public.repair_tickets USING btree (delivered_by);


--
-- Name: repair_tickets_received_by_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX repair_tickets_received_by_fk_idx ON public.repair_tickets USING btree (received_by);


--
-- Name: repair_tickets_store_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX repair_tickets_store_id_fk_idx ON public.repair_tickets USING btree (store_id);


--
-- Name: rfid_write_jobs_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX rfid_write_jobs_pending ON public.rfid_write_jobs USING btree (store_id, created_at) WHERE (status = ANY (ARRAY['pending'::text, 'working'::text]));


--
-- Name: rfid_write_jobs_piece_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX rfid_write_jobs_piece_id_fk_idx ON public.rfid_write_jobs USING btree (piece_id);


--
-- Name: staff_presence_store_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX staff_presence_store_idx ON public.staff_presence USING btree (store_id);


--
-- Name: staff_salaries_staff_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX staff_salaries_staff_id_fk_idx ON public.staff_salaries USING btree (staff_id);


--
-- Name: staff_salaries_updated_by_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX staff_salaries_updated_by_fk_idx ON public.staff_salaries USING btree (updated_by);


--
-- Name: staff_store_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX staff_store_id_fk_idx ON public.staff USING btree (store_id);


--
-- Name: stock_voucher_lines_party_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX stock_voucher_lines_party_idx ON public.stock_voucher_lines USING btree (party_id);


--
-- Name: stock_voucher_lines_piece_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX stock_voucher_lines_piece_id_fk_idx ON public.stock_voucher_lines USING btree (piece_id);


--
-- Name: stock_voucher_lines_store_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX stock_voucher_lines_store_id_fk_idx ON public.stock_voucher_lines USING btree (store_id);


--
-- Name: stock_voucher_lines_voucher_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX stock_voucher_lines_voucher_id_fk_idx ON public.stock_voucher_lines USING btree (voucher_id);


--
-- Name: stock_vouchers_created_by_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX stock_vouchers_created_by_fk_idx ON public.stock_vouchers USING btree (created_by);


--
-- Name: stock_vouchers_party_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX stock_vouchers_party_id_fk_idx ON public.stock_vouchers USING btree (party_id);


--
-- Name: stock_vouchers_store_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX stock_vouchers_store_idx ON public.stock_vouchers USING btree (store_id, created_at DESC);


--
-- Name: store_invites_invited_by_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX store_invites_invited_by_fk_idx ON public.store_invites USING btree (invited_by);


--
-- Name: store_invites_unique_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX store_invites_unique_pending ON public.store_invites USING btree (store_id, lower(email)) WHERE (status = 'pending'::text);


--
-- Name: stores_org_branch_code_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX stores_org_branch_code_key ON public.stores USING btree (organization_id, branch_code) WHERE (branch_code IS NOT NULL);


--
-- Name: stores_organization_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX stores_organization_id_fk_idx ON public.stores USING btree (organization_id);


--
-- Name: subscriptions_one_per_store; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX subscriptions_one_per_store ON public.subscriptions USING btree (store_id);


--
-- Name: subscriptions_pending_upgrade_plan_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX subscriptions_pending_upgrade_plan_id_fk_idx ON public.subscriptions USING btree (pending_upgrade_plan_id);


--
-- Name: subscriptions_plan_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX subscriptions_plan_id_fk_idx ON public.subscriptions USING btree (plan_id);


--
-- Name: support_requests_created_by_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX support_requests_created_by_fk_idx ON public.support_requests USING btree (created_by);


--
-- Name: support_requests_store_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX support_requests_store_id_fk_idx ON public.support_requests USING btree (store_id);


--
-- Name: trader_movements_created_by_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX trader_movements_created_by_fk_idx ON public.trader_movements USING btree (created_by);


--
-- Name: trader_movements_gold_stock_lot_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX trader_movements_gold_stock_lot_id_fk_idx ON public.trader_movements USING btree (gold_stock_lot_id);


--
-- Name: trader_movements_invoice_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX trader_movements_invoice_id_fk_idx ON public.trader_movements USING btree (invoice_id);


--
-- Name: trader_movements_piece_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX trader_movements_piece_id_fk_idx ON public.trader_movements USING btree (piece_id);


--
-- Name: trader_movements_store_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX trader_movements_store_id_fk_idx ON public.trader_movements USING btree (store_id);


--
-- Name: trader_movements_trader_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX trader_movements_trader_id_fk_idx ON public.trader_movements USING btree (trader_id);


--
-- Name: trader_scrap_draws_movement_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX trader_scrap_draws_movement_idx ON public.trader_scrap_draws USING btree (movement_id);


--
-- Name: traders_store_id_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX traders_store_id_fk_idx ON public.traders USING btree (store_id);


--
-- Name: zebra_label_fields_store_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX zebra_label_fields_store_idx ON public.zebra_label_fields USING btree (store_id, column_num, row_order);


--
-- Name: cash_movements audit_cash_movements; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_cash_movements AFTER INSERT ON public.cash_movements FOR EACH ROW EXECUTE FUNCTION public.log_audit_event();


--
-- Name: customers audit_customers; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_customers AFTER INSERT OR DELETE ON public.customers FOR EACH ROW EXECUTE FUNCTION public.log_audit_event();


--
-- Name: invoices audit_invoices; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_invoices AFTER INSERT OR DELETE OR UPDATE ON public.invoices FOR EACH ROW EXECUTE FUNCTION public.log_audit_event();


--
-- Name: pieces audit_pieces; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_pieces AFTER INSERT OR DELETE OR UPDATE ON public.pieces FOR EACH ROW EXECUTE FUNCTION public.log_audit_event();


--
-- Name: staff trg_auto_upgrade_on_staff_change; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_auto_upgrade_on_staff_change AFTER INSERT OR DELETE ON public.staff FOR EACH ROW EXECUTE FUNCTION public.auto_upgrade_on_staff_change();


--
-- Name: staff trg_auto_upgrade_on_staff_login; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_auto_upgrade_on_staff_login AFTER UPDATE OF user_id ON public.staff FOR EACH ROW WHEN (((old.user_id IS NULL) AND (new.user_id IS NOT NULL))) EXECUTE FUNCTION public.auto_upgrade_on_staff_change();


--
-- Name: daily_cash_log trg_cash_log_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_cash_log_guard BEFORE INSERT OR DELETE OR UPDATE ON public.daily_cash_log FOR EACH ROW EXECUTE FUNCTION public.gm_cash_log_guard();


--
-- Name: cash_movements trg_cash_movement_deleted_bank_sync; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_cash_movement_deleted_bank_sync AFTER DELETE ON public.cash_movements FOR EACH ROW EXECUTE FUNCTION public.trg_cash_movement_deleted_bank_sync();


--
-- Name: cash_movements trg_cash_movement_updated_daily_sync; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_cash_movement_updated_daily_sync AFTER UPDATE OF amount, direction, fx_amount ON public.cash_movements FOR EACH ROW EXECUTE FUNCTION public.trg_cash_movement_updated_daily_sync();


--
-- Name: cash_movements trg_cash_movements_currency; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_cash_movements_currency BEFORE INSERT ON public.cash_movements FOR EACH ROW EXECUTE FUNCTION public.fill_currency_from_store();


--
-- Name: customer_debts trg_customer_debts_allocate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_customer_debts_allocate AFTER INSERT ON public.customer_debts FOR EACH ROW WHEN ((new.source IS DISTINCT FROM 'allocation'::text)) EXECUTE FUNCTION public.trg_customer_debts_allocate();


--
-- Name: customer_debts trg_customer_debts_currency; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_customer_debts_currency BEFORE INSERT ON public.customer_debts FOR EACH ROW EXECUTE FUNCTION public.fill_currency_from_store();


--
-- Name: customer_deposits trg_customer_deposits_currency; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_customer_deposits_currency BEFORE INSERT ON public.customer_deposits FOR EACH ROW EXECUTE FUNCTION public.fill_currency_from_store();


--
-- Name: daily_cash_log trg_daily_cash_log_currency; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_daily_cash_log_currency BEFORE INSERT ON public.daily_cash_log FOR EACH ROW EXECUTE FUNCTION public.fill_currency_from_store();


--
-- Name: daily_cash_log trg_daily_label; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_daily_label BEFORE INSERT ON public.daily_cash_log FOR EACH ROW EXECUTE FUNCTION public.trg_daily_label();


--
-- Name: gold_prices trg_gold_prices_currency_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_gold_prices_currency_guard BEFORE INSERT OR UPDATE OF price_per_gram, karat ON public.gold_prices FOR EACH ROW EXECUTE FUNCTION public.gold_prices_currency_guard();


--
-- Name: invoices trg_invoice_bank_part_sync; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_invoice_bank_part_sync AFTER UPDATE ON public.invoices FOR EACH ROW EXECUTE FUNCTION public.trg_invoice_bank_part_sync();


--
-- Name: invoices trg_invoice_salesperson; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_invoice_salesperson BEFORE INSERT OR UPDATE OF salesperson_id ON public.invoices FOR EACH ROW EXECUTE FUNCTION public.gm_seller_stamp();


--
-- Name: invoices trg_invoice_status_piece_log; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_invoice_status_piece_log AFTER UPDATE OF status ON public.invoices FOR EACH ROW EXECUTE FUNCTION public.trg_invoice_status_piece_log();


--
-- Name: invoices trg_invoices_currency_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_invoices_currency_guard BEFORE INSERT ON public.invoices FOR EACH ROW EXECUTE FUNCTION public.invoices_currency_guard();


--
-- Name: cash_movements trg_mirror_invoice_cash_to_daily; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_mirror_invoice_cash_to_daily AFTER INSERT ON public.cash_movements FOR EACH ROW EXECUTE FUNCTION public.mirror_invoice_cash_to_daily();


--
-- Name: cash_movements trg_op_date; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_op_date BEFORE INSERT ON public.cash_movements FOR EACH ROW EXECUTE FUNCTION public.gm_op_date_stamp();


--
-- Name: customer_debts trg_op_date; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_op_date BEFORE INSERT ON public.customer_debts FOR EACH ROW EXECUTE FUNCTION public.gm_op_date_stamp();


--
-- Name: daily_cash_log trg_op_date; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_op_date BEFORE INSERT ON public.daily_cash_log FOR EACH ROW EXECUTE FUNCTION public.gm_op_date_stamp();


--
-- Name: piece_movements trg_op_date; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_op_date BEFORE INSERT ON public.piece_movements FOR EACH ROW EXECUTE FUNCTION public.gm_op_date_stamp();


--
-- Name: trader_movements trg_op_date; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_op_date BEFORE INSERT ON public.trader_movements FOR EACH ROW EXECUTE FUNCTION public.gm_op_date_stamp();


--
-- Name: organizations trg_org_head_office_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_org_head_office_check BEFORE INSERT OR UPDATE OF head_office_store_id ON public.organizations FOR EACH ROW EXECUTE FUNCTION public.check_head_office_in_org();


--
-- Name: pieces trg_piece_draws_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_piece_draws_delete BEFORE DELETE ON public.pieces FOR EACH ROW EXECUTE FUNCTION public.trg_piece_draws_delete();


--
-- Name: pieces trg_piece_draws_weight; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_piece_draws_weight BEFORE UPDATE OF weight_grams ON public.pieces FOR EACH ROW EXECUTE FUNCTION public.trg_piece_draws_weight();


--
-- Name: trader_movements trg_scrap_given_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_scrap_given_guard BEFORE DELETE OR UPDATE ON public.trader_movements FOR EACH ROW WHEN ((old.source = 'scrap_given'::text)) EXECUTE FUNCTION public.trg_scrap_given_guard();


--
-- Name: invoice_items trg_scrap_price_at_purchase; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_scrap_price_at_purchase BEFORE INSERT ON public.invoice_items FOR EACH ROW EXECUTE FUNCTION public.gm_scrap_price_at_purchase();


--
-- Name: stores trg_seed_default_zebra_label_fields; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_seed_default_zebra_label_fields AFTER INSERT ON public.stores FOR EACH ROW EXECUTE FUNCTION public.seed_default_zebra_label_fields();


--
-- Name: trader_movements trg_settlement_lot_sync; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_settlement_lot_sync AFTER DELETE OR UPDATE ON public.trader_movements FOR EACH ROW EXECUTE FUNCTION public.trg_settlement_lot_sync();


--
-- Name: staff trg_staff_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_staff_guard BEFORE INSERT OR DELETE OR UPDATE ON public.staff FOR EACH ROW EXECUTE FUNCTION public.gm_staff_guard();


--
-- Name: stores trg_stores_currency_convert_gold; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_stores_currency_convert_gold AFTER UPDATE OF currency ON public.stores FOR EACH ROW EXECUTE FUNCTION public.stores_currency_convert_gold();


--
-- Name: stores trg_stores_currency_usd_reprice; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_stores_currency_usd_reprice BEFORE UPDATE OF currency ON public.stores FOR EACH ROW EXECUTE FUNCTION public.stores_currency_usd_reprice();


--
-- Name: stores trg_stores_ensure_org; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_stores_ensure_org AFTER INSERT ON public.stores FOR EACH ROW WHEN ((new.organization_id IS NULL)) EXECUTE FUNCTION public.ensure_store_organization();


--
-- Name: stores trg_stores_sync_country; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_stores_sync_country AFTER UPDATE OF country ON public.stores FOR EACH ROW WHEN ((old.country IS DISTINCT FROM new.country)) EXECUTE FUNCTION public.sync_store_country_to_org();


--
-- Name: staff trg_sync_staff_to_hr_employee; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_sync_staff_to_hr_employee AFTER INSERT ON public.staff FOR EACH ROW EXECUTE FUNCTION public.sync_staff_to_hr_employee();


--
-- Name: trader_movements trg_tm_snapshot; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_tm_snapshot BEFORE INSERT ON public.trader_movements FOR EACH ROW EXECUTE FUNCTION public.gm_tm_snapshot();


--
-- Name: trader_movements trg_trader_received_sync; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_trader_received_sync BEFORE UPDATE ON public.trader_movements FOR EACH ROW WHEN (((new.source = 'stock_received'::text) AND ((new.piece_id IS NOT NULL) OR (new.gold_stock_lot_id IS NOT NULL)))) EXECUTE FUNCTION public.trg_trader_received_sync();


--
-- Name: audit_log audit_log_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(id);


--
-- Name: audit_log audit_log_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: auth_device_keys auth_device_keys_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_device_keys
    ADD CONSTRAINT auth_device_keys_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: auth_passkeys auth_passkeys_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_passkeys
    ADD CONSTRAINT auth_passkeys_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: auth_webauthn_challenges auth_webauthn_challenges_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_webauthn_challenges
    ADD CONSTRAINT auth_webauthn_challenges_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: branch_transfer_items branch_transfer_items_diamond_piece_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branch_transfer_items
    ADD CONSTRAINT branch_transfer_items_diamond_piece_id_fkey FOREIGN KEY (diamond_piece_id) REFERENCES public.diamond_pieces(id) ON DELETE SET NULL;


--
-- Name: branch_transfer_items branch_transfer_items_piece_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branch_transfer_items
    ADD CONSTRAINT branch_transfer_items_piece_id_fkey FOREIGN KEY (piece_id) REFERENCES public.pieces(id) ON DELETE SET NULL;


--
-- Name: branch_transfer_items branch_transfer_items_received_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branch_transfer_items
    ADD CONSTRAINT branch_transfer_items_received_by_fkey FOREIGN KEY (received_by) REFERENCES public.staff(id);


--
-- Name: branch_transfer_items branch_transfer_items_transfer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branch_transfer_items
    ADD CONSTRAINT branch_transfer_items_transfer_id_fkey FOREIGN KEY (transfer_id) REFERENCES public.branch_transfers(id) ON DELETE CASCADE;


--
-- Name: branch_transfers branch_transfers_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branch_transfers
    ADD CONSTRAINT branch_transfers_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.staff(id);


--
-- Name: branch_transfers branch_transfers_from_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branch_transfers
    ADD CONSTRAINT branch_transfers_from_store_id_fkey FOREIGN KEY (from_store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: branch_transfers branch_transfers_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branch_transfers
    ADD CONSTRAINT branch_transfers_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: branch_transfers branch_transfers_received_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branch_transfers
    ADD CONSTRAINT branch_transfers_received_by_fkey FOREIGN KEY (received_by) REFERENCES public.staff(id);


--
-- Name: branch_transfers branch_transfers_to_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branch_transfers
    ADD CONSTRAINT branch_transfers_to_store_id_fkey FOREIGN KEY (to_store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: cash_movements cash_movements_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_movements
    ADD CONSTRAINT cash_movements_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.staff(id);


--
-- Name: cash_movements cash_movements_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_movements
    ADD CONSTRAINT cash_movements_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id);


--
-- Name: cash_movements cash_movements_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_movements
    ADD CONSTRAINT cash_movements_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: cash_movements cash_movements_trader_movement_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_movements
    ADD CONSTRAINT cash_movements_trader_movement_id_fkey FOREIGN KEY (trader_movement_id) REFERENCES public.trader_movements(id) ON DELETE SET NULL;


--
-- Name: client_errors client_errors_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_errors
    ADD CONSTRAINT client_errors_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: company_kyc_documents company_kyc_documents_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_kyc_documents
    ADD CONSTRAINT company_kyc_documents_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: company_kyc_documents company_kyc_documents_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_kyc_documents
    ADD CONSTRAINT company_kyc_documents_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES public.staff(id);


--
-- Name: customer_debts customer_debts_cash_movement_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_debts
    ADD CONSTRAINT customer_debts_cash_movement_id_fkey FOREIGN KEY (cash_movement_id) REFERENCES public.cash_movements(id) ON DELETE SET NULL;


--
-- Name: customer_debts customer_debts_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_debts
    ADD CONSTRAINT customer_debts_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.staff(id);


--
-- Name: customer_debts customer_debts_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_debts
    ADD CONSTRAINT customer_debts_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE CASCADE;


--
-- Name: customer_debts customer_debts_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_debts
    ADD CONSTRAINT customer_debts_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id);


--
-- Name: customer_debts customer_debts_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_debts
    ADD CONSTRAINT customer_debts_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: customer_deposits customer_deposits_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_deposits
    ADD CONSTRAINT customer_deposits_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.staff(id) ON DELETE SET NULL;


--
-- Name: customer_deposits customer_deposits_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_deposits
    ADD CONSTRAINT customer_deposits_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: customer_deposits customer_deposits_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_deposits
    ADD CONSTRAINT customer_deposits_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: customer_phones customer_phones_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_phones
    ADD CONSTRAINT customer_phones_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE CASCADE;


--
-- Name: customer_phones customer_phones_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_phones
    ADD CONSTRAINT customer_phones_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: customers customers_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: daily_cash_log daily_cash_log_bank_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_cash_log
    ADD CONSTRAINT daily_cash_log_bank_invoice_id_fkey FOREIGN KEY (bank_invoice_id) REFERENCES public.invoices(id) ON DELETE CASCADE;


--
-- Name: daily_cash_log daily_cash_log_cash_movement_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_cash_log
    ADD CONSTRAINT daily_cash_log_cash_movement_id_fkey FOREIGN KEY (cash_movement_id) REFERENCES public.cash_movements(id) ON DELETE CASCADE;


--
-- Name: daily_cash_log daily_cash_log_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_cash_log
    ADD CONSTRAINT daily_cash_log_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.staff(id);


--
-- Name: daily_cash_log daily_cash_log_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_cash_log
    ADD CONSTRAINT daily_cash_log_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: diamond_pieces diamond_pieces_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.diamond_pieces
    ADD CONSTRAINT diamond_pieces_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.staff(id);


--
-- Name: diamond_pieces diamond_pieces_diamond_stock_lot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.diamond_pieces
    ADD CONSTRAINT diamond_pieces_diamond_stock_lot_id_fkey FOREIGN KEY (diamond_stock_lot_id) REFERENCES public.diamond_stock_lots(id);


--
-- Name: diamond_pieces diamond_pieces_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.diamond_pieces
    ADD CONSTRAINT diamond_pieces_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: diamond_stock_lots diamond_stock_lots_source_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.diamond_stock_lots
    ADD CONSTRAINT diamond_stock_lots_source_invoice_id_fkey FOREIGN KEY (source_invoice_id) REFERENCES public.invoices(id);


--
-- Name: diamond_stock_lots diamond_stock_lots_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.diamond_stock_lots
    ADD CONSTRAINT diamond_stock_lots_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: diamond_stock_lots diamond_stock_lots_trader_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.diamond_stock_lots
    ADD CONSTRAINT diamond_stock_lots_trader_id_fkey FOREIGN KEY (trader_id) REFERENCES public.traders(id);


--
-- Name: expense_categories expense_categories_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expense_categories
    ADD CONSTRAINT expense_categories_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: expense_entries expense_entries_cash_movement_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expense_entries
    ADD CONSTRAINT expense_entries_cash_movement_id_fkey FOREIGN KEY (cash_movement_id) REFERENCES public.cash_movements(id) ON DELETE SET NULL;


--
-- Name: expense_entries expense_entries_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expense_entries
    ADD CONSTRAINT expense_entries_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.expense_categories(id);


--
-- Name: expense_entries expense_entries_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expense_entries
    ADD CONSTRAINT expense_entries_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.staff(id);


--
-- Name: expense_entries expense_entries_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expense_entries
    ADD CONSTRAINT expense_entries_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: fiscal_year_closures fiscal_year_closures_closed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fiscal_year_closures
    ADD CONSTRAINT fiscal_year_closures_closed_by_fkey FOREIGN KEY (closed_by) REFERENCES public.staff(id);


--
-- Name: fiscal_year_closures fiscal_year_closures_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fiscal_year_closures
    ADD CONSTRAINT fiscal_year_closures_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: gold_prices gold_prices_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gold_prices
    ADD CONSTRAINT gold_prices_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: gold_stock_lots gold_stock_lots_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gold_stock_lots
    ADD CONSTRAINT gold_stock_lots_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.staff(id);


--
-- Name: gold_stock_lots gold_stock_lots_source_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gold_stock_lots
    ADD CONSTRAINT gold_stock_lots_source_invoice_id_fkey FOREIGN KEY (source_invoice_id) REFERENCES public.invoices(id);


--
-- Name: gold_stock_lots gold_stock_lots_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gold_stock_lots
    ADD CONSTRAINT gold_stock_lots_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: gold_stock_lots gold_stock_lots_trader_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gold_stock_lots
    ADD CONSTRAINT gold_stock_lots_trader_id_fkey FOREIGN KEY (trader_id) REFERENCES public.traders(id);


--
-- Name: hr_employees hr_employees_linked_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hr_employees
    ADD CONSTRAINT hr_employees_linked_staff_id_fkey FOREIGN KEY (linked_staff_id) REFERENCES public.staff(id) ON DELETE SET NULL;


--
-- Name: hr_employees hr_employees_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hr_employees
    ADD CONSTRAINT hr_employees_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: hr_leave_requests hr_leave_requests_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hr_leave_requests
    ADD CONSTRAINT hr_leave_requests_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.hr_employees(id);


--
-- Name: hr_leave_requests hr_leave_requests_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hr_leave_requests
    ADD CONSTRAINT hr_leave_requests_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: inventory_count_expected inventory_count_expected_count_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_count_expected
    ADD CONSTRAINT inventory_count_expected_count_id_fkey FOREIGN KEY (count_id) REFERENCES public.inventory_counts(id) ON DELETE CASCADE;


--
-- Name: inventory_count_expected inventory_count_expected_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_count_expected
    ADD CONSTRAINT inventory_count_expected_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: inventory_count_scans inventory_count_scans_count_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_count_scans
    ADD CONSTRAINT inventory_count_scans_count_id_fkey FOREIGN KEY (count_id) REFERENCES public.inventory_counts(id) ON DELETE CASCADE;


--
-- Name: inventory_count_scans inventory_count_scans_piece_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_count_scans
    ADD CONSTRAINT inventory_count_scans_piece_id_fkey FOREIGN KEY (piece_id) REFERENCES public.pieces(id);


--
-- Name: inventory_count_scans inventory_count_scans_scanned_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_count_scans
    ADD CONSTRAINT inventory_count_scans_scanned_by_fkey FOREIGN KEY (scanned_by) REFERENCES public.staff(id);


--
-- Name: inventory_count_scans inventory_count_scans_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_count_scans
    ADD CONSTRAINT inventory_count_scans_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: inventory_counts inventory_counts_started_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_counts
    ADD CONSTRAINT inventory_counts_started_by_fkey FOREIGN KEY (started_by) REFERENCES public.staff(id);


--
-- Name: inventory_counts inventory_counts_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_counts
    ADD CONSTRAINT inventory_counts_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: inventory_gifts inventory_gifts_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_gifts
    ADD CONSTRAINT inventory_gifts_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.staff(id);


--
-- Name: inventory_gifts inventory_gifts_expense_entry_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_gifts
    ADD CONSTRAINT inventory_gifts_expense_entry_id_fkey FOREIGN KEY (expense_entry_id) REFERENCES public.expense_entries(id) ON DELETE SET NULL;


--
-- Name: inventory_gifts inventory_gifts_piece_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_gifts
    ADD CONSTRAINT inventory_gifts_piece_id_fkey FOREIGN KEY (piece_id) REFERENCES public.pieces(id);


--
-- Name: inventory_gifts inventory_gifts_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_gifts
    ADD CONSTRAINT inventory_gifts_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: invoice_items invoice_items_diamond_piece_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_items
    ADD CONSTRAINT invoice_items_diamond_piece_id_fkey FOREIGN KEY (diamond_piece_id) REFERENCES public.diamond_pieces(id);


--
-- Name: invoice_items invoice_items_diamond_stock_lot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_items
    ADD CONSTRAINT invoice_items_diamond_stock_lot_id_fkey FOREIGN KEY (diamond_stock_lot_id) REFERENCES public.diamond_stock_lots(id);


--
-- Name: invoice_items invoice_items_gold_stock_lot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_items
    ADD CONSTRAINT invoice_items_gold_stock_lot_id_fkey FOREIGN KEY (gold_stock_lot_id) REFERENCES public.gold_stock_lots(id);


--
-- Name: invoice_items invoice_items_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_items
    ADD CONSTRAINT invoice_items_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id) ON DELETE CASCADE;


--
-- Name: invoice_items invoice_items_piece_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_items
    ADD CONSTRAINT invoice_items_piece_id_fkey FOREIGN KEY (piece_id) REFERENCES public.pieces(id);


--
-- Name: invoice_items invoice_items_returned_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_items
    ADD CONSTRAINT invoice_items_returned_item_id_fkey FOREIGN KEY (returned_item_id) REFERENCES public.invoice_items(id);


--
-- Name: invoice_number_counters invoice_number_counters_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_number_counters
    ADD CONSTRAINT invoice_number_counters_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: invoices invoices_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.staff(id);


--
-- Name: invoices invoices_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: invoices invoices_related_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_related_invoice_id_fkey FOREIGN KEY (related_invoice_id) REFERENCES public.invoices(id);


--
-- Name: invoices invoices_seller_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_seller_id_fkey FOREIGN KEY (salesperson_id) REFERENCES public.staff(id) ON DELETE SET NULL;


--
-- Name: invoices invoices_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: invoices invoices_trader_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_trader_id_fkey FOREIGN KEY (trader_id) REFERENCES public.traders(id);


--
-- Name: kyc_screenings kyc_screenings_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kyc_screenings
    ADD CONSTRAINT kyc_screenings_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: login_2fa login_2fa_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.login_2fa
    ADD CONSTRAINT login_2fa_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: organizations organizations_head_office_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_head_office_store_id_fkey FOREIGN KEY (head_office_store_id) REFERENCES public.stores(id) ON DELETE SET NULL;


--
-- Name: organizations organizations_primary_store_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_primary_store_fk FOREIGN KEY (primary_store_id) REFERENCES public.stores(id) ON DELETE SET NULL;


--
-- Name: payroll_payments payroll_payments_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_payments
    ADD CONSTRAINT payroll_payments_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.staff(id);


--
-- Name: payroll_payments payroll_payments_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_payments
    ADD CONSTRAINT payroll_payments_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(id) ON DELETE CASCADE;


--
-- Name: payroll_payments payroll_payments_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_payments
    ADD CONSTRAINT payroll_payments_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: piece_barcode_history piece_barcode_history_changed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.piece_barcode_history
    ADD CONSTRAINT piece_barcode_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: piece_barcode_history piece_barcode_history_piece_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.piece_barcode_history
    ADD CONSTRAINT piece_barcode_history_piece_id_fkey FOREIGN KEY (piece_id) REFERENCES public.pieces(id) ON DELETE SET NULL;


--
-- Name: piece_barcode_history piece_barcode_history_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.piece_barcode_history
    ADD CONSTRAINT piece_barcode_history_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: piece_chip_history piece_chip_history_changed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.piece_chip_history
    ADD CONSTRAINT piece_chip_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: piece_chip_history piece_chip_history_piece_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.piece_chip_history
    ADD CONSTRAINT piece_chip_history_piece_id_fkey FOREIGN KEY (piece_id) REFERENCES public.pieces(id) ON DELETE SET NULL;


--
-- Name: piece_chip_history piece_chip_history_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.piece_chip_history
    ADD CONSTRAINT piece_chip_history_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: piece_classification_options piece_classification_options_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.piece_classification_options
    ADD CONSTRAINT piece_classification_options_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.staff(id);


--
-- Name: piece_classification_options piece_classification_options_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.piece_classification_options
    ADD CONSTRAINT piece_classification_options_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: piece_intake_batches piece_intake_batches_source_lot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.piece_intake_batches
    ADD CONSTRAINT piece_intake_batches_source_lot_id_fkey FOREIGN KEY (source_lot_id) REFERENCES public.gold_stock_lots(id);


--
-- Name: piece_intake_batches piece_intake_batches_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.piece_intake_batches
    ADD CONSTRAINT piece_intake_batches_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: piece_lot_draws piece_lot_draws_lot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.piece_lot_draws
    ADD CONSTRAINT piece_lot_draws_lot_id_fkey FOREIGN KEY (lot_id) REFERENCES public.gold_stock_lots(id) ON DELETE CASCADE;


--
-- Name: piece_lot_draws piece_lot_draws_piece_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.piece_lot_draws
    ADD CONSTRAINT piece_lot_draws_piece_id_fkey FOREIGN KEY (piece_id) REFERENCES public.pieces(id) ON DELETE CASCADE;


--
-- Name: piece_lot_draws piece_lot_draws_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.piece_lot_draws
    ADD CONSTRAINT piece_lot_draws_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: piece_movements piece_movements_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.piece_movements
    ADD CONSTRAINT piece_movements_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.staff(id);


--
-- Name: piece_movements piece_movements_piece_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.piece_movements
    ADD CONSTRAINT piece_movements_piece_id_fkey FOREIGN KEY (piece_id) REFERENCES public.pieces(id) ON DELETE CASCADE;


--
-- Name: piece_movements piece_movements_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.piece_movements
    ADD CONSTRAINT piece_movements_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: pieces pieces_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pieces
    ADD CONSTRAINT pieces_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.staff(id);


--
-- Name: pieces pieces_intake_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pieces
    ADD CONSTRAINT pieces_intake_batch_id_fkey FOREIGN KEY (intake_batch_id) REFERENCES public.piece_intake_batches(id);


--
-- Name: pieces pieces_reserved_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pieces
    ADD CONSTRAINT pieces_reserved_customer_id_fkey FOREIGN KEY (reserved_customer_id) REFERENCES public.customers(id) ON DELETE SET NULL;


--
-- Name: pieces pieces_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pieces
    ADD CONSTRAINT pieces_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: platform_admins platform_admins_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_admins
    ADD CONSTRAINT platform_admins_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: repair_gold_lines repair_gold_lines_expense_entry_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.repair_gold_lines
    ADD CONSTRAINT repair_gold_lines_expense_entry_id_fkey FOREIGN KEY (expense_entry_id) REFERENCES public.expense_entries(id) ON DELETE CASCADE;


--
-- Name: repair_gold_lines repair_gold_lines_lot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.repair_gold_lines
    ADD CONSTRAINT repair_gold_lines_lot_id_fkey FOREIGN KEY (lot_id) REFERENCES public.gold_stock_lots(id);


--
-- Name: repair_tickets repair_tickets_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.repair_tickets
    ADD CONSTRAINT repair_tickets_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: repair_tickets repair_tickets_delivered_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.repair_tickets
    ADD CONSTRAINT repair_tickets_delivered_by_fkey FOREIGN KEY (delivered_by) REFERENCES public.staff(id);


--
-- Name: repair_tickets repair_tickets_received_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.repair_tickets
    ADD CONSTRAINT repair_tickets_received_by_fkey FOREIGN KEY (received_by) REFERENCES public.staff(id);


--
-- Name: repair_tickets repair_tickets_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.repair_tickets
    ADD CONSTRAINT repair_tickets_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: rfid_write_jobs rfid_write_jobs_piece_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rfid_write_jobs
    ADD CONSTRAINT rfid_write_jobs_piece_id_fkey FOREIGN KEY (piece_id) REFERENCES public.pieces(id);


--
-- Name: rfid_write_jobs rfid_write_jobs_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rfid_write_jobs
    ADD CONSTRAINT rfid_write_jobs_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: staff_presence staff_presence_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_presence
    ADD CONSTRAINT staff_presence_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(id) ON DELETE CASCADE;


--
-- Name: staff_presence staff_presence_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_presence
    ADD CONSTRAINT staff_presence_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: staff_salaries staff_salaries_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_salaries
    ADD CONSTRAINT staff_salaries_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(id) ON DELETE CASCADE;


--
-- Name: staff_salaries staff_salaries_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_salaries
    ADD CONSTRAINT staff_salaries_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: staff_salaries staff_salaries_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_salaries
    ADD CONSTRAINT staff_salaries_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.staff(id);


--
-- Name: staff staff_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff
    ADD CONSTRAINT staff_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: staff staff_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff
    ADD CONSTRAINT staff_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: stock_parties stock_parties_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_parties
    ADD CONSTRAINT stock_parties_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: stock_voucher_lines stock_voucher_lines_party_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_voucher_lines
    ADD CONSTRAINT stock_voucher_lines_party_id_fkey FOREIGN KEY (party_id) REFERENCES public.stock_parties(id);


--
-- Name: stock_voucher_lines stock_voucher_lines_piece_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_voucher_lines
    ADD CONSTRAINT stock_voucher_lines_piece_id_fkey FOREIGN KEY (piece_id) REFERENCES public.pieces(id);


--
-- Name: stock_voucher_lines stock_voucher_lines_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_voucher_lines
    ADD CONSTRAINT stock_voucher_lines_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: stock_voucher_lines stock_voucher_lines_voucher_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_voucher_lines
    ADD CONSTRAINT stock_voucher_lines_voucher_id_fkey FOREIGN KEY (voucher_id) REFERENCES public.stock_vouchers(id) ON DELETE CASCADE;


--
-- Name: stock_vouchers stock_vouchers_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_vouchers
    ADD CONSTRAINT stock_vouchers_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.staff(id);


--
-- Name: stock_vouchers stock_vouchers_party_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_vouchers
    ADD CONSTRAINT stock_vouchers_party_id_fkey FOREIGN KEY (party_id) REFERENCES public.stock_parties(id);


--
-- Name: stock_vouchers stock_vouchers_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_vouchers
    ADD CONSTRAINT stock_vouchers_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: store_invites store_invites_invited_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_invites
    ADD CONSTRAINT store_invites_invited_by_fkey FOREIGN KEY (invited_by) REFERENCES public.staff(id);


--
-- Name: store_invites store_invites_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_invites
    ADD CONSTRAINT store_invites_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: stores stores_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stores
    ADD CONSTRAINT stores_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE SET NULL;


--
-- Name: subscriptions subscriptions_pending_upgrade_plan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_pending_upgrade_plan_id_fkey FOREIGN KEY (pending_upgrade_plan_id) REFERENCES public.plans(id);


--
-- Name: subscriptions subscriptions_plan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES public.plans(id);


--
-- Name: subscriptions subscriptions_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: support_requests support_requests_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.support_requests
    ADD CONSTRAINT support_requests_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.staff(id);


--
-- Name: support_requests support_requests_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.support_requests
    ADD CONSTRAINT support_requests_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: trader_movements trader_movements_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trader_movements
    ADD CONSTRAINT trader_movements_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.staff(id);


--
-- Name: trader_movements trader_movements_gold_stock_lot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trader_movements
    ADD CONSTRAINT trader_movements_gold_stock_lot_id_fkey FOREIGN KEY (gold_stock_lot_id) REFERENCES public.gold_stock_lots(id);


--
-- Name: trader_movements trader_movements_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trader_movements
    ADD CONSTRAINT trader_movements_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id);


--
-- Name: trader_movements trader_movements_piece_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trader_movements
    ADD CONSTRAINT trader_movements_piece_id_fkey FOREIGN KEY (piece_id) REFERENCES public.pieces(id);


--
-- Name: trader_movements trader_movements_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trader_movements
    ADD CONSTRAINT trader_movements_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: trader_movements trader_movements_trader_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trader_movements
    ADD CONSTRAINT trader_movements_trader_id_fkey FOREIGN KEY (trader_id) REFERENCES public.traders(id) ON DELETE CASCADE;


--
-- Name: trader_scrap_draws trader_scrap_draws_lot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trader_scrap_draws
    ADD CONSTRAINT trader_scrap_draws_lot_id_fkey FOREIGN KEY (lot_id) REFERENCES public.gold_stock_lots(id);


--
-- Name: trader_scrap_draws trader_scrap_draws_movement_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trader_scrap_draws
    ADD CONSTRAINT trader_scrap_draws_movement_id_fkey FOREIGN KEY (movement_id) REFERENCES public.trader_movements(id) ON DELETE CASCADE;


--
-- Name: traders traders_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.traders
    ADD CONSTRAINT traders_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: user_profiles user_profiles_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_profiles
    ADD CONSTRAINT user_profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: zebra_label_fields zebra_label_fields_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.zebra_label_fields
    ADD CONSTRAINT zebra_label_fields_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: _backup_20260927_intake_batches; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public._backup_20260927_intake_batches ENABLE ROW LEVEL SECURITY;

--
-- Name: _backup_20260927_piece_batches; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public._backup_20260927_piece_batches ENABLE ROW LEVEL SECURITY;

--
-- Name: platform_admins admins can view admin list; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "admins can view admin list" ON public.platform_admins FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.platform_admins pa
  WHERE (pa.id = ( SELECT auth.uid() AS uid)))));


--
-- Name: plans anyone authenticated can view plans; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "anyone authenticated can view plans" ON public.plans FOR SELECT USING ((( SELECT auth.role() AS role) = 'authenticated'::text));


--
-- Name: audit_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_log audit_log_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY audit_log_select ON public.audit_log FOR SELECT USING ((public.is_store_member(store_id) AND public.has_permission('view_reports'::text, store_id)));


--
-- Name: auth_device_keys; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.auth_device_keys ENABLE ROW LEVEL SECURITY;

--
-- Name: auth_passkeys; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.auth_passkeys ENABLE ROW LEVEL SECURITY;

--
-- Name: auth_webauthn_challenges; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.auth_webauthn_challenges ENABLE ROW LEVEL SECURITY;

--
-- Name: organizations branch staff can view their organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "branch staff can view their organization" ON public.organizations FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.stores s
  WHERE ((s.organization_id = organizations.id) AND public.is_store_member(s.id)))));


--
-- Name: branch_transfer_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.branch_transfer_items ENABLE ROW LEVEL SECURITY;

--
-- Name: branch_transfer_items branch_transfer_items_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY branch_transfer_items_select ON public.branch_transfer_items FOR SELECT TO authenticated USING ((transfer_id IN ( SELECT t.id
   FROM public.branch_transfers t
  WHERE (public.is_store_member(t.from_store_id) OR public.is_store_member(t.to_store_id)))));


--
-- Name: branch_transfers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.branch_transfers ENABLE ROW LEVEL SECURITY;

--
-- Name: branch_transfers branch_transfers_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY branch_transfers_select ON public.branch_transfers FOR SELECT TO authenticated USING ((public.is_store_member(from_store_id) OR public.is_store_member(to_store_id)));


--
-- Name: cash_movements; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cash_movements ENABLE ROW LEVEL SECURITY;

--
-- Name: cash_movements cash_movements_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cash_movements_select ON public.cash_movements FOR SELECT USING ((public.is_store_member(store_id) AND public.has_permission('view_profit_report'::text, store_id)));


--
-- Name: cash_movements cash_movements_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cash_movements_write ON public.cash_movements USING ((public.is_store_member(store_id) AND public.has_permission('view_profit_report'::text, store_id))) WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('view_profit_report'::text, store_id)));


--
-- Name: client_errors; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.client_errors ENABLE ROW LEVEL SECURITY;

--
-- Name: company_kyc_documents; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.company_kyc_documents ENABLE ROW LEVEL SECURITY;

--
-- Name: company_register_attempts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.company_register_attempts ENABLE ROW LEVEL SECURITY;

--
-- Name: company_search_attempts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.company_search_attempts ENABLE ROW LEVEL SECURITY;

--
-- Name: customer_debts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customer_debts ENABLE ROW LEVEL SECURITY;

--
-- Name: customer_debts customer_debts_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY customer_debts_select ON public.customer_debts FOR SELECT USING ((public.is_store_member(store_id) AND public.has_permission('view_customers'::text, store_id)));


--
-- Name: customer_debts customer_debts_select_org; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY customer_debts_select_org ON public.customer_debts FOR SELECT TO authenticated USING (public.org_can(store_id, 'view_customers'::text));


--
-- Name: customer_debts customer_debts_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY customer_debts_write ON public.customer_debts USING ((public.is_store_member(store_id) AND public.has_permission('edit_customers'::text, store_id))) WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('edit_customers'::text, store_id)));


--
-- Name: customer_deposits; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customer_deposits ENABLE ROW LEVEL SECURITY;

--
-- Name: customer_deposits customer_deposits_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY customer_deposits_select ON public.customer_deposits FOR SELECT USING ((public.is_store_member(store_id) AND (public.has_permission('view_customers'::text, store_id) OR public.has_permission('manage_daily_cashbox'::text, store_id))));


--
-- Name: customer_deposits customer_deposits_select_org; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY customer_deposits_select_org ON public.customer_deposits FOR SELECT TO authenticated USING (public.org_can(store_id, 'view_customers'::text));


--
-- Name: customer_phones; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customer_phones ENABLE ROW LEVEL SECURITY;

--
-- Name: customer_phones customer_phones_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY customer_phones_select ON public.customer_phones FOR SELECT USING ((public.is_store_member(store_id) AND public.has_permission('view_customers'::text, store_id)));


--
-- Name: customer_phones customer_phones_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY customer_phones_write ON public.customer_phones USING ((public.is_store_member(store_id) AND public.has_permission('edit_customers'::text, store_id))) WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('edit_customers'::text, store_id)));


--
-- Name: customers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

--
-- Name: customers customers_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY customers_delete ON public.customers FOR DELETE USING ((public.is_store_member(store_id) AND public.has_permission('edit_customers'::text, store_id)));


--
-- Name: customers customers_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY customers_insert ON public.customers FOR INSERT WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('add_customers'::text, store_id)));


--
-- Name: customers customers_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY customers_select ON public.customers FOR SELECT USING ((public.is_store_member(store_id) AND public.has_permission('view_customers'::text, store_id)));


--
-- Name: customers customers_select_org; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY customers_select_org ON public.customers FOR SELECT TO authenticated USING (public.org_can(store_id, 'view_customers'::text));


--
-- Name: customers customers_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY customers_update ON public.customers FOR UPDATE USING ((public.is_store_member(store_id) AND public.has_permission('edit_customers'::text, store_id))) WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('edit_customers'::text, store_id)));


--
-- Name: daily_cash_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.daily_cash_log ENABLE ROW LEVEL SECURITY;

--
-- Name: daily_cash_log daily_cash_log_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY daily_cash_log_all ON public.daily_cash_log USING ((public.is_store_member(store_id) AND public.has_permission('manage_daily_cashbox'::text, store_id))) WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('manage_daily_cashbox'::text, store_id)));


--
-- Name: invoices delete_invoice; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY delete_invoice ON public.invoices FOR DELETE USING (public.has_permission('delete_invoice'::text, store_id));


--
-- Name: pieces delete_piece; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY delete_piece ON public.pieces FOR DELETE USING (public.has_permission('delete_piece'::text, store_id));


--
-- Name: diamond_pieces; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.diamond_pieces ENABLE ROW LEVEL SECURITY;

--
-- Name: diamond_pieces diamond_pieces_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY diamond_pieces_insert ON public.diamond_pieces FOR INSERT WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('add_piece'::text, store_id)));


--
-- Name: diamond_pieces diamond_pieces_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY diamond_pieces_select ON public.diamond_pieces FOR SELECT USING (public.is_store_member(store_id));


--
-- Name: diamond_pieces diamond_pieces_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY diamond_pieces_update ON public.diamond_pieces FOR UPDATE USING ((public.is_store_member(store_id) AND public.has_permission('edit_piece'::text, store_id))) WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('edit_piece'::text, store_id)));


--
-- Name: diamond_stock_lots; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.diamond_stock_lots ENABLE ROW LEVEL SECURITY;

--
-- Name: diamond_stock_lots diamond_stock_lots_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY diamond_stock_lots_select ON public.diamond_stock_lots FOR SELECT USING (public.is_store_member(store_id));


--
-- Name: diamond_stock_lots diamond_stock_lots_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY diamond_stock_lots_write ON public.diamond_stock_lots USING ((public.is_store_member(store_id) AND public.has_permission('add_piece'::text, store_id))) WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('add_piece'::text, store_id)));


--
-- Name: pieces edit_piece; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY edit_piece ON public.pieces FOR UPDATE USING (public.has_permission('edit_piece'::text, store_id)) WITH CHECK (public.has_permission('edit_piece'::text, store_id));


--
-- Name: stores edit_settings; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY edit_settings ON public.stores FOR UPDATE USING (public.has_permission('edit_settings'::text, id));


--
-- Name: expense_categories; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.expense_categories ENABLE ROW LEVEL SECURITY;

--
-- Name: expense_categories expense_categories_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY expense_categories_select ON public.expense_categories FOR SELECT USING (public.is_store_member(store_id));


--
-- Name: expense_categories expense_categories_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY expense_categories_write ON public.expense_categories USING ((public.is_store_member(store_id) AND public.has_permission('view_profit_report'::text, store_id))) WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('view_profit_report'::text, store_id)));


--
-- Name: expense_entries; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.expense_entries ENABLE ROW LEVEL SECURITY;

--
-- Name: expense_entries expense_entries_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY expense_entries_select ON public.expense_entries FOR SELECT USING ((public.is_store_member(store_id) AND public.gm_can_expense(store_id)));


--
-- Name: expense_entries expense_entries_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY expense_entries_write ON public.expense_entries USING ((public.is_store_member(store_id) AND public.has_permission('view_profit_report'::text, store_id))) WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('view_profit_report'::text, store_id)));


--
-- Name: fiscal_year_closures; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.fiscal_year_closures ENABLE ROW LEVEL SECURITY;

--
-- Name: gift_cost_adjust_20261006; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.gift_cost_adjust_20261006 ENABLE ROW LEVEL SECURITY;

--
-- Name: inventory_gifts gifts_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY gifts_select ON public.inventory_gifts FOR SELECT USING ((public.has_permission('give_gifts'::text, store_id) OR public.has_permission('view_profit_report'::text, store_id)));


--
-- Name: gold_prices; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.gold_prices ENABLE ROW LEVEL SECURITY;

--
-- Name: gold_prices gold_prices_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY gold_prices_select ON public.gold_prices FOR SELECT USING (public.is_store_member(store_id));


--
-- Name: gold_stock_lots; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.gold_stock_lots ENABLE ROW LEVEL SECURITY;

--
-- Name: gold_stock_lots gold_stock_lots_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY gold_stock_lots_select ON public.gold_stock_lots FOR SELECT USING (public.is_store_member(store_id));


--
-- Name: gold_stock_lots gold_stock_lots_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY gold_stock_lots_write ON public.gold_stock_lots USING ((public.is_store_member(store_id) AND public.has_permission('add_piece'::text, store_id))) WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('add_piece'::text, store_id)));


--
-- Name: hr_employees; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.hr_employees ENABLE ROW LEVEL SECURITY;

--
-- Name: hr_employees hr_employees_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hr_employees_select ON public.hr_employees FOR SELECT USING (public.is_store_member(store_id));


--
-- Name: hr_employees hr_employees_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hr_employees_write ON public.hr_employees USING ((public.is_store_member(store_id) AND public.has_permission('manage_payroll'::text, store_id))) WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('manage_payroll'::text, store_id)));


--
-- Name: hr_leave_requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.hr_leave_requests ENABLE ROW LEVEL SECURITY;

--
-- Name: hr_leave_requests hr_leave_requests_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hr_leave_requests_select ON public.hr_leave_requests FOR SELECT USING (public.is_store_member(store_id));


--
-- Name: hr_leave_requests hr_leave_requests_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hr_leave_requests_write ON public.hr_leave_requests USING ((public.is_store_member(store_id) AND public.has_permission('manage_payroll'::text, store_id))) WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('manage_payroll'::text, store_id)));


--
-- Name: inventory_count_expected; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.inventory_count_expected ENABLE ROW LEVEL SECURITY;

--
-- Name: inventory_count_scans; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.inventory_count_scans ENABLE ROW LEVEL SECURITY;

--
-- Name: inventory_count_scans inventory_count_scans_store_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY inventory_count_scans_store_access ON public.inventory_count_scans USING (public.is_store_member(store_id)) WITH CHECK (public.is_store_member(store_id));


--
-- Name: inventory_counts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.inventory_counts ENABLE ROW LEVEL SECURITY;

--
-- Name: inventory_counts inventory_counts_store_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY inventory_counts_store_access ON public.inventory_counts USING (public.is_store_member(store_id)) WITH CHECK (public.is_store_member(store_id));


--
-- Name: inventory_gifts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.inventory_gifts ENABLE ROW LEVEL SECURITY;

--
-- Name: invoice_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.invoice_items ENABLE ROW LEVEL SECURITY;

--
-- Name: invoice_items invoice_items: members read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "invoice_items: members read" ON public.invoice_items FOR SELECT USING ((invoice_id IN ( SELECT i.id
   FROM public.invoices i
  WHERE public.is_store_member(i.store_id))));


--
-- Name: invoice_items invoice_items_select_org; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY invoice_items_select_org ON public.invoice_items FOR SELECT TO authenticated USING ((invoice_id IN ( SELECT i.id
   FROM public.invoices i
  WHERE public.org_can(i.store_id, 'view_branch_invoices'::text))));


--
-- Name: invoice_number_counters; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.invoice_number_counters ENABLE ROW LEVEL SECURITY;

--
-- Name: invoices; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;

--
-- Name: invoices invoices_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY invoices_insert ON public.invoices FOR INSERT WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('create_invoice'::text, store_id)));


--
-- Name: invoices invoices_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY invoices_select ON public.invoices FOR SELECT USING (public.is_store_member(store_id));


--
-- Name: invoices invoices_select_org; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY invoices_select_org ON public.invoices FOR SELECT TO authenticated USING (public.org_can(store_id, 'view_branch_invoices'::text));


--
-- Name: invoices invoices_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY invoices_update ON public.invoices FOR UPDATE USING ((public.is_store_member(store_id) AND public.has_permission('edit_invoice'::text, store_id))) WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('edit_invoice'::text, store_id)));


--
-- Name: kyc_screenings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.kyc_screenings ENABLE ROW LEVEL SECURITY;

--
-- Name: kyc_screenings kyc_screenings_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY kyc_screenings_select ON public.kyc_screenings FOR SELECT USING (public.is_store_member(store_id));


--
-- Name: kyc_screenings kyc_screenings_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY kyc_screenings_write ON public.kyc_screenings USING ((public.is_store_member(store_id) AND public.has_permission('view_customers'::text, store_id))) WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('view_customers'::text, store_id)));


--
-- Name: login_2fa; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.login_2fa ENABLE ROW LEVEL SECURITY;

--
-- Name: lookup_username_attempts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.lookup_username_attempts ENABLE ROW LEVEL SECURITY;

--
-- Name: store_invites manage own store invites; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "manage own store invites" ON public.store_invites USING ((public.is_store_member(store_id) AND public.has_permission('manage_staff'::text, store_id))) WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('manage_staff'::text, store_id)));


--
-- Name: gold_prices manage_gold_price; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY manage_gold_price ON public.gold_prices USING (public.has_permission('manage_gold_price'::text, store_id)) WITH CHECK (public.has_permission('manage_gold_price'::text, store_id));


--
-- Name: subscriptions manage_subscription can edit subscription; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "manage_subscription can edit subscription" ON public.subscriptions USING ((public.is_store_member(store_id) AND public.has_permission('manage_subscription'::text, store_id))) WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('manage_subscription'::text, store_id)));


--
-- Name: trader_scrap_draws members read scrap draws; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "members read scrap draws" ON public.trader_scrap_draws FOR SELECT USING (public.is_store_member(store_id));


--
-- Name: organizations org owner can update organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "org owner can update organization" ON public.organizations FOR UPDATE TO authenticated USING (public.is_org_owner(id)) WITH CHECK (public.is_org_owner(id));


--
-- Name: organizations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;

--
-- Name: auth_device_keys own device keys: remove; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "own device keys: remove" ON public.auth_device_keys FOR DELETE TO authenticated USING ((user_id = ( SELECT auth.uid() AS uid)));


--
-- Name: auth_device_keys own device keys: view; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "own device keys: view" ON public.auth_device_keys FOR SELECT TO authenticated USING ((user_id = ( SELECT auth.uid() AS uid)));


--
-- Name: auth_passkeys own passkeys: remove; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "own passkeys: remove" ON public.auth_passkeys FOR DELETE TO authenticated USING ((user_id = ( SELECT auth.uid() AS uid)));


--
-- Name: auth_passkeys own passkeys: view; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "own passkeys: view" ON public.auth_passkeys FOR SELECT TO authenticated USING ((user_id = ( SELECT auth.uid() AS uid)));


--
-- Name: user_profiles own profile select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "own profile select" ON public.user_profiles FOR SELECT USING ((id = ( SELECT auth.uid() AS uid)));


--
-- Name: user_profiles own profile update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "own profile update" ON public.user_profiles FOR UPDATE USING ((id = ( SELECT auth.uid() AS uid)));


--
-- Name: user_profiles own profile upsert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "own profile upsert" ON public.user_profiles FOR INSERT WITH CHECK ((id = ( SELECT auth.uid() AS uid)));


--
-- Name: inventory_count_expected owner can delete expected snapshot rows; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "owner can delete expected snapshot rows" ON public.inventory_count_expected FOR DELETE USING (public.has_permission('edit_settings'::text, store_id));


--
-- Name: staff owner or manage_staff can manage staff; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "owner or manage_staff can manage staff" ON public.staff USING ((public.is_store_member(store_id) AND public.has_permission('manage_staff'::text, store_id))) WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('manage_staff'::text, store_id)));


--
-- Name: fiscal_year_closures owners can close a year; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "owners can close a year" ON public.fiscal_year_closures FOR INSERT WITH CHECK ((public.is_store_member(store_id) AND (EXISTS ( SELECT 1
   FROM public.staff
  WHERE ((staff.user_id = ( SELECT auth.uid() AS uid)) AND (staff.store_id = fiscal_year_closures.store_id) AND (staff.role = 'owner'::text))))));


--
-- Name: payroll_payments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payroll_payments ENABLE ROW LEVEL SECURITY;

--
-- Name: payroll_payments payroll_payments_rw; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_payments_rw ON public.payroll_payments USING ((public.is_store_member(store_id) AND public.has_permission('manage_payroll'::text, store_id))) WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('manage_payroll'::text, store_id)));


--
-- Name: piece_barcode_history; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.piece_barcode_history ENABLE ROW LEVEL SECURITY;

--
-- Name: piece_chip_history; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.piece_chip_history ENABLE ROW LEVEL SECURITY;

--
-- Name: piece_classification_options; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.piece_classification_options ENABLE ROW LEVEL SECURITY;

--
-- Name: piece_classification_options piece_classification_options_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY piece_classification_options_insert ON public.piece_classification_options FOR INSERT WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('add_piece'::text, store_id)));


--
-- Name: piece_classification_options piece_classification_options_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY piece_classification_options_select ON public.piece_classification_options FOR SELECT USING (public.is_store_member(store_id));


--
-- Name: piece_classification_options piece_classification_options_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY piece_classification_options_update ON public.piece_classification_options FOR UPDATE USING ((public.is_store_member(store_id) AND public.has_permission('add_piece'::text, store_id))) WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('add_piece'::text, store_id)));


--
-- Name: piece_cost_adjust_20261006; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.piece_cost_adjust_20261006 ENABLE ROW LEVEL SECURITY;

--
-- Name: piece_intake_batches; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.piece_intake_batches ENABLE ROW LEVEL SECURITY;

--
-- Name: piece_lot_draws; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.piece_lot_draws ENABLE ROW LEVEL SECURITY;

--
-- Name: piece_lot_draws piece_lot_draws_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY piece_lot_draws_read ON public.piece_lot_draws FOR SELECT USING (public.is_store_member(store_id));


--
-- Name: piece_movements; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.piece_movements ENABLE ROW LEVEL SECURITY;

--
-- Name: pieces; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pieces ENABLE ROW LEVEL SECURITY;

--
-- Name: pieces pieces_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pieces_insert ON public.pieces FOR INSERT WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('add_piece'::text, store_id)));


--
-- Name: pieces pieces_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pieces_select ON public.pieces FOR SELECT USING (public.is_store_member(store_id));


--
-- Name: plans; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.plans ENABLE ROW LEVEL SECURITY;

--
-- Name: organizations platform admins full access to organizations; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "platform admins full access to organizations" ON public.organizations USING (public.is_platform_admin()) WITH CHECK (public.is_platform_admin());


--
-- Name: client_errors platform admins read errors; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "platform admins read errors" ON public.client_errors FOR SELECT TO authenticated USING (( SELECT public.is_platform_admin() AS is_platform_admin));


--
-- Name: platform_admins; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.platform_admins ENABLE ROW LEVEL SECURITY;

--
-- Name: repair_gold_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.repair_gold_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: repair_tickets; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.repair_tickets ENABLE ROW LEVEL SECURITY;

--
-- Name: repair_tickets repair_tickets_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY repair_tickets_insert ON public.repair_tickets FOR INSERT WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('add_repair'::text, store_id)));


--
-- Name: repair_tickets repair_tickets_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY repair_tickets_select ON public.repair_tickets FOR SELECT USING ((public.is_store_member(store_id) AND public.has_permission('view_repairs'::text, store_id)));


--
-- Name: repair_tickets repair_tickets_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY repair_tickets_update ON public.repair_tickets FOR UPDATE USING ((public.is_store_member(store_id) AND public.has_permission('edit_repair'::text, store_id))) WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('edit_repair'::text, store_id)));


--
-- Name: client_errors report own errors; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "report own errors" ON public.client_errors FOR INSERT TO authenticated WITH CHECK (((user_id = ( SELECT auth.uid() AS uid)) AND ((store_id IS NULL) OR public.is_store_member(store_id))));


--
-- Name: diamond_pieces restrict delete_piece on diamond_pieces; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "restrict delete_piece on diamond_pieces" ON public.diamond_pieces FOR DELETE USING (public.has_permission('delete_piece'::text, store_id));


--
-- Name: rfid_write_jobs rfid_jobs_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rfid_jobs_insert ON public.rfid_write_jobs FOR INSERT WITH CHECK (public.has_permission('edit_piece'::text, store_id));


--
-- Name: rfid_write_jobs rfid_jobs_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rfid_jobs_select ON public.rfid_write_jobs FOR SELECT USING (public.is_store_member(store_id));


--
-- Name: rfid_write_jobs rfid_jobs_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rfid_jobs_update ON public.rfid_write_jobs FOR UPDATE USING (public.has_permission('edit_piece'::text, store_id));


--
-- Name: rfid_write_jobs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.rfid_write_jobs ENABLE ROW LEVEL SECURITY;

--
-- Name: inventory_count_expected run_inventory_count can insert expected snapshot; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "run_inventory_count can insert expected snapshot" ON public.inventory_count_expected FOR INSERT WITH CHECK ((public.has_permission('run_inventory_count'::text, store_id) OR public.has_permission('edit_settings'::text, store_id)));


--
-- Name: stock_parties sp_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sp_insert ON public.stock_parties FOR INSERT WITH CHECK (public.has_permission('stock_transfers'::text, store_id));


--
-- Name: stock_parties sp_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sp_select ON public.stock_parties FOR SELECT USING (public.is_store_member(store_id));


--
-- Name: stock_parties sp_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sp_update ON public.stock_parties FOR UPDATE USING (public.has_permission('stock_transfers'::text, store_id)) WITH CHECK (public.has_permission('stock_transfers'::text, store_id));


--
-- Name: staff; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.staff ENABLE ROW LEVEL SECURITY;

--
-- Name: staff staff can view colleagues; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff can view colleagues" ON public.staff FOR SELECT USING (public.is_store_member(store_id));


--
-- Name: organizations staff can view own organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff can view own organization" ON public.organizations FOR SELECT USING (public.is_store_member(primary_store_id));


--
-- Name: stores staff can view own store; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff can view own store" ON public.stores FOR SELECT USING (public.is_store_member(id));


--
-- Name: staff_presence; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.staff_presence ENABLE ROW LEVEL SECURITY;

--
-- Name: staff_presence staff_presence_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY staff_presence_select ON public.staff_presence FOR SELECT USING (public.is_store_member(store_id));


--
-- Name: staff_salaries; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.staff_salaries ENABLE ROW LEVEL SECURITY;

--
-- Name: staff_salaries staff_salaries_rw; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY staff_salaries_rw ON public.staff_salaries USING ((public.is_store_member(store_id) AND public.has_permission('manage_payroll'::text, store_id))) WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('manage_payroll'::text, store_id)));


--
-- Name: stock_parties; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stock_parties ENABLE ROW LEVEL SECURITY;

--
-- Name: stock_voucher_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stock_voucher_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: stock_vouchers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stock_vouchers ENABLE ROW LEVEL SECURITY;

--
-- Name: invoice_items store access: invoice_items; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "store access: invoice_items" ON public.invoice_items USING ((invoice_id IN ( SELECT i.id
   FROM public.invoices i
  WHERE (public.is_store_member(i.store_id) AND public.has_permission('edit_invoice'::text, i.store_id))))) WITH CHECK ((invoice_id IN ( SELECT i.id
   FROM public.invoices i
  WHERE (public.is_store_member(i.store_id) AND public.has_permission('edit_invoice'::text, i.store_id)))));


--
-- Name: subscriptions store can view own subscription; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "store can view own subscription" ON public.subscriptions FOR SELECT USING (public.is_store_member(store_id));


--
-- Name: company_kyc_documents store members can delete kyc docs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "store members can delete kyc docs" ON public.company_kyc_documents FOR DELETE USING (public.is_store_member(store_id));


--
-- Name: company_kyc_documents store members can insert kyc docs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "store members can insert kyc docs" ON public.company_kyc_documents FOR INSERT WITH CHECK (public.is_store_member(store_id));


--
-- Name: fiscal_year_closures store members can view closures; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "store members can view closures" ON public.fiscal_year_closures FOR SELECT USING (public.is_store_member(store_id));


--
-- Name: inventory_count_expected store members can view expected snapshot; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "store members can view expected snapshot" ON public.inventory_count_expected FOR SELECT USING (public.is_store_member(store_id));


--
-- Name: company_kyc_documents store members can view kyc docs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "store members can view kyc docs" ON public.company_kyc_documents FOR SELECT USING (public.is_store_member(store_id));


--
-- Name: piece_barcode_history store members read barcode history; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "store members read barcode history" ON public.piece_barcode_history FOR SELECT TO authenticated USING (public.is_store_member(store_id));


--
-- Name: piece_chip_history store members read chip history; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "store members read chip history" ON public.piece_chip_history FOR SELECT TO authenticated USING (public.is_store_member(store_id));


--
-- Name: piece_intake_batches store staff can create own intake batches; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "store staff can create own intake batches" ON public.piece_intake_batches FOR INSERT WITH CHECK (public.is_store_member(store_id));


--
-- Name: piece_movements store staff can create piece movements; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "store staff can create piece movements" ON public.piece_movements FOR INSERT WITH CHECK (public.is_store_member(store_id));


--
-- Name: support_requests store staff can create support requests; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "store staff can create support requests" ON public.support_requests FOR INSERT WITH CHECK (public.is_store_member(store_id));


--
-- Name: zebra_label_fields store staff can manage own label fields; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "store staff can manage own label fields" ON public.zebra_label_fields USING ((public.is_store_member(store_id) AND public.has_permission('edit_settings'::text, store_id))) WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('edit_settings'::text, store_id)));


--
-- Name: piece_intake_batches store staff can view own intake batches; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "store staff can view own intake batches" ON public.piece_intake_batches FOR SELECT USING (public.is_store_member(store_id));


--
-- Name: zebra_label_fields store staff can view own label fields; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "store staff can view own label fields" ON public.zebra_label_fields FOR SELECT USING (public.is_store_member(store_id));


--
-- Name: support_requests store staff can view own support requests; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "store staff can view own support requests" ON public.support_requests FOR SELECT USING (public.is_store_member(store_id));


--
-- Name: piece_movements store staff can view piece movements; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "store staff can view piece movements" ON public.piece_movements FOR SELECT USING (public.is_store_member(store_id));


--
-- Name: store_invites; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.store_invites ENABLE ROW LEVEL SECURITY;

--
-- Name: stores; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stores ENABLE ROW LEVEL SECURITY;

--
-- Name: subscriptions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

--
-- Name: support_requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.support_requests ENABLE ROW LEVEL SECURITY;

--
-- Name: stock_vouchers sv_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sv_select ON public.stock_vouchers FOR SELECT USING ((public.has_permission('stock_transfers'::text, store_id) OR public.has_permission('view_reports'::text, store_id)));


--
-- Name: stock_voucher_lines svl_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY svl_select ON public.stock_voucher_lines FOR SELECT USING ((public.has_permission('stock_transfers'::text, store_id) OR public.has_permission('view_reports'::text, store_id)));


--
-- Name: trader_movements; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.trader_movements ENABLE ROW LEVEL SECURITY;

--
-- Name: trader_movements trader_movements_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY trader_movements_select ON public.trader_movements FOR SELECT USING ((public.is_store_member(store_id) AND public.has_permission('view_traders'::text, store_id)));


--
-- Name: trader_movements trader_movements_select_org; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY trader_movements_select_org ON public.trader_movements FOR SELECT TO authenticated USING (public.org_can(store_id, 'view_traders'::text));


--
-- Name: trader_movements trader_movements_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY trader_movements_write ON public.trader_movements USING ((public.is_store_member(store_id) AND public.has_permission('edit_traders'::text, store_id))) WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('edit_traders'::text, store_id)));


--
-- Name: trader_scrap_draws; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.trader_scrap_draws ENABLE ROW LEVEL SECURITY;

--
-- Name: traders; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.traders ENABLE ROW LEVEL SECURITY;

--
-- Name: traders traders_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY traders_delete ON public.traders FOR DELETE USING ((public.is_store_member(store_id) AND public.has_permission('edit_traders'::text, store_id)));


--
-- Name: traders traders_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY traders_insert ON public.traders FOR INSERT WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('add_traders'::text, store_id)));


--
-- Name: traders traders_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY traders_select ON public.traders FOR SELECT USING ((public.is_store_member(store_id) AND public.has_permission('view_traders'::text, store_id)));


--
-- Name: traders traders_select_org; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY traders_select_org ON public.traders FOR SELECT TO authenticated USING (public.org_can(store_id, 'view_traders'::text));


--
-- Name: traders traders_update_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY traders_update_delete ON public.traders FOR UPDATE USING ((public.is_store_member(store_id) AND public.has_permission('edit_traders'::text, store_id))) WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('edit_traders'::text, store_id)));


--
-- Name: user_profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: zebra_label_fields; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.zebra_label_fields ENABLE ROW LEVEL SECURITY;

--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- Name: FUNCTION accounting_health_check(sid uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.accounting_health_check(sid uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.accounting_health_check(sid uuid) TO authenticated;
GRANT ALL ON FUNCTION public.accounting_health_check(sid uuid) TO service_role;


--
-- Name: FUNCTION admin_create_store(company_name text, owner_email text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_create_store(company_name text, owner_email text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_create_store(company_name text, owner_email text) TO authenticated;
GRANT ALL ON FUNCTION public.admin_create_store(company_name text, owner_email text) TO service_role;


--
-- Name: FUNCTION admin_delete_store(target_store_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_delete_store(target_store_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_delete_store(target_store_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.admin_delete_store(target_store_id uuid) TO service_role;


--
-- Name: FUNCTION admin_extend_subscription(target_store_id uuid, p_status text, p_trial_end timestamp with time zone, p_current_period_end timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.admin_extend_subscription(target_store_id uuid, p_status text, p_trial_end timestamp with time zone, p_current_period_end timestamp with time zone) TO anon;
GRANT ALL ON FUNCTION public.admin_extend_subscription(target_store_id uuid, p_status text, p_trial_end timestamp with time zone, p_current_period_end timestamp with time zone) TO authenticated;
GRANT ALL ON FUNCTION public.admin_extend_subscription(target_store_id uuid, p_status text, p_trial_end timestamp with time zone, p_current_period_end timestamp with time zone) TO service_role;


--
-- Name: FUNCTION admin_invite_staff(target_store_id uuid, invite_email text, invite_role text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_invite_staff(target_store_id uuid, invite_email text, invite_role text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_invite_staff(target_store_id uuid, invite_email text, invite_role text) TO authenticated;
GRANT ALL ON FUNCTION public.admin_invite_staff(target_store_id uuid, invite_email text, invite_role text) TO service_role;


--
-- Name: FUNCTION admin_list_platform_admin_accounts(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_list_platform_admin_accounts() FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_list_platform_admin_accounts() TO authenticated;
GRANT ALL ON FUNCTION public.admin_list_platform_admin_accounts() TO service_role;


--
-- Name: FUNCTION admin_list_store_invites(target_store_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_list_store_invites(target_store_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_list_store_invites(target_store_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.admin_list_store_invites(target_store_id uuid) TO service_role;


--
-- Name: FUNCTION admin_list_store_staff(target_store_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_list_store_staff(target_store_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_list_store_staff(target_store_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.admin_list_store_staff(target_store_id uuid) TO service_role;


--
-- Name: FUNCTION admin_list_stores(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.admin_list_stores() TO anon;
GRANT ALL ON FUNCTION public.admin_list_stores() TO authenticated;
GRANT ALL ON FUNCTION public.admin_list_stores() TO service_role;


--
-- Name: FUNCTION admin_list_support_requests(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_list_support_requests() FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_list_support_requests() TO authenticated;
GRANT ALL ON FUNCTION public.admin_list_support_requests() TO service_role;


--
-- Name: FUNCTION admin_remove_staff(target_staff_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_remove_staff(target_staff_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_remove_staff(target_staff_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.admin_remove_staff(target_staff_id uuid) TO service_role;


--
-- Name: FUNCTION admin_revoke_invite(target_invite_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_revoke_invite(target_invite_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_revoke_invite(target_invite_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.admin_revoke_invite(target_invite_id uuid) TO service_role;


--
-- Name: FUNCTION admin_update_store(target_store_id uuid, new_name text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_update_store(target_store_id uuid, new_name text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_update_store(target_store_id uuid, new_name text) TO authenticated;
GRANT ALL ON FUNCTION public.admin_update_store(target_store_id uuid, new_name text) TO service_role;


--
-- Name: FUNCTION admin_update_support_request(request_id uuid, new_status text, reply text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_update_support_request(request_id uuid, new_status text, reply text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_update_support_request(request_id uuid, new_status text, reply text) TO authenticated;
GRANT ALL ON FUNCTION public.admin_update_support_request(request_id uuid, new_status text, reply text) TO service_role;


--
-- Name: FUNCTION auto_upgrade_on_staff_change(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.auto_upgrade_on_staff_change() TO anon;
GRANT ALL ON FUNCTION public.auto_upgrade_on_staff_change() TO authenticated;
GRANT ALL ON FUNCTION public.auto_upgrade_on_staff_change() TO service_role;


--
-- Name: FUNCTION barcode_counter_store(p_store uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.barcode_counter_store(p_store uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.barcode_counter_store(p_store uuid) TO authenticated;
GRANT ALL ON FUNCTION public.barcode_counter_store(p_store uuid) TO service_role;


--
-- Name: FUNCTION cancel_branch_transfer(p_transfer uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cancel_branch_transfer(p_transfer uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cancel_branch_transfer(p_transfer uuid) TO authenticated;
GRANT ALL ON FUNCTION public.cancel_branch_transfer(p_transfer uuid) TO service_role;


--
-- Name: FUNCTION cancel_invoice(target_invoice_id uuid, reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cancel_invoice(target_invoice_id uuid, reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cancel_invoice(target_invoice_id uuid, reason text) TO authenticated;
GRANT ALL ON FUNCTION public.cancel_invoice(target_invoice_id uuid, reason text) TO service_role;


--
-- Name: FUNCTION cash_voucher(p jsonb); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.cash_voucher(p jsonb) TO anon;
GRANT ALL ON FUNCTION public.cash_voucher(p jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.cash_voucher(p jsonb) TO service_role;


--
-- Name: FUNCTION check_head_office_in_org(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.check_head_office_in_org() TO anon;
GRANT ALL ON FUNCTION public.check_head_office_in_org() TO authenticated;
GRANT ALL ON FUNCTION public.check_head_office_in_org() TO service_role;


--
-- Name: FUNCTION check_staff_limit(p_store_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.check_staff_limit(p_store_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.check_staff_limit(p_store_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.check_staff_limit(p_store_id uuid) TO service_role;


--
-- Name: FUNCTION close_fiscal_year(target_store_id uuid, target_year integer, notes text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.close_fiscal_year(target_store_id uuid, target_year integer, notes text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.close_fiscal_year(target_store_id uuid, target_year integer, notes text) TO authenticated;
GRANT ALL ON FUNCTION public.close_fiscal_year(target_store_id uuid, target_year integer, notes text) TO service_role;


--
-- Name: FUNCTION consume_diamond_stock_lot(target_lot_id uuid, amount numeric); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.consume_diamond_stock_lot(target_lot_id uuid, amount numeric) TO anon;
GRANT ALL ON FUNCTION public.consume_diamond_stock_lot(target_lot_id uuid, amount numeric) TO authenticated;
GRANT ALL ON FUNCTION public.consume_diamond_stock_lot(target_lot_id uuid, amount numeric) TO service_role;


--
-- Name: FUNCTION consume_gold_stock_lot(target_lot_id uuid, amount numeric); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.consume_gold_stock_lot(target_lot_id uuid, amount numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION public.consume_gold_stock_lot(target_lot_id uuid, amount numeric) TO authenticated;
GRANT ALL ON FUNCTION public.consume_gold_stock_lot(target_lot_id uuid, amount numeric) TO service_role;


--
-- Name: FUNCTION consume_gold_stock_lot_pooled(target_lot_id uuid, weight_amount numeric, fee_amount numeric); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.consume_gold_stock_lot_pooled(target_lot_id uuid, weight_amount numeric, fee_amount numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION public.consume_gold_stock_lot_pooled(target_lot_id uuid, weight_amount numeric, fee_amount numeric) TO authenticated;
GRANT ALL ON FUNCTION public.consume_gold_stock_lot_pooled(target_lot_id uuid, weight_amount numeric, fee_amount numeric) TO service_role;


--
-- Name: FUNCTION create_branch(p_from_store uuid, p_name text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.create_branch(p_from_store uuid, p_name text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_branch(p_from_store uuid, p_name text) TO authenticated;
GRANT ALL ON FUNCTION public.create_branch(p_from_store uuid, p_name text) TO service_role;


--
-- Name: FUNCTION create_customer_deposit(p jsonb); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.create_customer_deposit(p jsonb) TO anon;
GRANT ALL ON FUNCTION public.create_customer_deposit(p jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.create_customer_deposit(p jsonb) TO service_role;


--
-- Name: FUNCTION currency_usd_peg(cur text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.currency_usd_peg(cur text) TO anon;
GRANT ALL ON FUNCTION public.currency_usd_peg(cur text) TO authenticated;
GRANT ALL ON FUNCTION public.currency_usd_peg(cur text) TO service_role;


--
-- Name: FUNCTION current_store_id(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.current_store_id() TO anon;
GRANT ALL ON FUNCTION public.current_store_id() TO authenticated;
GRANT ALL ON FUNCTION public.current_store_id() TO service_role;


--
-- Name: FUNCTION customer_cash_out(p_customer uuid, p_amount numeric, p_method text, p_notes text, p_store uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.customer_cash_out(p_customer uuid, p_amount numeric, p_method text, p_notes text, p_store uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.customer_cash_out(p_customer uuid, p_amount numeric, p_method text, p_notes text, p_store uuid) TO authenticated;
GRANT ALL ON FUNCTION public.customer_cash_out(p_customer uuid, p_amount numeric, p_method text, p_notes text, p_store uuid) TO service_role;


--
-- Name: FUNCTION customer_credit(sid uuid, cust uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.customer_credit(sid uuid, cust uuid) TO authenticated;
GRANT ALL ON FUNCTION public.customer_credit(sid uuid, cust uuid) TO service_role;


--
-- Name: FUNCTION customer_debt_discount(p_customer uuid, p_amount numeric, p_notes text, p_store uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.customer_debt_discount(p_customer uuid, p_amount numeric, p_notes text, p_store uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.customer_debt_discount(p_customer uuid, p_amount numeric, p_notes text, p_store uuid) TO authenticated;
GRANT ALL ON FUNCTION public.customer_debt_discount(p_customer uuid, p_amount numeric, p_notes text, p_store uuid) TO service_role;


--
-- Name: FUNCTION customer_debt_discount_update(p_id uuid, p_amount numeric, p_notes text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.customer_debt_discount_update(p_id uuid, p_amount numeric, p_notes text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.customer_debt_discount_update(p_id uuid, p_amount numeric, p_notes text) TO authenticated;
GRANT ALL ON FUNCTION public.customer_debt_discount_update(p_id uuid, p_amount numeric, p_notes text) TO service_role;


--
-- Name: FUNCTION customer_deposit_remaining(sid uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.customer_deposit_remaining(sid uuid) TO authenticated;
GRANT ALL ON FUNCTION public.customer_deposit_remaining(sid uuid) TO service_role;


--
-- Name: FUNCTION customer_payment_update(p_id uuid, p_amount numeric, p_notes text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.customer_payment_update(p_id uuid, p_amount numeric, p_notes text) TO anon;
GRANT ALL ON FUNCTION public.customer_payment_update(p_id uuid, p_amount numeric, p_notes text) TO authenticated;
GRANT ALL ON FUNCTION public.customer_payment_update(p_id uuid, p_amount numeric, p_notes text) TO service_role;


--
-- Name: FUNCTION delete_expense(p_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.delete_expense(p_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.delete_expense(p_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.delete_expense(p_id uuid) TO service_role;


--
-- Name: FUNCTION delete_expense_category(p_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.delete_expense_category(p_id uuid) TO anon;
GRANT ALL ON FUNCTION public.delete_expense_category(p_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.delete_expense_category(p_id uuid) TO service_role;


--
-- Name: FUNCTION delete_last_sale_invoice(target_invoice_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.delete_last_sale_invoice(target_invoice_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.delete_last_sale_invoice(target_invoice_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.delete_last_sale_invoice(target_invoice_id uuid) TO service_role;


--
-- Name: FUNCTION ensure_store_organization(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.ensure_store_organization() FROM PUBLIC;
GRANT ALL ON FUNCTION public.ensure_store_organization() TO service_role;


--
-- Name: FUNCTION fill_currency_from_store(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.fill_currency_from_store() FROM PUBLIC;
GRANT ALL ON FUNCTION public.fill_currency_from_store() TO service_role;


--
-- Name: FUNCTION find_my_pending_invites(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.find_my_pending_invites() TO anon;
GRANT ALL ON FUNCTION public.find_my_pending_invites() TO authenticated;
GRANT ALL ON FUNCTION public.find_my_pending_invites() TO service_role;


--
-- Name: FUNCTION get_branch_count(p_organization_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.get_branch_count(p_organization_id uuid) TO anon;
GRANT ALL ON FUNCTION public.get_branch_count(p_organization_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_branch_count(p_organization_id uuid) TO service_role;


--
-- Name: FUNCTION get_effective_staff_count(p_store_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.get_effective_staff_count(p_store_id uuid) TO anon;
GRANT ALL ON FUNCTION public.get_effective_staff_count(p_store_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_effective_staff_count(p_store_id uuid) TO service_role;


--
-- Name: FUNCTION get_invoice_receipt(p_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.get_invoice_receipt(p_id uuid) TO anon;
GRANT ALL ON FUNCTION public.get_invoice_receipt(p_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_invoice_receipt(p_id uuid) TO service_role;


--
-- Name: FUNCTION get_repair_receipt(p_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.get_repair_receipt(p_id uuid) TO anon;
GRANT ALL ON FUNCTION public.get_repair_receipt(p_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_repair_receipt(p_id uuid) TO service_role;


--
-- Name: FUNCTION get_subscription_status(p_store_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_subscription_status(p_store_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_subscription_status(p_store_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_subscription_status(p_store_id uuid) TO service_role;


--
-- Name: FUNCTION gift_out_piece(target_piece_id uuid, p_recipient text, p_reason text, p_notes text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.gift_out_piece(target_piece_id uuid, p_recipient text, p_reason text, p_notes text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.gift_out_piece(target_piece_id uuid, p_recipient text, p_reason text, p_notes text) TO authenticated;
GRANT ALL ON FUNCTION public.gift_out_piece(target_piece_id uuid, p_recipient text, p_reason text, p_notes text) TO service_role;


--
-- Name: FUNCTION give_scrap_to_trader(p_trader uuid, p_karat integer, p_weight numeric, p_notes text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.give_scrap_to_trader(p_trader uuid, p_karat integer, p_weight numeric, p_notes text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.give_scrap_to_trader(p_trader uuid, p_karat integer, p_weight numeric, p_notes text) TO authenticated;
GRANT ALL ON FUNCTION public.give_scrap_to_trader(p_trader uuid, p_karat integer, p_weight numeric, p_notes text) TO service_role;


--
-- Name: FUNCTION gm_acting_store(home uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.gm_acting_store(home uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.gm_acting_store(home uuid) TO authenticated;
GRANT ALL ON FUNCTION public.gm_acting_store(home uuid) TO service_role;


--
-- Name: FUNCTION gm_allocate_customer_credit(sid uuid, cust uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.gm_allocate_customer_credit(sid uuid, cust uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.gm_allocate_customer_credit(sid uuid, cust uuid) TO authenticated;
GRANT ALL ON FUNCTION public.gm_allocate_customer_credit(sid uuid, cust uuid) TO service_role;


--
-- Name: FUNCTION gm_can_expense(sid uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.gm_can_expense(sid uuid) TO anon;
GRANT ALL ON FUNCTION public.gm_can_expense(sid uuid) TO authenticated;
GRANT ALL ON FUNCTION public.gm_can_expense(sid uuid) TO service_role;


--
-- Name: FUNCTION gm_cash_log_guard(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.gm_cash_log_guard() TO anon;
GRANT ALL ON FUNCTION public.gm_cash_log_guard() TO authenticated;
GRANT ALL ON FUNCTION public.gm_cash_log_guard() TO service_role;


--
-- Name: FUNCTION gm_daily_label(p_op text, p_notes text, p_cm uuid, OUT op text, OUT notes text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.gm_daily_label(p_op text, p_notes text, p_cm uuid, OUT op text, OUT notes text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.gm_daily_label(p_op text, p_notes text, p_cm uuid, OUT op text, OUT notes text) TO authenticated;
GRANT ALL ON FUNCTION public.gm_daily_label(p_op text, p_notes text, p_cm uuid, OUT op text, OUT notes text) TO service_role;


--
-- Name: FUNCTION gm_deposit_sale_to_daily(p_invoice uuid, p_customer uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.gm_deposit_sale_to_daily(p_invoice uuid, p_customer uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.gm_deposit_sale_to_daily(p_invoice uuid, p_customer uuid) TO service_role;


--
-- Name: FUNCTION gm_draw_for_piece(p_piece uuid, p_store uuid, p_box text, p_lot uuid, p_grams numeric); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.gm_draw_for_piece(p_piece uuid, p_store uuid, p_box text, p_lot uuid, p_grams numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION public.gm_draw_for_piece(p_piece uuid, p_store uuid, p_box text, p_lot uuid, p_grams numeric) TO service_role;


--
-- Name: FUNCTION gm_fiscal_closed(p_store uuid, p_day date); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.gm_fiscal_closed(p_store uuid, p_day date) TO anon;
GRANT ALL ON FUNCTION public.gm_fiscal_closed(p_store uuid, p_day date) TO authenticated;
GRANT ALL ON FUNCTION public.gm_fiscal_closed(p_store uuid, p_day date) TO service_role;


--
-- Name: FUNCTION gm_invoice_daily_rewrite(p_invoice uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.gm_invoice_daily_rewrite(p_invoice uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.gm_invoice_daily_rewrite(p_invoice uuid) TO authenticated;
GRANT ALL ON FUNCTION public.gm_invoice_daily_rewrite(p_invoice uuid) TO service_role;


--
-- Name: FUNCTION gm_op_date(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.gm_op_date() TO anon;
GRANT ALL ON FUNCTION public.gm_op_date() TO authenticated;
GRANT ALL ON FUNCTION public.gm_op_date() TO service_role;


--
-- Name: FUNCTION gm_op_date_stamp(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.gm_op_date_stamp() TO anon;
GRANT ALL ON FUNCTION public.gm_op_date_stamp() TO authenticated;
GRANT ALL ON FUNCTION public.gm_op_date_stamp() TO service_role;


--
-- Name: FUNCTION gm_pre_request(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.gm_pre_request() TO anon;
GRANT ALL ON FUNCTION public.gm_pre_request() TO authenticated;
GRANT ALL ON FUNCTION public.gm_pre_request() TO service_role;


--
-- Name: FUNCTION gm_return_draws(p_piece uuid, p_grams numeric); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.gm_return_draws(p_piece uuid, p_grams numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION public.gm_return_draws(p_piece uuid, p_grams numeric) TO service_role;


--
-- Name: FUNCTION gm_sale_debt_to_daily(p_invoice uuid, p_amount numeric); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.gm_sale_debt_to_daily(p_invoice uuid, p_amount numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION public.gm_sale_debt_to_daily(p_invoice uuid, p_amount numeric) TO service_role;


--
-- Name: FUNCTION gm_scrap_price_at_purchase(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.gm_scrap_price_at_purchase() TO anon;
GRANT ALL ON FUNCTION public.gm_scrap_price_at_purchase() TO authenticated;
GRANT ALL ON FUNCTION public.gm_scrap_price_at_purchase() TO service_role;


--
-- Name: FUNCTION gm_scrap_return_unrecorded(p_store uuid, p_karat integer, p_grams numeric, p_note text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.gm_scrap_return_unrecorded(p_store uuid, p_karat integer, p_grams numeric, p_note text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.gm_scrap_return_unrecorded(p_store uuid, p_karat integer, p_grams numeric, p_note text) TO service_role;


--
-- Name: FUNCTION gm_seller_stamp(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.gm_seller_stamp() TO anon;
GRANT ALL ON FUNCTION public.gm_seller_stamp() TO authenticated;
GRANT ALL ON FUNCTION public.gm_seller_stamp() TO service_role;


--
-- Name: FUNCTION gm_session_ok(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.gm_session_ok() TO anon;
GRANT ALL ON FUNCTION public.gm_session_ok() TO authenticated;
GRANT ALL ON FUNCTION public.gm_session_ok() TO service_role;


--
-- Name: FUNCTION gm_staff_guard(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.gm_staff_guard() TO anon;
GRANT ALL ON FUNCTION public.gm_staff_guard() TO authenticated;
GRANT ALL ON FUNCTION public.gm_staff_guard() TO service_role;


--
-- Name: FUNCTION gm_stock_in_rescrap(p_voucher uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.gm_stock_in_rescrap(p_voucher uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.gm_stock_in_rescrap(p_voucher uuid) TO service_role;


--
-- Name: FUNCTION gm_tm_snapshot(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.gm_tm_snapshot() TO anon;
GRANT ALL ON FUNCTION public.gm_tm_snapshot() TO authenticated;
GRANT ALL ON FUNCTION public.gm_tm_snapshot() TO service_role;


--
-- Name: FUNCTION gm_unallocate_customer_credit(sid uuid, cust uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.gm_unallocate_customer_credit(sid uuid, cust uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.gm_unallocate_customer_credit(sid uuid, cust uuid) TO service_role;


--
-- Name: FUNCTION gold_implied_usd_ounce(price_per_gram numeric, karat integer, cur text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.gold_implied_usd_ounce(price_per_gram numeric, karat integer, cur text) TO anon;
GRANT ALL ON FUNCTION public.gold_implied_usd_ounce(price_per_gram numeric, karat integer, cur text) TO authenticated;
GRANT ALL ON FUNCTION public.gold_implied_usd_ounce(price_per_gram numeric, karat integer, cur text) TO service_role;


--
-- Name: FUNCTION gold_price_problem(sid uuid, karat integer, price numeric); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.gold_price_problem(sid uuid, karat integer, price numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION public.gold_price_problem(sid uuid, karat integer, price numeric) TO authenticated;
GRANT ALL ON FUNCTION public.gold_price_problem(sid uuid, karat integer, price numeric) TO service_role;


--
-- Name: FUNCTION gold_prices_currency_guard(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.gold_prices_currency_guard() TO anon;
GRANT ALL ON FUNCTION public.gold_prices_currency_guard() TO authenticated;
GRANT ALL ON FUNCTION public.gold_prices_currency_guard() TO service_role;


--
-- Name: FUNCTION gold_reference_usd_ounce(exclude_store uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.gold_reference_usd_ounce(exclude_store uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.gold_reference_usd_ounce(exclude_store uuid) TO authenticated;
GRANT ALL ON FUNCTION public.gold_reference_usd_ounce(exclude_store uuid) TO service_role;


--
-- Name: FUNCTION has_permission(perm text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.has_permission(perm text) TO anon;
GRANT ALL ON FUNCTION public.has_permission(perm text) TO authenticated;
GRANT ALL ON FUNCTION public.has_permission(perm text) TO service_role;


--
-- Name: FUNCTION has_permission(perm text, target_store_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.has_permission(perm text, target_store_id uuid) TO anon;
GRANT ALL ON FUNCTION public.has_permission(perm text, target_store_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.has_permission(perm text, target_store_id uuid) TO service_role;


--
-- Name: FUNCTION invoices_currency_guard(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.invoices_currency_guard() TO anon;
GRANT ALL ON FUNCTION public.invoices_currency_guard() TO authenticated;
GRANT ALL ON FUNCTION public.invoices_currency_guard() TO service_role;


--
-- Name: FUNCTION is_org_owner(p_org uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.is_org_owner(p_org uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.is_org_owner(p_org uuid) TO authenticated;
GRANT ALL ON FUNCTION public.is_org_owner(p_org uuid) TO service_role;


--
-- Name: FUNCTION is_platform_admin(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.is_platform_admin() TO anon;
GRANT ALL ON FUNCTION public.is_platform_admin() TO authenticated;
GRANT ALL ON FUNCTION public.is_platform_admin() TO service_role;


--
-- Name: FUNCTION is_store_member(target_store_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.is_store_member(target_store_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.is_store_member(target_store_id uuid) TO anon;
GRANT ALL ON FUNCTION public.is_store_member(target_store_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.is_store_member(target_store_id uuid) TO service_role;


--
-- Name: FUNCTION join_company_by_invite(target_store_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.join_company_by_invite(target_store_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.join_company_by_invite(target_store_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.join_company_by_invite(target_store_id uuid) TO service_role;


--
-- Name: FUNCTION log_audit_event(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.log_audit_event() TO anon;
GRANT ALL ON FUNCTION public.log_audit_event() TO authenticated;
GRANT ALL ON FUNCTION public.log_audit_event() TO service_role;


--
-- Name: FUNCTION login_email_for(p_username text, p_password text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.login_email_for(p_username text, p_password text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.login_email_for(p_username text, p_password text) TO anon;
GRANT ALL ON FUNCTION public.login_email_for(p_username text, p_password text) TO authenticated;
GRANT ALL ON FUNCTION public.login_email_for(p_username text, p_password text) TO service_role;


--
-- Name: FUNCTION lookup_email_by_username(p_username text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.lookup_email_by_username(p_username text) TO anon;
GRANT ALL ON FUNCTION public.lookup_email_by_username(p_username text) TO authenticated;
GRANT ALL ON FUNCTION public.lookup_email_by_username(p_username text) TO service_role;


--
-- Name: FUNCTION mirror_invoice_cash_to_daily(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.mirror_invoice_cash_to_daily() FROM PUBLIC;
GRANT ALL ON FUNCTION public.mirror_invoice_cash_to_daily() TO service_role;


--
-- Name: FUNCTION my_stores(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.my_stores() TO anon;
GRANT ALL ON FUNCTION public.my_stores() TO authenticated;
GRANT ALL ON FUNCTION public.my_stores() TO service_role;


--
-- Name: FUNCTION next_invoice_number(target_store_id uuid, prefix text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.next_invoice_number(target_store_id uuid, prefix text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.next_invoice_number(target_store_id uuid, prefix text) TO authenticated;
GRANT ALL ON FUNCTION public.next_invoice_number(target_store_id uuid, prefix text) TO service_role;


--
-- Name: FUNCTION next_piece_barcode(target_store_id uuid, category text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.next_piece_barcode(target_store_id uuid, category text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.next_piece_barcode(target_store_id uuid, category text) TO authenticated;
GRANT ALL ON FUNCTION public.next_piece_barcode(target_store_id uuid, category text) TO service_role;


--
-- Name: FUNCTION next_repair_number(p_store_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.next_repair_number(p_store_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.next_repair_number(p_store_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.next_repair_number(p_store_id uuid) TO service_role;


--
-- Name: FUNCTION org_branches(sid uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.org_branches(sid uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.org_branches(sid uuid) TO authenticated;
GRANT ALL ON FUNCTION public.org_branches(sid uuid) TO service_role;


--
-- Name: FUNCTION org_can(p_store uuid, perm text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.org_can(p_store uuid, perm text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.org_can(p_store uuid, perm text) TO authenticated;
GRANT ALL ON FUNCTION public.org_can(p_store uuid, perm text) TO service_role;


--
-- Name: FUNCTION org_store_ids(sid uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.org_store_ids(sid uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.org_store_ids(sid uuid) TO authenticated;
GRANT ALL ON FUNCTION public.org_store_ids(sid uuid) TO service_role;


--
-- Name: FUNCTION post_purchase_invoice(p jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.post_purchase_invoice(p jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.post_purchase_invoice(p jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.post_purchase_invoice(p jsonb) TO service_role;


--
-- Name: FUNCTION post_sale_exchange(p jsonb); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.post_sale_exchange(p jsonb) TO anon;
GRANT ALL ON FUNCTION public.post_sale_exchange(p jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.post_sale_exchange(p jsonb) TO service_role;


--
-- Name: FUNCTION post_sale_invoice(p jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.post_sale_invoice(p jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.post_sale_invoice(p jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.post_sale_invoice(p jsonb) TO service_role;


--
-- Name: FUNCTION post_sales_return(p jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.post_sales_return(p jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.post_sales_return(p jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.post_sales_return(p jsonb) TO service_role;


--
-- Name: FUNCTION production_take(p_piece uuid, p_box text, p_lot uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.production_take(p_piece uuid, p_box text, p_lot uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.production_take(p_piece uuid, p_box text, p_lot uuid) TO authenticated;
GRANT ALL ON FUNCTION public.production_take(p_piece uuid, p_box text, p_lot uuid) TO service_role;


--
-- Name: FUNCTION receive_branch_transfer(p_transfer uuid, p_barcodes text[], p_items uuid[]); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.receive_branch_transfer(p_transfer uuid, p_barcodes text[], p_items uuid[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.receive_branch_transfer(p_transfer uuid, p_barcodes text[], p_items uuid[]) TO authenticated;
GRANT ALL ON FUNCTION public.receive_branch_transfer(p_transfer uuid, p_barcodes text[], p_items uuid[]) TO service_role;


--
-- Name: FUNCTION record_customer_payment(p_customer uuid, p_amount numeric, p_method text, p_notes text, p_store uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.record_customer_payment(p_customer uuid, p_amount numeric, p_method text, p_notes text, p_store uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.record_customer_payment(p_customer uuid, p_amount numeric, p_method text, p_notes text, p_store uuid) TO authenticated;
GRANT ALL ON FUNCTION public.record_customer_payment(p_customer uuid, p_amount numeric, p_method text, p_notes text, p_store uuid) TO service_role;


--
-- Name: FUNCTION record_expense(p jsonb); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.record_expense(p jsonb) TO anon;
GRANT ALL ON FUNCTION public.record_expense(p jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.record_expense(p jsonb) TO service_role;


--
-- Name: FUNCTION record_repair_gold(p jsonb); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.record_repair_gold(p jsonb) TO anon;
GRANT ALL ON FUNCTION public.record_repair_gold(p jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.record_repair_gold(p jsonb) TO service_role;


--
-- Name: FUNCTION record_subscription_payment(p_store_id uuid, p_months integer, p_payment_ref text, p_plan_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.record_subscription_payment(p_store_id uuid, p_months integer, p_payment_ref text, p_plan_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.record_subscription_payment(p_store_id uuid, p_months integer, p_payment_ref text, p_plan_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.record_subscription_payment(p_store_id uuid, p_months integer, p_payment_ref text, p_plan_id uuid) TO service_role;


--
-- Name: FUNCTION refund_customer_deposit(p_deposit uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.refund_customer_deposit(p_deposit uuid) TO anon;
GRANT ALL ON FUNCTION public.refund_customer_deposit(p_deposit uuid) TO authenticated;
GRANT ALL ON FUNCTION public.refund_customer_deposit(p_deposit uuid) TO service_role;


--
-- Name: FUNCTION regenerate_piece_barcode(p_piece_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.regenerate_piece_barcode(p_piece_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.regenerate_piece_barcode(p_piece_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.regenerate_piece_barcode(p_piece_id uuid) TO service_role;


--
-- Name: FUNCTION register_new_company(company_name text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.register_new_company(company_name text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.register_new_company(company_name text) TO authenticated;
GRANT ALL ON FUNCTION public.register_new_company(company_name text) TO service_role;


--
-- Name: FUNCTION register_new_company(company_name text, terms_accepted boolean, terms_version text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.register_new_company(company_name text, terms_accepted boolean, terms_version text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.register_new_company(company_name text, terms_accepted boolean, terms_version text) TO authenticated;
GRANT ALL ON FUNCTION public.register_new_company(company_name text, terms_accepted boolean, terms_version text) TO service_role;


--
-- Name: FUNCTION replace_piece_chip(p_piece_id uuid, p_old_epc text, p_new_epc text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.replace_piece_chip(p_piece_id uuid, p_old_epc text, p_new_epc text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.replace_piece_chip(p_piece_id uuid, p_old_epc text, p_new_epc text) TO authenticated;
GRANT ALL ON FUNCTION public.replace_piece_chip(p_piece_id uuid, p_old_epc text, p_new_epc text) TO service_role;


--
-- Name: FUNCTION reset_invoice_sequence(target_store_id uuid, new_seq integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.reset_invoice_sequence(target_store_id uuid, new_seq integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.reset_invoice_sequence(target_store_id uuid, new_seq integer) TO authenticated;
GRANT ALL ON FUNCTION public.reset_invoice_sequence(target_store_id uuid, new_seq integer) TO service_role;


--
-- Name: FUNCTION reset_piece_barcode_sequence(target_store_id uuid, category text, new_seq bigint); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.reset_piece_barcode_sequence(target_store_id uuid, category text, new_seq bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION public.reset_piece_barcode_sequence(target_store_id uuid, category text, new_seq bigint) TO authenticated;
GRANT ALL ON FUNCTION public.reset_piece_barcode_sequence(target_store_id uuid, category text, new_seq bigint) TO service_role;


--
-- Name: FUNCTION reset_piece_barcode_sequence(target_store_id uuid, category text, new_seq bigint, seq_width smallint); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.reset_piece_barcode_sequence(target_store_id uuid, category text, new_seq bigint, seq_width smallint) TO anon;
GRANT ALL ON FUNCTION public.reset_piece_barcode_sequence(target_store_id uuid, category text, new_seq bigint, seq_width smallint) TO authenticated;
GRANT ALL ON FUNCTION public.reset_piece_barcode_sequence(target_store_id uuid, category text, new_seq bigint, seq_width smallint) TO service_role;


--
-- Name: FUNCTION reset_piece_barcode_sequence(target_store_id uuid, category text, new_seq bigint, seq_width smallint, new_prefix text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.reset_piece_barcode_sequence(target_store_id uuid, category text, new_seq bigint, seq_width smallint, new_prefix text) TO anon;
GRANT ALL ON FUNCTION public.reset_piece_barcode_sequence(target_store_id uuid, category text, new_seq bigint, seq_width smallint, new_prefix text) TO authenticated;
GRANT ALL ON FUNCTION public.reset_piece_barcode_sequence(target_store_id uuid, category text, new_seq bigint, seq_width smallint, new_prefix text) TO service_role;


--
-- Name: FUNCTION restore_invoice(target_invoice_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.restore_invoice(target_invoice_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.restore_invoice(target_invoice_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.restore_invoice(target_invoice_id uuid) TO service_role;


--
-- Name: FUNCTION revert_gift(target_gift_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.revert_gift(target_gift_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.revert_gift(target_gift_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.revert_gift(target_gift_id uuid) TO service_role;


--
-- Name: FUNCTION rfid_device_done(p_key text, p_job uuid, p_ok boolean, p_msg text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.rfid_device_done(p_key text, p_job uuid, p_ok boolean, p_msg text) TO anon;
GRANT ALL ON FUNCTION public.rfid_device_done(p_key text, p_job uuid, p_ok boolean, p_msg text) TO authenticated;
GRANT ALL ON FUNCTION public.rfid_device_done(p_key text, p_job uuid, p_ok boolean, p_msg text) TO service_role;


--
-- Name: FUNCTION rfid_device_hello(p_key text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.rfid_device_hello(p_key text) TO anon;
GRANT ALL ON FUNCTION public.rfid_device_hello(p_key text) TO authenticated;
GRANT ALL ON FUNCTION public.rfid_device_hello(p_key text) TO service_role;


--
-- Name: FUNCTION rfid_device_key_reset(p_store uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.rfid_device_key_reset(p_store uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.rfid_device_key_reset(p_store uuid) TO authenticated;
GRANT ALL ON FUNCTION public.rfid_device_key_reset(p_store uuid) TO service_role;


--
-- Name: FUNCTION rfid_device_next(p_key text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.rfid_device_next(p_key text) TO anon;
GRANT ALL ON FUNCTION public.rfid_device_next(p_key text) TO authenticated;
GRANT ALL ON FUNCTION public.rfid_device_next(p_key text) TO service_role;


--
-- Name: FUNCTION sale_invoice_change_customer(p_invoice uuid, p_customer uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.sale_invoice_change_customer(p_invoice uuid, p_customer uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.sale_invoice_change_customer(p_invoice uuid, p_customer uuid) TO authenticated;
GRANT ALL ON FUNCTION public.sale_invoice_change_customer(p_invoice uuid, p_customer uuid) TO service_role;


--
-- Name: FUNCTION save_expense_category(p_store uuid, p_name text, p_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.save_expense_category(p_store uuid, p_name text, p_id uuid) TO anon;
GRANT ALL ON FUNCTION public.save_expense_category(p_store uuid, p_name text, p_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.save_expense_category(p_store uuid, p_name text, p_id uuid) TO service_role;


--
-- Name: FUNCTION seed_default_zebra_label_fields(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.seed_default_zebra_label_fields() TO anon;
GRANT ALL ON FUNCTION public.seed_default_zebra_label_fields() TO authenticated;
GRANT ALL ON FUNCTION public.seed_default_zebra_label_fields() TO service_role;


--
-- Name: FUNCTION send_branch_transfer(p_from uuid, p_to uuid, p_barcodes text[], p_notes text, p_scrap jsonb, p_cash jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.send_branch_transfer(p_from uuid, p_to uuid, p_barcodes text[], p_notes text, p_scrap jsonb, p_cash jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.send_branch_transfer(p_from uuid, p_to uuid, p_barcodes text[], p_notes text, p_scrap jsonb, p_cash jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.send_branch_transfer(p_from uuid, p_to uuid, p_barcodes text[], p_notes text, p_scrap jsonb, p_cash jsonb) TO service_role;


--
-- Name: FUNCTION set_branch_own_gold_price(p_store uuid, p_own boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.set_branch_own_gold_price(p_store uuid, p_own boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.set_branch_own_gold_price(p_store uuid, p_own boolean) TO authenticated;
GRANT ALL ON FUNCTION public.set_branch_own_gold_price(p_store uuid, p_own boolean) TO service_role;


--
-- Name: FUNCTION set_gold_ounce_price(target_store_id uuid, ounce numeric, rate numeric); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.set_gold_ounce_price(target_store_id uuid, ounce numeric, rate numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION public.set_gold_ounce_price(target_store_id uuid, ounce numeric, rate numeric) TO authenticated;
GRANT ALL ON FUNCTION public.set_gold_ounce_price(target_store_id uuid, ounce numeric, rate numeric) TO service_role;


--
-- Name: FUNCTION set_piece_weights(p_piece uuid, p_weight numeric, p_acc numeric); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.set_piece_weights(p_piece uuid, p_weight numeric, p_acc numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION public.set_piece_weights(p_piece uuid, p_weight numeric, p_acc numeric) TO authenticated;
GRANT ALL ON FUNCTION public.set_piece_weights(p_piece uuid, p_weight numeric, p_acc numeric) TO service_role;


--
-- Name: FUNCTION set_voucher_date(p_cash_movement uuid, p_date date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.set_voucher_date(p_cash_movement uuid, p_date date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.set_voucher_date(p_cash_movement uuid, p_date date) TO authenticated;
GRANT ALL ON FUNCTION public.set_voucher_date(p_cash_movement uuid, p_date date) TO service_role;


--
-- Name: FUNCTION staff_heartbeat(p_store uuid, p_page text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.staff_heartbeat(p_store uuid, p_page text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.staff_heartbeat(p_store uuid, p_page text) TO authenticated;
GRANT ALL ON FUNCTION public.staff_heartbeat(p_store uuid, p_page text) TO service_role;


--
-- Name: FUNCTION stock_in_from_party(target_party_id uuid, return_piece_ids uuid[], new_lines jsonb, p_notes text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.stock_in_from_party(target_party_id uuid, return_piece_ids uuid[], new_lines jsonb, p_notes text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.stock_in_from_party(target_party_id uuid, return_piece_ids uuid[], new_lines jsonb, p_notes text) TO authenticated;
GRANT ALL ON FUNCTION public.stock_in_from_party(target_party_id uuid, return_piece_ids uuid[], new_lines jsonb, p_notes text) TO service_role;


--
-- Name: FUNCTION stock_in_from_party(target_party_id uuid, return_piece_ids uuid[], new_lines jsonb, p_notes text, p_return_box text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.stock_in_from_party(target_party_id uuid, return_piece_ids uuid[], new_lines jsonb, p_notes text, p_return_box text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.stock_in_from_party(target_party_id uuid, return_piece_ids uuid[], new_lines jsonb, p_notes text, p_return_box text) TO authenticated;
GRANT ALL ON FUNCTION public.stock_in_from_party(target_party_id uuid, return_piece_ids uuid[], new_lines jsonb, p_notes text, p_return_box text) TO service_role;


--
-- Name: FUNCTION stock_in_from_party(target_party_id uuid, return_piece_ids uuid[], new_lines jsonb, p_notes text, p_return_box text, p_source_piece_ids uuid[]); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.stock_in_from_party(target_party_id uuid, return_piece_ids uuid[], new_lines jsonb, p_notes text, p_return_box text, p_source_piece_ids uuid[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.stock_in_from_party(target_party_id uuid, return_piece_ids uuid[], new_lines jsonb, p_notes text, p_return_box text, p_source_piece_ids uuid[]) TO authenticated;
GRANT ALL ON FUNCTION public.stock_in_from_party(target_party_id uuid, return_piece_ids uuid[], new_lines jsonb, p_notes text, p_return_box text, p_source_piece_ids uuid[]) TO service_role;


--
-- Name: FUNCTION stock_in_piece_update(p_line uuid, p_weight numeric, p_acc numeric, p_fab numeric, p_description text, p_box text, p_photo_url text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.stock_in_piece_update(p_line uuid, p_weight numeric, p_acc numeric, p_fab numeric, p_description text, p_box text, p_photo_url text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.stock_in_piece_update(p_line uuid, p_weight numeric, p_acc numeric, p_fab numeric, p_description text, p_box text, p_photo_url text) TO authenticated;
GRANT ALL ON FUNCTION public.stock_in_piece_update(p_line uuid, p_weight numeric, p_acc numeric, p_fab numeric, p_description text, p_box text, p_photo_url text) TO service_role;


--
-- Name: FUNCTION stock_out_to_party(target_party_id uuid, piece_ids uuid[], p_notes text, p_recipient text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.stock_out_to_party(target_party_id uuid, piece_ids uuid[], p_notes text, p_recipient text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.stock_out_to_party(target_party_id uuid, piece_ids uuid[], p_notes text, p_recipient text) TO authenticated;
GRANT ALL ON FUNCTION public.stock_out_to_party(target_party_id uuid, piece_ids uuid[], p_notes text, p_recipient text) TO service_role;


--
-- Name: FUNCTION store_legal(p_store_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.store_legal(p_store_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.store_legal(p_store_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.store_legal(p_store_id uuid) TO service_role;


--
-- Name: FUNCTION stores_currency_convert_gold(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.stores_currency_convert_gold() TO anon;
GRANT ALL ON FUNCTION public.stores_currency_convert_gold() TO authenticated;
GRANT ALL ON FUNCTION public.stores_currency_convert_gold() TO service_role;


--
-- Name: FUNCTION stores_currency_usd_reprice(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.stores_currency_usd_reprice() FROM PUBLIC;
GRANT ALL ON FUNCTION public.stores_currency_usd_reprice() TO service_role;


--
-- Name: FUNCTION sync_invoice_bank_part(p_invoice uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.sync_invoice_bank_part(p_invoice uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.sync_invoice_bank_part(p_invoice uuid) TO service_role;


--
-- Name: FUNCTION sync_staff_to_hr_employee(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.sync_staff_to_hr_employee() TO anon;
GRANT ALL ON FUNCTION public.sync_staff_to_hr_employee() TO authenticated;
GRANT ALL ON FUNCTION public.sync_staff_to_hr_employee() TO service_role;


--
-- Name: FUNCTION sync_store_country_to_org(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.sync_store_country_to_org() FROM PUBLIC;
GRANT ALL ON FUNCTION public.sync_store_country_to_org() TO anon;
GRANT ALL ON FUNCTION public.sync_store_country_to_org() TO authenticated;
GRANT ALL ON FUNCTION public.sync_store_country_to_org() TO service_role;


--
-- Name: FUNCTION trader_cash_move(p_trader uuid, p_direction text, p_amount numeric, p_notes text, p_daily boolean); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.trader_cash_move(p_trader uuid, p_direction text, p_amount numeric, p_notes text, p_daily boolean) TO anon;
GRANT ALL ON FUNCTION public.trader_cash_move(p_trader uuid, p_direction text, p_amount numeric, p_notes text, p_daily boolean) TO authenticated;
GRANT ALL ON FUNCTION public.trader_cash_move(p_trader uuid, p_direction text, p_amount numeric, p_notes text, p_daily boolean) TO service_role;


--
-- Name: FUNCTION trader_discount(p_trader uuid, p_for text, p_amount numeric, p_notes text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.trader_discount(p_trader uuid, p_for text, p_amount numeric, p_notes text) TO anon;
GRANT ALL ON FUNCTION public.trader_discount(p_trader uuid, p_for text, p_amount numeric, p_notes text) TO authenticated;
GRANT ALL ON FUNCTION public.trader_discount(p_trader uuid, p_for text, p_amount numeric, p_notes text) TO service_role;


--
-- Name: FUNCTION trader_gold_to_cash(p_trader uuid, p_weight numeric, p_karat integer, p_price numeric, p_direction text, p_notes text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.trader_gold_to_cash(p_trader uuid, p_weight numeric, p_karat integer, p_price numeric, p_direction text, p_notes text) TO anon;
GRANT ALL ON FUNCTION public.trader_gold_to_cash(p_trader uuid, p_weight numeric, p_karat integer, p_price numeric, p_direction text, p_notes text) TO authenticated;
GRANT ALL ON FUNCTION public.trader_gold_to_cash(p_trader uuid, p_weight numeric, p_karat integer, p_price numeric, p_direction text, p_notes text) TO service_role;


--
-- Name: FUNCTION trader_receive_stock(p_trader uuid, p_lines jsonb, p_vat_rate numeric, p_batch_ref text, p_notes text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.trader_receive_stock(p_trader uuid, p_lines jsonb, p_vat_rate numeric, p_batch_ref text, p_notes text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.trader_receive_stock(p_trader uuid, p_lines jsonb, p_vat_rate numeric, p_batch_ref text, p_notes text) TO authenticated;
GRANT ALL ON FUNCTION public.trader_receive_stock(p_trader uuid, p_lines jsonb, p_vat_rate numeric, p_batch_ref text, p_notes text) TO service_role;


--
-- Name: FUNCTION trader_return_piece(p_movement uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.trader_return_piece(p_movement uuid) TO anon;
GRANT ALL ON FUNCTION public.trader_return_piece(p_movement uuid) TO authenticated;
GRANT ALL ON FUNCTION public.trader_return_piece(p_movement uuid) TO service_role;


--
-- Name: FUNCTION trg_cash_movement_deleted_bank_sync(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.trg_cash_movement_deleted_bank_sync() TO anon;
GRANT ALL ON FUNCTION public.trg_cash_movement_deleted_bank_sync() TO authenticated;
GRANT ALL ON FUNCTION public.trg_cash_movement_deleted_bank_sync() TO service_role;


--
-- Name: FUNCTION trg_cash_movement_updated_daily_sync(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.trg_cash_movement_updated_daily_sync() FROM PUBLIC;
GRANT ALL ON FUNCTION public.trg_cash_movement_updated_daily_sync() TO service_role;


--
-- Name: FUNCTION trg_customer_debts_allocate(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.trg_customer_debts_allocate() TO anon;
GRANT ALL ON FUNCTION public.trg_customer_debts_allocate() TO authenticated;
GRANT ALL ON FUNCTION public.trg_customer_debts_allocate() TO service_role;


--
-- Name: FUNCTION trg_daily_label(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.trg_daily_label() TO anon;
GRANT ALL ON FUNCTION public.trg_daily_label() TO authenticated;
GRANT ALL ON FUNCTION public.trg_daily_label() TO service_role;


--
-- Name: FUNCTION trg_invoice_bank_part_sync(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.trg_invoice_bank_part_sync() TO anon;
GRANT ALL ON FUNCTION public.trg_invoice_bank_part_sync() TO authenticated;
GRANT ALL ON FUNCTION public.trg_invoice_bank_part_sync() TO service_role;


--
-- Name: FUNCTION trg_invoice_status_piece_log(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.trg_invoice_status_piece_log() TO anon;
GRANT ALL ON FUNCTION public.trg_invoice_status_piece_log() TO authenticated;
GRANT ALL ON FUNCTION public.trg_invoice_status_piece_log() TO service_role;


--
-- Name: FUNCTION trg_piece_draws_delete(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.trg_piece_draws_delete() TO anon;
GRANT ALL ON FUNCTION public.trg_piece_draws_delete() TO authenticated;
GRANT ALL ON FUNCTION public.trg_piece_draws_delete() TO service_role;


--
-- Name: FUNCTION trg_piece_draws_weight(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.trg_piece_draws_weight() TO anon;
GRANT ALL ON FUNCTION public.trg_piece_draws_weight() TO authenticated;
GRANT ALL ON FUNCTION public.trg_piece_draws_weight() TO service_role;


--
-- Name: FUNCTION trg_scrap_given_guard(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.trg_scrap_given_guard() TO anon;
GRANT ALL ON FUNCTION public.trg_scrap_given_guard() TO authenticated;
GRANT ALL ON FUNCTION public.trg_scrap_given_guard() TO service_role;


--
-- Name: FUNCTION trg_settlement_lot_sync(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.trg_settlement_lot_sync() FROM PUBLIC;
GRANT ALL ON FUNCTION public.trg_settlement_lot_sync() TO authenticated;
GRANT ALL ON FUNCTION public.trg_settlement_lot_sync() TO service_role;


--
-- Name: FUNCTION trg_trader_received_sync(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.trg_trader_received_sync() TO anon;
GRANT ALL ON FUNCTION public.trg_trader_received_sync() TO authenticated;
GRANT ALL ON FUNCTION public.trg_trader_received_sync() TO service_role;


--
-- Name: FUNCTION update_expense(p_id uuid, p_category uuid, p_amount numeric, p_description text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.update_expense(p_id uuid, p_category uuid, p_amount numeric, p_description text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.update_expense(p_id uuid, p_category uuid, p_amount numeric, p_description text) TO authenticated;
GRANT ALL ON FUNCTION public.update_expense(p_id uuid, p_category uuid, p_amount numeric, p_description text) TO service_role;


--
-- Name: FUNCTION update_expense_fx(p jsonb); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.update_expense_fx(p jsonb) TO anon;
GRANT ALL ON FUNCTION public.update_expense_fx(p jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.update_expense_fx(p jsonb) TO service_role;


--
-- Name: TABLE _backup_20260927_intake_batches; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public._backup_20260927_intake_batches TO anon;
GRANT ALL ON TABLE public._backup_20260927_intake_batches TO authenticated;
GRANT ALL ON TABLE public._backup_20260927_intake_batches TO service_role;


--
-- Name: TABLE _backup_20260927_piece_batches; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public._backup_20260927_piece_batches TO anon;
GRANT ALL ON TABLE public._backup_20260927_piece_batches TO authenticated;
GRANT ALL ON TABLE public._backup_20260927_piece_batches TO service_role;


--
-- Name: TABLE audit_log; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.audit_log TO anon;
GRANT ALL ON TABLE public.audit_log TO authenticated;
GRANT ALL ON TABLE public.audit_log TO service_role;


--
-- Name: TABLE auth_device_keys; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.auth_device_keys TO service_role;
GRANT DELETE ON TABLE public.auth_device_keys TO authenticated;


--
-- Name: COLUMN auth_device_keys.id; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(id) ON TABLE public.auth_device_keys TO authenticated;


--
-- Name: COLUMN auth_device_keys.user_id; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(user_id) ON TABLE public.auth_device_keys TO authenticated;


--
-- Name: COLUMN auth_device_keys.device_name; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(device_name) ON TABLE public.auth_device_keys TO authenticated;


--
-- Name: COLUMN auth_device_keys.created_at; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(created_at) ON TABLE public.auth_device_keys TO authenticated;


--
-- Name: COLUMN auth_device_keys.last_used_at; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(last_used_at) ON TABLE public.auth_device_keys TO authenticated;


--
-- Name: TABLE auth_passkeys; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.auth_passkeys TO service_role;
GRANT DELETE ON TABLE public.auth_passkeys TO authenticated;


--
-- Name: COLUMN auth_passkeys.id; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(id) ON TABLE public.auth_passkeys TO authenticated;


--
-- Name: COLUMN auth_passkeys.user_id; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(user_id) ON TABLE public.auth_passkeys TO authenticated;


--
-- Name: COLUMN auth_passkeys.device_name; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(device_name) ON TABLE public.auth_passkeys TO authenticated;


--
-- Name: COLUMN auth_passkeys.created_at; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(created_at) ON TABLE public.auth_passkeys TO authenticated;


--
-- Name: COLUMN auth_passkeys.last_used_at; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(last_used_at) ON TABLE public.auth_passkeys TO authenticated;


--
-- Name: TABLE auth_webauthn_challenges; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.auth_webauthn_challenges TO service_role;


--
-- Name: TABLE branch_transfer_items; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.branch_transfer_items TO anon;
GRANT ALL ON TABLE public.branch_transfer_items TO authenticated;
GRANT ALL ON TABLE public.branch_transfer_items TO service_role;


--
-- Name: TABLE branch_transfers; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.branch_transfers TO anon;
GRANT ALL ON TABLE public.branch_transfers TO authenticated;
GRANT ALL ON TABLE public.branch_transfers TO service_role;


--
-- Name: TABLE cash_movements; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.cash_movements TO anon;
GRANT ALL ON TABLE public.cash_movements TO authenticated;
GRANT ALL ON TABLE public.cash_movements TO service_role;


--
-- Name: TABLE client_errors; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.client_errors TO anon;
GRANT ALL ON TABLE public.client_errors TO authenticated;
GRANT ALL ON TABLE public.client_errors TO service_role;


--
-- Name: SEQUENCE client_errors_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.client_errors_id_seq TO anon;
GRANT ALL ON SEQUENCE public.client_errors_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.client_errors_id_seq TO service_role;


--
-- Name: TABLE company_kyc_documents; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.company_kyc_documents TO anon;
GRANT ALL ON TABLE public.company_kyc_documents TO authenticated;
GRANT ALL ON TABLE public.company_kyc_documents TO service_role;


--
-- Name: TABLE company_register_attempts; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.company_register_attempts TO service_role;


--
-- Name: SEQUENCE company_register_attempts_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.company_register_attempts_id_seq TO anon;
GRANT ALL ON SEQUENCE public.company_register_attempts_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.company_register_attempts_id_seq TO service_role;


--
-- Name: TABLE company_search_attempts; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.company_search_attempts TO anon;
GRANT ALL ON TABLE public.company_search_attempts TO authenticated;
GRANT ALL ON TABLE public.company_search_attempts TO service_role;


--
-- Name: SEQUENCE company_search_attempts_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.company_search_attempts_id_seq TO anon;
GRANT ALL ON SEQUENCE public.company_search_attempts_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.company_search_attempts_id_seq TO service_role;


--
-- Name: TABLE customer_debts; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.customer_debts TO anon;
GRANT ALL ON TABLE public.customer_debts TO authenticated;
GRANT ALL ON TABLE public.customer_debts TO service_role;


--
-- Name: TABLE customer_deposits; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.customer_deposits TO anon;
GRANT ALL ON TABLE public.customer_deposits TO authenticated;
GRANT ALL ON TABLE public.customer_deposits TO service_role;


--
-- Name: TABLE customer_phones; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.customer_phones TO anon;
GRANT ALL ON TABLE public.customer_phones TO authenticated;
GRANT ALL ON TABLE public.customer_phones TO service_role;


--
-- Name: TABLE customers; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.customers TO anon;
GRANT ALL ON TABLE public.customers TO authenticated;
GRANT ALL ON TABLE public.customers TO service_role;


--
-- Name: TABLE daily_cash_log; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.daily_cash_log TO anon;
GRANT ALL ON TABLE public.daily_cash_log TO authenticated;
GRANT ALL ON TABLE public.daily_cash_log TO service_role;


--
-- Name: TABLE diamond_pieces; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.diamond_pieces TO anon;
GRANT ALL ON TABLE public.diamond_pieces TO authenticated;
GRANT ALL ON TABLE public.diamond_pieces TO service_role;


--
-- Name: TABLE diamond_stock_lots; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.diamond_stock_lots TO anon;
GRANT ALL ON TABLE public.diamond_stock_lots TO authenticated;
GRANT ALL ON TABLE public.diamond_stock_lots TO service_role;


--
-- Name: TABLE expense_categories; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.expense_categories TO anon;
GRANT ALL ON TABLE public.expense_categories TO authenticated;
GRANT ALL ON TABLE public.expense_categories TO service_role;


--
-- Name: TABLE expense_entries; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.expense_entries TO anon;
GRANT ALL ON TABLE public.expense_entries TO authenticated;
GRANT ALL ON TABLE public.expense_entries TO service_role;


--
-- Name: TABLE fiscal_year_closures; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.fiscal_year_closures TO anon;
GRANT ALL ON TABLE public.fiscal_year_closures TO authenticated;
GRANT ALL ON TABLE public.fiscal_year_closures TO service_role;


--
-- Name: TABLE gift_cost_adjust_20261006; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.gift_cost_adjust_20261006 TO anon;
GRANT ALL ON TABLE public.gift_cost_adjust_20261006 TO authenticated;
GRANT ALL ON TABLE public.gift_cost_adjust_20261006 TO service_role;


--
-- Name: TABLE gold_prices; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.gold_prices TO anon;
GRANT ALL ON TABLE public.gold_prices TO authenticated;
GRANT ALL ON TABLE public.gold_prices TO service_role;


--
-- Name: TABLE gold_stock_lots; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.gold_stock_lots TO anon;
GRANT ALL ON TABLE public.gold_stock_lots TO authenticated;
GRANT ALL ON TABLE public.gold_stock_lots TO service_role;


--
-- Name: TABLE hr_employees; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.hr_employees TO anon;
GRANT ALL ON TABLE public.hr_employees TO authenticated;
GRANT ALL ON TABLE public.hr_employees TO service_role;


--
-- Name: TABLE hr_leave_requests; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.hr_leave_requests TO anon;
GRANT ALL ON TABLE public.hr_leave_requests TO authenticated;
GRANT ALL ON TABLE public.hr_leave_requests TO service_role;


--
-- Name: TABLE inventory_count_expected; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.inventory_count_expected TO anon;
GRANT ALL ON TABLE public.inventory_count_expected TO authenticated;
GRANT ALL ON TABLE public.inventory_count_expected TO service_role;


--
-- Name: TABLE inventory_count_scans; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.inventory_count_scans TO anon;
GRANT ALL ON TABLE public.inventory_count_scans TO authenticated;
GRANT ALL ON TABLE public.inventory_count_scans TO service_role;


--
-- Name: TABLE inventory_counts; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.inventory_counts TO anon;
GRANT ALL ON TABLE public.inventory_counts TO authenticated;
GRANT ALL ON TABLE public.inventory_counts TO service_role;


--
-- Name: TABLE inventory_gifts; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.inventory_gifts TO anon;
GRANT ALL ON TABLE public.inventory_gifts TO authenticated;
GRANT ALL ON TABLE public.inventory_gifts TO service_role;


--
-- Name: TABLE invoice_items; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.invoice_items TO anon;
GRANT ALL ON TABLE public.invoice_items TO authenticated;
GRANT ALL ON TABLE public.invoice_items TO service_role;


--
-- Name: TABLE invoice_number_counters; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.invoice_number_counters TO anon;
GRANT ALL ON TABLE public.invoice_number_counters TO authenticated;
GRANT ALL ON TABLE public.invoice_number_counters TO service_role;


--
-- Name: TABLE invoices; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.invoices TO anon;
GRANT ALL ON TABLE public.invoices TO authenticated;
GRANT ALL ON TABLE public.invoices TO service_role;


--
-- Name: TABLE kyc_screenings; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.kyc_screenings TO anon;
GRANT ALL ON TABLE public.kyc_screenings TO authenticated;
GRANT ALL ON TABLE public.kyc_screenings TO service_role;


--
-- Name: TABLE login_2fa; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.login_2fa TO anon;
GRANT ALL ON TABLE public.login_2fa TO authenticated;
GRANT ALL ON TABLE public.login_2fa TO service_role;


--
-- Name: TABLE lookup_username_attempts; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.lookup_username_attempts TO anon;
GRANT ALL ON TABLE public.lookup_username_attempts TO authenticated;
GRANT ALL ON TABLE public.lookup_username_attempts TO service_role;


--
-- Name: SEQUENCE lookup_username_attempts_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.lookup_username_attempts_id_seq TO anon;
GRANT ALL ON SEQUENCE public.lookup_username_attempts_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.lookup_username_attempts_id_seq TO service_role;


--
-- Name: TABLE organizations; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.organizations TO anon;
GRANT ALL ON TABLE public.organizations TO authenticated;
GRANT ALL ON TABLE public.organizations TO service_role;


--
-- Name: TABLE payroll_payments; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.payroll_payments TO anon;
GRANT ALL ON TABLE public.payroll_payments TO authenticated;
GRANT ALL ON TABLE public.payroll_payments TO service_role;


--
-- Name: TABLE piece_barcode_history; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.piece_barcode_history TO anon;
GRANT ALL ON TABLE public.piece_barcode_history TO authenticated;
GRANT ALL ON TABLE public.piece_barcode_history TO service_role;


--
-- Name: TABLE piece_chip_history; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.piece_chip_history TO anon;
GRANT ALL ON TABLE public.piece_chip_history TO authenticated;
GRANT ALL ON TABLE public.piece_chip_history TO service_role;


--
-- Name: TABLE piece_classification_options; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.piece_classification_options TO anon;
GRANT ALL ON TABLE public.piece_classification_options TO authenticated;
GRANT ALL ON TABLE public.piece_classification_options TO service_role;


--
-- Name: TABLE piece_cost_adjust_20261006; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.piece_cost_adjust_20261006 TO anon;
GRANT ALL ON TABLE public.piece_cost_adjust_20261006 TO authenticated;
GRANT ALL ON TABLE public.piece_cost_adjust_20261006 TO service_role;


--
-- Name: TABLE piece_intake_batches; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.piece_intake_batches TO anon;
GRANT ALL ON TABLE public.piece_intake_batches TO authenticated;
GRANT ALL ON TABLE public.piece_intake_batches TO service_role;


--
-- Name: TABLE piece_lot_draws; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.piece_lot_draws TO anon;
GRANT ALL ON TABLE public.piece_lot_draws TO authenticated;
GRANT ALL ON TABLE public.piece_lot_draws TO service_role;


--
-- Name: TABLE piece_movements; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.piece_movements TO anon;
GRANT ALL ON TABLE public.piece_movements TO authenticated;
GRANT ALL ON TABLE public.piece_movements TO service_role;


--
-- Name: TABLE pieces; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.pieces TO anon;
GRANT ALL ON TABLE public.pieces TO authenticated;
GRANT ALL ON TABLE public.pieces TO service_role;


--
-- Name: TABLE plans; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.plans TO anon;
GRANT ALL ON TABLE public.plans TO authenticated;
GRANT ALL ON TABLE public.plans TO service_role;


--
-- Name: TABLE platform_admins; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.platform_admins TO anon;
GRANT ALL ON TABLE public.platform_admins TO authenticated;
GRANT ALL ON TABLE public.platform_admins TO service_role;


--
-- Name: TABLE repair_gold_lines; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.repair_gold_lines TO anon;
GRANT ALL ON TABLE public.repair_gold_lines TO authenticated;
GRANT ALL ON TABLE public.repair_gold_lines TO service_role;


--
-- Name: TABLE repair_tickets; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.repair_tickets TO anon;
GRANT ALL ON TABLE public.repair_tickets TO authenticated;
GRANT ALL ON TABLE public.repair_tickets TO service_role;


--
-- Name: TABLE rfid_write_jobs; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.rfid_write_jobs TO anon;
GRANT ALL ON TABLE public.rfid_write_jobs TO authenticated;
GRANT ALL ON TABLE public.rfid_write_jobs TO service_role;


--
-- Name: TABLE staff; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.staff TO anon;
GRANT ALL ON TABLE public.staff TO authenticated;
GRANT ALL ON TABLE public.staff TO service_role;


--
-- Name: TABLE staff_presence; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.staff_presence TO authenticated;
GRANT ALL ON TABLE public.staff_presence TO service_role;


--
-- Name: TABLE staff_salaries; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.staff_salaries TO anon;
GRANT ALL ON TABLE public.staff_salaries TO authenticated;
GRANT ALL ON TABLE public.staff_salaries TO service_role;


--
-- Name: TABLE stock_parties; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.stock_parties TO anon;
GRANT ALL ON TABLE public.stock_parties TO authenticated;
GRANT ALL ON TABLE public.stock_parties TO service_role;


--
-- Name: TABLE stock_voucher_lines; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.stock_voucher_lines TO anon;
GRANT ALL ON TABLE public.stock_voucher_lines TO authenticated;
GRANT ALL ON TABLE public.stock_voucher_lines TO service_role;


--
-- Name: TABLE stock_vouchers; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.stock_vouchers TO anon;
GRANT ALL ON TABLE public.stock_vouchers TO authenticated;
GRANT ALL ON TABLE public.stock_vouchers TO service_role;


--
-- Name: TABLE store_invites; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.store_invites TO anon;
GRANT ALL ON TABLE public.store_invites TO authenticated;
GRANT ALL ON TABLE public.store_invites TO service_role;


--
-- Name: TABLE stores; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.stores TO anon;
GRANT ALL ON TABLE public.stores TO authenticated;
GRANT ALL ON TABLE public.stores TO service_role;


--
-- Name: TABLE subscriptions; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.subscriptions TO anon;
GRANT ALL ON TABLE public.subscriptions TO authenticated;
GRANT ALL ON TABLE public.subscriptions TO service_role;


--
-- Name: TABLE support_requests; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.support_requests TO anon;
GRANT ALL ON TABLE public.support_requests TO authenticated;
GRANT ALL ON TABLE public.support_requests TO service_role;


--
-- Name: TABLE trader_movements; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.trader_movements TO anon;
GRANT ALL ON TABLE public.trader_movements TO authenticated;
GRANT ALL ON TABLE public.trader_movements TO service_role;


--
-- Name: TABLE trader_scrap_draws; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.trader_scrap_draws TO anon;
GRANT ALL ON TABLE public.trader_scrap_draws TO authenticated;
GRANT ALL ON TABLE public.trader_scrap_draws TO service_role;


--
-- Name: TABLE traders; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.traders TO anon;
GRANT ALL ON TABLE public.traders TO authenticated;
GRANT ALL ON TABLE public.traders TO service_role;


--
-- Name: TABLE user_profiles; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.user_profiles TO anon;
GRANT ALL ON TABLE public.user_profiles TO authenticated;
GRANT ALL ON TABLE public.user_profiles TO service_role;


--
-- Name: TABLE zebra_label_fields; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.zebra_label_fields TO anon;
GRANT ALL ON TABLE public.zebra_label_fields TO authenticated;
GRANT ALL ON TABLE public.zebra_label_fields TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- PostgreSQL database dump complete
--

\unrestrict j570AKsyiQ0gzzXjRLt7j55k7f0NOQyUQgpv3QEveB28KiMzzImhjbhRmhX177r

