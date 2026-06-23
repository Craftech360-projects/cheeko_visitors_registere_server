# Visitors Register — Context

A tool for capturing sales leads at a physical event stall, where there is a
local network but **no internet access**. Leads are captured on phones,
stored on a central PC, reviewed on a dashboard, and contacted later (when
internet is available) via one-tap WhatsApp.

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
A phone (or tablet) used by stall staff to capture Leads. Runs nothing but a
web browser pointed at the Lead Server. Multiple Capture Devices may run at
once.

### Lead Server
A single PC on the event's local network. Holds the one database of Leads and
serves both the capture page and the dashboard to Capture Devices over LAN
HTTP. There is exactly one Lead Server. No internet required for capture.

### Follow-up
Contacting a Lead after the event via WhatsApp. Done from the Dashboard, one
Lead at a time, using a `wa.me` click-to-chat link that opens WhatsApp with a
pre-filled message. A human reviews and sends each one manually (no bulk /
automated send — that gets the number banned and needs the paid Business
API). One fixed message Template, editable before a send-session if needed.
Requires internet.

### Backup
Protecting captured Leads against loss of the single Lead Server. Two tiers:
- **Local (primary, offline):** the Lead Server auto-copies `visitors.db` to a
  `backups/` folder hourly; staff drag `visitors.db` + `photos/` to a USB at
  end of day. This is the only tier that works *at the venue* (no internet).
- **Cloud (secondary, online-only):** an opportunistic Dashboard action that
  pushes the database and photos to a Supabase Storage bucket whenever
  internet is available. Optional, off until configured. A bonus copy, never
  the primary safety net.

### LAN-only / Offline
"Offline" means **no internet (WAN)**, NOT "no network". The Lead Server and
Capture Devices share a local network (router or PC hotspot). Therefore there
is no peer-to-peer sync — it is plain client–server over LAN. (This is why
LocalSend / WebRTC are not used.)
