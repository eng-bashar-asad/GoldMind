-- upload with upsert:true needs SELECT on the object as well as INSERT/UPDATE
-- (purchase invoice photos failed with "new row violates row-level security policy")
drop policy if exists "store staff can read own invoice attachments" on storage.objects;
create policy "store staff can read own invoice attachments" on storage.objects for select
  using (bucket_id = 'invoice-attachments' and (storage.foldername(name))[1] in (select staff.store_id::text from staff where staff.user_id = auth.uid()));
