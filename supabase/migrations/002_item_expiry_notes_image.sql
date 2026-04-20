-- Migration 002: Add expiry_date, notes, image_url to items
-- Run in: Supabase dashboard → SQL Editor

alter table items
    add column if not exists expiry_date  timestamptz,
    add column if not exists notes        text,
    add column if not exists image_url    text;
