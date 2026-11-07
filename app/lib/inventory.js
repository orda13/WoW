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

function mergeInventories(store, data, file) {
  if (!data || !data.chars) return false;
  const account = accountOf(file);
  const cur = store.get("shared/inventories") || { chars: {} };
  const chars = { ...cur.chars };
  let changed = false;
  for (const [key, c] of Object.entries(data.chars)) {
    if (!c || !c.name) continue;
    const id = `${account}/${key}`;
    const prev = chars[id];
    const at = (c.stateAt || c.bagsAt || 0) * 1000;
    if (prev && prev.at >= at && !(c.bankAt && c.bankAt * 1000 > (prev.bankAt || 0))) continue;
    chars[id] = {
      name: c.name, key, account, level: c.level || null, cls: c.class || "", faction: c.faction || "",
      money: c.money != null ? c.money : (prev && prev.money) ?? null,
      rested: c.rested || 0, zone: c.zone || "", subzone: c.subzone || "", at,
      bags: c.bags ? toCounts(c.bags) : (prev && prev.bags) || {}, bagsAt: (c.bagsAt || 0) * 1000 || (prev && prev.bagsAt) || 0,
      bank: c.bank ? toCounts(c.bank) : (prev && prev.bank) || {}, bankAt: (c.bankAt || 0) * 1000 || (prev && prev.bankAt) || 0,
      professions: Object.fromEntries(Object.entries(c.skills || {}).map(([n, v]) => [n, v.rank || 0])),
    };
    if (JSON.stringify(prev) !== JSON.stringify(chars[id])) changed = true;
  }
  if (changed) store.set("shared/inventories", { chars, updatedAt: Date.now() });
  // item names and qualities the add-on has seen
  if (data.items) {
    const items = { ...((store.get("shared/items") || {}).items || {}) };
    let n = 0;
    for (const [id, it] of Object.entries(data.items)) if (it && it.n && !items[id]) { items[id] = [it.n, it.q ?? 1]; n++; }
    if (n) store.set("shared/items", { items, updatedAt: Date.now() });
  }
  return changed;
}

module.exports = { mergeInventories, accountOf };
