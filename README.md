# Visitors Register

Cloud lead capture for event stalls. A **Flutter app** captures leads offline (local SQLite + on-device photos) and uploads them via a manual Sync button when internet is available. The **Node/Express gateway** on a DigitalOcean droplet writes leads to **Supabase** (Postgres rows + Storage photos). Review, OCR enrichment, WhatsApp follow-up, and CSV export happen on the **web dashboard**. See [CONTEXT.md](CONTEXT.md) for the glossary and `docs/adr/` for the two key decisions.

## Run

### Environment

Create a `.env` file (never committed):

```
SUPABASE_URL=https://xxxx.supabase.co
SUPABASE_SECRET_KEY=...          # service_role key (Project Settings → API)
SUPABASE_BUCKET=cards            # optional — defaults to "cards"
GOOGLE_API_KEY=...               # Gemini key from Google AI Studio (for OCR/Enrich)
OCR_MODEL=gemini-2.5-flash       # optional — this is the default
PUBLIC_URL=https://your-droplet  # optional — logged on startup
```

### Start

```
npm install
npm start    # node server.js — listens on 0.0.0.0:8080
```

### Endpoints

- **Capture (browser fallback):** `http://<host>:8080/` — `capture.html` POSTs to the cloud server; use the Flutter app as the primary capture device.
- **Dashboard:** `http://<host>:8080/dashboard` — review leads, run OCR enrichment, send WhatsApp follow-ups, export CSV.
- **API:** `POST /api/leads` — used by the Flutter app and the browser fallback. Accepts lead fields + base64 card photos; uploads photos to Supabase Storage, normalizes the phone number, upserts the row keyed on the client-generated UUID.

## Flutter app (primary capture device)

The Flutter app is the intended capture tool. It works **fully offline** throughout the event day:

1. Capture leads on the phone — form + card photos saved to local SQLite (`synced=0`).
2. Press **Sync** when internet is available — each unsynced lead is posted to `/api/leads` one at a time; successes are marked `synced=1` and won't be re-sent.
3. Failures stay `synced=0` and are retried on the next Sync press.

Multiple phones can sync concurrently — each generates its own UUID locally, so upserts on the server never collide.

## Test

```
npm test    # node --test — covers phone normalization (the WhatsApp-critical bit)
```

## OCR enrichment (dashboard)

Each lead with a card photo shows an **✨ Enrich** button on the dashboard. It sends the Supabase Storage photo URL to **Gemini 2.5 Flash** (vision) and fills in any **blank** fields it can read — never overwriting what staff typed, never touching the phone number, skipping anything it can't read. See [ADR 0002](docs/adr/0002-defer-ocr-to-online-enrichment.md).

OCR is deliberately decoupled from upload — Sync is fast and robust; Enrich runs as a separate bulk step on the dashboard when you're ready.

Without `GOOGLE_API_KEY`, Enrich returns "not configured" and changes nothing.
