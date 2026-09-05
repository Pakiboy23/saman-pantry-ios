-- Quota log for extract-recipe. The Edge Function counts rows in the last 24h
-- under the service role and inserts one row per attempt. No client policies:
-- the table is not readable or writable with the anon/authenticated keys.
create table if not exists recipe_extraction_events (
    id          uuid primary key default uuid_generate_v4(),
    user_id     uuid not null references auth.users(id) on delete cascade,
    created_at  timestamptz not null default now()
);
alter table recipe_extraction_events enable row level security;
create index if not exists recipe_extraction_events_user_created_idx
    on recipe_extraction_events (user_id, created_at desc);
