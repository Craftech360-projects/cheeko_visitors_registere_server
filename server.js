const fs = require("fs");
const path = require("path");
const express = require("express");
const Database = require("better-sqlite3");
const QRCode = require("qrcode");
const { normalizeForWa } = require("./lib/phone");
const { lanIp } = require("./lib/net");
const { toCsv } = require("./lib/csv");
const { mergeEnrichment, parseOcrJson } = require("./lib/enrich");

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
    name TEXT, company TEXT, email TEXT, city TEXT, products TEXT, note TEXT,
    tag TEXT,
    front_photo TEXT, back_photo TEXT,
    created_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT);
`);
try { db.exec("ALTER TABLE leads ADD COLUMN email TEXT"); } catch { /* already migrated */ }

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

const app = express();
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
      `INSERT INTO leads (phone, wa_phone, name, company, email, city, products, note, tag, created_at)
       VALUES (@phone,@wa,@name,@company,@email,@city,@products,@note,@tag,@created_at)`
    )
    .run({
      phone: String(b.phone).trim(),
      wa,
      name: b.name || null,
      company: b.company || null,
      email: b.email || null,
      city: b.city || null,
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

// v2 (ADR 0002): OCR-enrich a lead's BLANK fields from its card photo(s).
// Internet + ANTHROPIC_API_KEY required. Never overwrites human input or phone.
app.post("/api/leads/:id/enrich", async (req, res) => {
  const key = process.env.GOOGLE_API_KEY; // Gemini key from Google AI Studio
  if (!key) return res.status(400).json({ error: "ocr_not_configured" });
  const lead = db.prepare("SELECT * FROM leads WHERE id=?").get(req.params.id);
  if (!lead) return res.status(404).json({ error: "not_found" });

  const images = []; // {data, mime} for each card photo
  for (const p of [lead.front_photo, lead.back_photo]) {
    if (!p) continue;
    try {
      const buf = fs.readFileSync(path.join(ROOT, p));
      const mime = buf[0] === 0x89 && buf[1] === 0x50 ? "image/png" : "image/jpeg"; // PNG magic vs JPEG
      images.push({ data: buf.toString("base64"), mime });
    } catch { /* missing file: skip */ }
  }
  if (!images.length) return res.status(400).json({ error: "no_photo" });

  const prompt =
    "This is a business/visiting card. Extract these fields as JSON: " +
    '{"name":..., "company":..., "email":..., "city":..., "products":...}. ' +
    "Use null for any field that is not clearly legible. Do not guess.";
  const model = process.env.OCR_MODEL || "gemini-2.5-flash";

  try {
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
    if (!r.ok) return res.status(502).json({ error: "ocr_failed", status: r.status });
    const data = await r.json();
    const c = data.candidates && data.candidates[0];
    const text = c && c.content && c.content.parts && c.content.parts[0] && c.content.parts[0].text;
    const ocr = parseOcrJson(text);
    const { updates, filled } = mergeEnrichment(lead, ocr); // filled ⊆ whitelisted fields
    if (filled.length) {
      const set = filled.map((f) => `${f}=@${f}`).join(", ");
      db.prepare(`UPDATE leads SET ${set} WHERE id=@id`).run({ ...updates, id: lead.id });
    }
    res.json({ filled, updates });
  } catch (e) {
    res.status(502).json({ error: String(e) });
  }
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

// ponytail: secondary backup only, no-op unless Supabase env is set. Primary
// safety net is the hourly local copy below + end-of-day USB.
app.post("/api/backup/cloud", async (req, res) => {
  const { SUPABASE_URL, SUPABASE_KEY, SUPABASE_BUCKET } = process.env;
  if (!SUPABASE_URL || !SUPABASE_KEY) return res.status(400).json({ error: "supabase_not_configured" });
  try {
    const bucket = SUPABASE_BUCKET || "visitors-backup";
    const key = `visitors-${new Date().toISOString().replace(/[:.]/g, "-")}.db`;
    const r = await fetch(`${SUPABASE_URL}/storage/v1/object/${bucket}/${key}`, {
      method: "POST",
      headers: { Authorization: `Bearer ${SUPABASE_KEY}`, "Content-Type": "application/octet-stream" },
      body: fs.readFileSync(DB_PATH),
    });
    if (!r.ok) return res.status(502).json({ error: "upload_failed", status: r.status });
    res.json({ ok: true, key });
  } catch (e) {
    res.status(502).json({ error: String(e) });
  }
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
});
