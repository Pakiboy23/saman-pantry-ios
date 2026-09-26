-- Anonymous product analytics (Saman Pantry 1.1).
-- One row per event. No user id, email, or content: only a random per-install
-- UUID, the event name, the app version, and the server timestamp.
-- Clients may INSERT only; nobody but the service role can read.

create table if not exists public.events (
  id          bigint generated always as identity primary key,
  install_id  uuid        not null,
  event       text        not null,
  app_version text,
  created_at  timestamptz not null default now(),
  constraint events_event_check check (event in (
    'app_open', 'signup', 'guest_start', 'item_added', 'list_item_bought',
    'pantry_restocked', 'recipe_saved', 'recipe_extracted', 'paywall_viewed',
    'purchase_started'
  )),
  constraint events_app_version_len check (app_version is null or char_length(app_version) <= 32)
);

create index if not exists events_created_at_idx on public.events (created_at);
create index if not exists events_event_created_at_idx on public.events (event, created_at);

alter table public.events enable row level security;

revoke all on table public.events from anon, authenticated;
grant insert (install_id, event, app_version) on table public.events to anon, authenticated;

drop policy if exists "events_insert_only" on public.events;
create policy "events_insert_only" on public.events
  for insert to anon, authenticated
  with check (true);
