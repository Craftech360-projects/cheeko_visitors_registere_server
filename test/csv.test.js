const { test } = require("node:test");
const assert = require("node:assert");
const { toCsv, cell } = require("../lib/csv");

test("plain values pass through unquoted", () => {
  assert.strictEqual(cell("Rajeev"), "Rajeev");
  assert.strictEqual(cell(919810324166), "919810324166");
});

test("null/undefined become empty string", () => {
  assert.strictEqual(cell(null), "");
  assert.strictEqual(cell(undefined), "");
});

test("comma forces quoting", () => {
  assert.strictEqual(cell("Baby walkers, carriers"), '"Baby walkers, carriers"');
});

test("internal quotes are doubled", () => {
  assert.strictEqual(cell('say "hi"'), '"say ""hi"""');
});

test("newline forces quoting (keeps row intact)", () => {
  assert.strictEqual(cell("line1\nline2"), '"line1\nline2"');
});

test("toCsv emits header + CRLF rows, escaping each field", () => {
  const csv = toCsv([{ name: "A, B", note: 'has "q"', tag: "hot" }], ["name", "note", "tag"]);
  assert.strictEqual(csv, 'name,note,tag\r\n"A, B","has ""q""",hot');
});
