-- Two-step login for password sign-ins: after the password, an 8-digit code sent to the
-- account's email (edge function login-2fa) must be entered. Fingerprint / Face ID and
-- email-code sign-ins are not password sessions and pass straight through. Accounts made
-- with a username only (placeholder @staff.goldmind.app email, no real inbox) are left out.
-- Enforced by the server for every REST/RPC request (PostgREST pre-request hook), so a
-- stolen password alone cannot read or change anything.
create table if not exists public.login_2fa (
  session_id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  code_hash text,
  expires_at timestamptz,
  attempts int not null default 0,
  sent_count int not null default 0,
  last_sent_at timestamptz,
  verified_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists login_2fa_user_id_idx on public.login_2fa (user_id);
alter table public.login_2fa enable row level security; -- no policies: only the edge function (service role) touches it

create or replace function public.gm_session_ok()
returns boolean language sql stable security definer set search_path = public as $$
  select auth.uid() is null
    -- not a password session (fingerprint/Face ID, email code); no amr claim at all → not a password session either
    or coalesce((select bool_or(a->>'method' <> 'password') from jsonb_array_elements(coalesce(auth.jwt()->'amr', '[]'::jsonb)) a), true)
    or exists (select 1 from auth.users u where u.id = auth.uid() and u.email like '%@staff.goldmind.app')
    or exists (select 1 from public.login_2fa l where l.session_id = nullif(auth.jwt()->>'session_id', '')::uuid
                 and l.user_id = auth.uid() and l.verified_at is not null);
$$;
grant execute on function public.gm_session_ok() to authenticated, anon;

create or replace function public.gm_pre_request()
returns void language plpgsql security definer set search_path = public as $$
begin
  if coalesce(auth.role(), '') <> 'authenticated' then return; end if;
  if coalesce(current_setting('request.path', true), '') = '/rpc/gm_session_ok' then return; end if;
  if not public.gm_session_ok() then
    raise sqlstate 'PT403' using message = '2FA_REQUIRED', hint = 'أدخل رمز التحقق المرسل إلى بريدك الإلكتروني';
  end if;
end $$;
grant execute on function public.gm_pre_request() to authenticated, anon;

alter role authenticator set pgrst.db_pre_request to 'public.gm_pre_request';
notify pgrst, 'reload config';
