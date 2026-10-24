-- Security audit R1 fixes (SEC-001..004). No data is deleted.

-- SEC-002: only the scrap trigger (runs as owner) may call this.
revoke execute on function public.gm_scrap_return_unrecorded(uuid, integer, numeric, text) from public, anon, authenticated;

-- SEC-003: anyone in the store can read invoice lines; changing them needs "edit_invoice".
-- (Sales and purchases write their lines through SECURITY DEFINER functions.)
create policy "invoice_items: members read" on public.invoice_items for select
  using (invoice_id in (select i.id from public.invoices i where public.is_store_member(i.store_id)));
alter policy "store access: invoice_items" on public.invoice_items
  using (invoice_id in (select i.id from public.invoices i where public.is_store_member(i.store_id) and public.has_permission('edit_invoice', i.store_id)))
  with check (invoice_id in (select i.id from public.invoices i where public.is_store_member(i.store_id) and public.has_permission('edit_invoice', i.store_id)));

-- SEC-001: the daily reports were readable without signing in.
alter policy "public can read daily reports" on storage.objects using (false);

-- SEC-004: the email-code (2FA) check now also guards private files.
alter policy "store members can read own daily reports" on storage.objects
  using (bucket_id = 'daily-reports' and public.is_store_member(((storage.foldername(name))[1])::uuid) and public.gm_session_ok());
alter policy "store members can upload daily reports" on storage.objects
  with check (bucket_id = 'daily-reports' and public.is_store_member(((storage.foldername(name))[1])::uuid) and public.gm_session_ok());
alter policy "store members can read own kyc files" on storage.objects
  using (bucket_id = 'company-kyc-documents' and public.is_store_member(((storage.foldername(name))[1])::uuid) and public.gm_session_ok());
alter policy "store members can upload kyc files" on storage.objects
  with check (bucket_id = 'company-kyc-documents' and public.is_store_member(((storage.foldername(name))[1])::uuid) and public.gm_session_ok());
alter policy "store members can delete kyc files" on storage.objects
  using (bucket_id = 'company-kyc-documents' and public.is_store_member(((storage.foldername(name))[1])::uuid) and public.gm_session_ok());
alter policy "store staff can read own invoice attachments" on storage.objects
  using (bucket_id = 'invoice-attachments' and (storage.foldername(name))[1] in (select s.store_id::text from public.staff s where s.user_id = auth.uid()) and public.gm_session_ok());
alter policy "store staff can upload invoice attachments" on storage.objects
  with check (bucket_id = 'invoice-attachments' and (storage.foldername(name))[1] in (select s.store_id::text from public.staff s where s.user_id = auth.uid()) and public.gm_session_ok());
alter policy "store staff can update own invoice attachments" on storage.objects
  using (bucket_id = 'invoice-attachments' and (storage.foldername(name))[1] in (select s.store_id::text from public.staff s where s.user_id = auth.uid()) and public.gm_session_ok());
alter policy "store staff can delete own invoice attachments" on storage.objects
  using (bucket_id = 'invoice-attachments' and (storage.foldername(name))[1] in (select s.store_id::text from public.staff s where s.user_id = auth.uid()) and public.gm_session_ok());
alter policy "store staff can upload piece photos" on storage.objects
  with check (bucket_id = 'piece-photos' and (storage.foldername(name))[1] in (select s.store_id::text from public.staff s where s.user_id = auth.uid()) and public.gm_session_ok());
alter policy "store staff can update own piece photos" on storage.objects
  using (bucket_id = 'piece-photos' and (storage.foldername(name))[1] in (select s.store_id::text from public.staff s where s.user_id = auth.uid()) and public.gm_session_ok());
alter policy "store staff can delete own piece photos" on storage.objects
  using (bucket_id = 'piece-photos' and (storage.foldername(name))[1] in (select s.store_id::text from public.staff s where s.user_id = auth.uid()) and public.gm_session_ok());

-- SEC-007: real emails are no longer returned for a username alone; see 20261024151000_login_email_for.sql.
-- The old function stays for older app builds and returns only internal staff login addresses.
create or replace function public.lookup_email_by_username(p_username text)
returns text language plpgsql security definer set search_path = public as $$
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

-- SEC-015 (low, same pass): fixed search_path.
alter function public.gm_op_date_stamp() set search_path = public;
