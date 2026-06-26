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
