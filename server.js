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

// Create/replace a lead. All fields are optional: a lead is accepted as long as
// it carries at least one non-blank field OR at least one photo — only a totally
// empty submission is rejected. Phone, when present and valid, is normalized into
// wa_phone; an absent/invalid phone just leaves wa_phone null (still saveable).
// Idempotent: re-sending the same id upserts (never duplicates).
const LEAD_FIELDS = ["phone", "name", "company", "email", "website", "city", "state", "products", "note", "tag"];
const isBlank = (v) => v == null || String(v).trim() === "";
const isPhoto = (v) => typeof v === "string" && v.startsWith("data:");

app.post("/api/leads", async (req, res) => {
  const b = req.body || {};
  const wa = normalizeForWa(b.phone); // null if missing/invalid — no longer fatal
  const filledFields = LEAD_FIELDS.filter((k) => !isBlank(b[k]));
  const hasPhoto = isPhoto(b.frontPhoto) || isPhoto(b.backPhoto);
  const phoneState = isBlank(b.phone) ? "none" : wa ? "valid" : "invalid";
  console.log(`[POST /api/leads] fields=[${filledFields.join(",")}] photos=${[isPhoto(b.frontPhoto) && "front", isPhoto(b.backPhoto) && "back"].filter(Boolean).join("+") || "none"} phone=${phoneState}`);
  if (!filledFields.length && !hasPhoto) {
    console.log("[POST /api/leads] rejected: empty_lead (no fields, no photo)");
    return res.status(400).json({ error: "empty_lead" });
  }
  const id = typeof b.id === "string" && b.id ? b.id : crypto.randomUUID();
  try {
    const frontUrl = await db.uploadPhoto(b.frontPhoto, `${id}-front.jpg`);
    const backUrl = await db.uploadPhoto(b.backPhoto, `${id}-back.jpg`);
    await db.upsertLead(
      {
        id, phone: isBlank(b.phone) ? null : String(b.phone).trim(), wa_phone: wa,
        name: b.name, company: b.company, email: b.email, website: b.website,
        city: b.city, state: b.state, products: b.products, note: b.note, tag: b.tag,
        created_at: b.created_at || new Date().toISOString(),
      },
      { frontUrl, backUrl }
    );
    console.log(`[POST /api/leads] saved id=${id} wa_phone=${wa || "null"}`);
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
    "This is a business/visiting card or an ID card. Extract these fields as JSON: " +
    '{"name":..., "company":..., "email":..., "website":..., "city":..., "state":..., "products":...}. ' +
    '"name" is the PERSON\'S full name printed on the card (often the most prominent line, not the company). ' +
    "Always return the name if any human name is legible. " +
    "Use null only for a field that is truly absent or unreadable. Do not invent data.";
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
  const ocr = parseOcrJson(text);
  console.log(`[enrich ${lead.id}] OCR raw: ${JSON.stringify(ocr)}`);
  console.log(`[enrich ${lead.id}] lead blanks: ${["name","company","email","website","city","state","products"].filter((f) => !lead[f]).join(",") || "(none)"}`);
  const { updates, filled } = mergeEnrichment(lead, ocr);
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
    const updated = await db.getLead(req.params.id); // return the fresh row so the client shows filled values without a refetch
    res.json({ filled, lead: updated });
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
