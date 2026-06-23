// Maps a local SQLite lead row to the row we upsert into Supabase.
// Pure (no network) so it's unit-testable; the actual upload lives in server.js.
// `id` is carried through and used as the upsert conflict key, so re-syncing a
// lead UPDATES its row instead of inserting a duplicate.

const COLS = [
  "id", "name", "company", "email", "website", "phone", "wa_phone",
  "city", "state", "products", "note", "tag", "enriched_at", "created_at",
];

function leadToRow(lead, urls = {}) {
  const row = {};
  for (const c of COLS) row[c] = lead[c] == null ? null : lead[c];
  row.front_url = urls.frontUrl || null;
  row.back_url = urls.backUrl || null;
  return row;
}

module.exports = { leadToRow, COLS };
