-- Phase 1 hardening (Supabase advisors 0011 / 0028 / 0029) and account-deletion
-- completeness.
--
-- 1. The three SECURITY DEFINER functions are trigger / event-trigger functions.
--    Nobody should call them over /rest/v1/rpc. Trigger firing does not check
--    EXECUTE, so revoking it does not affect signup or default pantries.
--
-- Those functions, update_updated_at, reset_instacart_pushes, and public.users
-- were created in the hosted project before this repo tracked migrations.
-- A fresh local database does not have them. Guard each statement so
-- `supabase start` can apply the rest of the history.

do $$
begin
  if to_regprocedure('public.create_default_pantries()') is not null then
    execute 'revoke execute on function public.create_default_pantries() from public, anon, authenticated';
  end if;
  if to_regprocedure('public.handle_new_user()') is not null then
    execute 'revoke execute on function public.handle_new_user() from public, anon, authenticated';
  end if;
  if to_regprocedure('public.rls_auto_enable()') is not null then
    execute 'revoke execute on function public.rls_auto_enable() from public, anon, authenticated';
  end if;
  if to_regprocedure('public.update_updated_at()') is not null then
    execute 'alter function public.update_updated_at() set search_path = public';
  end if;
  if to_regprocedure('public.reset_instacart_pushes()') is not null then
    execute 'alter function public.reset_instacart_pushes() set search_path = public';
  end if;
end $$;

-- 3. public.users (holds email) had no FK to auth.users, so delete-account left
--    the row behind. Remove rows whose auth user is already gone, then cascade.
do $$
begin
  if to_regclass('public.users') is null then
    return;
  end if;
  delete from public.users pu
  where not exists (select 1 from auth.users au where au.id = pu.id);

  if not exists (
    select 1 from pg_constraint
    where conname = 'users_id_fkey' and conrelid = 'public.users'::regclass
  ) then
    alter table public.users
      add constraint users_id_fkey foreign key (id)
      references auth.users(id) on delete cascade;
  end if;
end $$;
