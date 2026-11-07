// The in-game summary: every character's level, gold, location, bags and bank, from every device and account.
// The hub serves it as JSON; the hub and each relay write it into the add-on's folder as Shared.lua, which WoW
// loads at login and /reload. WoW runs that file as code, so it is written here from checked data only:
// numbers, and text with every special or non-ASCII byte escaped, so nothing in a name can become code.
const fs = require("fs");
const path = require("path");

const MAX_CHARS = 60, MAX_ITEMS = 4000;

// shared/inventories + shared/items -> plain JSON for relays (timestamps in seconds, like the add-on's own)
function buildSummary(store) {
  const inv = (store.get("shared/inventories") || {}).chars || {};
  const names = (store.get("shared/items") || {}).items || {};
  const chars = {}, used = new Set();
  for (const c of Object.values(inv).sort((a, b) => (b.at || 0) - (a.at || 0)).slice(0, MAX_CHARS)) {
    const key = c.key || c.name;
    if (chars[key] && (chars[key].stateAt || 0) >= Math.floor((c.at || 0) / 1000)) continue;
    chars[key] = {
      name: c.name, account: c.account || "", level: c.level || 0, class: c.cls || "", money: c.money || 0, rested: c.rested || 0,
      zone: c.zone || "", subzone: c.subzone || "", stateAt: Math.floor((c.at || 0) / 1000),
      bagsAt: Math.floor((c.bagsAt || 0) / 1000), bankAt: Math.floor((c.bankAt || 0) / 1000), bags: c.bags || {}, bank: c.bank || {},
    };
    for (const id of [...Object.keys(c.bags || {}), ...Object.keys(c.bank || {})]) used.add(id);
  }
  const items = {};
  for (const id of used) if (names[id]) items[id] = names[id];
  return { generated: Math.floor(Date.now() / 1000), chars, items };
}

// ---------- JSON -> Lua, strictly ----------
const int = (v, max = 1e12) => { const n = Math.floor(Number(v)); return Number.isFinite(n) && n >= 0 ? Math.min(n, max) : 0; };
function luaStr(s, max = 80) {
  const bytes = Buffer.from(String(s == null ? "" : s).slice(0, max), "utf8");
  let out = '"';
  for (const b of bytes) {
    if (b >= 0x30 && b <= 0x39) out += String.fromCharCode(b); // digits stay plain
    else if ((b >= 0x41 && b <= 0x5a) || (b >= 0x61 && b <= 0x7a) || b === 0x20 || b === 0x2d || b === 0x27 || b === 0x2c || b === 0x2e || b === 0x28 || b === 0x29 || b === 0x3a)
      out += String.fromCharCode(b); // letters, space and - ' , . ( ) :
    else out += "\\" + String(b).padStart(3, "0"); // everything else as a decimal escape (Lua 5.1)
  }
  return out + '"';
}
function counts(o) {
  const parts = [];
  for (const [id, n] of Object.entries(o || {}).slice(0, MAX_ITEMS)) if (/^\d{1,9}$/.test(id) && int(n, 1e7) > 0) parts.push(`[${id}]=${int(n, 1e7)}`);
  return "{" + parts.join(",") + "}";
}
function toLua(sum) {
  const chars = [];
  for (const [key, c] of Object.entries((sum && sum.chars) || {}).slice(0, MAX_CHARS)) {
    if (!c || typeof c !== "object") continue;
    chars.push(`  [${luaStr(key)}] = { name = ${luaStr(c.name, 40)}, account = ${luaStr(c.account, 40)}, level = ${int(c.level, 200)}, class = ${luaStr(c.class, 20)},` +
      ` money = ${int(c.money)}, rested = ${int(c.rested, 1e9)}, zone = ${luaStr(c.zone, 60)}, subzone = ${luaStr(c.subzone, 60)},` +
      ` stateAt = ${int(c.stateAt, 4e9)}, bagsAt = ${int(c.bagsAt, 4e9)}, bankAt = ${int(c.bankAt, 4e9)},\n    bags = ${counts(c.bags)},\n    bank = ${counts(c.bank)} },`);
  }
  const items = [];
  for (const [id, v] of Object.entries((sum && sum.items) || {}).slice(0, MAX_ITEMS)) {
    if (!/^\d{1,9}$/.test(id) || !Array.isArray(v)) continue;
    items.push(`[${id}]={${luaStr(v[0], 80)},${int(v[1], 7)}}`);
  }
  return "-- Leveling Ledger: your characters on every device and account (bags, bank, gold).\n" +
    "-- Written automatically by the Leveling Ledger app; changes here are replaced.\n" +
    `LevelingLedgerShared = {\n generated = ${int(sum && sum.generated, 4e9)},\n chars = {\n${chars.join("\n")}\n },\n items = {${items.join(",")}},\n}\n`;
}

// Write Shared.lua into an add-on folder, only when it changed (atomic: temp file, then rename)
function writeShared(addonDir, sum) {
  if (!addonDir || !fs.existsSync(path.join(addonDir, "LevelingLedger.toc"))) return false;
  const text = toLua(sum);
  const f = path.join(addonDir, "Shared.lua");
  const strip = (t) => t.replace(/ generated = \d+,/, "");
  try { if (strip(fs.readFileSync(f, "latin1")) === strip(text)) return false; } catch {}
  fs.writeFileSync(f + ".tmp", text, "latin1");
  fs.renameSync(f + ".tmp", f);
  return true;
}

module.exports = { buildSummary, toLua, writeShared, luaStr };
