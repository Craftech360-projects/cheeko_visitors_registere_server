# 1. LAN client–server, not peer-to-peer (no LocalSend/WebRTC)

Date: 2026-06-23

## Status

Accepted

## Context

The brief was "capture leads at an event stall with no internet, on phones,
saved locally." The first instinct was to make the phones peer-to-peer and
sync between them using the LocalSend protocol over WebRTC, with an offline
local database on each phone.

The decisive fact emerged during design: there *is* a central PC available on
the same local network as the phones. "No internet" means no WAN — it does not
mean no LAN. The phones and the PC can all talk to each other over a router or
the PC's hotspot.

## Decision

Use a plain **client–server** architecture over the LAN:

- One PC is the single **Lead Server** (Node + Express). It holds the one
  SQLite database and the photos, and serves both the capture page and the
  dashboard.
- Phones are dumb clients: a browser pointed at `http://<lan-ip>:8080`. No
  installed app, no per-phone database, no sync.

We explicitly do **not** use LocalSend, WebRTC, peer-to-peer discovery, or
per-device offline storage.

## Consequences

- Drastically less to build: no sync protocol, no conflict resolution, no
  per-device storage, no peer discovery. There is exactly one copy of the
  data and one writer of record.
- The Lead Server is a single point of failure during the event. Mitigated by
  the Backup tiers (hourly local copy + end-of-day USB; optional cloud), not
  by replication.
- Depends on the venue LAN existing and being stable. If there were genuinely
  no shared network at all (only phones, no PC), this decision would have to
  be revisited and the peer-to-peer approach reconsidered.
- The phones need the PC's current LAN IP. Handled by generating a QR code
  from the IP the server detects at startup, not a hardcoded address.
