-- Run once in the Supabase SQL editor (Bashar).
-- The login check (login_email_for) cleans its own rate-limit rows again: attempt rows
-- older than 10 minutes are removed on every login try. Nothing else is deleted.
create or replace function public.login_email_for(p_username text, p_password text)
returns text language plpgsql security definer set search_path = public, extensions as $$
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
end $$;
