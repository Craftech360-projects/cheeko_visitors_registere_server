const os = require("os");

// First non-internal IPv4 address — the address phones use to reach this PC.
// Returns "127.0.0.1" only if no LAN interface is up (then the QR is useless,
// which is the signal to check the WiFi).
function lanIp() {
  for (const iface of Object.values(os.networkInterfaces())) {
    for (const a of iface || []) {
      if (a.family === "IPv4" && !a.internal) return a.address;
    }
  }
  return "127.0.0.1";
}

module.exports = { lanIp };
