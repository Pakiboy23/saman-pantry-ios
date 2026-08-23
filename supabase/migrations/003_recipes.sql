-- Recipes. The local SwiftData model had isDirty with nowhere to go.
create table if not exists recipes (
    id              uuid primary key default uuid_generate_v4(),
    user_id         uuid not null references auth.users(id) on delete cascade,
    title           text not null,
    raw_transcript  text not null default '',
    extracted_json  text,
    attribution     text,
    updated_at      timestamptz not null default now(),
    created_at      timestamptz not null default now()
);
alter table recipes enable row level security;
drop policy if exists "owner" on recipes;
create policy "owner" on recipes using (auth.uid() = user_id) with check (auth.uid() = user_id);
