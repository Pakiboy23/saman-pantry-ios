-- Phase 1 hardening (Supabase advisors 0011 / 0028 / 0029) and account-deletion
-- completeness.
--
-- 1. The three SECURITY DEFINER functions are trigger / event-trigger functions.
--    Nobody should call them over /rest/v1/rpc. Trigger firing does not check
--    EXECUTE, so revoking it does not affect signup or default pantries.
revoke execute on function public.create_default_pantries() from public, anon, authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;

-- 2. Pin search_path on the two remaining trigger functions.
alter function public.update_updated_at() set search_path = public;
alter function public.reset_instacart_pushes() set search_path = public;

-- 3. public.users (holds email) had no FK to auth.users, so delete-account left
--    the row behind. Remove rows whose auth user is already gone, then cascade.
delete from public.users pu
where not exists (select 1 from auth.users au where au.id = pu.id);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'users_id_fkey' and conrelid = 'public.users'::regclass
  ) then
    alter table public.users
      add constraint users_id_fkey foreign key (id)
      references auth.users(id) on delete cascade;
  end if;
end $$;
