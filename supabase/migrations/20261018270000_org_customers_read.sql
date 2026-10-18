-- Multi-branch 2.1 (part 1, read access only): one customer list and one balance for the
-- organization (decision by بشار 2026-10-18). Each movement stays recorded on the branch where
-- it happened; this migration only lets the other branches of the same organization READ them.
--   * customers, customer_debts, customer_deposits: readable from any branch of the organization
--     by staff who have view_customers in their own branch (balance + dates).
--   * invoices and their lines from another branch: only with the new permission
--     'view_branch_invoices' (owners always), so a plain employee sees the balance and the dates
--     but cannot open another branch's invoice.
-- Single-branch shops: nothing changes (the organization is the store itself). No data is touched.

-- true when the user has `perm` in some branch of the same organization as p_store
create or replace function public.org_can(p_store uuid, perm text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from stores a join stores b on b.organization_id = a.organization_id
    where a.id = p_store and has_permission(perm, b.id));
$$;
revoke all on function public.org_can(uuid, text) from public, anon;
grant execute on function public.org_can(uuid, text) to authenticated;

drop policy if exists customers_select_org on public.customers;
create policy customers_select_org on public.customers for select to authenticated
  using (org_can(store_id, 'view_customers'));

drop policy if exists customer_debts_select_org on public.customer_debts;
create policy customer_debts_select_org on public.customer_debts for select to authenticated
  using (org_can(store_id, 'view_customers'));

drop policy if exists customer_deposits_select_org on public.customer_deposits;
create policy customer_deposits_select_org on public.customer_deposits for select to authenticated
  using (org_can(store_id, 'view_customers'));

drop policy if exists invoices_select_org on public.invoices;
create policy invoices_select_org on public.invoices for select to authenticated
  using (org_can(store_id, 'view_branch_invoices'));

drop policy if exists invoice_items_select_org on public.invoice_items;
create policy invoice_items_select_org on public.invoice_items for select to authenticated
  using (invoice_id in (select i.id from invoices i where org_can(i.store_id, 'view_branch_invoices')));
