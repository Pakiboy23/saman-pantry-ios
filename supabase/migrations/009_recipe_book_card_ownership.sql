-- Harden existing installations that have already applied 008_recipe_book.sql.
-- The owner applies this migration; no card data or write policies are changed.

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

