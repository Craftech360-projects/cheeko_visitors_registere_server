# Visitors Register — Context

A tool for capturing sales leads at a physical event stall. A **Flutter app**
captures leads offline (local SQLite + on-device photos), then uploads them
to a cloud server via a manual Sync button when internet is available. The
server is a stateless Node/Express gateway on a DigitalOcean droplet, backed
by **Supabase** (Postgres for lead rows, Storage for card photos). Leads are
reviewed, enriched, and followed up on the web dashboard.

## Glossary

### Lead
A person who visited the stall and whose contact details we captured, so we
can follow up with them later for sales. Distinct from a **Member** (see
below): a Member is a pre-known company in a reference directory; a Lead is
someone newly met at the event.

### Member
A pre-loaded, known company/contact in a reference directory (e.g. the
`cheeko-toybiz-2026` TAI directory). We do not capture Members — they already
exist. They are the *style reference* for how captured Leads are displayed
and contacted. Not part of v1 data capture.

### Stall
The team's booth at the event. The physical place where Leads are captured.

### Card
The visiting card / business card a Lead hands over at the Stall (NOT a
government ID). The source of truth for a Lead's details. In v1 it is
captured as a photo (front, plus an optional back for the rare two-sided
case) and the phone number is typed by hand. OCR is deferred to v2, run from
the Dashboard once internet is available (see ADR 0002).

### Enrichment (v2)
A Dashboard action, available only when internet is back, that runs OCR on a
Lead's Card photo(s) to fill in fields left blank at capture time. Per-Lead,
best-effort: any field OCR cannot read is skipped, never guessed.

### Capture Device
A phone (or tablet) running the **Flutter app**, used by stall staff to
capture Leads offline. Stores leads locally (SQLite) with card photos on
device; syncs to the cloud server via a manual Sync button when internet is
available. `capture.html` (served at `/`) acts as a browser fallback for
devices without the app.

### Lead Server
A stateless **Node/Express gateway** running on a DigitalOcean droplet. It is
the single front door to Supabase — normalises phone numbers, stores card
photos in Supabase Storage, and upserts lead rows in Supabase Postgres.
Secrets (Supabase, Gemini) are held only server-side. A droplet restart loses
no data — all state lives in Supabase.

### Follow-up
Contacting a Lead after the event via WhatsApp. Done from the Dashboard, one
Lead at a time, using a `wa.me` click-to-chat link that opens WhatsApp with a
pre-filled message. A human reviews and sends each one manually (no bulk /
automated send — that gets the number banned and needs the paid Business
API). One fixed message Template, editable before a send-session if needed.
Requires internet.

### Backup
Leads are durable in **Supabase** (Postgres + Storage) as soon as the Flutter
app's Sync button is pressed. There is no separate backup step — Supabase is
the primary datastore, not a secondary copy. The server is stateless and holds
no local data; a droplet restart or replacement loses nothing.

### LAN-only / Offline
These terms no longer describe the system. **Offline** now means the Flutter
app works without internet during the event, storing leads locally on the
device. **Sync** (the in-app button) uploads accumulated leads to the cloud
server when internet is available. There is no LAN, no central PC, no
peer-to-peer sync. The architecture is Flutter app → cloud server (droplet) →
Supabase. This supersedes the no-internet premise of
[ADR 0001](docs/adr/0001-lan-client-server-not-peer-to-peer.md); see the
[online lead capture design spec](docs/superpowers/specs/2026-06-26-online-lead-capture-design.md)
for the authoritative current architecture.
