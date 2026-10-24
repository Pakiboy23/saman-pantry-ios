-- Run after family_books_setup.sql, only in a disposable database.
\set ON_ERROR_STOP on
begin;
insert into auth.users (id, email, created_at) values
  ('00000000-0000-0000-0000-0000000000a1', 'pro@example.test', now()),
  ('00000000-0000-0000-0000-0000000000a2', 'member@example.test', now()),
  ('00000000-0000-0000-0000-0000000000a3', 'outsider@example.test', now()),
  ('00000000-0000-0000-0000-0000000000a4', 'oldtimer@example.test', '2026-01-01');
update public.user_accounts set is_pro = true where id = '00000000-0000-0000-0000-0000000000a1';
update public.user_accounts set grandfathered = true where id = '00000000-0000-0000-0000-0000000000a4';

set local role authenticated;

-- A user can't grant themselves Pro.
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a3';
do $$ begin
  begin
    update public.user_accounts set is_pro = true where id = auth.uid();
    raise exception 'self-grant of is_pro was accepted';
  exception when insufficient_privilege then null; end;
  -- Free users can't create a family.
  begin
    perform public.create_family('Nope');
    raise exception 'free user created a family';
  exception when raise_exception then
    if sqlerrm <> 'Samaan Pro required' then raise; end if;
  end;
end $$;

-- Grandfathered accounts can create families (decision 3).
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a4';
do $$ begin perform public.create_family('Old family'); end $$;

-- Pro owner creates a family and a private transcript recipe.
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a1';
create temp table ctx (k text primary key, v text) on commit drop;
grant all on ctx to authenticated;
do $$
declare fam public.families; inv jsonb; i int;
begin
  fam := public.create_family('Khan family');
  insert into ctx values ('fam', fam.id::text);
  insert into public.recipes (id, user_id, title, raw_transcript, extracted_json)
  values ('20000000-0000-0000-0000-000000000001', auth.uid(), 'Aloo keema',
          'SECRET spoken words', '{"steps":["Fry onions"],"ingredients":[{"original_phrase":"andaza namak"}]}');
  perform public.add_recipe_to_family(fam.id, '20000000-0000-0000-0000-000000000001');
  inv := public.create_family_invite(fam.id);
  insert into ctx values ('code', inv ->> 'code'), ('token', inv ->> 'token');
  -- Owner limit is 5 families.
  for i in 2..5 loop perform public.create_family('Family ' || i); end loop;
  begin
    perform public.create_family('Sixth');
    raise exception 'sixth family accepted';
  exception when raise_exception then
    if sqlerrm <> 'Family limit reached' then raise; end if;
  end;
end $$;

-- Outsider can't see the family, its recipes, or invites; bad codes fail.
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a3';
do $$ begin
  assert not exists (select 1 from public.families where name = 'Khan family'), 'outsider sees family';
  assert not exists (select 1 from public.family_recipes), 'outsider sees family recipes';
  assert public.redeem_family_invite('ZZZZZZZZ') is null, 'bad code joined';
  begin
    perform public.add_recipe_to_family((select v::uuid from ctx where k = 'fam'), gen_random_uuid());
    raise exception 'outsider added to family';
  exception when insufficient_privilege then null; end;
end $$;

-- Member joins by link token, sees the snapshot without the transcript, and can invite (decision 4).
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a2';
do $$
declare fid uuid := (select v::uuid from ctx where k = 'fam');
begin
  assert public.redeem_family_invite((select v from ctx where k = 'token')) = fid;
  assert public.redeem_family_invite((select v from ctx where k = 'code')) = fid, 'rejoin is a no-op';
  assert (select count(*) from public.family_recipes where family_id = fid) = 1;
  assert not exists (select 1 from public.family_recipes
                     where to_jsonb(family_recipes)::text like '%SECRET%'), 'transcript leaked';
  assert not exists (select 1 from public.recipes), 'member reads owner recipes row';
  assert (public.create_family_invite(fid) ->> 'code') is not null, 'member could not invite';
  insert into public.family_recipe_notes (family_id, recipe_id, author_id, body)
  values (fid, '20000000-0000-0000-0000-000000000001', auth.uid(), 'Ammi adds more chilli');
  insert into public.recipes (id, user_id, title) values
    ('20000000-0000-0000-0000-000000000002', auth.uid(), 'Gajar halwa');
  perform public.add_recipe_to_family(fid, '20000000-0000-0000-0000-000000000002');
  -- Members can't remove others.
  begin
    perform public.remove_family_member(fid, '00000000-0000-0000-0000-0000000000a1');
    raise exception 'member removed the owner';
  exception when raise_exception then
    if sqlerrm not like 'Transfer ownership%' then raise; end if;
  end;
end $$;

-- Owner edits the recipe: snapshot follows. Owner removes the member: their recipe stays (decision 5).
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a1';
do $$
declare fid uuid := (select v::uuid from ctx where k = 'fam');
begin
  update public.recipes set title = 'Aloo keema (Sunday)' where id = '20000000-0000-0000-0000-000000000001';
  assert exists (select 1 from public.family_recipes where title = 'Aloo keema (Sunday)');
  perform public.remove_family_member(fid, '00000000-0000-0000-0000-0000000000a2');
  assert exists (select 1 from public.family_recipes where title = 'Gajar halwa'), 'removed member recipe vanished';
  -- Pro lapses: the family keeps working (decision 2).
end $$;
reset role;
-- Explicit recipe delete removes the snapshot. Account deletion keeps it.
do $$ begin
  delete from public.recipes where id = '20000000-0000-0000-0000-000000000001';
  assert not exists (select 1 from public.family_recipes
    where recipe_id = '20000000-0000-0000-0000-000000000001'),
    'explicit recipe delete left the family snapshot';
  delete from auth.users where id = '00000000-0000-0000-0000-0000000000a2';
  assert exists (select 1 from public.family_recipes
    where recipe_id = '20000000-0000-0000-0000-000000000002' and added_by is null),
    'account delete dropped the family snapshot';
end $$;
update public.user_accounts set is_pro = false where id = '00000000-0000-0000-0000-0000000000a1';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a1';
do $$
declare fid uuid := (select v::uuid from ctx where k = 'fam');
begin
  assert exists (select 1 from public.families where id = fid), 'family froze on lapse';
  assert (public.create_family_invite(fid) ->> 'code') is not null, 'invites froze on lapse';
  perform public.delete_family(fid);
  assert not exists (select 1 from public.families where id = fid);
end $$;
rollback;
\echo family_books_security: ok
