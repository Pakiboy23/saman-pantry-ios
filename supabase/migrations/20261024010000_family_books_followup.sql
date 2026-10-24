-- Family books follow-up (Samaan Pantry 1.6). Applies after 20261024000000_family_books.sql.
-- 1. Display names: user_accounts.display_name, set by the user through set_my_display_name.
--    Member labels fall back to the part of the email before @, then 'A cook'.
-- 2. Security advisor: is_family_member and is_family_owner move to a private schema
--    that PostgREST doesn't expose, so clients can't probe family IDs through the API.
-- 3. Performance advisor: FK indexes, a primary key on family_invite_attempts,
--    and (select auth.uid()) in policies.

-- 1. Display name ------------------------------------------------------------
alter table public.user_accounts
  add column if not exists display_name text;
alter table public.user_accounts drop constraint if exists user_accounts_display_name_check;
alter table public.user_accounts add constraint user_accounts_display_name_check
  check (display_name is null
         or (display_name = btrim(display_name) and char_length(display_name) between 1 and 40));

create or replace function public.family_label_for(uid uuid)
returns text language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select nullif(btrim(ua.display_name), '') from public.user_accounts ua where ua.id = uid),
    (select nullif(split_part(coalesce(au.email, ''), '@', 1), '') from auth.users au where au.id = uid),
    'A cook');
$$;

-- Sets (or clears, with null or blank) the caller's name and refreshes their labels
-- in every family. Returns the label members now see.
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
  return lbl;
end;
$$;

-- 2. Private helpers -----------------------------------------------------------
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create or replace function private.is_family_member(fid uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.family_members m
                 where m.family_id = fid and m.user_id = (select auth.uid()));
$$;

create or replace function private.is_family_owner(fid uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.family_members m
                 where m.family_id = fid and m.user_id = (select auth.uid()) and m.role = 'owner');
$$;

-- Policies run as the caller, so authenticated keeps EXECUTE here. The private
-- schema isn't in the API's exposed schemas, so there is no /rpc route to them.
revoke all on function private.is_family_member(uuid), private.is_family_owner(uuid) from public, anon;
grant execute on function private.is_family_member(uuid), private.is_family_owner(uuid) to authenticated;

drop policy if exists families_select_member on public.families;
create policy families_select_member on public.families
  for select to authenticated using (private.is_family_member(id));
drop policy if exists families_update_owner on public.families;
create policy families_update_owner on public.families
  for update to authenticated
  using (private.is_family_owner(id)) with check (private.is_family_owner(id));

drop policy if exists family_members_select on public.family_members;
create policy family_members_select on public.family_members
  for select to authenticated using (private.is_family_member(family_id));

drop policy if exists family_invites_select_member on public.family_invites;
create policy family_invites_select_member on public.family_invites
  for select to authenticated using (private.is_family_member(family_id));

drop policy if exists family_recipes_select on public.family_recipes;
create policy family_recipes_select on public.family_recipes
  for select to authenticated using (private.is_family_member(family_id));
drop policy if exists family_recipes_delete on public.family_recipes;
create policy family_recipes_delete on public.family_recipes
  for delete to authenticated
  using (private.is_family_member(family_id)
         and (added_by = (select auth.uid()) or private.is_family_owner(family_id)));

drop policy if exists family_recipe_notes_select on public.family_recipe_notes;
create policy family_recipe_notes_select on public.family_recipe_notes
  for select to authenticated using (private.is_family_member(family_id));
drop policy if exists family_recipe_notes_insert on public.family_recipe_notes;
create policy family_recipe_notes_insert on public.family_recipe_notes
  for insert to authenticated
  with check (author_id = (select auth.uid()) and private.is_family_member(family_id));
drop policy if exists family_recipe_notes_update on public.family_recipe_notes;
create policy family_recipe_notes_update on public.family_recipe_notes
  for update to authenticated
  using (author_id = (select auth.uid()))
  with check (author_id = (select auth.uid()) and private.is_family_member(family_id));
drop policy if exists family_recipe_notes_delete on public.family_recipe_notes;
create policy family_recipe_notes_delete on public.family_recipe_notes
  for delete to authenticated using (author_id = (select auth.uid()));

-- RPCs repointed at the private helpers (bodies otherwise unchanged).
create or replace function public.create_family_invite(p_family_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  new_code text; raw_token text; inv public.family_invites; i int; attempt int := 0;
begin
  if not private.is_family_member(p_family_id) then
    raise exception 'Not a member' using errcode = '42501';
  end if;
  if (select count(*) from public.family_invites fi
      where fi.family_id = p_family_id and fi.created_at > now() - interval '1 day') >= 20 then
    raise exception 'Invite limit reached' using errcode = 'P0001', hint = 'invite_rate';
  end if;
  loop
    attempt := attempt + 1;
    new_code := '';
    for i in 1..8 loop
      new_code := new_code || substr(alphabet,
        1 + (get_byte(extensions.gen_random_bytes(1), 0) % 32), 1);
    end loop;
    raw_token := encode(extensions.gen_random_bytes(32), 'hex');
    begin
      insert into public.family_invites (family_id, code, token_hash, created_by)
      values (p_family_id, new_code,
              encode(extensions.digest(raw_token, 'sha256'), 'hex'), auth.uid())
      returning * into inv;
      exit;
    exception when unique_violation then
      if attempt > 5 then raise; end if;
    end;
  end loop;
  return jsonb_build_object('id', inv.id, 'code', inv.code, 'token', raw_token,
                            'expires_at', inv.expires_at);
end;
$$;

create or replace function public.revoke_family_invite(p_invite_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.family_invites fi set revoked_at = now()
  where fi.id = p_invite_id and fi.revoked_at is null
    and (fi.created_by = auth.uid() or private.is_family_owner(fi.family_id));
  if not found then raise exception 'Invite not found' using errcode = '42501'; end if;
end;
$$;

create or replace function public.preview_family_invite(p_code_or_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); inv public.family_invites; fam public.families; v text;
begin
  if uid is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if (select count(*) from public.family_invite_attempts a
      where a.user_id = uid and a.attempted_at > now() - interval '1 hour' and not a.ok) >= 10 then
    raise exception 'Too many tries' using errcode = 'P0001', hint = 'rate_limited';
  end if;
  v := upper(btrim(coalesce(p_code_or_token, '')));
  select * into inv from public.family_invites fi
  where fi.code = v or fi.token_hash = encode(extensions.digest(lower(btrim(p_code_or_token)), 'sha256'), 'hex');
  if not found or inv.revoked_at is not null or inv.expires_at <= now() or inv.use_count >= inv.max_uses then
    insert into public.family_invite_attempts (user_id, ok) values (uid, false);
    return null;
  end if;
  select * into fam from public.families f where f.id = inv.family_id;
  return jsonb_build_object('family_id', fam.id, 'name', fam.name,
    'owner_label', public.family_label_for(fam.owner_id),
    'member_count', (select count(*) from public.family_members m where m.family_id = fam.id),
    'already_member', private.is_family_member(fam.id));
end;
$$;

create or replace function public.redeem_family_invite(p_code_or_token text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); inv public.family_invites; v text;
begin
  if uid is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if (select count(*) from public.family_invite_attempts a
      where a.user_id = uid and a.attempted_at > now() - interval '1 hour' and not a.ok) >= 10 then
    raise exception 'Too many tries' using errcode = 'P0001', hint = 'rate_limited';
  end if;
  v := upper(btrim(coalesce(p_code_or_token, '')));
  select * into inv from public.family_invites fi
  where fi.code = v or fi.token_hash = encode(extensions.digest(lower(btrim(p_code_or_token)), 'sha256'), 'hex')
  for update;
  if not found or inv.revoked_at is not null or inv.expires_at <= now() or inv.use_count >= inv.max_uses then
    -- Return null rather than raise, so the failed attempt row is kept for the rate limit.
    insert into public.family_invite_attempts (user_id, ok) values (uid, false);
    return null;
  end if;
  if private.is_family_member(inv.family_id) then
    return inv.family_id; -- already in: no-op success
  end if;
  perform 1 from public.families f where f.id = inv.family_id for update;
  if (select count(*) from public.family_members m where m.family_id = inv.family_id) >= 50 then
    raise exception 'Family is full' using errcode = 'P0001', hint = 'family_full';
  end if;
  if (select count(*) from public.family_members m where m.user_id = uid) >= 20 then
    raise exception 'Membership limit reached' using errcode = 'P0001', hint = 'membership_limit';
  end if;
  insert into public.family_members (family_id, user_id, role, display_label)
  values (inv.family_id, uid, 'member', public.family_label_for(uid));
  update public.family_invites set use_count = use_count + 1 where id = inv.id;
  insert into public.family_invite_attempts (user_id, ok) values (uid, true);
  return inv.family_id;
end;
$$;

create or replace function public.remove_family_member(p_family_id uuid, p_user_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare target_role text;
begin
  select m.role into target_role from public.family_members m
  where m.family_id = p_family_id and m.user_id = p_user_id;
  if not found then raise exception 'Not a member' using errcode = '42501'; end if;
  if target_role = 'owner' then
    raise exception 'Transfer ownership or delete the family first' using errcode = 'P0001', hint = 'owner_must_transfer';
  end if;
  if p_user_id <> auth.uid() and not private.is_family_owner(p_family_id) then
    raise exception 'Only the owner can remove members' using errcode = '42501';
  end if;
  delete from public.family_members m where m.family_id = p_family_id and m.user_id = p_user_id;
end;
$$;

create or replace function public.transfer_family_ownership(p_family_id uuid, p_new_owner uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_family_owner(p_family_id) then
    raise exception 'Only the owner can transfer' using errcode = '42501';
  end if;
  if not exists (select 1 from public.family_members m
                 where m.family_id = p_family_id and m.user_id = p_new_owner) then
    raise exception 'New owner must be a member' using errcode = 'P0001';
  end if;
  update public.family_members set role = 'member'
  where family_id = p_family_id and user_id = auth.uid();
  update public.family_members set role = 'owner'
  where family_id = p_family_id and user_id = p_new_owner;
  update public.families set owner_id = p_new_owner where id = p_family_id;
end;
$$;

create or replace function public.delete_family(p_family_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_family_owner(p_family_id) then
    raise exception 'Only the owner can delete the family' using errcode = '42501';
  end if;
  delete from public.families where id = p_family_id;
end;
$$;

create or replace function public.add_recipe_to_family(p_family_id uuid, p_recipe_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); r public.recipes; s jsonb;
begin
  if not private.is_family_member(p_family_id) then
    raise exception 'Not a member' using errcode = '42501';
  end if;
  select * into r from public.recipes x where x.id = p_recipe_id and x.user_id = uid;
  if not found then raise exception 'Recipe not found' using errcode = '42501'; end if;
  s := public.family_recipe_snapshot(r);
  insert into public.family_recipes as fr (family_id, recipe_id, added_by, added_by_label,
    title, attribution, steps, ingredient_phrases, source_url)
  values (p_family_id, r.id, uid, public.family_label_for(uid), s ->> 'title', s ->> 'attribution',
    s -> 'steps', s -> 'ingredient_phrases', s ->> 'source_url')
  on conflict (family_id, recipe_id) do update set
    title = excluded.title, attribution = excluded.attribution, steps = excluded.steps,
    ingredient_phrases = excluded.ingredient_phrases, source_url = excluded.source_url,
    updated_at = now()
  where fr.added_by = uid;
end;
$$;

create or replace function public.list_family_invites(p_family_id uuid)
returns table (id uuid, code text, expires_at timestamptz, use_count int, max_uses int)
language sql stable security definer set search_path = '' as $$
  select fi.id, fi.code, fi.expires_at, fi.use_count, fi.max_uses
  from public.family_invites fi
  where fi.family_id = p_family_id and private.is_family_member(p_family_id)
    and fi.revoked_at is null and fi.expires_at > now() and fi.use_count < fi.max_uses
  order by fi.created_at desc;
$$;

drop function if exists public.is_family_member(uuid);
drop function if exists public.is_family_owner(uuid);

-- family_invite_attempts: RLS on, no policies, no client grants. Only the
-- security definer RPCs above write to it.
revoke all on public.family_invite_attempts from public, anon, authenticated;

-- 3. Performance -------------------------------------------------------------
create index if not exists family_invites_created_by_idx on public.family_invites (created_by);
create index if not exists family_recipe_notes_author_idx on public.family_recipe_notes (author_id);
create index if not exists family_recipes_added_by_idx on public.family_recipes (added_by);

alter table public.family_invite_attempts
  add column if not exists id bigint generated always as identity;
do $$ begin
  if not exists (select 1 from pg_constraint
                 where conrelid = 'public.family_invite_attempts'::regclass and contype = 'p') then
    alter table public.family_invite_attempts add constraint family_invite_attempts_pkey primary key (id);
  end if;
end $$;

-- Function grants.
revoke all on function public.set_my_display_name(text) from public, anon;
grant execute on function public.set_my_display_name(text) to authenticated;
revoke all on function public.family_label_for(uuid) from public, anon, authenticated;
do $$
declare fn text;
begin
  foreach fn in array array[
    'public.create_family_invite(uuid)', 'public.revoke_family_invite(uuid)',
    'public.preview_family_invite(text)', 'public.redeem_family_invite(text)',
    'public.remove_family_member(uuid, uuid)', 'public.transfer_family_ownership(uuid, uuid)',
    'public.delete_family(uuid)', 'public.add_recipe_to_family(uuid, uuid)',
    'public.list_family_invites(uuid)'
  ] loop
    execute format('revoke all on function %s from public, anon', fn);
    execute format('grant execute on function %s to authenticated', fn);
  end loop;
end $$;
