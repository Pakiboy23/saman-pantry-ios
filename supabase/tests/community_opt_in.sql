-- Run only in a disposable database that already has 003, 008, 011, 012 and both
-- family-books migrations applied (see family_books_setup.sql for the order).
-- Applies 20261123000000_community_opt_in.sql inside this transaction, then rolls back.
\set ON_ERROR_STOP on
begin;

insert into auth.users (id, email) values
  ('30000000-0000-0000-0000-000000000001', 'ammi.cook@example.test'),
  ('30000000-0000-0000-0000-000000000002', 'named.cook@example.test');

-- Before the migration: a transcript publishes on its own (012 behavior).
insert into public.recipes (
  id, user_id, title, raw_transcript, extracted_json, attribution, source_kind,
  created_at, updated_at
) values (
  '30000000-0000-0000-0000-000000000010',
  '30000000-0000-0000-0000-000000000001',
  'Karahi',
  'Private words from ammi',
  '{"steps":["Cook"],"ingredients":[{"original_phrase":"haldi andaza se"}]}',
  'Ammi',
  'transcript',
  timestamptz '2020-01-01',
  timestamptz '2020-01-01'
);

insert into public.recipe_book_notes (card_id, author_id, body) values (
  '30000000-0000-0000-0000-000000000010',
  '30000000-0000-0000-0000-000000000002',
  'Less oil next time'
);

do $$
begin
  assert exists (
    select 1 from public.recipe_book_cards
    where id = '30000000-0000-0000-0000-000000000010'
      and added_by_label = 'ammi.cook'
  ), 'Precondition: 012 publishes a transcript with the email label';
end $$;

\ir ../migrations/20261123000000_community_opt_in.sql

-- 1. The existing card stays, with its note, and its recipe now carries the flag.
do $$
begin
  assert exists (
    select 1 from public.recipe_book_cards
    where id = '30000000-0000-0000-0000-000000000010' and title = 'Karahi'
  ), 'Migration must keep an existing transcript card';
  assert (
    select share_in_family_book from public.recipes
    where id = '30000000-0000-0000-0000-000000000010'
  ), 'Backfill sets the flag on recipes that already had a card';
  assert (
    select updated_at from public.recipes
    where id = '30000000-0000-0000-0000-000000000010'
  ) > timestamptz '2020-01-01', 'Backfill moves updated_at so phones pull the flag';
  assert exists (
    select 1 from public.recipe_book_notes
    where card_id = '30000000-0000-0000-0000-000000000010'
  ), 'Backfill must not drop notes';
end $$;

-- 2. A new recording saves private.
insert into public.recipes (id, user_id, title, raw_transcript, source_kind)
values (
  '30000000-0000-0000-0000-000000000011',
  '30000000-0000-0000-0000-000000000001',
  'Aloo keema',
  'Spoken words',
  'transcript'
);

do $$
begin
  assert not exists (
    select 1 from public.recipe_book_cards
    where id = '30000000-0000-0000-0000-000000000011'
  ), 'A new transcript must stay private without the flag';
end $$;

-- 3. Sharing it publishes the card, without the spoken words.
update public.recipes set share_in_family_book = true, updated_at = now()
where id = '30000000-0000-0000-0000-000000000011';

do $$
begin
  assert exists (
    select 1 from public.recipe_book_cards
    where id = '30000000-0000-0000-0000-000000000011'
      and source_url is null
  ), 'Opt-in publishes a transcript card';
  assert not exists (
    select 1 from public.recipe_book_cards c
    where to_jsonb(c)::text like '%Spoken words%'
  ), 'raw_transcript must not reach a card';
end $$;

-- 4. Unsharing removes the card and keeps the recipe.
update public.recipes set share_in_family_book = false
where id = '30000000-0000-0000-0000-000000000011';

do $$
begin
  assert not exists (
    select 1 from public.recipe_book_cards
    where id = '30000000-0000-0000-0000-000000000011'
  ), 'Clearing the flag removes a transcript card';
  assert exists (
    select 1 from public.recipes
    where id = '30000000-0000-0000-0000-000000000011'
  ), 'Clearing the flag keeps the recipe';
end $$;

-- 5. Labels use the display name when one is set.
select public.ensure_user_account('30000000-0000-0000-0000-000000000002');
update public.user_accounts set display_name = 'Nani'
where id = '30000000-0000-0000-0000-000000000002';

insert into public.recipes (id, user_id, title, raw_transcript, source_kind, share_in_family_book)
values (
  '30000000-0000-0000-0000-000000000012',
  '30000000-0000-0000-0000-000000000002',
  'Nani''s daal',
  'Spoken words',
  'transcript',
  true
);

do $$
begin
  assert (
    select added_by_label from public.recipe_book_cards
    where id = '30000000-0000-0000-0000-000000000012'
  ) = 'Nani', 'Card label uses the display name';
end $$;

-- 6. Changing the display name updates Community cards.
set local role authenticated;
select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000002', true);
select public.set_my_display_name('Nani Jaan');
reset role;

do $$
begin
  assert (
    select added_by_label from public.recipe_book_cards
    where id = '30000000-0000-0000-0000-000000000012'
  ) = 'Nani Jaan', 'set_my_display_name refreshes Community labels';
end $$;

-- 7. A link recipe still needs the flag, and still shows its source link.
insert into public.recipes (id, user_id, title, raw_transcript, source_kind, share_in_family_book)
values
  ('30000000-0000-0000-0000-000000000013', '30000000-0000-0000-0000-000000000001',
   'Private link', 'https://example.com/a', 'url', false),
  ('30000000-0000-0000-0000-000000000014', '30000000-0000-0000-0000-000000000001',
   'Shared link', 'https://example.com/b', 'url', true);

do $$
begin
  assert not exists (
    select 1 from public.recipe_book_cards
    where id = '30000000-0000-0000-0000-000000000013'
  ), 'A link stays private without the flag';
  assert exists (
    select 1 from public.recipe_book_cards
    where id = '30000000-0000-0000-0000-000000000014'
      and source_url = 'https://example.com/b'
  ), 'A shared link keeps its source link';
end $$;

-- 8. Another owner's recipe cannot take over a card by reusing its ID.
-- Cards may exist without recipes, so start from an orphan card.
insert into public.recipe_book_cards (id, owner_id, title, added_by_label)
values ('30000000-0000-0000-0000-000000000020', '30000000-0000-0000-0000-000000000002',
        'Victim card', 'Nani Jaan');

do $$
begin
  begin
    insert into public.recipes (id, user_id, title, raw_transcript, source_kind, share_in_family_book)
    values ('30000000-0000-0000-0000-000000000020', '30000000-0000-0000-0000-000000000001',
            'Hijack', 'x', 'transcript', true);
    raise exception 'Cross-owner card collision was accepted';
  exception when insufficient_privilege then null;
  end;
  assert (
    select title from public.recipe_book_cards
    where id = '30000000-0000-0000-0000-000000000020'
  ) = 'Victim card', 'Victim card must survive';
end $$;

rollback;
