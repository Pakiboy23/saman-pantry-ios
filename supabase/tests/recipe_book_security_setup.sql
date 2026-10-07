-- Run only in an empty disposable PostgreSQL database as its superuser.
-- Minimal Supabase auth fixture; all authorization assertions use authenticated.
create role anon nologin;
create role authenticated nologin;
create schema auth;
create table auth.users (id uuid primary key, email text);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
grant usage on schema auth, public to authenticated;
grant execute on function auth.uid() to authenticated;
create extension if not exists "uuid-ossp";
\ir ../migrations/003_recipes.sql
\ir ../migrations/008_recipe_book.sql
grant select, insert, update, delete on all tables in schema public to authenticated;
