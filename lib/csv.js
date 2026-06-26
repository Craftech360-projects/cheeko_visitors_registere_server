// Minimal RFC-4180 CSV. The only real logic is cell escaping: a field that
// contains a comma, quote, or newline must be wrapped in quotes with internal
// quotes doubled. Get this wrong and a note with a comma shifts every column.

const COLUMNS = [
  "id", "name", "company", "email", "website", "phone", "wa_phone", "city", "state",
  "products", "note", "tag", "enriched_at", "front_url", "back_url", "created_at",
];

function cell(v) {
  if (v == null) return "";
  const s = String(v);
  return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
}

function toCsv(rows, columns = COLUMNS) {
  const lines = [columns.join(",")];
  for (const r of rows) lines.push(columns.map((c) => cell(r[c])).join(","));
  return lines.join("\r\n");
}

module.exports = { toCsv, cell, COLUMNS };
