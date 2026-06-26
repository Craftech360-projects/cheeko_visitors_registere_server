# Online Lead Capture — Flutter App + Cloud Server

**Date:** 2026-06-26
**Status:** Approved (design), pending implementation plan

## Summary

Convert Visitors Register from a LAN-only, no-internet tool into a
cloud-hosted system. A **Flutter app** becomes the capture device: it works
fully offline (local SQLite + on-device photos) and uploads a day's leads on a
**manual Sync button** when internet is available. The Node server moves to a
**stateless gateway** on a DigitalOcean droplet, backed by **Supabase**
(Postgres for rows, Storage for photos). Review, OCR enrichment, WhatsApp
follow-up, and CSV export all happen on the existing **web dashboard**.

This supersedes the no-internet premise of
[ADR 0001](../../adr/0001-lan-client-server-not-peer-to-peer.md). OCR stays
deferred to an online dashboard step, consistent with
[ADR 0002](../../adr/0002-defer-ocr-to-online-enrichment.md).

## Decisions (from brainstorming)

| Question | Decision |
|---|---|
| Auth / tenancy | **None.** Fully open server; the app is only handed to trusted staff. `add a SYNC_TOKEN header if the URL ever leaks.` |
| Sync direction | **Upload-only.** App pushes; review happens on the web dashboard. |
| Hosting | **DigitalOcean droplet** runs the Node server. |
| Database | **Supabase Postgres** is the primary DB. SQLite is dropped. |
| Photos | **Supabase Storage** (`cards` bucket), public URLs on each row. |
| Gateway | **Approach A** — the Node server is the only front door. The app talks **only** to our HTTP API; Supabase keys and the Gemini key stay server-side. |
| Old LAN pieces | Drop `/qr`, hourly backups, LAN-IP logic, on-disk `photos/`, SQLite. **Keep `capture.html`** as a browser fallback hitting the cloud. |
| OCR | **Decoupled from upload.** Sync only stores data; OCR runs as a separate bulk step on the dashboard. |

## Architecture

```
PHONE (all day, offline)        SYNC button (internet)         DASHBOARD (web, when you want)
─────────────────────────       ──────────────────────         ─────────────────────────────
Flutter app                     POST /api/leads (per lead)      reads/writes Supabase via server
  capture → local SQLite,  ───▶ Node gateway (droplet)    ───▶  "Enrich all" → bulk Gemini OCR
  photos on device,               upsert row on id (uuid)        WhatsApp follow-up links
  synced=0                        upload photos → Storage        CSV export
                                  normalize phone                (browser capture.html fallback)
                                ▼
                          Supabase: Postgres (leads) + Storage (cards)
```

Single trust boundary: only the Node server holds Supabase / Gemini secrets.
The server is stateless — a droplet restart loses nothing.

## Data model (Supabase Postgres `leads`)

Extends the existing `supabase-schema.sql`.

| column | type | notes |
|---|---|---|
| `id` | uuid PK | **client-generated** by the app at capture; server generates one (`crypto.randomUUID()`) for web-capture rows. The idempotency / upsert conflict key. |
| `phone` | text not null | raw typed phone. |
| `wa_phone` | text | normalized by the server via existing `normalizeForWa`. |
| `name, company, email, website, city, state, products, note, tag` | text | as today. |
| `front_url, back_url` | text | Supabase Storage public URLs. No on-disk paths. |
| `enriched_at` | text | set when OCR has run (even if it filled nothing). |
| `created_at` | text not null | capture time (client) or insert time (web). |

Photos in Storage are named `<id>-front.jpg` / `<id>-back.jpg` in the `cards`
bucket (Public, for openable URLs).

`id` changes from integer autoincrement to a client-supplied uuid so the app
can assign it offline and the server can upsert idempotently.

## Server changes (`server.js`)

- **Add `@supabase/supabase-js`** on the server. Replaces hand-built PostgREST
  `fetch` URLs with `.select()/.upsert()/.update()`. (Raw `fetch` is the
  fallback; the SDK is justified by the number of distinct query shapes,
  especially the dynamic enrich UPDATE.)
- **`POST /api/leads`** — accepts `{ id, phone, name, ..., frontPhoto, backPhoto }`
  (photos base64). Uploads photos to Storage, normalizes phone, **upserts** the
  row keyed on `id`. Used by both the app and the web fallback. Idempotent:
  re-sending updates, never duplicates.
- **`GET /api/leads`**, **`/api/enrich-all`**, **`/api/leads/:id/enrich`**,
  **`/export.csv`** — same behavior, now reading/writing Supabase. Enrich
  fetches photo bytes from the Storage URL (instead of disk) before calling
  Gemini.
- **Remove** the 409 duplicate-phone confirm flow from the server — dedup moves
  into the app (it owns the local list); uuid-upsert makes re-sync safe anyway.
- **Remove** SQLite, `/qr`, hourly `localBackup` + `setInterval`, `BACKUP_DIR`,
  on-disk `PHOTO_DIR`, and LAN-IP logging. `listen` logs the configured public
  URL.
- Keep `lib/phone.js`, `lib/csv.js`, `lib/enrich.js`, `lib/supabase.js`
  (`leadToRow`) — all still apply.

## Flutter app

**Stack:** `sqflite` (local DB), `path_provider` (photo files),
`image_picker` or `camera` + `image` (capture + downscale to ~1280px / JPEG
~0.7, matching the web capture's small payloads), `http`, `uuid`.

**Local table** mirrors the server fields plus `front_path`, `back_path` (local
file paths) and `synced` (0/1).

**Screens:**
1. **Capture** — form (phone required + optional fields), snap front + optional
   back card photo → save locally, `synced=0`. Warn if the phone was already
   captured today (local dedup).
2. **Leads list** — today's captures with a synced/pending badge; **Sync**
   button in the app bar.
3. **Lead detail** (light) — view/edit a row before sync.

**Sync service (the button):**
```
unsynced = SELECT * FROM leads WHERE synced = 0
for each lead:
    POST {SERVER_URL}/api/leads  (fields + base64 photos)
    on HTTP 200 → UPDATE synced = 1
    on failure  → leave synced = 0 (shown as pending, retried next press)
show progress "23 / 50"; report failures at the end
```
Per-lead, not one bulk payload: a day's photos can be ~20 MB, and a dropped
connection mid-upload must not force re-sending everything. Each success is
banked; the next press resumes the rest. Idempotent by the uuid upsert.

Server base URL is a config constant, editable in a small settings field.

## Flow: bulk upload + OCR

Upload and OCR are **two separate steps**, deliberately decoupled.

1. **All day (offline):** capture → local SQLite, photos on device, `synced=0`.
2. **Sync button:** upload unsynced leads one-by-one → Supabase. Fast, robust,
   resumable. **OCR has not run yet.**
3. **Dashboard "Enrich all":** server selects leads with a photo and no
   `enriched_at`, sends each card to Gemini, fills **blank** fields only, stamps
   `enriched_at`. Best-effort: failures are recorded and skipped, the rest
   continue.

OCR is not glued onto upload because it is slow (~2–5s/card) and costs money;
coupling would let a Gemini hiccup block getting data safe, and a lead with no
card photo needs no OCR.

`ponytail: bulk Enrich-all is sequential (~2–3 min for 50 cards). Add bounded
concurrency only if the wait bites.`

## Error handling

- **Sync:** per-lead try/catch. A dropped connection leaves the rest pending
  for the next press. Nothing is marked synced unless the server returned 200.
- **Server:** invalid phone → 400; Storage/upsert failure → 502 (that lead
  stays pending on the app and is retried); OCR best-effort as today.
- **Open server:** no auth by design. Risk accepted: anyone with the URL could
  read/post. Mitigation path documented (SYNC_TOKEN header) but not built.

## Testing

- Existing pure-logic unit tests stay valid and green: `phone`, `csv`,
  `enrich`, `supabase` (`leadToRow`) mapping.
- Add one Flutter test: capture → sync marks `synced = 1`. No extra frameworks.

## Out of scope (YAGNI)

- Two-way sync / pulling leads back to the phone.
- Per-user accounts, login, RLS.
- Auto-OCR on upload.
- Bulk-batch upload endpoint (per-lead is enough and more robust).
