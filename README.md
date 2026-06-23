# Visitors Register

Offline event lead capture. Phones on the venue LAN capture leads → one PC
stores them → dashboard follows up via WhatsApp later. See [CONTEXT.md](CONTEXT.md)
for the glossary and `docs/adr/` for the two key decisions.

## Run

```
npm install     # ONCE, on a machine WITH internet (see checklist)
npm start       # node server.js — serves on 0.0.0.0:8080
```

On boot it prints the LAN URLs:

- **Capture (phones):** `http://<pc-lan-ip>:8080/`
- **Stall QR code:** `http://<pc-lan-ip>:8080/qr` — open on the PC, print/show it; phones scan to open the capture page
- **Dashboard:** `http://<pc-lan-ip>:8080/dashboard`

## ⚠️ Pre-venue checklist (there is no internet at the stall)

1. On the venue PC, **install Node 18+** beforehand.
2. Copy the **entire project folder including `node_modules/`** to the PC.
   You cannot `npm install` at the venue — vendor it now.
3. Make sure the PC and phones join the **same WiFi/router** (or the PC's
   hotspot). No internet needed — just a shared network.
4. `npm start`, open `/qr` on the PC, and you're live.

## Data & backup

- `visitors.db` (SQLite) + `photos/` hold everything. Both gitignored.
- **Primary backup:** server auto-copies the DB to `backups/` hourly; drag
  `visitors.db` + `photos/` to a USB at end of day.
- **Cloud backup (optional, internet only):** set `SUPABASE_URL`,
  `SUPABASE_KEY`, `SUPABASE_BUCKET` env vars, then `POST /api/backup/cloud`.

## Test

```
npm test    # node --test — covers phone normalization (the WhatsApp-critical bit)
```

## v2 (when internet is back)

Dashboard-triggered OCR enrichment of card photos to fill blank fields. Not
built yet — see [ADR 0002](docs/adr/0002-defer-ocr-to-online-enrichment.md).
