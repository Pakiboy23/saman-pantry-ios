-- Private family books (Samaan Pantry 1.6).
-- The public family book (recipe_book_cards) stays as the community book.
-- Family recipes live in separate member-only tables. Members read a snapshot
-- (title, attribution, steps, ingredient phrases, source link). raw_transcript
-- never leaves the author's recipes row.
--
-- Decisions (Haaris, Oct 23 2026):
--   * Creating a family needs Samaan Pro (user_accounts.is_pro) or a
--     grandfathered account. If the owner's Pro lapses, the family keeps working.
--   * Any member can invite. Invites expire after 7 days.
--   * Recipes a member added stay after they leave or are removed.
--   * 5 owned families per user, 50 members per family.
--
-- Named by timestamp: 010 was never applied and 009 has two files.

create extension if not exists pgcrypto with schema extensions;

-- Pro cache, written only by the revenuecat-webhook Edge Function (service role).
alter table public.user_accounts
  add column if not exists is_pro boolean not null default false,
  add column if not exists pro_updated_at timestamptz;

revoke insert, update, delete on public.user_accounts from anon, authenticated;

create table if not exists public.families (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 60),
  owner_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists families_owner_idx on public.families (owner_id);

create table if not exists public.family_members (
  family_id uuid not null references public.families(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'member')),
  display_label text not null default 'A cook',
  joined_at timestamptz not null default now(),
  primary key (family_id, user_id)
);
create unique index if not exists family_members_one_owner
  on public.family_members (family_id) where role = 'owner';
create index if not exists family_members_user_idx on public.family_members (user_id);

create table if not exists public.family_invites (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  code text not null unique check (code ~ '^[A-HJ-NP-Z2-9]{8}$'),
  token_hash text not null unique,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  max_uses int not null default 20 check (max_uses between 1 and 50),
  use_count int not null default 0,
  revoked_at timestamptz
);
create index if not exists family_invites_family_idx on public.family_invites (family_id);

create table if not exists public.family_recipes (
  family_id uuid not null references public.families(id) on delete cascade,
  recipe_id uuid not null,
  -- Kept after the author leaves (decision 5). Null once their account is gone.
  added_by uuid references auth.users(id) on delete set null,
  added_by_label text not null default 'A cook',
  title text not null,
  attribution text,
  steps jsonb not null default '[]'::jsonb,
  ingredient_phrases jsonb not null default '[]'::jsonb,
  source_url text check (source_url is null or source_url ~* '^https?://[^[:space:]]+$'),
  added_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (family_id, recipe_id)
);
-- No FK to recipes: the snapshot outlives the author's row and their membership.

create table if not exists public.family_recipe_notes (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null,
  recipe_id uuid not null,
  author_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (family_id, recipe_id)
    references public.family_recipes(family_id, recipe_id) on delete cascade
);
create index if not exists family_recipe_notes_recipe_idx
  on public.family_recipe_notes (family_id, recipe_id, created_at);

create table if not exists public.family_invite_attempts (
  user_id uuid not null references auth.users(id) on delete cascade,
  attempted_at timestamptz not null default now(),
  ok boolean not null
);
create index if not exists family_invite_attempts_user_idx
  on public.family_invite_attempts (user_id, attempted_at desc);

alter table public.recipes add column if not exists copied_from uuid;

-- Helpers. security definer avoids RLS recursion on family_members.
create or replace function public.is_family_member(fid uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.family_members m
                 where m.family_id = fid and m.user_id = auth.uid());
$$;

create or replace function public.is_family_owner(fid uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.family_members m
                 where m.family_id = fid and m.user_id = auth.uid() and m.role = 'owner');
$$;

create or replace function public.can_create_family(uid uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select ua.is_pro or ua.grandfathered
                   from public.user_accounts ua where ua.id = uid), false);
$$;

create or replace function public.family_label_for(uid uuid)
returns text language sql stable security definer set search_path = '' as $$
  select coalesce(nullif(split_part(coalesce(au.email, ''), '@', 1), ''), 'A cook')
  from auth.users au where au.id = uid;
$$;

-- RLS. Writes to families, members and invites go through the RPCs below.
alter table public.families enable row level security;
alter table public.family_members enable row level security;
alter table public.family_invites enable row level security;
alter table public.family_recipes enable row level security;
alter table public.family_recipe_notes enable row level security;
alter table public.family_invite_attempts enable row level security;

drop policy if exists families_select_member on public.families;
create policy families_select_member on public.families
  for select to authenticated using (public.is_family_member(id));
drop policy if exists families_update_owner on public.families;
create policy families_update_owner on public.families
  for update to authenticated
  using (public.is_family_owner(id)) with check (public.is_family_owner(id));

drop policy if exists family_members_select on public.family_members;
create policy family_members_select on public.family_members
  for select to authenticated using (public.is_family_member(family_id));

drop policy if exists family_invites_select_member on public.family_invites;
create policy family_invites_select_member on public.family_invites
  for select to authenticated using (public.is_family_member(family_id));

drop policy if exists family_recipes_select on public.family_recipes;
create policy family_recipes_select on public.family_recipes
  for select to authenticated using (public.is_family_member(family_id));
drop policy if exists family_recipes_delete on public.family_recipes;
create policy family_recipes_delete on public.family_recipes
  for delete to authenticated
  using (public.is_family_member(family_id)
         and (added_by = auth.uid() or public.is_family_owner(family_id)));

drop policy if exists family_recipe_notes_select on public.family_recipe_notes;
create policy family_recipe_notes_select on public.family_recipe_notes
  for select to authenticated using (public.is_family_member(family_id));
drop policy if exists family_recipe_notes_insert on public.family_recipe_notes;
create policy family_recipe_notes_insert on public.family_recipe_notes
  for insert to authenticated
  with check (author_id = auth.uid() and public.is_family_member(family_id));
drop policy if exists family_recipe_notes_update on public.family_recipe_notes;
create policy family_recipe_notes_update on public.family_recipe_notes
  for update to authenticated
  using (author_id = auth.uid()) with check (author_id = auth.uid() and public.is_family_member(family_id));
drop policy if exists family_recipe_notes_delete on public.family_recipe_notes;
create policy family_recipe_notes_delete on public.family_recipe_notes
  for delete to authenticated using (author_id = auth.uid());

revoke all on public.families, public.family_members, public.family_invites,
  public.family_recipes, public.family_recipe_notes, public.family_invite_attempts
  from anon, authenticated;
grant select on public.families, public.family_members, public.family_recipes,
  public.family_recipe_notes to authenticated;
grant update (name) on public.families to authenticated;
grant delete on public.family_recipes to authenticated;
grant insert (family_id, recipe_id, author_id, body), update (body), delete
  on public.family_recipe_notes to authenticated;
-- Invite codes and hashes are never readable by clients; list_family_invites returns them.
revoke select on public.family_invites from authenticated;

-- Snapshot of a recipe row. Shared by add_recipe_to_family and the sync trigger.
create or replace function public.family_recipe_snapshot(r public.recipes)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  parsed jsonb;
  steps jsonb;
  ingredients jsonb;
  phrases jsonb;
  link text;
begin
  begin parsed := r.extracted_json::jsonb; exception when others then parsed := '{}'::jsonb; end;
  steps := coalesce(parsed -> 'steps', '[]'::jsonb);
  if jsonb_typeof(steps) <> 'array' then steps := '[]'::jsonb; end if;
  ingredients := coalesce(parsed -> 'ingredients', '[]'::jsonb);
  if jsonb_typeof(ingredients) <> 'array' then ingredients := '[]'::jsonb; end if;
  select coalesce(jsonb_agg(coalesce(e ->> 'original_phrase', e ->> 'ingredient', '')), '[]'::jsonb)
    into phrases from jsonb_array_elements(ingredients) e;
  -- Only a link is ever copied. Spoken or pasted words stay private.
  if r.source_kind = 'url' and btrim(coalesce(r.raw_transcript, '')) ~* '^https?://[^[:space:]]+$' then
    link := btrim(r.raw_transcript);
  end if;
  return jsonb_build_object('title', r.title, 'attribution', r.attribution,
    'steps', steps, 'ingredient_phrases', phrases, 'source_url', link);
end;
$$;

-- RPCs ---------------------------------------------------------------------

create or replace function public.create_family(p_name text)
returns public.families language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); fam public.families;
begin
  if uid is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  perform public.ensure_user_account(uid);
  if not public.can_create_family(uid) then
    raise exception 'Samaan Pro required' using errcode = 'P0001', hint = 'pro_required';
  end if;
  perform pg_advisory_xact_lock(hashtext('family_owner:' || uid::text));
  if (select count(*) from public.families f where f.owner_id = uid) >= 5 then
    raise exception 'Family limit reached' using errcode = 'P0001', hint = 'family_limit';
  end if;
  insert into public.families (name, owner_id) values (btrim(p_name), uid) returning * into fam;
  insert into public.family_members (family_id, user_id, role, display_label)
  values (fam.id, uid, 'owner', public.family_label_for(uid));
  return fam;
end;
$$;

-- Any member can invite (decision 4). Returns the raw token once.
create or replace function public.create_family_invite(p_family_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  new_code text; raw_token text; inv public.family_invites; i int; attempt int := 0;
begin
  if not public.is_family_member(p_family_id) then
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
    and (fi.created_by = auth.uid() or public.is_family_owner(fi.family_id));
  if not found then raise exception 'Invite not found' using errcode = '42501'; end if;
end;
$$;

-- Look up an invite without joining, so the app can show the family name first.
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
    'already_member', public.is_family_member(fam.id));
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
  if public.is_family_member(inv.family_id) then
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

-- Leave (self) or remove (owner removes a member). Added recipes stay (decision 5).
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
  if p_user_id <> auth.uid() and not public.is_family_owner(p_family_id) then
    raise exception 'Only the owner can remove members' using errcode = '42501';
  end if;
  delete from public.family_members m where m.family_id = p_family_id and m.user_id = p_user_id;
end;
$$;

create or replace function public.transfer_family_ownership(p_family_id uuid, p_new_owner uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_family_owner(p_family_id) then
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
  if not public.is_family_owner(p_family_id) then
    raise exception 'Only the owner can delete the family' using errcode = '42501';
  end if;
  delete from public.families where id = p_family_id;
end;
$$;

-- Add one of my recipes to a family I belong to. Multiple families allowed.
create or replace function public.add_recipe_to_family(p_family_id uuid, p_recipe_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); r public.recipes; s jsonb;
begin
  if not public.is_family_member(p_family_id) then
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

-- Keep snapshots fresh while the author edits. Deleting the source recipe
-- removes it from families (members' saved copies stay in their own books).
-- Account deletion cascades the recipe too, but that snapshot stays: the
-- author row is already gone, and added_by is nulled before the cascade.
create or replace function public.sync_family_recipes()
returns trigger language plpgsql security definer set search_path = '' as $$
declare s jsonb;
begin
  if tg_op = 'DELETE' then
    if exists (select 1 from auth.users u where u.id = old.user_id) then
      delete from public.family_recipes where recipe_id = old.id and added_by = old.user_id;
    end if;
    return old;
  end if;
  s := public.family_recipe_snapshot(new);
  update public.family_recipes set
    title = s ->> 'title', attribution = s ->> 'attribution', steps = s -> 'steps',
    ingredient_phrases = s -> 'ingredient_phrases', source_url = s ->> 'source_url',
    updated_at = now()
  where recipe_id = new.id and added_by = new.user_id;
  return new;
end;
$$;

drop trigger if exists recipes_sync_family_recipes on public.recipes;
create trigger recipes_sync_family_recipes
after update or delete on public.recipes
for each row execute function public.sync_family_recipes();

-- Owner deletes account: hand the family to the longest-standing member, or drop it.
create or replace function public.handoff_families_on_user_delete()
returns trigger language plpgsql security definer set search_path = '' as $$
declare f record; heir uuid;
begin
  -- Null before recipes cascade. sync_family_recipes would otherwise see
  -- added_by still matching and drop snapshots the family is supposed to keep.
  -- ON DELETE SET NULL on added_by is not ordered ahead of that cascade.
  update public.family_recipes set added_by = null where added_by = old.id;
  for f in select id from public.families where owner_id = old.id loop
    select m.user_id into heir from public.family_members m
    where m.family_id = f.id and m.user_id <> old.id order by m.joined_at limit 1;
    if heir is not null then
      delete from public.family_members where family_id = f.id and user_id = old.id;
      update public.family_members set role = 'owner' where family_id = f.id and user_id = heir;
      update public.families set owner_id = heir where id = f.id;
    end if;
  end loop;
  return old;
end;
$$;

drop trigger if exists auth_user_handoff_families on auth.users;
create trigger auth_user_handoff_families
before delete on auth.users
for each row execute function public.handoff_families_on_user_delete();

create or replace function public.list_family_invites(p_family_id uuid)
returns table (id uuid, code text, expires_at timestamptz, use_count int, max_uses int)
language sql stable security definer set search_path = '' as $$
  select fi.id, fi.code, fi.expires_at, fi.use_count, fi.max_uses
  from public.family_invites fi
  where fi.family_id = p_family_id and public.is_family_member(p_family_id)
    and fi.revoked_at is null and fi.expires_at > now() and fi.use_count < fi.max_uses
  order by fi.created_at desc;
$$;

-- Grants on functions.
do $$
declare fn text;
begin
  foreach fn in array array[
    'public.is_family_member(uuid)', 'public.is_family_owner(uuid)',
    'public.create_family(text)', 'public.create_family_invite(uuid)',
    'public.revoke_family_invite(uuid)', 'public.preview_family_invite(text)',
    'public.redeem_family_invite(text)', 'public.remove_family_member(uuid, uuid)',
    'public.transfer_family_ownership(uuid, uuid)', 'public.delete_family(uuid)',
    'public.add_recipe_to_family(uuid, uuid)', 'public.list_family_invites(uuid)'
  ] loop
    execute format('revoke all on function %s from public, anon', fn);
    execute format('grant execute on function %s to authenticated', fn);
  end loop;
  foreach fn in array array[
    'public.can_create_family(uuid)', 'public.family_label_for(uuid)',
    'public.family_recipe_snapshot(public.recipes)', 'public.sync_family_recipes()',
    'public.handoff_families_on_user_delete()'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', fn);
  end loop;
end $$;
