-- Run after recipe_book_security_setup.sql, only in a disposable database.
-- Applies 012 inside this transaction, then rolls everything back.
\set ON_ERROR_STOP on
begin;

insert into auth.users (id, email) values
  ('20000000-0000-0000-0000-000000000001', 'owner@example.test'),
  ('20000000-0000-0000-0000-000000000002', 'attacker@example.test');

-- Cards created by the 008 trigger must still be there after 012.
insert into public.recipes (
  id, user_id, title, raw_transcript, extracted_json, attribution, source_kind, created_at
) values (
  '20000000-0000-0000-0000-000000000010',
  '20000000-0000-0000-0000-000000000001',
  'Karahi',
  'Private words from ammi',
  '{"steps":["Cook"],"ingredients":[{"original_phrase":"haldi andaza se"}]}',
  'Ammi',
  'transcript',
  timestamptz '2020-01-01'
);

insert into public.recipes (
  id, user_id, title, raw_transcript, attribution, source_kind, created_at
) values (
  '20000000-0000-0000-0000-000000000011',
  '20000000-0000-0000-0000-000000000001',
  'YouTube Karahi',
  'https://www.youtube.com/watch?v=example',
  'youtube.com',
  'url',
  timestamptz '2020-01-02'
);

do $$
begin
  assert exists (
    select 1 from public.recipe_book_cards
    where id = '20000000-0000-0000-0000-000000000010'
  ), 'Transcript card must exist before 012';
  assert not exists (
    select 1 from public.recipe_book_cards
    where id = '20000000-0000-0000-0000-000000000011'
  ), 'URL recipe must stay private before opt-in';
end $$;

\ir ../migrations/012_recipe_book_url_opt_in.sql

do $$
begin
  assert exists (
    select 1 from public.recipe_book_cards
    where id = '20000000-0000-0000-0000-000000000010'
      and title = 'Karahi'
  ), '012 must not drop an existing transcript card';
  assert not exists (
    select 1 from public.recipe_book_cards
    where id = '20000000-0000-0000-0000-000000000011'
  ), '012 must not publish existing URL recipes';
  assert (
    select share_in_family_book from public.recipes
    where id = '20000000-0000-0000-0000-000000000011'
  ) = false, 'URL recipes default to private';
  assert exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'recipes'
      and policyname = 'owner'
      and qual like '%auth.uid()%'
      and qual like '%user_id%'
      and with_check like '%auth.uid()%'
      and with_check like '%user_id%'
  ), 'Only the recipe owner can update the flag';
  assert not has_function_privilege(
    'authenticated', 'public.sync_recipe_book_card()', 'execute'
  );
end $$;

set local role authenticated;
set local request.jwt.claim.sub = '20000000-0000-0000-0000-000000000002';

do $$
begin
  update public.recipes
  set share_in_family_book = true
  where id = '20000000-0000-0000-0000-000000000011';
  assert not found, 'Another cook cannot opt the recipe in';
  assert not exists (
    select 1 from public.recipe_book_cards
    where id = '20000000-0000-0000-0000-000000000011'
  ), 'Denied toggle must not publish a card';
end $$;

set local request.jwt.claim.sub = '20000000-0000-0000-0000-000000000001';

update public.recipes
set share_in_family_book = true
where id = '20000000-0000-0000-0000-000000000011';

do $$
begin
  assert (
    select count(*) from public.recipe_book_cards
    where id = '20000000-0000-0000-0000-000000000011'
  ) = 1, 'Opt-in publishes one card';
  assert exists (
    select 1 from public.recipe_book_cards
    where id = '20000000-0000-0000-0000-000000000011'
      and owner_id = '20000000-0000-0000-0000-000000000001'
      and title = 'YouTube Karahi'
      and attribution = 'youtube.com'
      and source_url = 'https://www.youtube.com/watch?v=example'
      and created_at > timestamptz '2020-01-02'
  ), 'Shared link card shows attribution and the source link, dated when it was added';
  assert not exists (
    select 1 from public.recipe_book_cards c
    where c.id = '20000000-0000-0000-0000-000000000010'
      and (
        to_jsonb(c) ? 'raw_transcript'
        or coalesce(c.source_url, '') <> ''
        or to_jsonb(c)::text like '%Private words%'
      )
  ), 'Transcript cards still hide raw_transcript';
end $$;

-- Saying yes again does not duplicate the card or move its place in the book.
update public.recipes
set title = 'YouTube Karahi again', share_in_family_book = true
where id = '20000000-0000-0000-0000-000000000011';

do $$
declare
  first_created timestamptz;
  second_created timestamptz;
begin
  select created_at into first_created from public.recipe_book_cards
  where id = '20000000-0000-0000-0000-000000000011';
  update public.recipes
  set share_in_family_book = true
  where id = '20000000-0000-0000-0000-000000000011';
  select created_at into second_created from public.recipe_book_cards
  where id = '20000000-0000-0000-0000-000000000011';
  assert first_created = second_created, 'Repeat opt-in keeps the same card';
  assert (
    select count(*) from public.recipe_book_cards
    where id = '20000000-0000-0000-0000-000000000011'
  ) = 1;
  assert (
    select title from public.recipe_book_cards
    where id = '20000000-0000-0000-0000-000000000011'
  ) = 'YouTube Karahi again';
end $$;

insert into public.recipe_book_notes (card_id, author_id, body)
values (
  '20000000-0000-0000-0000-000000000011',
  '20000000-0000-0000-0000-000000000001',
  'Less oil next time'
);

update public.recipes
set share_in_family_book = false
where id = '20000000-0000-0000-0000-000000000011';

do $$
begin
  assert exists (
    select 1 from public.recipes
    where id = '20000000-0000-0000-0000-000000000011'
      and title = 'YouTube Karahi again'
      and share_in_family_book = false
  ), 'Removing the card leaves the recipe';
  assert not exists (
    select 1 from public.recipe_book_cards
    where id = '20000000-0000-0000-0000-000000000011'
  ), 'The card leaves the family book';
  assert not exists (
    select 1 from public.recipe_book_notes where body = 'Less oil next time'
  ), 'Notes go with the card';
end $$;

-- A transcript stays in the book even when the flag is false.
update public.recipes
set share_in_family_book = false
where id = '20000000-0000-0000-0000-000000000010';

do $$
begin
  assert exists (
    select 1 from public.recipe_book_cards
    where id = '20000000-0000-0000-0000-000000000010'
      and source_url is null
  ), 'Transcript publish does not depend on the flag';
end $$;

-- Opt in a link whose raw text is not an http(s) URL. Share the recipe, not the text.
insert into public.recipes (
  id, user_id, title, raw_transcript, source_kind, share_in_family_book
) values (
  '20000000-0000-0000-0000-000000000012',
  '20000000-0000-0000-0000-000000000001',
  'Messy link',
  'notes that are not a link',
  'url',
  true
);

do $$
begin
  assert exists (
    select 1 from public.recipe_book_cards
    where id = '20000000-0000-0000-0000-000000000012'
      and source_url is null
  ), 'Non-URL text is not published as a source link';
  assert not exists (
    select 1 from public.recipe_book_cards c
    where to_jsonb(c)::text like '%notes that are not a link%'
  ), 'raw_transcript must not leak onto a link card';
end $$;

-- Opting in again after a removal publishes a fresh card, without the old note.
update public.recipes
set share_in_family_book = true
where id = '20000000-0000-0000-0000-000000000011';

do $$
begin
  assert exists (
    select 1 from public.recipe_book_cards
    where id = '20000000-0000-0000-0000-000000000011'
      and source_url = 'https://www.youtube.com/watch?v=example'
  ), 'The owner can add the same link recipe again';
  assert not exists (
    select 1 from public.recipe_book_notes where body = 'Less oil next time'
  ), 'A new card does not bring the old note back';
end $$;

-- An opt-in cannot take over a card that already belongs to someone else.
set local request.jwt.claim.sub = '20000000-0000-0000-0000-000000000002';
insert into public.recipes (id, user_id, title, source_kind)
values (
  '20000000-0000-0000-0000-000000000013',
  '20000000-0000-0000-0000-000000000002',
  'Collision',
  'url'
);
set local request.jwt.claim.sub = '20000000-0000-0000-0000-000000000001';
insert into public.recipe_book_cards (id, owner_id, title, added_by_label)
values (
  '20000000-0000-0000-0000-000000000013',
  '20000000-0000-0000-0000-000000000001',
  'Victim link card',
  'owner'
);
set local request.jwt.claim.sub = '20000000-0000-0000-0000-000000000002';

do $$
begin
  begin
    update public.recipes
    set share_in_family_book = true
    where id = '20000000-0000-0000-0000-000000000013';
    raise exception 'Cross-owner opt-in was accepted';
  exception when insufficient_privilege then
    null;
  end;
  assert exists (
    select 1 from public.recipe_book_cards
    where id = '20000000-0000-0000-0000-000000000013'
      and owner_id = '20000000-0000-0000-0000-000000000001'
      and title = 'Victim link card'
  ), 'Victim card must survive a colliding opt-in';
  assert (
    select share_in_family_book from public.recipes
    where id = '20000000-0000-0000-0000-000000000013'
  ) = false, 'Rejected opt-in must not stick';
end $$;

-- Opt-in must publish when ingredients is JSON null or an object, not only an array.
set local request.jwt.claim.sub = '20000000-0000-0000-0000-000000000001';
insert into public.recipes (
  id, user_id, title, raw_transcript, extracted_json, source_kind, share_in_family_book
) values
(
  '20000000-0000-0000-0000-000000000014',
  '20000000-0000-0000-0000-000000000001',
  'Null ingredients',
  'https://example.com/null-ingredients',
  '{"ingredients":null,"steps":["Cook"]}',
  'url',
  true
),
(
  '20000000-0000-0000-0000-000000000015',
  '20000000-0000-0000-0000-000000000001',
  'Object ingredients',
  'https://example.com/object-ingredients',
  '{"ingredients":{"haldi":"andaza"},"steps":["Cook"]}',
  'url',
  true
);

do $$
begin
  assert exists (
    select 1 from public.recipe_book_cards
    where id = '20000000-0000-0000-0000-000000000014'
      and ingredient_phrases = '[]'::jsonb
      and steps = '["Cook"]'::jsonb
  ), 'JSON null ingredients must still publish the card';
  assert exists (
    select 1 from public.recipe_book_cards
    where id = '20000000-0000-0000-0000-000000000015'
      and ingredient_phrases = '[]'::jsonb
      and steps = '["Cook"]'::jsonb
  ), 'Object ingredients must still publish the card';
  assert (
    select share_in_family_book from public.recipes
    where id = '20000000-0000-0000-0000-000000000014'
  ) = true, 'A non-array ingredients value must not roll back the opt-in';
end $$;

rollback;
