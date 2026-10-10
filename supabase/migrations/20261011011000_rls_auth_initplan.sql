-- Speed: evaluate auth.uid()/auth.role() once per query instead of once per row (Supabase linter 0003)
alter policy "anyone authenticated can view plans" on public.plans using ((select auth.role()) = 'authenticated');
alter policy "admins can view admin list" on public.platform_admins using (exists (select 1 from public.platform_admins pa where pa.id = (select auth.uid())));
alter policy "own profile update" on public.user_profiles using (id = (select auth.uid()));
alter policy "own profile select" on public.user_profiles using (id = (select auth.uid()));
alter policy "own profile upsert" on public.user_profiles with check (id = (select auth.uid()));
alter policy "owners can close a year" on public.fiscal_year_closures with check (is_store_member(store_id) and exists (select 1 from public.staff where staff.user_id = (select auth.uid()) and staff.store_id = fiscal_year_closures.store_id and staff.role = 'owner'));
alter policy "own device keys: view" on public.auth_device_keys using (user_id = (select auth.uid()));
alter policy "own device keys: remove" on public.auth_device_keys using (user_id = (select auth.uid()));
alter policy "own passkeys: remove" on public.auth_passkeys using (user_id = (select auth.uid()));
alter policy "own passkeys: view" on public.auth_passkeys using (user_id = (select auth.uid()));
