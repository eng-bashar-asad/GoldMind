-- Computer home screen layout per person (which boxes show, their size, quick-access order),
-- kept on the account so it follows them to any computer. Written by the person only
-- (existing "own profile update" policy on user_profiles).
alter table public.user_profiles add column if not exists home_prefs jsonb;
