const fs = require("fs");
const path = require("path");
const express = require("express");
const Database = require("better-sqlite3");
const QRCode = require("qrcode");
const { normalizeForWa } = require("./lib/phone");
const { lanIp } = require("./lib/net");
const { toCsv } = require("./lib/csv");
const { mergeEnrichment, parseOcrJson } = require("./lib/enrich");
const { leadToRow } = require("./lib/supabase");

const PORT = process.env.PORT || 8080;
const ROOT = __dirname;
const PHOTO_DIR = path.join(ROOT, "photos");
const BACKUP_DIR = path.join(ROOT, "backups");
const DB_PATH = path.join(ROOT, "visitors.db");
fs.mkdirSync(PHOTO_DIR, { recursive: true });
fs.mkdirSync(BACKUP_DIR, { recursive: true });

const db = new Database(DB_PATH);
db.pragma("journal_mode = WAL"); // safe concurrent writes from several phones
db.exec(`
  CREATE TABLE IF NOT EXISTS leads (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    phone TEXT NOT NULL,
    wa_phone TEXT,
    name TEXT, company TEXT, email TEXT, website TEXT, city TEXT, state TEXT, products TEXT, note TEXT,
    tag TEXT,
    front_photo TEXT, back_photo TEXT,
    enriched_at TEXT,
    created_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT);
`);
// Migrations for DBs created before these columns existed.
for (const col of ["email", "website", "state", "enriched_at"]) {
  try { db.exec(`ALTER TABLE leads ADD COLUMN ${col} TEXT`); } catch { /* already present */ }
}

const DEFAULT_TEMPLATE =
  "Hi {name}, great meeting you at our stall! Here's our catalogue — would love to work with you.";
function getTemplate() {
  const row = db.prepare("SELECT value FROM settings WHERE key='template'").get();
  return row ? row.value : DEFAULT_TEMPLATE;
}

// Save a base64 data-URL photo to photos/<id>-<side>.jpg, return relative path.
function savePhoto(dataUrl, id, side) {
  if (!dataUrl || typeof dataUrl !== "string" || !dataUrl.startsWith("data:")) return null;
  const b64 = dataUrl.slice(dataUrl.indexOf(",") + 1);
  const file = `${id}-${side}.jpg`;
  fs.writeFileSync(path.join(PHOTO_DIR, file), Buffer.from(b64, "base64"));
  return "photos/" + file;
}

// --- Supabase sync (online-only, optional). Push leads -> table, photos -> bucket. ---
function supaConfig() {
  const url = process.env.SUPABASE_URL;
  // New Supabase naming is SUPABASE_SECRET_KEY; fall back to the older service_role name.
  const key = process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_KEY;
  if (!url || !key) return null;
  return { url, key, bucket: process.env.SUPABASE_BUCKET || "cards" };
}

// Upload one photo to the bucket (upsert), return its public URL. null if no file.
async function uploadPhoto(supa, relPath) {
  if (!relPath) return null;
  let buf;
  try { buf = fs.readFileSync(path.join(ROOT, relPath)); } catch { return null; }
  const name = path.basename(relPath); // e.g. "3-front.jpg"
  const mime = buf[0] === 0x89 && buf[1] === 0x50 ? "image/png" : "image/jpeg";
  const r = await fetch(`${supa.url}/storage/v1/object/${supa.bucket}/${name}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${supa.key}`, apikey: supa.key, "Content-Type": mime, "x-upsert": "true" },
    body: buf,
  });
  if (!r.ok) throw new Error(`storage ${r.status}: ${(await r.text().catch(() => "")).slice(0, 200)}`);
  return `${supa.url}/storage/v1/object/public/${supa.bucket}/${name}`;
}

// Upsert a single lead (photos + row) into Supabase. Keyed on id -> updates, never duplicates.
async function syncLead(supa, lead) {
  const frontUrl = await uploadPhoto(supa, lead.front_photo);
  const backUrl = await uploadPhoto(supa, lead.back_photo);
  const row = leadToRow(lead, { frontUrl, backUrl });
  const r = await fetch(`${supa.url}/rest/v1/leads?on_conflict=id`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${supa.key}`, apikey: supa.key,
      "Content-Type": "application/json", Prefer: "resolution=merge-duplicates,return=minimal",
    },
    body: JSON.stringify([row]),
  });
  if (!r.ok) throw new Error(`upsert ${r.status}: ${(await r.text().catch(() => "")).slice(0, 200)}`);
}

const app = express();
// Request log: method, path, status, duration — so the console shows activity.
app.use((req, res, next) => {
  const t = Date.now();
  res.on("finish", () => console.log(`${req.method} ${req.url} → ${res.statusCode} (${Date.now() - t}ms)`));
  next();
});
app.use(express.json({ limit: "8mb" })); // downscaled photos arrive as base64 JSON
app.use(express.static(path.join(ROOT, "public")));
app.use("/photos", express.static(PHOTO_DIR));

app.get("/", (_req, res) => res.sendFile(path.join(ROOT, "public", "capture.html")));
app.get("/dashboard", (_req, res) => res.sendFile(path.join(ROOT, "public", "dashboard.html")));

// Create a lead. Phone is the only required field. Soft-warn on duplicate:
// if the phone already exists and the client didn't pass confirm, return 409.
app.post("/api/leads", (req, res) => {
  const b = req.body || {};
  const wa = normalizeForWa(b.phone);
  if (!wa) return res.status(400).json({ error: "invalid_phone" });

  if (!b.confirm) {
    const dup = db.prepare("SELECT id FROM leads WHERE wa_phone=?").get(wa);
    if (dup) return res.status(409).json({ duplicate: true });
  }

  const info = db
    .prepare(
      `INSERT INTO leads (phone, wa_phone, name, company, email, website, city, state, products, note, tag, created_at)
       VALUES (@phone,@wa,@name,@company,@email,@website,@city,@state,@products,@note,@tag,@created_at)`
    )
    .run({
      phone: String(b.phone).trim(),
      wa,
      name: b.name || null,
      company: b.company || null,
      email: b.email || null,
      website: b.website || null,
      city: b.city || null,
      state: b.state || null,
      products: b.products || null,
      note: b.note || null,
      tag: b.tag || null,
      created_at: new Date().toISOString(),
    });

  const id = info.lastInsertRowid;
  const front = savePhoto(b.frontPhoto, id, "front");
  const back = savePhoto(b.backPhoto, id, "back");
  if (front || back) {
    db.prepare("UPDATE leads SET front_photo=?, back_photo=? WHERE id=?").run(front, back, id);
  }
  res.json({ id, wa_phone: wa });
});

app.get("/api/leads", (_req, res) => {
  res.json(db.prepare("SELECT * FROM leads ORDER BY created_at DESC").all());
});

// v2 (ADR 0002): OCR core. Fills a lead's BLANK fields from its card photo(s),
// stamps enriched_at (even if nothing was filled — it was attempted), and pushes
// to Supabase if configured. Throws Error with .code ("no_photo"|"ocr_failed").
// Shared by the single (✨) and bulk (Enrich all) routes.
async function enrichLead(lead) {
  const key = process.env.GOOGLE_API_KEY;
  const images = []; // {data, mime} for each card photo
  for (const p of [lead.front_photo, lead.back_photo]) {
    if (!p) continue;
    try {
      const buf = fs.readFileSync(path.join(ROOT, p));
      const mime = buf[0] === 0x89 && buf[1] === 0x50 ? "image/png" : "image/jpeg"; // PNG magic vs JPEG
      images.push({ data: buf.toString("base64"), mime });
    } catch { /* missing file: skip */ }
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
        generationConfig: {
          responseMimeType: "application/json",
          maxOutputTokens: 800,
          thinkingConfig: { thinkingBudget: 0 }, // OCR needs no reasoning; thinking ate the output budget
        },
      }),
    }
  );
  if (!r.ok) {
    const body = await r.text().catch(() => "");
    console.error(`[enrich #${lead.id}] Gemini ${r.status}: ${body.slice(0, 300)}`);
    const e = new Error("ocr_failed"); e.code = "ocr_failed"; e.status = r.status; throw e;
  }
  const data = await r.json();
  const c = data.candidates && data.candidates[0];
  const text = c && c.content && c.content.parts && c.content.parts[0] && c.content.parts[0].text;
  const ocr = parseOcrJson(text);
  const { updates, filled } = mergeEnrichment(lead, ocr); // filled ⊆ whitelisted fields
  const sets = filled.map((f) => `${f}=@${f}`).concat("enriched_at=@enriched_at");
  db.prepare(`UPDATE leads SET ${sets.join(", ")} WHERE id=@id`)
    .run({ ...updates, enriched_at: new Date().toISOString(), id: lead.id });
  console.log(`[enrich #${lead.id}] filled: ${filled.join(", ") || "(none)"}`);

  const supa = supaConfig(); // auto-push (best-effort; never fails the enrich)
  if (supa) {
    const fresh = db.prepare("SELECT * FROM leads WHERE id=?").get(lead.id);
    try { await syncLead(supa, fresh); console.log(`[enrich #${lead.id}] synced to Supabase`); }
    catch (e) { console.error(`[enrich #${lead.id}] Supabase sync failed:`, e.message); }
  }
  return { filled };
}

// Enrich one lead (the ✨ button). Internet + GOOGLE_API_KEY required.
app.post("/api/leads/:id/enrich", async (req, res) => {
  if (!process.env.GOOGLE_API_KEY) return res.status(400).json({ error: "ocr_not_configured" });
  const lead = db.prepare("SELECT * FROM leads WHERE id=?").get(req.params.id);
  if (!lead) return res.status(404).json({ error: "not_found" });
  try {
    const { filled } = await enrichLead(lead);
    res.json({ filled });
  } catch (e) {
    if (e.code === "no_photo") return res.status(400).json({ error: "no_photo" });
    if (e.code === "ocr_failed") return res.status(502).json({ error: "ocr_failed", status: e.status });
    console.error(`[enrich #${lead.id}] error:`, e);
    res.status(502).json({ error: String(e) });
  }
});

// Enrich ALL pending leads (have a photo, never enriched). The bulk button.
app.post("/api/enrich-all", async (_req, res) => {
  if (!process.env.GOOGLE_API_KEY) return res.status(400).json({ error: "ocr_not_configured" });
  const pending = db.prepare("SELECT * FROM leads WHERE enriched_at IS NULL AND front_photo IS NOT NULL").all();
  let enriched = 0;
  const errors = [];
  for (const lead of pending) {
    try { await enrichLead(lead); enriched++; }
    catch (e) { errors.push(`#${lead.id}: ${e.code || e.message}`); }
  }
  console.log(`[enrich-all] ${enriched}/${pending.length} enriched${errors.length ? ", " + errors.length + " failed" : ""}`);
  res.json({ enriched, total: pending.length, errors });
});

// Export all leads as a CSV download (open in Excel / Google Sheets).
app.get("/export.csv", (_req, res) => {
  const rows = db.prepare("SELECT * FROM leads ORDER BY created_at DESC").all();
  const stamp = new Date().toISOString().slice(0, 10);
  res.setHeader("Content-Type", "text/csv; charset=utf-8");
  res.setHeader("Content-Disposition", `attachment; filename="leads-${stamp}.csv"`);
  res.send("﻿" + toCsv(rows)); // BOM so Excel reads UTF-8 correctly
});

app.get("/api/template", (_req, res) => res.json({ template: getTemplate() }));
app.post("/api/template", (req, res) => {
  const t = (req.body && req.body.template) || "";
  db.prepare(
    "INSERT INTO settings(key,value) VALUES('template',?) ON CONFLICT(key) DO UPDATE SET value=?"
  ).run(t, t);
  res.json({ template: t });
});

// Stall QR: encodes the live LAN URL so phones just scan to open the capture page.
app.get("/qr", async (_req, res) => {
  const url = `http://${lanIp()}:${PORT}/`;
  const img = await QRCode.toDataURL(url, { width: 320, margin: 2 });
  res.send(
    `<!doctype html><meta name=viewport content="width=device-width,initial-scale=1">
     <body style="font-family:sans-serif;text-align:center;padding:40px">
     <h2>Scan to open the capture page</h2>
     <img src="${img}" alt="QR"><p style="font-size:20px"><a href="${url}">${url}</a></p>
     </body>`
  );
});

// Sync ALL leads to Supabase (rows + photos). Online-only, idempotent upsert.
// Catch-all for leads never enriched; enrich already auto-pushes each lead.
app.post("/api/sync", async (_req, res) => {
  const supa = supaConfig();
  if (!supa) return res.status(400).json({ error: "supabase_not_configured" });
  const leads = db.prepare("SELECT * FROM leads").all();
  let synced = 0;
  const errors = [];
  for (const lead of leads) {
    try { await syncLead(supa, lead); synced++; }
    catch (e) { errors.push(`#${lead.id}: ${e.message}`); console.error(`[sync #${lead.id}]`, e.message); }
  }
  console.log(`[sync] ${synced}/${leads.length} leads synced${errors.length ? ", " + errors.length + " failed" : ""}`);
  res.json({ synced, total: leads.length, errors });
});

// Primary backup: hourly timestamped copy of the DB (cheap, always-on, offline).
function localBackup() {
  try {
    const dst = path.join(BACKUP_DIR, `visitors-${new Date().toISOString().slice(0, 13).replace(/[:T]/g, "-")}.db`);
    db.backup(dst); // better-sqlite3: consistent online backup even mid-write
  } catch (e) {
    console.error("backup failed:", e.message);
  }
}
setInterval(localBackup, 60 * 60 * 1000);

app.listen(PORT, "0.0.0.0", () => {
  const url = `http://${lanIp()}:${PORT}`;
  console.log(`Visitors Register running.`);
  console.log(`  Capture (phones): ${url}/`);
  console.log(`  Stall QR code:    ${url}/qr`);
  console.log(`  Dashboard:        ${url}/dashboard`);
  console.log(`  OCR (Enrich):     ${process.env.GOOGLE_API_KEY ? "enabled (Gemini)" : "disabled — set GOOGLE_API_KEY in .env"}`);
  console.log(`  Supabase sync:    ${supaConfig() ? "enabled (bucket: " + supaConfig().bucket + ")" : "disabled — set SUPABASE_URL + SUPABASE_SERVICE_KEY in .env"}`);
});
