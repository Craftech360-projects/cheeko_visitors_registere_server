const { test } = require("node:test");
const assert = require("node:assert");
const { mergeEnrichment, parseOcrJson } = require("../lib/enrich");

test("fills only blank fields, never overwrites human input", () => {
  const lead = { name: "Rajeev", company: "", city: null, products: "  " };
  const ocr = { name: "WRONG", company: "3 Generations", city: "Noida", products: "Walkers" };
  const { updates, filled } = mergeEnrichment(lead, ocr);
  assert.deepStrictEqual(updates, { company: "3 Generations", city: "Noida", products: "Walkers" });
  assert.deepStrictEqual(filled.sort(), ["city", "company", "products"]);
  assert.ok(!("name" in updates)); // existing name kept
});

test("skips fields OCR could not read (null/empty), never guesses", () => {
  const lead = { name: "", company: "", city: "", products: "" };
  const ocr = { name: "Anil", company: null, city: "", products: "  " };
  const { updates, filled } = mergeEnrichment(lead, ocr);
  assert.deepStrictEqual(updates, { name: "Anil" });
  assert.deepStrictEqual(filled, ["name"]);
});

test("phone is never enriched even if OCR returns one", () => {
  const lead = { phone: "9810324166", name: "" };
  const { updates } = mergeEnrichment(lead, { phone: "9999999999", name: "X" });
  assert.ok(!("phone" in updates));
});

test("audio_transcript fills only when blank (server-owned after that)", () => {
  const { updates, filled } = mergeEnrichment({ audio_transcript: null }, { audio_transcript: "call back Monday" });
  assert.strictEqual(updates.audio_transcript, "call back Monday");
  assert.ok(filled.includes("audio_transcript"));
  const second = mergeEnrichment({ audio_transcript: "existing" }, { audio_transcript: "new attempt" });
  assert.ok(!("audio_transcript" in second.updates));
});

test("empty OCR result -> no updates", () => {
  assert.deepStrictEqual(mergeEnrichment({ name: "" }, {}).filled, []);
  assert.deepStrictEqual(mergeEnrichment({ name: "" }, null).filled, []);
});

test("parseOcrJson strips markdown fences", () => {
  assert.deepStrictEqual(parseOcrJson('```json\n{"name":"A"}\n```'), { name: "A" });
  assert.deepStrictEqual(parseOcrJson('Here:\n{"city":"Pune"} done'), { city: "Pune" });
});

test("parseOcrJson returns {} on garbage", () => {
  assert.deepStrictEqual(parseOcrJson("no json here"), {});
  assert.deepStrictEqual(parseOcrJson(""), {});
});
