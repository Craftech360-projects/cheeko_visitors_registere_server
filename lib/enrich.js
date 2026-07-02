// v2 OCR enrichment helpers (ADR 0002). Pure logic only — the network call
// lives in server.js. Rules: fill a field ONLY if it is currently blank and
// OCR returned something; never overwrite human input; never touch phone.

const FIELDS = ["name", "company", "email", "website", "city", "state", "products", "audio_transcript"];

function blank(v) {
  return v == null || String(v).trim() === "";
}

// Decide which fields to write. Returns { updates, filled[] }.
function mergeEnrichment(lead, ocr) {
  const updates = {};
  const filled = [];
  for (const f of FIELDS) {
    if (blank(lead[f]) && !blank(ocr && ocr[f])) {
      updates[f] = String(ocr[f]).trim();
      filled.push(f);
    }
  }
  return { updates, filled };
}

// The model is told to return only JSON, but be defensive: strip markdown
// fences and parse. Returns {} on anything unparseable (so we fill nothing).
function parseOcrJson(text) {
  if (!text) return {};
  const m = String(text).match(/\{[\s\S]*\}/);
  if (!m) return {};
  try {
    return JSON.parse(m[0]);
  } catch {
    return {};
  }
}

module.exports = { mergeEnrichment, parseOcrJson, FIELDS, blank };
