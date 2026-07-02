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
  assert.ok(!("enriched_at" in row));  // server-owned; never set via upsert
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

test("dataUrlToBuffer trusts the declared mime for audio", () => {
  const m4a = "data:audio/mp4;base64," + Buffer.from("ftypM4A fake").toString("base64");
  const out = dataUrlToBuffer(m4a);
  assert.strictEqual(out.mime, "audio/mp4");
  // a jpeg-labelled image still falls back to magic-byte detection
  const jpg = "data:image/jpeg;base64," + Buffer.from([0xff, 0xd8, 0xff]).toString("base64");
  assert.strictEqual(dataUrlToBuffer(jpg).mime, "image/jpeg");
});

test("buildUpsertRow carries audio_url, drops it when absent", () => {
  const base = { id: "u1", phone: "9744187790", created_at: "2026-07-02" };
  const withAudio = buildUpsertRow(base, { audioUrl: "http://x/u1-audio.m4a" });
  assert.strictEqual(withAudio.audio_url, "http://x/u1-audio.m4a");
  const without = buildUpsertRow(base, {});
  assert.ok(!("audio_url" in without)); // null dropped → re-sync never wipes it
});
