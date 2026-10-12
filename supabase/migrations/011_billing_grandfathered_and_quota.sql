-- Billing free-tier: grandfathered daily quota vs lifetime quota for new users.
-- Accounts created before 2026-10-12 keep 5 extractions / rolling 24h.
-- Newer accounts get 5 lifetime extractions. Pro bypasses quota in the Edge
-- Function (RevenueCat entitlement check); this RPC only gates free users.
--
-- Do not deploy extract-recipe against this until Haaris applies the migration.

create table if not exists public.user_accounts (
    id              uuid primary key references auth.users(id) on delete cascade,
    grandfathered   boolean not null default false,
    created_at      timestamptz not null default now()
);

alter table public.user_accounts enable row level security;

-- Clients may read their own grandfathered flag for the extraction counter.
create policy "user_accounts_select_own" on public.user_accounts
    for select to authenticated
    using (auth.uid() = id);

-- No client inserts/updates: signup trigger and service role only.
revoke insert, update, delete on public.user_accounts from anon, authenticated;
grant select on public.user_accounts to authenticated;
grant all on public.user_accounts to service_role;

-- Cutoff: every account created before 2026-10-12 UTC is grandfathered.
insert into public.user_accounts (id, grandfathered, created_at)
select
    au.id,
    (au.created_at < timestamptz '2026-10-12 00:00:00+00') as grandfathered,
    coalesce(au.created_at, now())
from auth.users au
on conflict (id) do nothing;

-- New signups are never grandfathered.
create or replace function public.handle_user_account_signup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    insert into public.user_accounts (id, grandfathered)
    values (new.id, false)
    on conflict (id) do nothing;
    return new;
end;
$$;

drop trigger if exists on_auth_user_created_user_account on auth.users;
create trigger on_auth_user_created_user_account
    after insert on auth.users
    for each row
    execute function public.handle_user_account_signup();

revoke all on function public.handle_user_account_signup() from public, anon, authenticated;
grant execute on function public.handle_user_account_signup() to supabase_auth_admin, service_role;

-- Ensure a row exists for this user, applying the same cutoff for late rows.
create or replace function public.ensure_user_account(p_user_id uuid)
returns boolean
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
    is_grandfathered boolean;
    account_created timestamptz;
begin
    select ua.grandfathered into is_grandfathered
    from public.user_accounts ua
    where ua.id = p_user_id;

    if found then
        return is_grandfathered;
    end if;

    select au.created_at into account_created
    from auth.users au
    where au.id = p_user_id;

    is_grandfathered := coalesce(
        account_created < timestamptz '2026-10-12 00:00:00+00',
        false
    );

    insert into public.user_accounts (id, grandfathered, created_at)
    values (p_user_id, is_grandfathered, coalesce(account_created, now()))
    on conflict (id) do nothing;

    select ua.grandfathered into is_grandfathered
    from public.user_accounts ua
    where ua.id = p_user_id;

    return coalesce(is_grandfathered, false);
end;
$$;

revoke all on function public.ensure_user_account(uuid) from public, anon, authenticated;
grant execute on function public.ensure_user_account(uuid) to service_role;

-- Free-tier reservation. Pro callers skip this RPC entirely in extract-recipe.
create or replace function public.reserve_recipe_extraction(p_user_id uuid)
returns uuid
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
    reserved_id uuid;
    reserved_at timestamptz;
    is_grandfathered boolean;
    used_count bigint;
begin
    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('recipe_extraction:' || p_user_id::text, 0)
    );
    reserved_at := clock_timestamp();
    is_grandfathered := public.ensure_user_account(p_user_id);

    if is_grandfathered then
        -- Keep the five-attempt rolling 24h cap in sync with FreeLimits.extractLimit.
        select count(*) into used_count
        from public.recipe_extraction_events
        where user_id = p_user_id
          and created_at >= reserved_at - interval '24 hours';
    else
        -- New free users: five lifetime extractions, no daily reset.
        select count(*) into used_count
        from public.recipe_extraction_events
        where user_id = p_user_id;
    end if;

    if used_count >= 5 then
        return null;
    end if;

    insert into public.recipe_extraction_events (user_id, created_at)
    values (p_user_id, reserved_at)
    returning id into reserved_id;
    return reserved_id;
end;
$$;

revoke all on function public.reserve_recipe_extraction(uuid) from public, anon, authenticated;
grant execute on function public.reserve_recipe_extraction(uuid) to service_role;

-- Authenticated users can read their own free-tier counter state.
create or replace function public.my_extraction_quota_status()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
    uid uuid := auth.uid();
    is_grandfathered boolean;
    used_count bigint;
begin
    if uid is null then
        raise exception 'not authenticated';
    end if;

    -- SECURITY DEFINER so ensure_user_account can insert the row if missing.
    is_grandfathered := public.ensure_user_account(uid);

    if is_grandfathered then
        select count(*) into used_count
        from public.recipe_extraction_events
        where user_id = uid
          and created_at >= clock_timestamp() - interval '24 hours';
    else
        select count(*) into used_count
        from public.recipe_extraction_events
        where user_id = uid;
    end if;

    return jsonb_build_object(
        'grandfathered', is_grandfathered,
        'used', used_count,
        'limit', 5,
        'resets_daily', is_grandfathered
    );
end;
$$;

revoke all on function public.my_extraction_quota_status() from public, anon;
grant execute on function public.my_extraction_quota_status() to authenticated, service_role;
