-- Rate limit for public company registration (register-company edge function, service role only)
create table if not exists public.company_register_attempts (
  id bigint generated always as identity primary key,
  caller_ip text not null,
  attempted_at timestamptz not null default now()
);
create index if not exists company_register_attempts_at_idx on public.company_register_attempts (attempted_at);
alter table public.company_register_attempts enable row level security;
-- no policies: only the register-company edge function (service role) reads/writes it
revoke all on public.company_register_attempts from anon, authenticated;
