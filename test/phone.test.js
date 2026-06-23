const { test } = require("node:test");
const assert = require("node:assert");
const { normalizeForWa } = require("../lib/phone");

// wa.me wants digits only, country code, no "+". Default region: India (91).
// A wrong digit = an unreachable lead, so this is the one piece we test.

test("plain 10-digit Indian mobile gets 91 prefixed", () => {
  assert.strictEqual(normalizeForWa("9810324166"), "919810324166");
});

test("strips spaces, dashes, parens", () => {
  assert.strictEqual(normalizeForWa("98103-241 66"), "919810324166");
  assert.strictEqual(normalizeForWa("(981) 032-4166"), "919810324166");
});

test("leading 0 (STD-style) is dropped before prefixing", () => {
  assert.strictEqual(normalizeForWa("09810324166"), "919810324166");
});

test("already has 91 country code -> unchanged digits", () => {
  assert.strictEqual(normalizeForWa("919810324166"), "919810324166");
});

test("+91 form -> plus stripped", () => {
  assert.strictEqual(normalizeForWa("+91 98103 24166"), "919810324166");
});

test("00 international prefix is treated as +", () => {
  assert.strictEqual(normalizeForWa("0091 9810324166"), "919810324166");
});

test("foreign number with its own country code is kept as-is", () => {
  // 11-digit US: 1 + 10 digits, already a country code -> keep
  assert.strictEqual(normalizeForWa("12025550123"), "12025550123");
});

test("garbage / too short returns null (do not guess)", () => {
  assert.strictEqual(normalizeForWa("12345"), null);
  assert.strictEqual(normalizeForWa(""), null);
  assert.strictEqual(normalizeForWa("abcd"), null);
  assert.strictEqual(normalizeForWa(null), null);
});
