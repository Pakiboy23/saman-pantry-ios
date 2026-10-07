-- Run after recipe_book_security_setup.sql, only in a disposable database.
\set ON_ERROR_STOP on
begin;
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'owner@example.test'),
  ('00000000-0000-0000-0000-000000000002', 'attacker@example.test');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
-- The victim creates a card with no backing recipe through the allowed policy.
insert into public.recipe_book_cards (id, owner_id, title, added_by_label)
values ('10000000-0000-0000-0000-000000000001', auth.uid(), 'Victim card', 'owner');
insert into public.recipe_book_notes (card_id, author_id, body)
values ('10000000-0000-0000-0000-000000000001', auth.uid(), 'Keep this note');

set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
do $$
declare kind text;
begin
  -- Public reads expose the target ID; direct writes are already blocked by RLS.
  assert exists (select 1 from public.recipe_book_cards where title = 'Victim card');
  update public.recipe_book_cards set title = 'Direct attack';
  assert not found, 'Direct cross-owner update must be denied by RLS';
  delete from public.recipe_book_cards;
  assert not found, 'Direct cross-owner delete must be denied by RLS';

  foreach kind in array array['url', 'transcript'] loop
    begin
      insert into public.recipes (id, user_id, title, source_kind)
      values ('10000000-0000-0000-0000-000000000001', auth.uid(), 'Attack', kind);
      raise exception 'Cross-owner % collision was accepted', kind;
    exception when insufficient_privilege then null;
    end;
    assert not exists (select 1 from public.recipes), 'Failed insert must roll back';
    assert exists (select 1 from public.recipe_book_cards
      where title = 'Victim card' and owner_id = '00000000-0000-0000-0000-000000000001');
    assert exists (select 1 from public.recipe_book_notes where body = 'Keep this note');
  end loop;
end $$;

-- An existing private recipe can also collide with a subsequently created card.
insert into public.recipes (id, user_id, title, source_kind)
values ('10000000-0000-0000-0000-000000000002', auth.uid(), 'Private recipe', 'url');
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
insert into public.recipe_book_cards (id, owner_id, title, added_by_label)
values ('10000000-0000-0000-0000-000000000002', auth.uid(), 'Second victim card', 'owner');
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
do $$
declare kind text;
begin
  foreach kind in array array['url', 'transcript'] loop
    begin
      update public.recipes set source_kind = kind;
      raise exception 'Cross-owner % update was accepted', kind;
    exception when insufficient_privilege then null;
    end;
  end loop;
  begin
    delete from public.recipes;
    raise exception 'Cross-owner delete was accepted';
  exception when insufficient_privilege then null;
  end;
  assert (select count(*) = 2 from public.recipe_book_cards), 'Victim cards must survive';
  assert exists (select 1 from public.recipes where source_kind = 'url'), 'Recipe deletion must roll back';
end $$;

-- Normal publication, same-owner conflict update, privacy flip and deletion.
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
insert into public.recipes (id, user_id, title, raw_transcript, extracted_json)
values ('10000000-0000-0000-0000-000000000003', auth.uid(), 'Karahi', 'Private words',
  '{"steps":["Cook"],"ingredients":[{"original_phrase":"haldi andaza se"}]}');
update public.recipes set title = 'Updated Karahi'
where id = '10000000-0000-0000-0000-000000000003';
do $$
begin
  assert exists (select 1 from public.recipe_book_cards
    where title = 'Updated Karahi' and owner_id = auth.uid()
      and steps = '["Cook"]'::jsonb and ingredient_phrases = '["haldi andaza se"]'::jsonb);
  assert not exists (select 1 from public.recipe_book_cards c where to_jsonb(c)::text like '%Private words%');
end $$;
update public.recipes set source_kind = 'url'
where id = '10000000-0000-0000-0000-000000000003';
do $$ begin
  assert not exists (select 1 from public.recipe_book_cards where id = '10000000-0000-0000-0000-000000000003');
end $$;
update public.recipes set source_kind = 'transcript'
where id = '10000000-0000-0000-0000-000000000003';
insert into public.recipe_book_notes (card_id, author_id, body)
values ('10000000-0000-0000-0000-000000000003', auth.uid(), 'Remove with card');
delete from public.recipes where id = '10000000-0000-0000-0000-000000000003';
do $$ begin
  assert not exists (select 1 from public.recipe_book_cards where id = '10000000-0000-0000-0000-000000000003');
  assert not exists (select 1 from public.recipe_book_notes where body = 'Remove with card');
  assert exists (select 1 from public.recipe_book_notes where body = 'Keep this note');
  assert not has_function_privilege('authenticated', 'public.sync_recipe_book_card()', 'execute');
end $$;
rollback;
