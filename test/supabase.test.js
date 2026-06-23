const { test } = require("node:test");
const assert = require("node:assert");
const { leadToRow } = require("../lib/supabase");

test("maps lead fields and attaches photo urls", () => {
  const lead = { id: 3, name: "Rahul", company: "craftech360", phone: "9744187790",
    wa_phone: "919744187790", email: null, products: "AI", created_at: "2026-06-23" };
  const row = leadToRow(lead, { frontUrl: "http://x/3-front.jpg", backUrl: null });
  assert.strictEqual(row.id, 3);
  assert.strictEqual(row.name, "Rahul");
  assert.strictEqual(row.wa_phone, "919744187790");
  assert.strictEqual(row.front_url, "http://x/3-front.jpg");
  assert.strictEqual(row.back_url, null);
});

test("missing fields become null (no undefined sent to Supabase)", () => {
  const row = leadToRow({ id: 1, phone: "9999999999" });
  assert.strictEqual(row.company, null);
  assert.strictEqual(row.front_url, null);
  assert.ok(!Object.values(row).includes(undefined));
});

test("id is always present (upsert conflict key)", () => {
  assert.strictEqual(leadToRow({ id: 42 }).id, 42);
});
