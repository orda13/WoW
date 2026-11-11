// Every character the add-on knows, across all WoW accounts, with gold, bags and bank:
// kept in shared/inventories (not per character, so every ledger sees all of them) and item names in shared/items.
const path = require("path");
const { arr } = require("./lua");

const toCounts = (o) => {
  const out = {};
  for (const [id, n] of Object.entries(o || {})) if (/^\d+$/.test(id) && n > 0) out[id] = n;
  return out;
};

// file: ...\WTF\Account\<account>\SavedVariables\LevelingLedger.lua
const accountOf = (file) => path.basename(path.dirname(path.dirname(file || ""))) || "";

// A row is a full name when it has a surname ("Talwyn Orda"); a first name alone ("Talwyn") is a WoW Forever
// character recorded by an add-on before 1.0.46, so once any full-name row shares that first name the old row is
// stale. And a character shows once: the newest row for each name, whatever file or account it came from.
const nameOf = (x) => String((x && x.name) || "").trim();
const isFull = (x) => /\s/.test(nameOf(x));
function tidy(chars) {
  const fullFirsts = new Set(Object.values(chars).filter(isFull).map((x) => nameOf(x).split(/\s+/)[0].toLowerCase()));
  const out = {}, newest = new Map(); let changed = false;
  for (const [id, x] of Object.entries(chars)) {
    if (!x || !nameOf(x)) { changed = true; continue; }
    if (!isFull(x) && fullFirsts.has(nameOf(x).toLowerCase())) { changed = true; continue; }
    const k = nameOf(x).toLowerCase(), o = newest.get(k);
    if (o) { changed = true; if ((out[o].at || 0) >= (x.at || 0)) continue; delete out[o]; }
    newest.set(k, id); out[id] = x;
  }
  return { chars: out, changed };
}
// at startup: clear what earlier versions left behind
function tidyInventories(store) {
  const cur = store.get("shared/inventories"); if (!cur || !cur.chars) return 0;
  const t = tidy(cur.chars);
  if (t.changed) store.set("shared/inventories", { ...cur, chars: t.chars, updatedAt: Date.now() });
  return Object.keys(cur.chars).length - Object.keys(t.chars).length;
}

function mergeInventories(store, data, file) {
  if (!data || !data.chars) return false;
  const account = accountOf(file);
  const cur = store.get("shared/inventories") || { chars: {} };
  const chars = { ...cur.chars };
  let changed = false;
  // first names that have a full-name row (add-on 1.0.46+): an entry under that first name alone isn't added
  const fullFirsts = new Set([...Object.values(chars).filter(isFull).map((x) => nameOf(x).split(/\s+/)[0].toLowerCase()),
    ...Object.values(data.chars).filter((c) => c && c.surname && c.name).map((c) => String(c.name).trim().toLowerCase())]);
  for (const [key, c] of Object.entries(data.chars)) {
    if (!c || !c.name) continue;
    if (!c.surname && fullFirsts.has(String(c.name).trim().toLowerCase())) continue;
    const id = `${account}/${key}`;
    const prev = chars[id];
    const at = (c.stateAt || c.bagsAt || 0) * 1000;
    if (prev && prev.at >= at && !(c.bankAt && c.bankAt * 1000 > (prev.bankAt || 0))) continue;
    chars[id] = {
      // the full name (WoW Forever: first name and surname), so two characters with one first name stay apart
      name: [c.name, c.surname].filter(Boolean).join(" "), first: c.name, key, account, level: c.level || null, cls: c.class || "", faction: c.faction || "",
      money: c.money != null ? c.money : (prev && prev.money) ?? null,
      rested: c.rested || 0, zone: c.zone || "", subzone: c.subzone || "", at,
      // for the rested estimate: resting (inn or city) when last seen, and the size of this level's XP bar
      resting: !!c.resting, xp: c.lastXP ?? null, xpMax: (c.xpMax && c.level && c.xpMax[c.level]) || null,
      bags: c.bags ? toCounts(c.bags) : (prev && prev.bags) || {}, bagsAt: (c.bagsAt || 0) * 1000 || (prev && prev.bagsAt) || 0,
      bank: c.bank ? toCounts(c.bank) : (prev && prev.bank) || {}, bankAt: (c.bankAt || 0) * 1000 || (prev && prev.bankAt) || 0,
      // the bags themselves: in the bag slots (and reagent slot), and in the bank's bag slots
      bagItems: Array.isArray(c.bagItems) ? c.bagItems.map(Number).filter((n) => n > 0) : c.bagItems && typeof c.bagItems === "object" ? Object.values(c.bagItems).map(Number).filter((n) => n > 0) : (prev && prev.bagItems) || [],
      bankBagItems: Array.isArray(c.bankBagItems) ? c.bankBagItems.map(Number).filter((n) => n > 0) : c.bankBagItems && typeof c.bankBagItems === "object" ? Object.values(c.bankBagItems).map(Number).filter((n) => n > 0) : (prev && prev.bankBagItems) || [],
      professions: Object.fromEntries(Object.entries(c.skills || {}).map(([n, v]) => [n, v.rank || 0])),
    };
    if (JSON.stringify(prev) !== JSON.stringify(chars[id])) changed = true;
  }
  // add-ons before 1.0.46 filed WoW Forever characters by first name and realm ("Talwyn-Normal"), one entry for every
  // character with that first name; once the full names arrive from that account, the old entry goes
  const t = tidy(chars);
  if (t.changed) changed = true;
  if (changed) store.set("shared/inventories", { chars: t.chars, updatedAt: Date.now() });
  // auction prices (whole account): the newest price seen per item wins, across every account and device
  if (data.ah && typeof data.ah === "object") {
    const cur = store.get("shared/ahprices") || {}; const items = { ...(cur.items || {}) }; let n = 0;
    for (const [id, v] of Object.entries(data.ah)) {
      if (!/^\d{1,9}$/.test(id) || !v || !(v.p > 0)) continue;
      const at = (v.at || 0) * 1000;
      if (items[id] && items[id].at >= at) continue;
      items[id] = { p: Math.round(v.p), n: v.n || 0, at }; n++;
    }
    if (n) store.set("shared/ahprices", { items, updatedAt: Date.now() });
  }
  // item names and qualities the add-on has seen
  if (data.items) {
    const items = { ...((store.get("shared/items") || {}).items || {}) };
    let n = 0;
    for (const [id, it] of Object.entries(data.items)) if (it && it.n && !items[id]) { items[id] = [it.n, it.q ?? 1]; n++; }
    if (n) store.set("shared/items", { items, updatedAt: Date.now() });
  }
  return changed;
}

module.exports = { mergeInventories, tidyInventories, accountOf };
