-- ============================================================
-- Saman — Initial Schema
-- Run this in: Supabase dashboard → SQL Editor
-- ============================================================

-- Enable UUID extension (already on by default in Supabase)
create extension if not exists "uuid-ossp";

-- ── pantries ─────────────────────────────────────────────────
create table if not exists pantries (
    id          uuid primary key default uuid_generate_v4(),
    user_id     uuid not null references auth.users(id) on delete cascade,
    name        text not null,
    updated_at  timestamptz not null default now(),
    created_at  timestamptz not null default now()
);
alter table pantries enable row level security;
create policy "owner" on pantries using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ── products ─────────────────────────────────────────────────
create table if not exists products (
    id          uuid primary key default uuid_generate_v4(),
    user_id     uuid not null references auth.users(id) on delete cascade,
    name        text not null,
    barcode     text,
    brand       text,
    category    text,
    updated_at  timestamptz not null default now(),
    created_at  timestamptz not null default now()
);
alter table products enable row level security;
create policy "owner" on products using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ── items ─────────────────────────────────────────────────────
create table if not exists items (
    id                  uuid primary key default uuid_generate_v4(),
    user_id             uuid not null references auth.users(id) on delete cascade,
    pantry_id           uuid references pantries(id) on delete set null,
    product_id          uuid references products(id) on delete set null,
    name                text not null,
    quantity            integer not null default 0,
    unit                text not null default 'unit',
    minimum_quantity    integer not null default 1,
    barcode             text,
    updated_at          timestamptz not null default now(),
    created_at          timestamptz not null default now()
);
alter table items enable row level security;
create policy "owner" on items using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ── stores ────────────────────────────────────────────────────
create table if not exists stores (
    id          uuid primary key default uuid_generate_v4(),
    user_id     uuid not null references auth.users(id) on delete cascade,
    name        text not null,
    address     text,
    updated_at  timestamptz not null default now(),
    created_at  timestamptz not null default now()
);
alter table stores enable row level security;
create policy "owner" on stores using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ── shopping_lists ────────────────────────────────────────────
create table if not exists shopping_lists (
    id              uuid primary key default uuid_generate_v4(),
    user_id         uuid not null references auth.users(id) on delete cascade,
    store_id        uuid references stores(id) on delete set null,
    name            text not null,
    is_completed    boolean not null default false,
    updated_at      timestamptz not null default now(),
    created_at      timestamptz not null default now()
);
alter table shopping_lists enable row level security;
create policy "owner" on shopping_lists using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ── shopping_list_items ───────────────────────────────────────
create table if not exists shopping_list_items (
    id                  uuid primary key default uuid_generate_v4(),
    user_id             uuid not null references auth.users(id) on delete cascade,
    shopping_list_id    uuid references shopping_lists(id) on delete cascade,
    product_id          uuid references products(id) on delete set null,
    quantity            integer not null default 1,
    unit                text not null default 'unit',
    is_purchased        boolean not null default false,
    estimated_price     numeric(10,2),
    updated_at          timestamptz not null default now(),
    created_at          timestamptz not null default now()
);
alter table shopping_list_items enable row level security;
create policy "owner" on shopping_list_items using (auth.uid() = user_id) with check (auth.uid() = user_id);
