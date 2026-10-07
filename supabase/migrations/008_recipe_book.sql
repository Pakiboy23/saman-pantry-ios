-- Public family recipe book.
-- A transcript save publishes a card automatically. A URL extract stays on the
-- owner's recipes row and never becomes a card. Public read is the card only:
-- title, steps, original ingredient phrases, attribution, and who added it.
-- raw_transcript never appears on the card. Reading the book is free and does
-- not touch recipe_extraction_events. Household mode stays off.

alter table public.recipes
  add column if not exists source_kind text not null default 'transcript';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'recipes_source_kind_check'
      and conrelid = 'public.recipes'::regclass
  ) then
    alter table public.recipes
      add constraint recipes_source_kind_check
      check (source_kind in ('transcript', 'url'));
  end if;
end $$;

create table if not exists public.recipe_book_cards (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  attribution text,
  steps jsonb not null default '[]'::jsonb,
  ingredient_phrases jsonb not null default '[]'::jsonb,
  added_by_label text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists recipe_book_cards_created_at_idx
  on public.recipe_book_cards (created_at desc);

alter table public.recipe_book_cards enable row level security;

drop policy if exists "recipe_book_cards_select_authenticated" on public.recipe_book_cards;
create policy "recipe_book_cards_select_authenticated" on public.recipe_book_cards
  for select to authenticated
  using (true);

drop policy if exists "recipe_book_cards_owner_insert" on public.recipe_book_cards;
create policy "recipe_book_cards_owner_insert" on public.recipe_book_cards
  for insert to authenticated
  with check (auth.uid() = owner_id);

drop policy if exists "recipe_book_cards_owner_update" on public.recipe_book_cards;
create policy "recipe_book_cards_owner_update" on public.recipe_book_cards
  for update to authenticated
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

drop policy if exists "recipe_book_cards_owner_delete" on public.recipe_book_cards;
create policy "recipe_book_cards_owner_delete" on public.recipe_book_cards
  for delete to authenticated
  using (auth.uid() = owner_id);

create table if not exists public.recipe_book_notes (
  id uuid primary key default uuid_generate_v4(),
  card_id uuid not null references public.recipe_book_cards(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint recipe_book_notes_body_not_blank check (char_length(trim(body)) > 0)
);

create index if not exists recipe_book_notes_card_created_idx
  on public.recipe_book_notes (card_id, created_at desc);

alter table public.recipe_book_notes enable row level security;

drop policy if exists "recipe_book_notes_select_authenticated" on public.recipe_book_notes;
create policy "recipe_book_notes_select_authenticated" on public.recipe_book_notes
  for select to authenticated
  using (true);

drop policy if exists "recipe_book_notes_insert_own" on public.recipe_book_notes;
create policy "recipe_book_notes_insert_own" on public.recipe_book_notes
  for insert to authenticated
  with check (auth.uid() = author_id);

drop policy if exists "recipe_book_notes_update_own" on public.recipe_book_notes;
create policy "recipe_book_notes_update_own" on public.recipe_book_notes
  for update to authenticated
  using (auth.uid() = author_id)
  with check (auth.uid() = author_id);

drop policy if exists "recipe_book_notes_delete_own" on public.recipe_book_notes;
create policy "recipe_book_notes_delete_own" on public.recipe_book_notes
  for delete to authenticated
  using (auth.uid() = author_id);

create or replace function public.sync_recipe_book_card()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  recipe_row public.recipes%rowtype;
  card_owner uuid;
  parsed jsonb;
  card_steps jsonb := '[]'::jsonb;
  card_phrases jsonb := '[]'::jsonb;
  label text;
  email text;
begin
  if tg_op = 'DELETE' then
    recipe_row := old;
  else
    recipe_row := new;
  end if;

  -- Cards may exist without recipes. An ID match does not prove ownership.
  select owner_id into card_owner from public.recipe_book_cards
  where id = recipe_row.id for update;
  if found and card_owner is distinct from recipe_row.user_id then
    raise exception 'Recipe card ownership conflict' using errcode = '42501';
  end if;

  if tg_op = 'DELETE' then
    delete from public.recipe_book_cards where id = old.id and owner_id = old.user_id;
    return old;
  end if;

  -- URL extracts stay private. Drop any stale card if the source flips.
  if new.source_kind is distinct from 'transcript' then
    delete from public.recipe_book_cards where id = new.id and owner_id = new.user_id;
    return new;
  end if;

  begin
    parsed := new.extracted_json::jsonb;
  exception when others then
    parsed := '{}'::jsonb;
  end;

  card_steps := coalesce(parsed -> 'steps', '[]'::jsonb);
  if jsonb_typeof(card_steps) <> 'array' then
    card_steps := '[]'::jsonb;
  end if;

  select coalesce(
    jsonb_agg(coalesce(elem ->> 'original_phrase', elem ->> 'ingredient', '')),
    '[]'::jsonb
  )
  into card_phrases
  from jsonb_array_elements(coalesce(parsed -> 'ingredients', '[]'::jsonb)) as elem;

  select au.email into email from auth.users au where au.id = new.user_id;
  label := coalesce(
    nullif(split_part(coalesce(email, ''), '@', 1), ''),
    'A cook in the village'
  );

  insert into public.recipe_book_cards as c (
    id,
    owner_id,
    title,
    attribution,
    steps,
    ingredient_phrases,
    added_by_label,
    created_at,
    updated_at
  ) values (
    new.id,
    new.user_id,
    new.title,
    new.attribution,
    card_steps,
    coalesce(card_phrases, '[]'::jsonb),
    label,
    coalesce(new.created_at, now()),
    new.updated_at
  )
  on conflict (id) do update set
    title = excluded.title,
    attribution = excluded.attribution,
    steps = excluded.steps,
    ingredient_phrases = excluded.ingredient_phrases,
    added_by_label = excluded.added_by_label,
    updated_at = excluded.updated_at
  -- Recheck under the conflict lock if another transaction inserted the card.
  where c.owner_id = excluded.owner_id;

  if not found then
    raise exception 'Recipe card ownership conflict' using errcode = '42501';
  end if;

  return new;
end;
$$;

revoke all on function public.sync_recipe_book_card() from public;
revoke execute on function public.sync_recipe_book_card() from anon, authenticated;

drop trigger if exists recipes_sync_recipe_book_card on public.recipes;
create trigger recipes_sync_recipe_book_card
after insert or update or delete on public.recipes
for each row execute function public.sync_recipe_book_card();
