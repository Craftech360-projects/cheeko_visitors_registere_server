# Voice Notes: record → sync → transcribe Implementation Plan

**Goal:** Staff can record one voice note per lead in the app; Sync uploads it to
Supabase Storage and saves its URL on the row (`audio_url`); Enrich transcribes
it with Gemini into `audio_transcript` (fill-only-when-blank, like OCR fields).

**Architecture:** The note follows the exact path card photos already take:
local file on device → base64 data URL in the `POST /api/leads` payload →
Supabase Storage (`<id>-audio.m4a`) → URL on the row. Transcription is folded
into the existing single Gemini enrich call (audio is just one more `inline_data`
part; the JSON response gains an `audio_transcript` key), so no new enrich
pipeline, no new endpoints.

**Tech:** Flutter `record` package (AAC/m4a), existing `open_file` for playback,
Gemini 2.5 Flash (already handles audio), Supabase Storage.

## Decisions

| Question | Decision |
|---|---|
| Notes per lead | **One** (like front/back photo — single column). Re-record replaces. |
| Format | AAC-LC `.m4a`, ~0.5 MB/min — fits the 8 MB JSON body limit. |
| Playback in app | Open with the system player via `open_file` (already a dep). No player dep. |
| Transcription | Same Gemini call as OCR; prompt asks for `audio_transcript` in the same JSON. `audio_transcript` joins the fill-only-blank whitelist. |
| Enrich eligibility | A lead is enrichable if it has photos **or** audio; `getPending` updated to match. |
| Ownership | `audio_transcript` is server-owned (written only by enrich); `audio_url` set on upload; blank-omitting upsert means re-sync without audio never wipes an existing URL. |

## Tasks

### 1. Supabase schema (user runs in Studio)
```sql
alter table public.leads add column if not exists audio_url text;
alter table public.leads add column if not exists audio_transcript text;
```
Also add both columns to `supabase-schema.sql` for fresh installs.

### 2. Server
- `lib/db.js` — `dataUrlToBuffer`: use the mime declared in the data-URL header
  for non-image payloads (keep magic-byte detection for images). `uploadPhoto`
  then works for any media. `getPending`: `enriched_at is null AND
  (front_url OR audio_url not null)`.
- `lib/supabase.js` — `leadToRow` gains `row.audio_url = urls.audioUrl || null`.
- `lib/enrich.js` — add `"audio_transcript"` to `FIELDS`.
- `lib/csv.js` — add `audio_url`, `audio_transcript` columns.
- `server.js` — `POST /api/leads`: accept `b.audio` (data URL), upload as
  `<id>-audio.m4a`, pass `audioUrl` to upsert; count audio as "not empty".
  `enrichLead`: fetch audio bytes from `audio_url` (only when transcript blank),
  add as `inline_data` part (`audio/aac`), extend prompt to also return
  `audio_transcript`; accept leads with audio but no photos (error only when
  neither exists).
- Tests: audio mime in `test/db.test.js`, transcript merge in `test/enrich.test.js`.

### 3. Web dashboard (`public/dashboard.html`)
- Details panel: Voice note link + transcript text.
- "Enrich all" pending filter: `(front_url || audio_url) && !enriched_at`.

### 4. App data layer
- `pubspec`: add `record`.
- `lead.dart`: `audioPath` (local), `audioUrl` + `audioTranscript` (server rows);
  `copyWith` carries `enrichedAt`/`audioUrl`/`audioTranscript` through (fixes the
  existing drop of `enrichedAt`).
- `db.dart`: schema v2 + `onUpgrade` → `ALTER TABLE leads ADD COLUMN audio_path TEXT`.
- `audio.dart` (new): `LeadRecorder` start/stop → `<docs>/<id>-audio.m4a`;
  `audioToDataUrl(path)` → `data:audio/mp4;base64,…`.
- `sync.dart`: payload gains `'audio'` when `audioPath` set.
- Android: `RECORD_AUDIO` permission. iOS: `NSMicrophoneUsageDescription`.

### 5. App UI
- Capture/edit screen: Voice note row — mic button toggles record (red while
  recording), then "✓ + play + delete"; audio counts toward `_hasAnyInput`.
- Detail screen: Voice note row (play local file via `open_file`, or open
  server URL via `url_launcher`) + transcript text when present.

### 6. Verify
`npm test` green; `flutter analyze` + `flutter test` green; commit. User then
runs the SQL in Supabase Studio and redeploys the droplet (`git pull` + restart).

## Known limits (accepted)
- A voice note added *after* a lead was already enriched won't be picked up by
  the app's Enrich buttons (they disable on `enriched_at`) — the web dashboard's
  "↻ Re-enrich" covers it. `ponytail: revisit only if it bites.`
- No in-app waveform/duration UI — record/stop/play/delete only.
