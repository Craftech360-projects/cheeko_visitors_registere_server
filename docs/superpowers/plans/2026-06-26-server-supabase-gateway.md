# Server: Supabase Gateway Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the Node server into a stateless gateway over Supabase (Postgres rows + Storage photos), replacing SQLite, `/qr`, and on-disk backups.

**Architecture:** Express stays, but all persistence moves to a single Supabase data-access module (`lib/db.js`). Routes accept the same JSON the existing frontend sends; `id` becomes a client-suppliable UUID so the upcoming Flutter app can assign it offline and the server can upsert idempotently. Photos go to Supabase Storage; their public URLs are stored on each row.

**Tech Stack:** Node 18+ (CommonJS), Express, `@supabase/supabase-js`, Supabase (Postgres + Storage), Gemini (OCR, unchanged), `node --test`.

## Global Constraints

- CommonJS (`require`), Node's built-in `node --test` runner, no extra test frameworks.
- No auth — the server is fully open by design (`add a SYNC_TOKEN header later if the URL leaks`).
- Supabase is the only datastore. No SQLite, no on-disk `photos/`, no local backups.
- `id` is a UUID string (client-supplied; server generates one with `crypto.randomUUID()` when absent).
- Upsert must **omit blank fields** so a re-uploaded lead never overwrites server-side enrichment with blanks.
- Keep the existing frontend JSON contract: `POST /api/leads` accepts `{ id?, phone, name, company, email, website, city, state, products, note, tag, frontPhoto, backPhoto, created_at? }` (photos as base64 data URLs).
- Phone normalization stays server-side via `lib/phone.js` `normalizeForWa` (single source of truth).

---

### Task 1: Supabase schema + Storage bucket

**Files:**
- Modify: `supabase-schema.sql`

**Interfaces:**
- Produces: a `leads` table keyed on `id uuid` and a `settings` table (`key`, `value`). All later tasks read/write these.

- [ ] **Step 1: Rewrite `supabase-schema.sql`**

```sql
-- Visitors Register → Supabase setup (run in Supabase Studio → SQL Editor).
-- Then create a Storage bucket named "cards" (Storage → New bucket → Public).
-- Put SUPABASE_URL + SUPABASE_SECRET_KEY (+ optional SUPABASE_BUCKET) in .env.
-- The server uses the secret key (bypasses RLS), so no RLS policies are needed.

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
  enriched_at timestamptz,              -- set when OCR ran (null = pending)
  created_at  timestamptz
);

create index if not exists leads_created_at_idx on public.leads (created_at desc);

-- Editable WhatsApp follow-up template (moved off SQLite).
create table if not exists public.settings (
  key   text primary key,
  value text
);
```

- [ ] **Step 2: Apply it**

Run the SQL in Supabase Studio → SQL Editor. In Storage, create a **Public** bucket named `cards`.
Expected: `leads` and `settings` tables exist; `cards` bucket listed.

- [ ] **Step 3: Commit**

```bash
git add supabase-schema.sql
git commit -m "schema: uuid id + settings table for stateless server"
```

---

### Task 2: Swap dependencies

**Files:**
- Modify: `package.json`

**Interfaces:**
- Produces: `@supabase/supabase-js` available to `require`; `better-sqlite3` and `qrcode` gone.

- [ ] **Step 1: Edit `package.json` dependencies**

Replace the `dependencies` block with:

```json
  "dependencies": {
    "@supabase/supabase-js": "^2.45.0",
    "express": "^4.21.0"
  }
```

(Removes `better-sqlite3` and `qrcode`.)

- [ ] **Step 2: Install**

Run: `npm install`
Expected: installs `@supabase/supabase-js`, removes the two packages, exits 0.

- [ ] **Step 3: Verify it loads**

Run: `node -e "require('@supabase/supabase-js'); console.log('ok')"`
Expected: prints `ok`.

- [ ] **Step 4: Commit**

```bash
git add package.json package-lock.json
git commit -m "deps: add supabase-js, drop better-sqlite3 + qrcode"
```

---

### Task 3: Supabase data-access module (`lib/db.js`)

**Files:**
- Create: `lib/db.js`
- Test: `test/db.test.js`

**Interfaces:**
- Consumes: `leadToRow` from `lib/supabase.js`.
- Produces:
  - `omitBlank(obj, keep[])` → new object without null/`""` values except keys in `keep`.
  - `buildUpsertRow(lead, urls)` → row object for upsert (blank fields omitted; `id`, `phone`, `wa_phone`, `created_at` always kept).
  - `dataUrlToBuffer(dataUrl)` → `{ buf, mime }` or `null`.
  - `async uploadPhoto(dataUrl, name, c?)` → public URL string, or `null` if no photo.
  - `async upsertLead(lead, urls, c?)` → void.
  - `async getLeads(c?)` / `async getLead(id, c?)` / `async getPending(c?)` → rows.
  - `async updateFields(id, fields, c?)` → void.
  - `async getTemplate(c?)` / `async setTemplate(value, c?)`.
  - `c?` is an optional Supabase client for tests; production uses the lazily-built default.

- [ ] **Step 1: Write the failing test**

Create `test/db.test.js`:

```js
const { test } = require("node:test");
const assert = require("node:assert");
const { omitBlank, buildUpsertRow, dataUrlToBuffer } = require("../lib/db");

test("omitBlank drops null/empty but keeps protected keys", () => {
  const r = omitBlank({ id: "u1", name: "", company: null, city: "Pune" }, ["id"]);
  assert.deepStrictEqual(r, { id: "u1", city: "Pune" });
});

test("buildUpsertRow keeps id/phone/wa_phone/created_at, drops blank optionals", () => {
  const row = buildUpsertRow(
    { id: "u1", phone: "9744187790", wa_phone: "919744187790",
      created_at: "2026-06-26T10:00:00Z", name: "", company: "Acme", note: null },
    { frontUrl: "http://x/u1-front.jpg", backUrl: null }
  );
  assert.strictEqual(row.id, "u1");
  assert.strictEqual(row.wa_phone, "919744187790");
  assert.strictEqual(row.company, "Acme");
  assert.strictEqual(row.front_url, "http://x/u1-front.jpg");
  assert.ok(!("name" in row));      // blank optional dropped
  assert.ok(!("note" in row));      // null optional dropped
  assert.ok(!("back_url" in row));  // null url dropped (preserves server value on re-upsert)
});

test("dataUrlToBuffer decodes base64 and detects mime", () => {
  // 1x1 transparent PNG
  const png = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M8AAAMBAQDJ/pZ3AAAAAElFTkSuQmCC";
  const out = dataUrlToBuffer(png);
  assert.strictEqual(out.mime, "image/png");
  assert.ok(out.buf[0] === 0x89 && out.buf[1] === 0x50); // PNG magic
  assert.strictEqual(dataUrlToBuffer("not-a-data-url"), null);
  assert.strictEqual(dataUrlToBuffer(null), null);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test test/db.test.js`
Expected: FAIL — `Cannot find module '../lib/db'`.

- [ ] **Step 3: Write `lib/db.js`**

```js
// All Supabase access lives here so routes stay readable and the row-shaping
// logic stays unit-testable with a fake client. Network calls are the only
// thing in this file that needs a live Supabase.
const { createClient } = require("@supabase/supabase-js");
const { leadToRow } = require("./supabase");

const BUCKET = process.env.SUPABASE_BUCKET || "cards";
const PROTECTED = ["id", "phone", "wa_phone", "created_at"];

let _client;
function client() {
  if (_client) return _client;
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_KEY;
  if (!url || !key) throw new Error("supabase_not_configured");
  _client = createClient(url, key, { auth: { persistSession: false } });
  return _client;
}

const isBlank = (v) => v == null || String(v).trim() === "";

// Drop null/empty values so a re-upsert never overwrites server data (e.g.
// OCR-filled fields) with blanks. `keep` columns survive even if blank.
function omitBlank(obj, keep = []) {
  const out = {};
  for (const [k, v] of Object.entries(obj)) {
    if (keep.includes(k) || !isBlank(v)) out[k] = v;
  }
  return out;
}

function buildUpsertRow(lead, urls = {}) {
  const full = leadToRow(lead, urls); // all columns, nulls for missing
  // enriched_at is server-owned; never let an upload set/clear it.
  delete full.enriched_at;
  return omitBlank(full, PROTECTED);
}

// "data:image/jpeg;base64,...." -> { buf, mime }. null if not a data URL.
function dataUrlToBuffer(dataUrl) {
  if (!dataUrl || typeof dataUrl !== "string" || !dataUrl.startsWith("data:")) return null;
  const buf = Buffer.from(dataUrl.slice(dataUrl.indexOf(",") + 1), "base64");
  const mime = buf[0] === 0x89 && buf[1] === 0x50 ? "image/png" : "image/jpeg";
  return { buf, mime };
}

async function uploadPhoto(dataUrl, name, c = client()) {
  const dec = dataUrlToBuffer(dataUrl);
  if (!dec) return null;
  const { error } = await c.storage
    .from(BUCKET)
    .upload(name, dec.buf, { contentType: dec.mime, upsert: true });
  if (error) throw new Error(`storage upload ${name}: ${error.message}`);
  return c.storage.from(BUCKET).getPublicUrl(name).data.publicUrl;
}

async function upsertLead(lead, urls, c = client()) {
  const row = buildUpsertRow(lead, urls);
  const { error } = await c.from("leads").upsert(row, { onConflict: "id" });
  if (error) throw new Error(`upsert ${row.id}: ${error.message}`);
}

async function getLeads(c = client()) {
  const { data, error } = await c.from("leads").select("*").order("created_at", { ascending: false });
  if (error) throw new Error(`getLeads: ${error.message}`);
  return data;
}

async function getLead(id, c = client()) {
  const { data, error } = await c.from("leads").select("*").eq("id", id).maybeSingle();
  if (error) throw new Error(`getLead: ${error.message}`);
  return data;
}

async function getPending(c = client()) {
  const { data, error } = await c.from("leads")
    .select("*").is("enriched_at", null).not("front_url", "is", null);
  if (error) throw new Error(`getPending: ${error.message}`);
  return data;
}

async function updateFields(id, fields, c = client()) {
  const { error } = await c.from("leads").update(fields).eq("id", id);
  if (error) throw new Error(`updateFields ${id}: ${error.message}`);
}

async function getTemplate(c = client()) {
  const { data, error } = await c.from("settings").select("value").eq("key", "template").maybeSingle();
  if (error) throw new Error(`getTemplate: ${error.message}`);
  return data ? data.value : null;
}

async function setTemplate(value, c = client()) {
  const { error } = await c.from("settings").upsert({ key: "template", value }, { onConflict: "key" });
  if (error) throw new Error(`setTemplate: ${error.message}`);
}

module.exports = {
  omitBlank, buildUpsertRow, dataUrlToBuffer, uploadPhoto, upsertLead,
  getLeads, getLead, getPending, updateFields, getTemplate, setTemplate, BUCKET,
};
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test test/db.test.js`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/db.js test/db.test.js
git commit -m "feat: Supabase data-access module with blank-preserving upsert"
```

---

### Task 4: Rewrite `server.js` onto `lib/db.js`

**Files:**
- Modify: `server.js` (full rewrite)

**Interfaces:**
- Consumes: everything from `lib/db.js`; `normalizeForWa`, `toCsv`, `mergeEnrichment`, `parseOcrJson`.
- Produces: routes `GET /`, `GET /dashboard`, `POST /api/leads`, `GET /api/leads`, `POST /api/leads/:id/enrich`, `POST /api/enrich-all`, `GET /export.csv`, `GET /api/template`, `POST /api/template`. (No `/qr`, no `/api/sync`.)

- [ ] **Step 1: Replace `server.js` entirely**

```js
const path = require("path");
const crypto = require("crypto");
const express = require("express");
const { normalizeForWa } = require("./lib/phone");
const { toCsv } = require("./lib/csv");
const { mergeEnrichment, parseOcrJson } = require("./lib/enrich");
const db = require("./lib/db");

const PORT = process.env.PORT || 8080;
const ROOT = __dirname;

const app = express();
app.use((req, res, next) => {
  const t = Date.now();
  res.on("finish", () => console.log(`${req.method} ${req.url} → ${res.statusCode} (${Date.now() - t}ms)`));
  next();
});
app.use(express.json({ limit: "8mb" })); // downscaled photos arrive as base64 JSON
app.use(express.static(path.join(ROOT, "public")));

app.get("/", (_req, res) => res.sendFile(path.join(ROOT, "public", "capture.html")));
app.get("/dashboard", (_req, res) => res.sendFile(path.join(ROOT, "public", "dashboard.html")));

// Create/replace a lead. Phone is the only required field. Idempotent: re-sending
// the same id upserts (never duplicates). Photos -> Storage, urls onto the row.
app.post("/api/leads", async (req, res) => {
  const b = req.body || {};
  const wa = normalizeForWa(b.phone);
  if (!wa) return res.status(400).json({ error: "invalid_phone" });
  const id = typeof b.id === "string" && b.id ? b.id : crypto.randomUUID();
  try {
    const frontUrl = await db.uploadPhoto(b.frontPhoto, `${id}-front.jpg`);
    const backUrl = await db.uploadPhoto(b.backPhoto, `${id}-back.jpg`);
    await db.upsertLead(
      {
        id, phone: String(b.phone).trim(), wa_phone: wa,
        name: b.name, company: b.company, email: b.email, website: b.website,
        city: b.city, state: b.state, products: b.products, note: b.note, tag: b.tag,
        created_at: b.created_at || new Date().toISOString(),
      },
      { frontUrl, backUrl }
    );
    res.json({ id, wa_phone: wa });
  } catch (e) {
    console.error("[POST /api/leads]", e.message);
    res.status(502).json({ error: "save_failed" });
  }
});

app.get("/api/leads", async (_req, res) => {
  try { res.json(await db.getLeads()); }
  catch (e) { console.error("[GET /api/leads]", e.message); res.status(502).json({ error: "read_failed" }); }
});

// OCR core (ADR 0002): fill a lead's BLANK fields from its card photo(s), stamp
// enriched_at. Photos are fetched from their Storage URLs. Throws Error with
// .code ("no_photo" | "ocr_failed").
async function enrichLead(lead) {
  const key = process.env.GOOGLE_API_KEY;
  const images = [];
  for (const url of [lead.front_url, lead.back_url]) {
    if (!url) continue;
    try {
      const r = await fetch(url);
      if (!r.ok) continue;
      const buf = Buffer.from(await r.arrayBuffer());
      const mime = buf[0] === 0x89 && buf[1] === 0x50 ? "image/png" : "image/jpeg";
      images.push({ data: buf.toString("base64"), mime });
    } catch { /* unreachable photo: skip */ }
  }
  if (!images.length) { const e = new Error("no_photo"); e.code = "no_photo"; throw e; }

  const prompt =
    "This is a business/visiting card. Extract these fields as JSON: " +
    '{"name":..., "company":..., "email":..., "website":..., "city":..., "state":..., "products":...}. ' +
    "Use null for any field that is not clearly legible. Do not guess.";
  const model = process.env.OCR_MODEL || "gemini-2.5-flash";
  const parts = images.map((im) => ({ inline_data: { mime_type: im.mime, data: im.data } }));
  parts.push({ text: prompt });

  const r = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
    {
      method: "POST",
      headers: { "x-goog-api-key": key, "content-type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts }],
        generationConfig: { responseMimeType: "application/json", maxOutputTokens: 800, thinkingConfig: { thinkingBudget: 0 } },
      }),
    }
  );
  if (!r.ok) {
    const body = await r.text().catch(() => "");
    console.error(`[enrich ${lead.id}] Gemini ${r.status}: ${body.slice(0, 300)}`);
    const e = new Error("ocr_failed"); e.code = "ocr_failed"; e.status = r.status; throw e;
  }
  const data = await r.json();
  const c = data.candidates && data.candidates[0];
  const text = c && c.content && c.content.parts && c.content.parts[0] && c.content.parts[0].text;
  const { updates, filled } = mergeEnrichment(lead, parseOcrJson(text));
  await db.updateFields(lead.id, { ...updates, enriched_at: new Date().toISOString() });
  console.log(`[enrich ${lead.id}] filled: ${filled.join(", ") || "(none)"}`);
  return { filled };
}

app.post("/api/leads/:id/enrich", async (req, res) => {
  if (!process.env.GOOGLE_API_KEY) return res.status(400).json({ error: "ocr_not_configured" });
  try {
    const lead = await db.getLead(req.params.id);
    if (!lead) return res.status(404).json({ error: "not_found" });
    const { filled } = await enrichLead(lead);
    res.json({ filled });
  } catch (e) {
    if (e.code === "no_photo") return res.status(400).json({ error: "no_photo" });
    if (e.code === "ocr_failed") return res.status(502).json({ error: "ocr_failed", status: e.status });
    console.error("[enrich]", e.message);
    res.status(502).json({ error: String(e.message) });
  }
});

app.post("/api/enrich-all", async (_req, res) => {
  if (!process.env.GOOGLE_API_KEY) return res.status(400).json({ error: "ocr_not_configured" });
  try {
    const pending = await db.getPending();
    let enriched = 0;
    const errors = [];
    for (const lead of pending) {
      try { await enrichLead(lead); enriched++; }
      catch (e) { errors.push(`${lead.id}: ${e.code || e.message}`); }
    }
    console.log(`[enrich-all] ${enriched}/${pending.length} enriched${errors.length ? ", " + errors.length + " failed" : ""}`);
    res.json({ enriched, total: pending.length, errors });
  } catch (e) {
    console.error("[enrich-all]", e.message);
    res.status(502).json({ error: "read_failed" });
  }
});

app.get("/export.csv", async (_req, res) => {
  try {
    const rows = await db.getLeads();
    const stamp = new Date().toISOString().slice(0, 10);
    res.setHeader("Content-Type", "text/csv; charset=utf-8");
    res.setHeader("Content-Disposition", `attachment; filename="leads-${stamp}.csv"`);
    res.send("﻿" + toCsv(rows)); // BOM so Excel reads UTF-8
  } catch (e) {
    console.error("[export.csv]", e.message);
    res.status(502).send("export failed");
  }
});

app.get("/api/template", async (_req, res) => {
  const DEFAULT = "Hi {name}, great meeting you at our stall! Here's our catalogue — would love to work with you.";
  try { res.json({ template: (await db.getTemplate()) || DEFAULT }); }
  catch (e) { console.error("[GET template]", e.message); res.status(502).json({ error: "read_failed" }); }
});

app.post("/api/template", async (req, res) => {
  const t = (req.body && req.body.template) || "";
  try { await db.setTemplate(t); res.json({ template: t }); }
  catch (e) { console.error("[POST template]", e.message); res.status(502).json({ error: "save_failed" }); }
});

app.listen(PORT, "0.0.0.0", () => {
  const base = process.env.PUBLIC_URL || `http://localhost:${PORT}`;
  console.log(`Visitors Register (cloud) running on :${PORT}`);
  console.log(`  Capture (browser fallback): ${base}/`);
  console.log(`  Dashboard:                  ${base}/dashboard`);
  console.log(`  OCR (Enrich):  ${process.env.GOOGLE_API_KEY ? "enabled (Gemini)" : "disabled — set GOOGLE_API_KEY"}`);
  console.log(`  Supabase:      ${process.env.SUPABASE_URL ? "configured" : "NOT configured — set SUPABASE_URL + SUPABASE_SECRET_KEY"}`);
});

module.exports = { enrichLead }; // exported for future tests
```

- [ ] **Step 2: Update the CSV columns to use Storage URLs**

In `lib/csv.js`, change the `COLUMNS` array: replace `"front_photo", "back_photo"` with `"front_url", "back_url"`.

```js
const COLUMNS = [
  "id", "name", "company", "email", "website", "phone", "wa_phone", "city", "state",
  "products", "note", "tag", "enriched_at", "front_url", "back_url", "created_at",
];
```

- [ ] **Step 3: Run the full unit suite (pure logic must still pass)**

Run: `npm test`
Expected: PASS — `phone`, `csv`, `enrich`, `supabase`, `db` tests all green. (No network in these.)

- [ ] **Step 4: Smoke-test against real Supabase**

With `.env` holding `SUPABASE_URL` + `SUPABASE_SECRET_KEY`, run `npm start` in one terminal, then in another:

```bash
curl -s -X POST http://localhost:8080/api/leads -H "Content-Type: application/json" \
  -d '{"phone":"9744187790","name":"Smoke Test"}'
curl -s http://localhost:8080/api/leads
```
Expected: first returns `{"id":"<uuid>","wa_phone":"919744187790"}`; second lists the lead. Confirm the row appears in Supabase Studio → `leads`.

- [ ] **Step 5: Commit**

```bash
git add server.js lib/csv.js
git commit -m "feat: stateless server over Supabase; drop SQLite/qr/backups/sync"
```

---

### Task 5: Update dashboard for Storage URLs + UUID ids; drop the Sync button

**Files:**
- Modify: `public/dashboard.html`

**Interfaces:**
- Consumes: `GET /api/leads` rows now carry `front_url` / `back_url` (full URLs) and string `id`.

- [ ] **Step 1: Photo references → `front_url` / `back_url`**

In `public/dashboard.html`, the thumbnail and photo links currently build `/${l.front_photo}`. Storage URLs are absolute, so use them directly:

- Line ~136–137 (thumbnail):
```js
    const thumb = l.front_url
      ? `<a href="${l.front_url}" target="_blank"><img class="thumb" src="${l.front_url}"></a>`
      : "";
```
- Line ~144 "pending" badge: replace `l.front_photo` with `l.front_url`.
- Line ~152 Enrich button: replace `l.front_photo` with `l.front_url`, **and quote the id** (it is now a UUID string, not a number):
```js
              ${l.front_url ? `<button class="btn be" onclick="enrich('${l.id}',this)">${l.enriched_at ? "↻ Re-enrich" : "✨ Enrich"}</button>` : ""}
```
- Lines ~176–177 (detail panel): replace `l.front_photo` → `l.front_url`, `l.back_photo` → `l.back_url`, and drop the leading `/` so the hrefs are `${l.front_url}` / `${l.back_url}`.

- [ ] **Step 2: Make `enrich()` accept a string id**

Find `async function enrich(id, btn)` and confirm it interpolates `` `/api/leads/${id}/enrich` `` — it already does, and a UUID string works unchanged. No edit needed beyond Step 1's quoting.

- [ ] **Step 3: Remove the "Sync to Supabase" button and its handler**

The data already lives in Supabase, so `/api/sync` no longer exists. Delete the button element that calls the sync handler (around line 97's `fetch("/api/sync"...)` function and its triggering button in the toolbar). Leave "Enrich all", "Export CSV", and the template editor intact.

- [ ] **Step 4: Manual verify in browser**

Run `npm start`, open `http://localhost:8080/dashboard`.
Expected: the smoke-test lead shows; if it has a photo the thumbnail loads from the Supabase URL; no "Sync to Supabase" button remains; no console errors.

- [ ] **Step 5: Commit**

```bash
git add public/dashboard.html
git commit -m "dashboard: use Storage URLs + string ids, drop redundant Sync button"
```

---

### Task 6: Docs + cleanup

**Files:**
- Modify: `README.md`, `CONTEXT.md`, `.gitignore`

**Interfaces:** none (documentation).

- [ ] **Step 1: README** — replace the "Run / LAN / QR / pre-venue checklist / local backup" sections with cloud instructions: set `.env` (`SUPABASE_URL`, `SUPABASE_SECRET_KEY`, optional `SUPABASE_BUCKET`, `GOOGLE_API_KEY`, optional `PUBLIC_URL`), `npm install`, `npm start`; the Flutter app is the capture device, `capture.html` is the browser fallback, dashboard for review/enrich/CSV. Remove SQLite/USB-backup wording (Supabase is the store).

- [ ] **Step 2: CONTEXT.md** — update the "LAN-only / Offline" and "Backup" glossary entries: capture is now offline-on-device (Flutter) with manual upload to a cloud server; Supabase is the datastore. Note this supersedes ADR 0001 (link the new spec).

- [ ] **Step 3: .gitignore** — remove `photos/` and `visitors.db`/`backups/` lines (no longer produced). Keep `.env`, `node_modules/`.

- [ ] **Step 4: Commit**

```bash
git add README.md CONTEXT.md .gitignore
git commit -m "docs: cloud run instructions; retire LAN/SQLite/backup wording"
```

---

## Self-Review

- **Spec coverage:** Supabase-as-DB (Tasks 1,3,4) ✓; Storage photos (Task 3,4) ✓; uuid client id + upsert (Tasks 1,3,4) ✓; phone normalized server-side (Task 4) ✓; drop SQLite/qr/backups/LAN-IP/sync (Tasks 2,4,5) ✓; keep capture.html fallback (Task 4 serves `/`) ✓; enrich from Storage URL (Task 4) ✓; CSV uses front_url/back_url (Task 4) ✓; template moved to Supabase settings (Tasks 1,3,4) ✓; blank-preserving upsert protects server enrichment (Task 3) ✓.
- **Edge:** editing an already-enriched lead on the phone re-sends blank optionals — `buildUpsertRow` omits blanks so server-side OCR values survive; `enriched_at` is deleted from the upsert payload entirely (server-owned).
- **Type consistency:** `id` is a string everywhere (route, db.js, dashboard onclick quoted). `front_url`/`back_url` used consistently in db.js, csv.js, dashboard.html.
- **Placeholders:** none — every step has full code or an exact command.
