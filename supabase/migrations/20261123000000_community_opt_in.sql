-- Community is opt-in for every recipe (Samaan Pantry, before Product Hunt).
-- Applies after 012_recipe_book_url_opt_in.sql and 20261024010000_family_books_followup.sql.
--
-- 1. A recipe gets a card in recipe_book_cards only when the owner sets
--    recipes.share_in_family_book. Spoken, uploaded, and pasted recipes
--    (source_kind = 'transcript') no longer publish on save. Clearing the flag
--    removes the card and keeps the recipe.
-- 2. Existing transcript cards stay: their recipes get share_in_family_book = true
--    so the trigger keeps them. updated_at moves forward so the next pull carries
--    the flag to the phone instead of the phone pushing its old false back.
-- 3. Card labels use family_label_for(): display name, then the part of the email
--    before @, then 'A cook'. set_my_display_name also refreshes Community labels.
--
-- Apply this with the app build that has the Share to Community toggle. Older
-- builds still save new recordings with the flag false, so those stay private
-- even though the old app says they are in the book.

comment on column public.recipes.share_in_family_book is
  'Owner opt-in to the public Community book, for every source kind. False keeps the recipe private. RLS on recipes lets only that owner change the flag.';

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
  card_ingredients jsonb := '[]'::jsonb;
  label text;
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

  -- Only an owner opt-in publishes. Anything else drops a stale card and keeps the row.
  if not (
    new.source_kind in ('transcript', 'url')
    and new.share_in_family_book
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

  -- JSON null and objects are not SQL null, so coalesce will not replace them.
  card_ingredients := coalesce(parsed -> 'ingredients', '[]'::jsonb);
  if jsonb_typeof(card_ingredients) <> 'array' then
    card_ingredients := '[]'::jsonb;
  end if;

  select coalesce(
    jsonb_agg(coalesce(elem ->> 'original_phrase', elem ->> 'ingredient', '')),
    '[]'::jsonb
  )
  into card_phrases
  from jsonb_array_elements(card_ingredients) as elem;

  -- Publish the link only. Spoken or pasted words in raw_transcript stay off the card.
  source_link := null;
  if new.source_kind = 'url'
     and btrim(coalesce(new.raw_transcript, '')) ~* '^https?://[^[:space:]]+$' then
    source_link := btrim(new.raw_transcript);
  end if;

  label := public.family_label_for(new.user_id);

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
    -- A recipe is new to Community on the day the owner shares it.
    now(),
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

-- Keep the cards that are already public. The trigger rebuilds each one in place,
-- so notes stay attached, and its label switches to family_label_for().
update public.recipes r
set share_in_family_book = true,
    updated_at = now()
where r.source_kind = 'transcript'
  and not r.share_in_family_book
  and exists (
    select 1 from public.recipe_book_cards c
    where c.id = r.id and c.owner_id = r.user_id
  );

-- Opted-in link cards and orphan cards pick up the new label too.
update public.recipe_book_cards c
set added_by_label = public.family_label_for(c.owner_id)
where c.added_by_label is distinct from public.family_label_for(c.owner_id);

-- A display name change now reaches Community cards as well as family books.
create or replace function public.set_my_display_name(p_name text)
returns text language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); v text := nullif(btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g')), ''); lbl text;
begin
  if uid is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if v is not null and char_length(v) > 40 then
    raise exception 'Name is too long' using errcode = 'P0001', hint = 'name_too_long';
  end if;
  perform public.ensure_user_account(uid);
  update public.user_accounts set display_name = v where id = uid;
  lbl := public.family_label_for(uid);
  update public.family_members set display_label = lbl where user_id = uid and display_label <> lbl;
  update public.family_recipes set added_by_label = lbl where added_by = uid and added_by_label <> lbl;
  update public.recipe_book_cards set added_by_label = lbl where owner_id = uid and added_by_label <> lbl;
  return lbl;
end;
$$;

revoke all on function public.set_my_display_name(text) from public, anon;
grant execute on function public.set_my_display_name(text) to authenticated;
