-- Staff can see their own store's piece-photo object rows (the bucket is public, so this exposes nothing new).
-- Needed so storage remove()/list work for the «تحسين الصور» cleanup: DELETE … RETURNING only reaches rows SELECT can see.
create policy "store staff can read own piece photos" on storage.objects for select
using (bucket_id = 'piece-photos' and (storage.foldername(name))[1] in (select s.store_id::text from public.staff s where s.user_id = auth.uid()) and public.gm_session_ok());
