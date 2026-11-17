-- Display preferences follow the account: merge keys into user_profiles.home_prefs
-- (theme, nav size, favourites, quick actions, home boxes) without overwriting the others.
create or replace function public.gm_merge_home_prefs(p jsonb)
returns void
language sql
security invoker
set search_path = ''
as $$
  insert into public.user_profiles (id, home_prefs)
  values ((select auth.uid()), coalesce(p, '{}'::jsonb))
  on conflict (id) do update
    set home_prefs = coalesce(public.user_profiles.home_prefs, '{}'::jsonb) || coalesce(p, '{}'::jsonb);
$$;
revoke all on function public.gm_merge_home_prefs(jsonb) from public, anon;
grant execute on function public.gm_merge_home_prefs(jsonb) to authenticated;
