# 2. Defer OCR to online v2 enrichment, do not OCR at capture

Date: 2026-06-23

## Status

Accepted

## Context

A headline idea was to OCR the visitor's card at the stall and auto-fill the
lead's fields. But capture happens with no internet, so any OCR done at the
stall must run on-device/offline. Offline OCR on a phone-camera shot of a
glossy business card is mediocre — it misreads digits and merges lines. The
one field that must be exact is the phone number, because it is the WhatsApp
key; a wrong digit means a lead we can never reach. So every OCR result would
have to be hand-verified anyway.

## Decision

- **v1 capture (offline, at the stall):** no OCR. Staff snap a photo of the
  card (front, plus optional back) and type the phone number by hand. Phone is
  the only mandatory field; everything else is optional and can be left blank.
- **v2 enrichment (online, from the dashboard):** once internet is available,
  a per-lead "enrich" action runs a real cloud/vision OCR on the stored card
  photo(s) to fill fields left blank at capture. Best-effort — any field it
  cannot read is skipped, never guessed. Capturing both sides of the card in
  v1 exists to feed this.

## Consequences

- Capture stays fast and 100% reliable at a busy stall: snap + type a number,
  ~5 seconds, no waiting on a flaky offline OCR engine.
- We get *better* OCR than the offline approach would have, because v2 runs
  against a real cloud model — at the cost of a later, deliberate enrichment
  pass instead of instant auto-fill.
- The card photo must be stored at a resolution good enough for later OCR. The
  ~1280px downscale chosen for upload size is also the OCR input; if it proves
  too low for reliable OCR, the downscale target must be raised.
- v1 data will have many blank fields until enrichment runs. The dashboard and
  any export must tolerate sparse leads.
