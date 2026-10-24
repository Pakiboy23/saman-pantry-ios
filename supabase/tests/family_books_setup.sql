-- Run only in an empty disposable PostgreSQL database as its superuser.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin;
create role supabase_auth_admin nologin;
create schema auth;
create schema extensions;
create table auth.users (id uuid primary key, email text, created_at timestamptz default now());
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
grant usage on schema auth, public, extensions to authenticated;
grant execute on function auth.uid() to authenticated;
create extension if not exists "uuid-ossp";
\ir ../migrations/003_recipes.sql
\ir ../migrations/008_recipe_book.sql
\ir ../migrations/011_billing_grandfathered_and_quota.sql
\ir ../migrations/012_recipe_book_url_opt_in.sql
grant select, insert, update, delete on public.recipes to authenticated;
\ir ../migrations/20261024000000_family_books.sql
