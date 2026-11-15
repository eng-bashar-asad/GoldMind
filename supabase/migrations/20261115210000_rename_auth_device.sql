-- Let a user name their own fingerprint / Face ID devices («هاتفي سامسونج»، «كمبيوتر المحل») — بشار 2026-11-15.
-- Only device_name changes, only on the caller's own rows; key material is never touched.
create or replace function public.rename_auth_device(p_kind text, p_id uuid, p_name text)
returns void language plpgsql security definer set search_path to 'public' as $$
declare n text := nullif(left(trim(regexp_replace(coalesce(p_name, ''), '[<>]', '', 'g')), 60), '');
begin
  if auth.uid() is null then raise exception 'سجّل الدخول أولاً' using errcode = '42501'; end if;
  if n is null then raise exception 'اكتب اسماً للجهاز'; end if;
  if p_kind = 'auth_device_keys' then
    update auth_device_keys set device_name = n where id = p_id and user_id = auth.uid();
  elsif p_kind = 'auth_passkeys' then
    update auth_passkeys set device_name = n where id = p_id and user_id = auth.uid();
  else
    raise exception 'نوع غير معروف';
  end if;
  if not found then raise exception 'الجهاز غير موجود'; end if;
end $$;
revoke all on function public.rename_auth_device(text, uuid, text) from public, anon;
grant execute on function public.rename_auth_device(text, uuid, text) to authenticated;
