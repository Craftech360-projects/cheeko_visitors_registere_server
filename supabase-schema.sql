-- Visitors Register → Supabase setup (run in Supabase Studio → SQL Editor).
-- Then create a Storage bucket named "cards" (Storage → New bucket → Public).
-- Put SUPABASE_URL + SUPABASE_SECRET_KEY (+ optional SUPABASE_BUCKET) in .env.
-- The server uses the secret key (bypasses RLS), so no RLS policies are needed.

-- The old table used `id bigint`; recreate it with `id uuid`. Drops existing
-- rows (confirmed dev/test data only).
drop table if exists public.leads cascade;

create table if not exists public.leads (
  id          uuid primary key,        -- client-generated; upsert conflict key
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
  front_url   text,                     -- public URL of the front card photo
  back_url    text,                     -- public URL of the back card photo
  audio_url   text,                     -- public URL of the voice note (m4a)
  audio_transcript text,                -- filled by enrich (Gemini transcription)
  enriched_at timestamptz,              -- set when OCR ran (null = pending)
  created_at  timestamptz
);

-- Upgrading an existing install? Run just these:
-- alter table public.leads add column if not exists audio_url text;
-- alter table public.leads add column if not exists audio_transcript text;

create index if not exists leads_created_at_idx on public.leads (created_at desc);

-- Editable WhatsApp follow-up template (moved off SQLite).
create table if not exists public.settings (
  key   text primary key,
  value text
);
