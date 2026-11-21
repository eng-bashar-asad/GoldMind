-- Speed (بشار 2026-11-21): the advisor found 90 cases of several permissive RLS policies for the same table/command,
-- so every row was checked against each of them. For the tables below, each command now has ONE permissive policy
-- whose rule is the OR of the old ones (that is exactly how Postgres combined them), and «FOR ALL» write policies are
-- split per command so they no longer also count for SELECT. Restrictive policies are untouched.
-- Verified: what 5 real users (owners and limited staff of 3 stores) and anon can see in all 21 tables is identical
-- before and after (row counts and content hashes).
-- The old definitions are kept in gm_admin.rls_policy_backup for a rollback.
create schema if not exists gm_admin;
create table if not exists gm_admin.rls_policy_backup as select now() saved_at, * from pg_policies where false;
do $m$
declare
  tb text; r record;
  sel text; ins text; updu text; updc text; del text;
begin
  foreach tb in array array['cash_movements','customer_debts','customer_deposits','customer_phones','customers','diamond_stock_lots','expense_categories','expense_entries','gold_prices','gold_stock_lots','hr_employees','hr_leave_requests','invoice_items','invoices','kyc_screenings','organizations','staff','subscriptions','trader_movements','traders','zebra_label_fields'] loop
    insert into gm_admin.rls_policy_backup select now(), * from pg_policies where schemaname = 'public' and tablename = tb and permissive = 'PERMISSIVE';
    select string_agg('(' || qual || ')', ' OR ') filter (where cmd in ('SELECT','ALL') and qual is not null),
           string_agg('(' || coalesce(with_check, qual) || ')', ' OR ') filter (where cmd in ('INSERT','ALL')),  -- FOR ALL without WITH CHECK checks new rows with USING
           string_agg('(' || qual || ')', ' OR ') filter (where cmd in ('UPDATE','ALL') and qual is not null),
           string_agg('(' || coalesce(with_check, qual) || ')', ' OR ') filter (where cmd in ('UPDATE','ALL')),
           string_agg('(' || qual || ')', ' OR ') filter (where cmd in ('DELETE','ALL') and qual is not null)
      into sel, ins, updu, updc, del
      from pg_policies where schemaname = 'public' and tablename = tb and permissive = 'PERMISSIVE';
    for r in select policyname from pg_policies where schemaname = 'public' and tablename = tb and permissive = 'PERMISSIVE' loop
      execute format('drop policy %I on public.%I', r.policyname, tb);
    end loop;
    -- TO authenticated: every rule here needs a login; anon (which may not run org_can) keeps getting no rows
    if sel  is not null then execute format('create policy %I on public.%I for select to authenticated using (%s)', tb || '_read', tb, sel); end if;
    if ins  is not null then execute format('create policy %I on public.%I for insert to authenticated with check (%s)', tb || '_add', tb, ins); end if;
    if updu is not null then execute format('create policy %I on public.%I for update to authenticated using (%s) with check (%s)', tb || '_change', tb, updu, updc); end if;
    if del  is not null then execute format('create policy %I on public.%I for delete to authenticated using (%s)', tb || '_remove', tb, del); end if;
  end loop;
end $m$;
