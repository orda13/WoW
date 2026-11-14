// The in-game summary: every character's level, gold, location, bags and bank, from every device and account.
// The hub serves it as JSON; the hub and each relay write it into the add-on's folder as Shared.lua, which WoW
// loads at login and /reload. WoW runs that file as code, so it is written here from checked data only:
// numbers, and text with every special or non-ASCII byte escaped, so nothing in a name can become code.
const fs = require("fs");
const path = require("path");

const MAX_CHARS = 60, MAX_ITEMS = 4000, MAX_PRICES = 3000;

// shared/inventories + shared/items -> plain JSON for relays (timestamps in seconds, like the add-on's own)
function buildSummary(store) {
  const inv = (store.get("shared/inventories") || {}).chars || {};
  const names = (store.get("shared/items") || {}).items || {};
  // characters removed on the page (shared/hiddenchars, keyed "<account>/<key>") stay out of the game too
  const hidden = (store.get("shared/hiddenchars") || {}).ids || {};
  const chars = {}, used = new Set();
  for (const c of Object.values(inv).filter((c) => !hidden[(c.account || "") + "/" + (c.key || c.name)]).sort((a, b) => (b.at || 0) - (a.at || 0)).slice(0, MAX_CHARS)) {
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
  // quests planned on the page, per character (first name, lower case): { [questId]: title }
  const plans = {};
  for (const [who, q] of Object.entries((store.get("shared/questplan") || {}).byChar || {})) {
    const ids = Object.entries(q || {}).filter(([id]) => /^\d{1,7}$/.test(id)).slice(0, 100);
    if (ids.length) plans[String(who).toLowerCase()] = Object.fromEntries(ids.map(([id, t]) => [id, String(t || "")]));
  }
  // recipes each character needs and the vendors (npc ids) that sell them: { who: { items: {id: name}, npcs: {npc: [ids]} } }
  const recipes = {};
  for (const [who, r] of Object.entries((store.get("shared/recipeneeds") || {}).byChar || {})) {
    if (!r || typeof r !== "object") continue;
    const items = Object.fromEntries(Object.entries(r.items || {}).filter(([id]) => /^\d{1,9}$/.test(id)).slice(0, 100).map(([id, n]) => [id, String(n || "")]));
    const npcs = Object.fromEntries(Object.entries(r.npcs || {}).filter(([id, l]) => /^\d{1,9}$/.test(id) && Array.isArray(l)).slice(0, 400)
      .map(([id, l]) => [id, l.filter((x) => /^\d{1,9}$/.test(String(x))).slice(0, 20).map(Number)]));
    if (Object.keys(items).length) recipes[String(who).toLowerCase()] = { items, npcs };
  }
  // talent plans, per character: { who: { from: first level, picks: ["Ferocity 1/5", ...] } }
  const talents = {};
  for (const [who, t] of Object.entries((store.get("shared/talentplans") || {}).byChar || {})) {
    if (!t || !Array.isArray(t.labels) || !t.labels.length) continue;
    talents[String(who).toLowerCase()] = { from: Number(t.from) || 10, picks: t.labels.slice(0, 80).map((x) => String(x || "")) };
  }
  // secrets ticked on the page, per character (first name, lower case): { who: { "torch": true } }, so the add-on drops their pins
  const secrets = {};
  for (const [who, t] of Object.entries((store.get("shared/secretticks") || {}).byChar || {})) {
    const ids = Object.keys(t || {}).filter((id) => t[id] && /^[a-z0-9-]{1,40}$/.test(id)).slice(0, 100);
    if (ids.length) secrets[String(who).toLowerCase()] = ids;
  }
  // auction prices from every device (shared/ahprices), the newest MAX_PRICES: { id: [copper each, listed, seen at (s)] },
  // for the price line on reagent tooltips in game
  const ah = {};
  const prices = Object.entries((store.get("shared/ahprices") || {}).items || {}).filter(([id, v]) => /^\d{1,9}$/.test(id) && v && v.p > 0)
    .sort((a, b) => (b[1].at || 0) - (a[1].at || 0)).slice(0, MAX_PRICES);
  for (const [id, v] of prices) ah[id] = [Math.round(v.p), v.n || 0, Math.floor((v.at || 0) / 1000)];
  // which of your characters knows which recipe (shared/knownrecipes): { "talwyn bank": { name, profs: { Tailoring: { skill, recipes } } } }
  const known = {};
  for (const [who, k] of Object.entries((store.get("shared/knownrecipes") || {}).byChar || {}).slice(0, MAX_CHARS)) {
    if (!k || !k.profs) continue;
    const profs = {};
    for (const [prof, p] of Object.entries(k.profs).slice(0, 14)) profs[prof] = { skill: p.skill || 0, recipes: (p.recipes || []).slice(0, 400).map((r) => String(r).toLowerCase()) };
    known[String(who).toLowerCase()] = { name: k.name || who, profs };
  }
  // the next crafting steps the profession guide worked out, per character: { who: { Tailoring: [{ n, crafts, from, to, short: [[name, qty]] }] } }
  const crafts = {};
  for (const [who, byProf] of Object.entries((store.get("shared/craftplan") || {}).byChar || {}).slice(0, MAX_CHARS)) {
    if (!byProf || typeof byProf !== "object") continue;
    const o = {};
    for (const [prof, steps] of Object.entries(byProf).slice(0, 14)) if (Array.isArray(steps)) o[prof] = steps.slice(0, 5);
    if (Object.keys(o).length) crafts[String(who).toLowerCase()] = o;
  }
  return { generated: Math.floor(Date.now() / 1000), chars, items, plans, recipes, talents, secrets, ah, known, crafts };
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
  const plans = [];
  for (const [who, q] of Object.entries((sum && sum.plans) || {}).slice(0, MAX_CHARS)) {
    if (!q || typeof q !== "object") continue;
    const ids = Object.entries(q).filter(([id]) => /^\d{1,7}$/.test(id)).slice(0, 100).map(([id, t]) => `[${id}]=${luaStr(t, 80)}`);
    if (ids.length) plans.push(`  [${luaStr(who, 40)}] = {${ids.join(",")}},`);
  }
  const known = [];
  for (const [who, k] of Object.entries((sum && sum.known) || {}).slice(0, MAX_CHARS)) {
    if (!k || typeof k !== "object" || !k.profs || typeof k.profs !== "object") continue;
    const profs = [];
    for (const [prof, p] of Object.entries(k.profs).slice(0, 14)) {
      if (!p || typeof p !== "object") continue;
      profs.push(`[${luaStr(prof, 30)}] = { skill = ${int(p.skill, 1000)}, recipes = {${(Array.isArray(p.recipes) ? p.recipes : []).slice(0, 400).map((r) => luaStr(r, 60)).join(",")}} }`);
    }
    known.push(`  [${luaStr(who, 40)}] = { name = ${luaStr(k.name, 40)}, profs = { ${profs.join(", ")} } },`);
  }
  const crafts = [];
  for (const [who, byProf] of Object.entries((sum && sum.crafts) || {}).slice(0, MAX_CHARS)) {
    if (!byProf || typeof byProf !== "object") continue;
    const profs = [];
    for (const [prof, steps] of Object.entries(byProf).slice(0, 14)) {
      if (!Array.isArray(steps)) continue;
      const st = steps.slice(0, 5).filter((x) => x && typeof x === "object").map((x) =>
        `{ n = ${luaStr(x.n, 60)}, crafts = ${int(x.crafts, 9999)}, from = ${int(x.from, 1000)}, to = ${int(x.to, 1000)}, short = {${(Array.isArray(x.short) ? x.short : []).slice(0, 8).filter(Array.isArray).map((m) => `{${luaStr(m[0], 60)},${int(m[1], 99999)}}`).join(",")}} }`);
      profs.push(`[${luaStr(prof, 30)}] = {${st.join(",")}}`);
    }
    crafts.push(`  [${luaStr(who, 40)}] = { ${profs.join(", ")} },`);
  }
  const ah = [];
  for (const [id, v] of Object.entries((sum && sum.ah) || {}).slice(0, MAX_PRICES)) {
    if (!/^\d{1,9}$/.test(id) || !Array.isArray(v) || !(int(v[0], 1e10) > 0)) continue;
    ah.push(`[${id}]={${int(v[0], 1e10)},${int(v[1], 1e7)},${int(v[2], 4e9)}}`);
  }
  const recipes = [];
  for (const [who, r] of Object.entries((sum && sum.recipes) || {}).slice(0, MAX_CHARS)) {
    if (!r || typeof r !== "object") continue;
    const items = Object.entries(r.items || {}).filter(([id]) => /^\d{1,9}$/.test(id)).slice(0, 100).map(([id, n]) => `[${id}]=${luaStr(n, 80)}`);
    const npcs = Object.entries(r.npcs || {}).filter(([id, l]) => /^\d{1,9}$/.test(id) && Array.isArray(l)).slice(0, 400)
      .map(([id, l]) => `[${id}]={${l.map((x) => int(x, 1e9)).filter((x) => x > 0).slice(0, 20).join(",")}}`);
    if (items.length) recipes.push(`  [${luaStr(who, 40)}] = { items = {${items.join(",")}}, npcs = {${npcs.join(",")}} },`);
  }
  const talents = [];
  for (const [who, t] of Object.entries((sum && sum.talents) || {}).slice(0, MAX_CHARS)) {
    if (!t || !Array.isArray(t.picks) || !t.picks.length) continue;
    talents.push(`  [${luaStr(who, 40)}] = { from = ${int(t.from, 100)}, picks = {${t.picks.slice(0, 80).map((x) => luaStr(x, 60)).join(",")}} },`);
  }
  const secrets = [];
  for (const [who, ids] of Object.entries((sum && sum.secrets) || {}).slice(0, MAX_CHARS)) {
    if (!Array.isArray(ids)) continue;
    const l = ids.filter((id) => /^[a-z0-9-]{1,40}$/.test(String(id))).slice(0, 100).map((id) => `[${luaStr(id, 40)}]=true`);
    if (l.length) secrets.push(`  [${luaStr(who, 40)}] = {${l.join(",")}},`);
  }
  return "-- Leveling Ledger: your characters on every device and account (bags, bank, gold).\n" +
    "-- Written automatically by the Leveling Ledger app; changes here are replaced.\n" +
    `LevelingLedgerShared = {\n generated = ${int(sum && sum.generated, 4e9)},\n chars = {\n${chars.join("\n")}\n },\n items = {${items.join(",")}},\n plans = {\n${plans.join("\n")}\n },\n recipes = {\n${recipes.join("\n")}\n },\n talents = {\n${talents.join("\n")}\n },\n secrets = {\n${secrets.join("\n")}\n },\n ah = {${ah.join(",")}},\n known = {\n${known.join("\n")}\n },\n crafts = {\n${crafts.join("\n")}\n },\n}\n`;
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
