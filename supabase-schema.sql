-- Visitors Register → Supabase sync setup.
-- 1. Run this in Supabase Studio → SQL Editor.
-- 2. Create a Storage bucket named "cards" (Storage → New bucket; make it Public
--    if you want the photo URLs to open without auth).
-- 3. Put SUPABASE_URL + SUPABASE_SERVICE_KEY (+ optional SUPABASE_BUCKET) in .env.
--
-- The server uses the service_role key, which bypasses Row Level Security, so no
-- RLS policies are needed for the sync to work.

create table if not exists public.leads (
  id          bigint primary key,   -- same id as the local SQLite lead; upsert key
  name        text,
  company     text,
  email       text,
  website     text,
  phone       text,
  wa_phone    text,
  city        text,
  state       text,
  products    text,
  note        text,
  tag         text,
  front_url   text,                  -- public URL of the front card photo
  back_url    text,                  -- public URL of the back card photo
  created_at  timestamptz
);
