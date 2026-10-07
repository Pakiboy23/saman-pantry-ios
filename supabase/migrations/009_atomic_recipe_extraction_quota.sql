-- Only the Edge Function may reserve quota, using its verified auth user ID.
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
begin
    -- Held until the RPC transaction commits. VOLATILE gives the count a fresh
    -- snapshot after waiting, so it sees the preceding caller's reservation.
    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('recipe_extraction:' || p_user_id::text, 0)
    );
    reserved_at := clock_timestamp();

    -- Keep the five-attempt rolling 24h cap in sync with FreeLimits.extractPerDay.
    if (select count(*) from public.recipe_extraction_events
        where user_id = p_user_id
          and created_at >= reserved_at - interval '24 hours') >= 5 then
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
