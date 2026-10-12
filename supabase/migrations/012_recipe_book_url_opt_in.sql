-- Opt a URL recipe into the family book.
-- Transcript saves still publish on their own. URL extracts stay private until
-- the owner sets recipes.share_in_family_book. Clearing the flag removes the
-- card and leaves the recipe. This migration does not update or delete
-- existing recipes or cards.
--
-- A shared link card may carry source_url when raw_transcript is an http(s)
-- link. raw_transcript itself is never a card column. Transcript cards keep
-- source_url null.
--
-- Only the recipe owner can change the flag. recipes keeps the owner policy
-- (auth.uid() = user_id) from 003_recipes.sql.

alter table public.recipes
  add column if not exists share_in_family_book boolean not null default false;

comment on column public.recipes.share_in_family_book is
  'Owner opt-in for a URL recipe. Transcript recipes publish either way. RLS on recipes lets only that owner change the flag.';

alter table public.recipe_book_cards
  add column if not exists source_url text;

comment on column public.recipe_book_cards.source_url is
  'Public source link for an opted-in URL recipe. Null for transcript cards. Never a copy of a spoken transcript.';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'recipe_book_cards_source_url_http_check'
      and conrelid = 'public.recipe_book_cards'::regclass
  ) then
    alter table public.recipe_book_cards
      add constraint recipe_book_cards_source_url_http_check
      check (
        source_url is null
        or source_url ~* '^https?://[^[:space:]]+$'
      );
  end if;
end $$;

-- Reassert owner-only writes. The flag is a column on recipes, so this policy
-- is what stops another cook from opting a recipe in.
drop policy if exists "owner" on public.recipes;
create policy "owner" on public.recipes
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

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
  source_link text;
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

  -- Transcripts always publish. URL extracts publish only when the owner opts in.
  -- Any other shape drops a stale card owned by this recipe and leaves the row.
  if not (
    new.source_kind = 'transcript'
    or (new.source_kind = 'url' and new.share_in_family_book)
  ) then
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

  -- Publish the link only. Spoken or pasted words in raw_transcript stay off the card.
  source_link := null;
  if new.source_kind = 'url'
     and btrim(coalesce(new.raw_transcript, '')) ~* '^https?://[^[:space:]]+$' then
    source_link := btrim(new.raw_transcript);
  end if;

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
    source_url,
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
    source_link,
    -- A link is new to the book on the day the owner adds it, not the day they saved it.
    case
      when new.source_kind = 'url' then now()
      else coalesce(new.created_at, now())
    end,
    new.updated_at
  )
  on conflict (id) do update set
    title = excluded.title,
    attribution = excluded.attribution,
    steps = excluded.steps,
    ingredient_phrases = excluded.ingredient_phrases,
    added_by_label = excluded.added_by_label,
    source_url = excluded.source_url,
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
