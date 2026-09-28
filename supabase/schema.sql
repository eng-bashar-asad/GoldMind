--
-- PostgreSQL database dump
--

\restrict aMC22eeeSYxJseIYwg7btHvAVcfbpIi7zbvijwCy03z1lPNd8meHGsxMebdIUgv


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

  -- 1) gold prices that don't fit the store currency (the AED/USD mix-up)
  return query
  select 'error', 'gold_price_currency', 'سعر الذهب لا يتناسب مع عملة المحل',
         gold_price_problem(sid, g.karat, g.price_per_gram), null::uuid, g.karat || 'K'
  from gold_prices g where g.store_id = sid and gold_price_problem(sid, g.karat, g.price_per_gram) is not null;

  -- 2) invoices in a currency other than the store's
  return query
  select 'warning', 'invoice_currency', 'فاتورة بعملة غير عملة المحل',
         format('الفاتورة بـ %s والمحل بـ %s', i.currency, scur), i.id, i.invoice_number
  from invoices i where i.store_id = sid and i.currency is not null and upper(i.currency) <> scur and i.status <> 'cancelled';

  -- 3) sale invoices whose lines don't add up to the total (or have no lines)
  return query
  select 'error', 'invoice_lines_total', 'مجموع سطور الفاتورة ≠ الإجمالي',
         format('السطور %s — الإجمالي %s', coalesce(x.s, 0), i.total_amount), i.id, i.invoice_number
  from invoices i left join lateral (select sum(line_total) s, count(*) n from invoice_items where invoice_id = i.id) x on true
  where i.store_id = sid and i.type = 'sale' and i.status <> 'cancelled'
    and (x.n = 0 or abs(coalesce(x.s, 0) - i.total_amount) > 0.01);

  -- 4) paid amount vs cash actually booked for the invoice
  return query
  select 'warning', 'invoice_cash_mismatch', 'المقبوض بالفاتورة ≠ المسجّل بالصندوق',
         format('مدفوع %s — بالصندوق %s', i.amount_paid, coalesce(c.s, 0)), i.id, i.invoice_number
  from invoices i left join lateral (
      select sum(case when direction = 'in' then amount else -amount end) s from cash_movements where invoice_id = i.id) c on true
  where i.store_id = sid and i.type = 'sale' and i.status <> 'cancelled' and i.payment_method in ('cash','bank','mixed')
    and abs(coalesce(c.s, 0) - coalesce(i.amount_paid, 0)) > 0.01;

  -- 5) unpaid part not recorded as customer debt
  return query
  select 'warning', 'invoice_debt_mismatch', 'المبلغ المتبقي على العميل غير مسجّل كدين',
         format('متبقي %s — مسجّل دين %s', i.total_amount - coalesce(i.amount_paid,0), coalesce(d.s, 0)), i.id, i.invoice_number
  from invoices i left join lateral (
      select sum(cash_amount) s from customer_debts where invoice_id = i.id and movement_type = 'debt_increase') d on true
  where i.store_id = sid and i.type = 'sale' and i.status <> 'cancelled'
    and abs((i.total_amount - coalesce(i.amount_paid,0)) - coalesce(d.s, 0)) > 0.01;

  -- 6) invoice-linked cash booked in another currency
  return query
  select 'error', 'cash_currency', 'حركة صندوق لفاتورة بعملة غلط',
         format('%s %s — عملة المحل %s', cm.amount, cm.currency, scur), cm.invoice_id, i.invoice_number
  from cash_movements cm join invoices i on i.id = cm.invoice_id
  where cm.store_id = sid and cm.currency is not null and upper(cm.currency) <> upper(coalesce(i.currency, scur));

  -- 7) a piece on a live sale invoice that is still "available" (could be sold twice)
  return query
  select 'error', 'piece_still_available', 'قطعة مباعة لكنها ما زالت تظهر متاحة',
         format('القطعة %s بالفاتورة %s', p.barcode, i.invoice_number), p.id, p.barcode
  from invoice_items ii join invoices i on i.id = ii.invoice_id join pieces p on p.id = ii.piece_id
  where i.store_id = sid and i.type = 'sale' and i.status <> 'cancelled' and p.status = 'available';

  -- 8) negative bulk stock
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
           (select count(*) from public.staff st where st.store_id = s.id) as staff_count,
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
  if inv is null then
    raise exception 'INVOICE_NOT_FOUND';
  end if;
  if not public.has_permission('delete_invoice', inv.store_id) then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if inv.status = 'cancelled' then
    raise exception 'ALREADY_CANCELLED';
  end if;

  select id into actor_staff_id from public.staff where user_id = auth.uid() and store_id = inv.store_id limit 1;

  -- Never delete the invoice or renumber it — mark it cancelled and keep it
  -- in the record permanently (tax-compliance requirement: no gaps, no reuse).
  update public.invoices set status = 'cancelled' where id = target_invoice_id;

  -- Return any pieces this invoice touched to a sane inventory state.
  if inv.type = 'sale' then
    update public.pieces set status = 'available'
    where id in (select piece_id from public.invoice_items where invoice_id = target_invoice_id and piece_id is not null);
  elsif inv.type in ('buyTrader', 'buyRetail') then
    update public.pieces set status = 'cancelled'
    where id in (select piece_id from public.invoice_items where invoice_id = target_invoice_id and piece_id is not null);
  end if;

  -- Zero out any bulk gold lot (رصيد بالجملة) this purchase invoice created —
  -- previously left untouched, so a cancelled bulk buyTrader invoice kept
  -- silently counting toward warehouse stock (company-balances-ar.html,
  -- reports-ar.html) forever. Only zeroes the remainder, never the total, so
  -- the lot's history stays intact if any of it was already sold onward.
  update public.gold_stock_lots
    set weight_grams_remaining = 0
    where source_invoice_id = target_invoice_id and weight_grams_remaining > 0;

  -- Post reversing entries everywhere this invoice created a ledger movement
  -- (never delete history — a cancellation is itself an auditable event).
  insert into public.cash_movements (store_id, box, direction, amount, currency, description, created_by, invoice_id)
  select store_id, box, case when direction = 'in' then 'out' else 'in' end, amount, currency,
         'إلغاء فاتورة ' || inv.invoice_number || coalesce(' — ' || reason, ''), actor_staff_id, target_invoice_id
  from public.cash_movements where invoice_id = target_invoice_id;

  insert into public.customer_debts (store_id, customer_id, invoice_id, movement_type, cash_amount, gold_grams_24k, notes, created_by)
  select store_id, customer_id, invoice_id,
         case when movement_type = 'debt_increase' then 'debt_decrease' else 'debt_increase' end,
         cash_amount, gold_grams_24k, 'إلغاء فاتورة ' || inv.invoice_number || coalesce(' — ' || reason, ''), actor_staff_id
  from public.customer_debts where invoice_id = target_invoice_id;

  insert into public.trader_movements (store_id, trader_id, invoice_id, movement_type, weight_grams, karat, gold_24k_equivalent, fab_fee_amount, notes)
  select store_id, trader_id, invoice_id,
         case when movement_type = 'debt_increase' then 'debt_decrease' else 'debt_increase' end,
         weight_grams, karat, gold_24k_equivalent, fab_fee_amount, 'إلغاء فاتورة ' || inv.invoice_number || coalesce(' — ' || reason, '')
  from public.trader_movements where invoice_id = target_invoice_id;
end;
$$;


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
-- Name: currency_usd_peg(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.currency_usd_peg(cur text) RETURNS numeric
    LANGUAGE sql IMMUTABLE
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
-- Name: delete_last_sale_invoice(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_last_sale_invoice(target_invoice_id uuid) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  inv record;
  st record;
  inv_seq integer;
  inv_year integer;
  actor uuid;
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

  -- number format PREFIX-YYYY-NNNNNN; must be the last one issued
  inv_year := nullif(split_part(inv.invoice_number, '-', 2), '')::integer;
  inv_seq  := nullif(split_part(inv.invoice_number, '-', 3), '')::integer;
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
$$;


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
  select count(*)::int from staff where store_id = p_store_id;
$$;


--
-- Name: get_invoice_receipt(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_invoice_receipt(p_id uuid) RETURNS TABLE(invoice_number text, invoice_type text, status text, payment_method text, vat_amount numeric, total_amount numeric, created_at timestamp with time zone, store_name text, store_logo_url text, store_address text, store_phone text, store_email text, vat_rate numeric, tax_number text, currency text, secondary_currency text, secondary_currency_rate numeric, customer_name text, customer_phone text, items jsonb)
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT
    inv.invoice_number,
    inv.type,
    inv.status,
    inv.payment_method,
    inv.vat_amount,
    inv.total_amount,
    inv.created_at,
    s.name,
    s.logo_url,
    s.address,
    s.phone,
    s.email,
    s.vat_rate,
    s.tax_number,
    s.currency,
    s.secondary_currency,
    s.secondary_currency_rate,
    c.name,
    c.phone,
    COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'description', ii.description,
        'description_en', ii.description_en,
        'karat', ii.karat,
        'weight_grams', ii.weight_grams,
        'line_total', ii.line_total,
        'quantity', 1
      ) ORDER BY ii.id)
      FROM invoice_items ii WHERE ii.invoice_id = inv.id
    ), '[]'::jsonb)
  FROM invoices inv
  JOIN stores s ON s.id = inv.store_id
  LEFT JOIN customers c ON c.id = inv.customer_id
  WHERE inv.id = p_id AND inv.status != 'cancelled';
$$;


--
-- Name: get_repair_receipt(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_repair_receipt(p_id uuid) RETURNS TABLE(ticket_number text, piece_description text, problem_description text, intake_photo_url text, ready_photo_url text, status text, received_at timestamp with time zone, ready_at timestamp with time zone, store_name text, store_logo_url text, store_address text, store_phone text, received_by_name text, invoice_print_frame text, invoice_print_shape text, estimated_cost numeric, actual_cost numeric, vat_rate numeric, tax_number text)
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
    SELECT
        rt.ticket_number,
        rt.piece_description,
        rt.problem_description,
        rt.intake_photo_url,
        rt.ready_photo_url,
        rt.status,
        rt.received_at,
        rt.ready_at,
        s.name,
        s.logo_url,
        s.address,
        s.phone,
        st.full_name,
        s.invoice_print_frame,
        s.invoice_print_shape,
        rt.estimated_cost,
        rt.actual_cost,
        s.vat_rate,
        s.tax_number
    FROM repair_tickets rt
    JOIN stores s ON s.id = rt.store_id
    LEFT JOIN staff st ON st.id = rt.received_by
    WHERE rt.id = p_id;
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
-- Name: gold_implied_usd_ounce(numeric, integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gold_implied_usd_ounce(price_per_gram numeric, karat integer, cur text) RETURNS numeric
    LANGUAGE sql IMMUTABLE
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
-- Name: lookup_email_by_username(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.lookup_email_by_username(p_username text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_ip text;
  v_recent_count int;
begin
  v_ip := coalesce(
    (current_setting('request.headers', true)::json ->> 'x-forwarded-for'),
    'unknown'
  );
  v_ip := split_part(v_ip, ',', 1);

  select count(*) into v_recent_count
  from public.lookup_username_attempts
  where caller_ip = v_ip and attempted_at > now() - interval '60 seconds';

  if v_recent_count >= 5 then
    raise exception 'RATE_LIMITED' using errcode = '42901';
  end if;

  insert into public.lookup_username_attempts (caller_ip) values (v_ip);

  delete from public.lookup_username_attempts
  where attempted_at < now() - interval '10 minutes';

  return (
    select u.email::text
    from public.user_profiles up
    join auth.users u on u.id = up.id
    where lower(up.username) = lower(trim(p_username))
    limit 1
  );
end;
$$;


--
-- Name: mirror_invoice_cash_to_daily(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mirror_invoice_cash_to_daily() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  inv record;
  share numeric;
  amt numeric;
begin
  if new.invoice_id is null then return new; end if;
  select type, payment_method, cash_paid_amount, bank_paid_amount into inv
    from public.invoices where id = new.invoice_id;
  if inv is null then return new; end if;

  share := case inv.payment_method
    when 'cash' then 1
    when 'mixed' then case when coalesce(inv.cash_paid_amount, 0) + coalesce(inv.bank_paid_amount, 0) > 0
                           then coalesce(inv.cash_paid_amount, 0) / (coalesce(inv.cash_paid_amount, 0) + coalesce(inv.bank_paid_amount, 0))
                           else 0 end
    else 0 end;
  amt := round(new.amount * share, 2);
  if amt <= 0 then return new; end if;

  insert into public.daily_cash_log (store_id, operation_type, direction, amount, currency, notes, created_by, cash_movement_id)
  values (new.store_id,
          case inv.type when 'sale' then 'فاتورة بيع' when 'return' then 'مرتجع مبيعات' else 'فاتورة شراء' end,
          new.direction, amt, new.currency, new.description, new.created_by, new.id);
  return new;
end;
$$;


--
-- Name: my_stores(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.my_stores() RETURNS TABLE(store_id uuid, store_name text, role text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select s.store_id, st.name, s.role
  from public.staff s
  join public.stores st on st.id = s.store_id
  where s.user_id = auth.uid()
  order by st.name;
$$;


--
-- Name: next_invoice_number(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.next_invoice_number(target_store_id uuid, prefix text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
declare
  seq integer;
  yr integer := extract(year from now())::integer;
  stored_year integer;
begin
  if not public.is_store_member(target_store_id) then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if prefix is null or prefix !~ '^[A-Z]{2,6}$' then
    raise exception 'INVALID_PREFIX';
  end if;

  if prefix = 'INV' then
    -- sales keep the store counter (used by delete_last_sale_invoice / reset_invoice_sequence)
    select next_invoice_seq_year into stored_year from public.stores where id = target_store_id for update;
    if stored_year is null or stored_year <> yr then
      update public.stores set next_invoice_seq = 2, next_invoice_seq_year = yr where id = target_store_id;
      seq := 1;
    else
      update public.stores set next_invoice_seq = next_invoice_seq + 1
       where id = target_store_id returning next_invoice_seq - 1 into seq;
    end if;
  else
    -- every other kind (purchases PINV, returns RET, ...) has its own sequence
    insert into public.invoice_number_counters as c (store_id, prefix, year, next_seq)
    values (target_store_id, prefix, yr,
            coalesce((select max(nullif(split_part(i.invoice_number, '-', 3), '')::integer)
                        from public.invoices i
                       where i.store_id = target_store_id
                         and i.invoice_number ~ ('^' || prefix || '-' || yr || '-[0-9]+$')), 0) + 2)
    on conflict (store_id, prefix, year) do update set next_seq = c.next_seq + 1
    returning next_seq - 1 into seq;
  end if;

  return prefix || '-' || yr::text || '-' || lpad(seq::text, 6, '0');
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
  result_prefix text;
  result_seq bigint;
  result_width smallint;
begin
  if not is_store_member(target_store_id) then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if category not in ('gold', 'diamond') then
    raise exception 'INVALID_CATEGORY';
  end if;

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
  return coalesce(result_prefix, '') || case
    when result_width is not null and result_width > 0 then lpad(result_seq::text, result_width, '0')
    else result_seq::text
  end;
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
  new_id uuid; bc text; chk numeric;
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
    if tid is null or not exists (select 1 from traders where id = tid and store_id = sid) then
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
      insert into pieces (store_id, barcode, weight_grams, karat, description_ar, status, created_by)
        values (sid, bc, w, k, it->>'description', 'available', me) returning id into new_id;
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
          description_ar, status, created_by)
        values (sid, bc, has_gold, w, k, nullif(it->>'gold_fab_cost','')::numeric,
          nullif(it->>'diamond_carat','')::numeric, nullif(it->>'diamond_price_per_carat','')::numeric,
          nullif(it->>'shape',''), nullif(it->>'clarity',''), nullif(it->>'cut',''), nullif(it->>'color',''),
          nullif(it->>'cert_lab',''), nullif(it->>'cert_number',''), it->>'description', 'available', me)
        returning id into new_id;
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

  return jsonb_build_object('id', inv_id, 'invoice_number', inv_no, 'total', total, 'duplicate', false);
exception when unique_violation then
  if ref is not null then
    select id, invoice_number into ex from invoices where client_ref = ref and store_id = sid;
    if found then return jsonb_build_object('id', ex.id, 'invoice_number', ex.invoice_number, 'duplicate', true); end if;
  end if;
  raise;
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
    select id into cust from customers where store_id = sid and name = trim(p->'new_customer'->>'name')
      and coalesce(phone, '') = coalesce(nullif(trim(p->'new_customer'->>'phone'), ''), '') limit 1;
  end if;
  if cust is null and nullif(trim(p->'new_customer'->>'name'), '') is not null then
    insert into customers (store_id, name, phone) values (sid, trim(p->'new_customer'->>'name'), nullif(trim(p->'new_customer'->>'phone'), ''))
    returning id into cust;
  end if;
  if cust is null or not exists (select 1 from customers where id = cust and store_id = sid) then
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
      'fee', case when mode = 'stock' and coalesce((it->>'is_pooled')::boolean, false) then coalesce((it->>'manual_fab_fee')::numeric, 0) else 0 end,
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
      case when pm = 'mixed' then format('تحصيل جزئي لفاتورة بيع %s (%s نقدي + %s فيزا/بنك)', inv_no, cash_amt, bank_amt)
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
    raise exception 'بعض القطع المختارة أُرجعت مسبقاً';
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
declare
  is_owner boolean;
begin
  select (role = 'owner') into is_owner from staff
    where store_id = target_store_id and user_id = auth.uid() limit 1;
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
    update stores set next_piece_seq_diamond = new_seq where id = target_store_id;
  else
    update stores set next_piece_seq_gold = new_seq where id = target_store_id;
  end if;
end;
$$;


--
-- Name: reset_piece_barcode_sequence(uuid, text, bigint, smallint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reset_piece_barcode_sequence(target_store_id uuid, category text, new_seq bigint, seq_width smallint DEFAULT NULL::smallint) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  is_owner boolean;
begin
  select (role = 'owner') into is_owner from staff
    where store_id = target_store_id and user_id = auth.uid() limit 1;
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
    update stores set next_piece_seq_diamond = new_seq, piece_barcode_seq_width_diamond = seq_width where id = target_store_id;
  else
    update stores set next_piece_seq_gold = new_seq, piece_barcode_seq_width_gold = seq_width where id = target_store_id;
  end if;
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
begin
  select (role = 'owner') into is_owner from staff
    where store_id = target_store_id and user_id = auth.uid() limit 1;
  if not coalesce(is_owner, false) then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if category not in ('gold', 'diamond') then
    raise exception 'INVALID_CATEGORY';
  end if;
  if new_seq < 1 then
    raise exception 'INVALID_SEQ';
  end if;

  -- Updating the sequence used to always re-fetch the store row afterward
  -- (loadStore()), which would silently overwrite an in-progress, not-yet
  -- -saved prefix edit sitting in the input with whatever was still in
  -- the DB. Now the prefix the user currently has typed is saved in the
  -- SAME update, atomically with the sequence number, so this button
  -- fully commits both instead of quietly reverting one of them.
  if category = 'diamond' then
    update stores set
      next_piece_seq_diamond = new_seq,
      piece_barcode_seq_width_diamond = seq_width,
      piece_barcode_prefix_diamond = nullif(upper(trim(new_prefix)), '')
      where id = target_store_id;
  else
    update stores set
      next_piece_seq_gold = new_seq,
      piece_barcode_seq_width_gold = seq_width,
      piece_barcode_prefix_gold = nullif(upper(trim(new_prefix)), '')
      where id = target_store_id;
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
  if inv is null then
    raise exception 'INVOICE_NOT_FOUND';
  end if;
  if not public.has_permission('delete_invoice', inv.store_id) then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if inv.status != 'cancelled' then
    raise exception 'NOT_CANCELLED';
  end if;

  select id into actor_staff_id from public.staff where user_id = auth.uid() and store_id = inv.store_id limit 1;

  -- The pre-cancel status wasn't stored anywhere, so re-derive it the same
  -- way it was originally set at creation time (credit -> unpaid, else paid).
  restored_status := case when inv.payment_method = 'credit' then 'unpaid' else 'paid' end;
  update public.invoices set status = restored_status where id = target_invoice_id;

  -- Put pieces back in the state they'd be in for an active invoice of this type.
  if inv.type = 'sale' then
    update public.pieces set status = 'sold'
    where id in (select piece_id from public.invoice_items where invoice_id = target_invoice_id and piece_id is not null);
  elsif inv.type in ('buyTrader', 'buyRetail') then
    update public.pieces set status = 'available'
    where id in (select piece_id from public.invoice_items where invoice_id = target_invoice_id and piece_id is not null);
  end if;

  -- Never delete or edit the cancellation's reversing entries (they're a real
  -- past event) — post a new batch that reverses the reversal, restoring the
  -- original ledger effect while keeping full history.
  insert into public.cash_movements (store_id, box, direction, amount, currency, description, created_by, invoice_id)
  select store_id, box, case when direction = 'in' then 'out' else 'in' end, amount, currency,
         'استعادة فاتورة ' || inv.invoice_number, actor_staff_id, target_invoice_id
  from public.cash_movements where invoice_id = target_invoice_id and description like 'إلغاء فاتورة%';

  insert into public.customer_debts (store_id, customer_id, invoice_id, movement_type, cash_amount, gold_grams_24k, notes, created_by)
  select store_id, customer_id, invoice_id,
         case when movement_type = 'debt_increase' then 'debt_decrease' else 'debt_increase' end,
         cash_amount, gold_grams_24k, 'استعادة فاتورة ' || inv.invoice_number, actor_staff_id
  from public.customer_debts where invoice_id = target_invoice_id and notes like 'إلغاء فاتورة%';

  insert into public.trader_movements (store_id, trader_id, invoice_id, movement_type, weight_grams, karat, gold_24k_equivalent, fab_fee_amount, notes)
  select store_id, trader_id, invoice_id,
         case when movement_type = 'debt_increase' then 'debt_decrease' else 'debt_increase' end,
         weight_grams, karat, gold_24k_equivalent, fab_fee_amount, 'استعادة فاتورة ' || inv.invoice_number
  from public.trader_movements where invoice_id = target_invoice_id and notes like 'إلغاء فاتورة%';
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
-- Name: set_gold_ounce_price(uuid, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_gold_ounce_price(target_store_id uuid, ounce numeric, rate numeric) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare g24 numeric;
begin
  if not public.has_permission('manage_gold_price', target_store_id) then
    raise exception 'ليس لديك صلاحية تعديل سعر الذهب' using errcode = '42501';
  end if;
  if (select upper(currency) from public.stores where id = target_store_id) = 'USD' then
    rate := 1;
  end if;
  if ounce is null or ounce <= 0 or ounce > 1000000 then raise exception 'سعر أونصة غير صحيح'; end if;
  if rate is null or rate <= 0 or rate > 1000000 then raise exception 'سعر صرف غير صحيح'; end if;

  g24 := ounce / 31.1034768 * rate;
  insert into public.gold_prices (store_id, karat, price_per_gram, mode, updated_at)
  select target_store_id, k, round(g24 * k / 24.0, 2), 'manual_ounce', now()
  from unnest(array[24, 22, 21, 18]) as k
  on conflict (store_id, karat) do update
    set price_per_gram = excluded.price_per_gram, mode = excluded.mode, updated_at = now();

  update public.stores
     set last_gold_ounce_price = ounce, last_gold_ounce_rate = rate
   where id = target_store_id;
end;
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
    trader_movement_id uuid
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
    currency text
);


--
-- Name: COLUMN customer_debts.movement_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.customer_debts.movement_type IS 'debt_increase (credit sale) or debt_decrease (customer payment/settlement), mirroring trader_movements design.';


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
    attachment_url text
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
    CONSTRAINT inventory_count_scans_match_status_check CHECK ((match_status = ANY (ARRAY['matched'::text, 'unexpected'::text, 'duplicate'::text])))
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
    diamond_stock_lot_id uuid
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
    created_at timestamp with time zone DEFAULT now() NOT NULL
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
-- Name: piece_movements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.piece_movements (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    piece_id uuid NOT NULL,
    event_type text NOT NULL,
    note text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL
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
    CONSTRAINT pieces_karat_check CHECK ((karat = ANY (ARRAY[18, 21, 22, 24])))
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
    einvoice_monthly_quota integer
);


--
-- Name: COLUMN plans.prices; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.plans.prices IS 'Per-currency price list: {"AED":{yearly,quarterly,extra_staff_yearly,einvoice_addon_monthly,einvoice_overage}, "USD":{...}}. Annual commitment; quarterly = installment (+10%).';


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
    logo_url text,
    email text,
    manager_name text,
    contact_person_name text,
    commercial_registration_number text,
    tax_number text,
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
    legal_name text,
    legal_registration_id_type text,
    emirate_code text,
    peppol_endpoint_id text,
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
    CONSTRAINT invoice_print_frame_check CHECK ((invoice_print_frame = ANY (ARRAY['classic'::text, 'gold'::text, 'double'::text, 'dashed'::text, 'none'::text]))),
    CONSTRAINT invoice_print_shape_check CHECK ((invoice_print_shape = ANY (ARRAY['square'::text, 'soft'::text, 'round'::text])))
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
    CONSTRAINT trader_movements_source_check CHECK ((source = ANY (ARRAY['settlement'::text, 'stock_given'::text, 'stock_received'::text, 'opening_balance'::text])))
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
    kyc_completed_at timestamp with time zone
);


--
-- Name: user_profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_profiles (
    id uuid NOT NULL,
    username text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    privacy_accepted_at timestamp with time zone,
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
    CONSTRAINT zebra_label_fields_content_type_check CHECK ((content_type = ANY (ARRAY['barcode_number'::text, 'barcode_graphic'::text, 'company_name'::text, 'weight'::text, 'karat'::text, 'mc'::text, 'description'::text, 'custom_text'::text, 'blank_line'::text, 'diamond_carat'::text])))
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
-- Name: cash_movements cash_movements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_movements
    ADD CONSTRAINT cash_movements_pkey PRIMARY KEY (id);


--
-- Name: company_kyc_documents company_kyc_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_kyc_documents
    ADD CONSTRAINT company_kyc_documents_pkey PRIMARY KEY (id);


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
-- Name: repair_tickets repair_tickets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.repair_tickets
    ADD CONSTRAINT repair_tickets_pkey PRIMARY KEY (id);


--
-- Name: staff staff_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff
    ADD CONSTRAINT staff_pkey PRIMARY KEY (id);


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
-- Name: auth_device_keys_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_device_keys_user_idx ON public.auth_device_keys USING btree (user_id);


--
-- Name: auth_passkeys_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_passkeys_user_idx ON public.auth_passkeys USING btree (user_id);


--
-- Name: daily_cash_log_cash_movement_uidx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX daily_cash_log_cash_movement_uidx ON public.daily_cash_log USING btree (cash_movement_id) WHERE (cash_movement_id IS NOT NULL);


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
-- Name: inventory_count_scans_count_value_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX inventory_count_scans_count_value_uniq ON public.inventory_count_scans USING btree (count_id, rfid_epc);


--
-- Name: inventory_gifts_store_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX inventory_gifts_store_idx ON public.inventory_gifts USING btree (store_id, created_at DESC);


--
-- Name: invoices_client_ref_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX invoices_client_ref_key ON public.invoices USING btree (client_ref) WHERE (client_ref IS NOT NULL);


--
-- Name: piece_intake_batches_store_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX piece_intake_batches_store_idx ON public.piece_intake_batches USING btree (store_id, created_at DESC);


--
-- Name: pieces_intake_batch_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pieces_intake_batch_idx ON public.pieces USING btree (intake_batch_id);


--
-- Name: pieces_rfid_epc_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX pieces_rfid_epc_unique ON public.pieces USING btree (rfid_epc) WHERE (rfid_epc IS NOT NULL);


--
-- Name: stock_voucher_lines_party_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX stock_voucher_lines_party_idx ON public.stock_voucher_lines USING btree (party_id);


--
-- Name: stock_vouchers_store_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX stock_vouchers_store_idx ON public.stock_vouchers USING btree (store_id, created_at DESC);


--
-- Name: store_invites_unique_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX store_invites_unique_pending ON public.store_invites USING btree (store_id, lower(email)) WHERE (status = 'pending'::text);


--
-- Name: subscriptions_one_per_store; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX subscriptions_one_per_store ON public.subscriptions USING btree (store_id);


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
-- Name: cash_movements trg_cash_movements_currency; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_cash_movements_currency BEFORE INSERT ON public.cash_movements FOR EACH ROW EXECUTE FUNCTION public.fill_currency_from_store();


--
-- Name: customer_debts trg_customer_debts_currency; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_customer_debts_currency BEFORE INSERT ON public.customer_debts FOR EACH ROW EXECUTE FUNCTION public.fill_currency_from_store();


--
-- Name: daily_cash_log trg_daily_cash_log_currency; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_daily_cash_log_currency BEFORE INSERT ON public.daily_cash_log FOR EACH ROW EXECUTE FUNCTION public.fill_currency_from_store();


--
-- Name: gold_prices trg_gold_prices_currency_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_gold_prices_currency_guard BEFORE INSERT OR UPDATE OF price_per_gram, karat ON public.gold_prices FOR EACH ROW EXECUTE FUNCTION public.gold_prices_currency_guard();


--
-- Name: invoices trg_invoices_currency_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_invoices_currency_guard BEFORE INSERT ON public.invoices FOR EACH ROW EXECUTE FUNCTION public.invoices_currency_guard();


--
-- Name: cash_movements trg_mirror_invoice_cash_to_daily; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_mirror_invoice_cash_to_daily AFTER INSERT ON public.cash_movements FOR EACH ROW EXECUTE FUNCTION public.mirror_invoice_cash_to_daily();


--
-- Name: stores trg_seed_default_zebra_label_fields; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_seed_default_zebra_label_fields AFTER INSERT ON public.stores FOR EACH ROW EXECUTE FUNCTION public.seed_default_zebra_label_fields();


--
-- Name: stores trg_stores_currency_convert_gold; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_stores_currency_convert_gold AFTER UPDATE OF currency ON public.stores FOR EACH ROW EXECUTE FUNCTION public.stores_currency_convert_gold();


--
-- Name: stores trg_stores_currency_usd_reprice; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_stores_currency_usd_reprice BEFORE UPDATE OF currency ON public.stores FOR EACH ROW EXECUTE FUNCTION public.stores_currency_usd_reprice();


--
-- Name: staff trg_sync_staff_to_hr_employee; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_sync_staff_to_hr_employee AFTER INSERT ON public.staff FOR EACH ROW EXECUTE FUNCTION public.sync_staff_to_hr_employee();


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
    ADD CONSTRAINT diamond_stock_lots_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id);


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
    ADD CONSTRAINT hr_employees_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id);


--
-- Name: hr_leave_requests hr_leave_requests_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hr_leave_requests
    ADD CONSTRAINT hr_leave_requests_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.hr_employees(id);


--
-- Name: hr_leave_requests hr_leave_requests_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hr_leave_requests
    ADD CONSTRAINT hr_leave_requests_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id);


--
-- Name: inventory_count_expected inventory_count_expected_count_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_count_expected
    ADD CONSTRAINT inventory_count_expected_count_id_fkey FOREIGN KEY (count_id) REFERENCES public.inventory_counts(id) ON DELETE CASCADE;


--
-- Name: inventory_count_expected inventory_count_expected_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_count_expected
    ADD CONSTRAINT inventory_count_expected_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id);


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
    ADD CONSTRAINT inventory_count_scans_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id);


--
-- Name: inventory_counts inventory_counts_started_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_counts
    ADD CONSTRAINT inventory_counts_started_by_fkey FOREIGN KEY (started_by) REFERENCES public.staff(id);


--
-- Name: inventory_counts inventory_counts_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_counts
    ADD CONSTRAINT inventory_counts_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id);


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
    ADD CONSTRAINT kyc_screenings_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id);


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
  WHERE (pa.id = auth.uid()))));


--
-- Name: plans anyone authenticated can view plans; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "anyone authenticated can view plans" ON public.plans FOR SELECT USING ((auth.role() = 'authenticated'::text));


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
-- Name: company_kyc_documents; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.company_kyc_documents ENABLE ROW LEVEL SECURITY;

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
-- Name: customer_debts customer_debts_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY customer_debts_write ON public.customer_debts USING ((public.is_store_member(store_id) AND public.has_permission('edit_customers'::text, store_id))) WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('edit_customers'::text, store_id)));


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

CREATE POLICY expense_entries_select ON public.expense_entries FOR SELECT USING ((public.is_store_member(store_id) AND public.has_permission('view_profit_report'::text, store_id)));


--
-- Name: expense_entries expense_entries_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY expense_entries_write ON public.expense_entries USING ((public.is_store_member(store_id) AND public.has_permission('view_profit_report'::text, store_id))) WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('view_profit_report'::text, store_id)));


--
-- Name: fiscal_year_closures; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.fiscal_year_closures ENABLE ROW LEVEL SECURITY;

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
-- Name: organizations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;

--
-- Name: auth_device_keys own device keys: remove; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "own device keys: remove" ON public.auth_device_keys FOR DELETE TO authenticated USING ((user_id = auth.uid()));


--
-- Name: auth_device_keys own device keys: view; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "own device keys: view" ON public.auth_device_keys FOR SELECT TO authenticated USING ((user_id = auth.uid()));


--
-- Name: auth_passkeys own passkeys: remove; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "own passkeys: remove" ON public.auth_passkeys FOR DELETE TO authenticated USING ((user_id = auth.uid()));


--
-- Name: auth_passkeys own passkeys: view; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "own passkeys: view" ON public.auth_passkeys FOR SELECT TO authenticated USING ((user_id = auth.uid()));


--
-- Name: user_profiles own profile select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "own profile select" ON public.user_profiles FOR SELECT USING ((id = auth.uid()));


--
-- Name: user_profiles own profile update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "own profile update" ON public.user_profiles FOR UPDATE USING ((id = auth.uid()));


--
-- Name: user_profiles own profile upsert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "own profile upsert" ON public.user_profiles FOR INSERT WITH CHECK ((id = auth.uid()));


--
-- Name: inventory_count_expected owner can delete expected snapshot rows; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "owner can delete expected snapshot rows" ON public.inventory_count_expected FOR DELETE USING (public.has_permission('edit_settings'::text, store_id));


--
-- Name: organizations owner can update own organization; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "owner can update own organization" ON public.organizations FOR UPDATE USING (public.has_permission('edit_settings'::text, primary_store_id)) WITH CHECK (public.has_permission('edit_settings'::text, primary_store_id));


--
-- Name: staff owner or manage_staff can manage staff; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "owner or manage_staff can manage staff" ON public.staff USING ((public.is_store_member(store_id) AND public.has_permission('manage_staff'::text, store_id))) WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('manage_staff'::text, store_id)));


--
-- Name: fiscal_year_closures owners can close a year; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "owners can close a year" ON public.fiscal_year_closures FOR INSERT WITH CHECK ((public.is_store_member(store_id) AND (EXISTS ( SELECT 1
   FROM public.staff
  WHERE ((staff.user_id = auth.uid()) AND (staff.store_id = fiscal_year_closures.store_id) AND (staff.role = 'owner'::text))))));


--
-- Name: payroll_payments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payroll_payments ENABLE ROW LEVEL SECURITY;

--
-- Name: payroll_payments payroll_payments_rw; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_payments_rw ON public.payroll_payments USING ((public.is_store_member(store_id) AND public.has_permission('manage_payroll'::text, store_id))) WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('manage_payroll'::text, store_id)));


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
-- Name: piece_intake_batches; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.piece_intake_batches ENABLE ROW LEVEL SECURITY;

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
-- Name: platform_admins; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.platform_admins ENABLE ROW LEVEL SECURITY;

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
-- Name: diamond_pieces restrict delete_piece on diamond_pieces; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "restrict delete_piece on diamond_pieces" ON public.diamond_pieces FOR DELETE USING (public.has_permission('delete_piece'::text, store_id));


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

CREATE POLICY "store access: invoice_items" ON public.invoice_items USING ((invoice_id IN ( SELECT invoices.id
   FROM public.invoices
  WHERE public.is_store_member(invoices.store_id))));


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
-- Name: trader_movements trader_movements_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY trader_movements_write ON public.trader_movements USING ((public.is_store_member(store_id) AND public.has_permission('edit_traders'::text, store_id))) WITH CHECK ((public.is_store_member(store_id) AND public.has_permission('edit_traders'::text, store_id)));


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
-- Name: FUNCTION cancel_invoice(target_invoice_id uuid, reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cancel_invoice(target_invoice_id uuid, reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cancel_invoice(target_invoice_id uuid, reason text) TO authenticated;
GRANT ALL ON FUNCTION public.cancel_invoice(target_invoice_id uuid, reason text) TO service_role;


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
-- Name: FUNCTION delete_last_sale_invoice(target_invoice_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.delete_last_sale_invoice(target_invoice_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.delete_last_sale_invoice(target_invoice_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.delete_last_sale_invoice(target_invoice_id uuid) TO service_role;


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
-- Name: FUNCTION post_purchase_invoice(p jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.post_purchase_invoice(p jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.post_purchase_invoice(p jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.post_purchase_invoice(p jsonb) TO service_role;


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
-- Name: FUNCTION record_subscription_payment(p_store_id uuid, p_months integer, p_payment_ref text, p_plan_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.record_subscription_payment(p_store_id uuid, p_months integer, p_payment_ref text, p_plan_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.record_subscription_payment(p_store_id uuid, p_months integer, p_payment_ref text, p_plan_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.record_subscription_payment(p_store_id uuid, p_months integer, p_payment_ref text, p_plan_id uuid) TO service_role;


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
-- Name: FUNCTION seed_default_zebra_label_fields(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.seed_default_zebra_label_fields() TO anon;
GRANT ALL ON FUNCTION public.seed_default_zebra_label_fields() TO authenticated;
GRANT ALL ON FUNCTION public.seed_default_zebra_label_fields() TO service_role;


--
-- Name: FUNCTION set_gold_ounce_price(target_store_id uuid, ounce numeric, rate numeric); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.set_gold_ounce_price(target_store_id uuid, ounce numeric, rate numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION public.set_gold_ounce_price(target_store_id uuid, ounce numeric, rate numeric) TO authenticated;
GRANT ALL ON FUNCTION public.set_gold_ounce_price(target_store_id uuid, ounce numeric, rate numeric) TO service_role;


--
-- Name: FUNCTION stock_in_from_party(target_party_id uuid, return_piece_ids uuid[], new_lines jsonb, p_notes text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.stock_in_from_party(target_party_id uuid, return_piece_ids uuid[], new_lines jsonb, p_notes text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.stock_in_from_party(target_party_id uuid, return_piece_ids uuid[], new_lines jsonb, p_notes text) TO authenticated;
GRANT ALL ON FUNCTION public.stock_in_from_party(target_party_id uuid, return_piece_ids uuid[], new_lines jsonb, p_notes text) TO service_role;


--
-- Name: FUNCTION stock_out_to_party(target_party_id uuid, piece_ids uuid[], p_notes text, p_recipient text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.stock_out_to_party(target_party_id uuid, piece_ids uuid[], p_notes text, p_recipient text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.stock_out_to_party(target_party_id uuid, piece_ids uuid[], p_notes text, p_recipient text) TO authenticated;
GRANT ALL ON FUNCTION public.stock_out_to_party(target_party_id uuid, piece_ids uuid[], p_notes text, p_recipient text) TO service_role;


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
-- Name: FUNCTION sync_staff_to_hr_employee(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.sync_staff_to_hr_employee() TO anon;
GRANT ALL ON FUNCTION public.sync_staff_to_hr_employee() TO authenticated;
GRANT ALL ON FUNCTION public.sync_staff_to_hr_employee() TO service_role;


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
-- Name: TABLE cash_movements; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.cash_movements TO anon;
GRANT ALL ON TABLE public.cash_movements TO authenticated;
GRANT ALL ON TABLE public.cash_movements TO service_role;


--
-- Name: TABLE company_kyc_documents; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.company_kyc_documents TO anon;
GRANT ALL ON TABLE public.company_kyc_documents TO authenticated;
GRANT ALL ON TABLE public.company_kyc_documents TO service_role;


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
-- Name: TABLE piece_classification_options; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.piece_classification_options TO anon;
GRANT ALL ON TABLE public.piece_classification_options TO authenticated;
GRANT ALL ON TABLE public.piece_classification_options TO service_role;


--
-- Name: TABLE piece_intake_batches; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.piece_intake_batches TO anon;
GRANT ALL ON TABLE public.piece_intake_batches TO authenticated;
GRANT ALL ON TABLE public.piece_intake_batches TO service_role;


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
-- Name: TABLE repair_tickets; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.repair_tickets TO anon;
GRANT ALL ON TABLE public.repair_tickets TO authenticated;
GRANT ALL ON TABLE public.repair_tickets TO service_role;


--
-- Name: TABLE staff; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.staff TO anon;
GRANT ALL ON TABLE public.staff TO authenticated;
GRANT ALL ON TABLE public.staff TO service_role;


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

\unrestrict aMC22eeeSYxJseIYwg7btHvAVcfbpIi7zbvijwCy03z1lPNd8meHGsxMebdIUgv

