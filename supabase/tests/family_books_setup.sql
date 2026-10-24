-- Prepares a database for family_books_security.sql. Plain SQL, safe to rerun.
--
-- Supabase branch: apply the migrations first (the branch does this), then run
-- this file. Roles, auth.users and auth.uid() already exist and are left alone.
--
-- Plain PostgreSQL (disposable, as superuser): run this file, then apply in order
-- 003_recipes, 008_recipe_book, 011_billing_grandfathered_and_quota,
-- 012_recipe_book_url_opt_in, 20261024000000_family_books and
-- 20261024010000_family_books_followup, then run this file again for the grants.
do $$
declare r text;
begin
  foreach r in array array['anon', 'authenticated', 'service_role', 'supabase_auth_admin'] loop
    if not exists (select 1 from pg_roles where rolname = r) then
      execute format('create role %I nologin', r);
    end if;
  end loop;
end $$;
create schema if not exists auth;
create schema if not exists extensions;
create table if not exists auth.users (id uuid primary key, email text, created_at timestamptz default now());
do $$ begin
  if to_regprocedure('auth.uid()') is null then
    execute $f$create function auth.uid() returns uuid language sql stable as
      'select nullif(current_setting(''request.jwt.claim.sub'', true), '''')::uuid'$f$;
  end if;
end $$;
grant usage on schema auth, public, extensions to authenticated;
grant execute on function auth.uid() to authenticated;
create extension if not exists "uuid-ossp";
-- Fresh Supabase branches lack these grants; production has them.
do $$ begin
  if to_regclass('public.recipes') is not null then
    grant select, insert, update, delete on public.recipes to authenticated;
  end if;
end $$;
