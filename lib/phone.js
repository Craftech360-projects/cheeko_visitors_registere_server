// Normalize a typed phone number into the digits wa.me expects:
// country code + number, no "+", no separators. Default region India (91).
// Returns null for anything too short/long to be a real number — we never
// guess, because a wrong number is a lead we can never reach.

function normalizeForWa(raw) {
  if (raw == null) return null;
  let digits = String(raw).replace(/\D/g, "");
  if (digits.startsWith("00")) digits = digits.slice(2); // 00 = international prefix
  if (digits.length < 10 || digits.length > 15) return null; // E.164 caps at 15
  if (digits.length === 10) return "91" + digits; // bare Indian mobile
  if (digits.length === 11 && digits[0] === "0") return "91" + digits.slice(1); // STD 0-prefix
  return digits; // already carries a country code (91…, 1…, etc.)
}

module.exports = { normalizeForWa };
