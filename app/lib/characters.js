// Characters tracked by the ledger. The main character's data uses plain paths ("state/character");
// each alt's data lives under its own prefix ("c1a2b3c4.state/character") in the same store, so backups cover all of them.
const crypto = require("crypto");

// A stable id from the character's Blizzard name: removing and adding an alt again finds its old data.
const altId = (slug) => "c" + crypto.createHash("sha1").update(String(slug)).digest("hex").slice(0, 8);

function characters(config) {
  const main = (config.blizzard && config.blizzard.character) || "";
  const alts = [...new Set((config.alts || []).filter((s) => s && s !== main))];
  return [{ id: "", character: main, main: true }, ...alts.map((s) => ({ id: altId(s), character: s, main: false }))];
}

// A view of the store for one character, with the same methods the importer and sync use
function charStore(store, id) {
  if (!id) return store;
  const pre = id + ".";
  return {
    id,
    get: (p) => store.get(pre + p),
    set: (p, d) => store.set(pre + p, d),
    update: (p, d) => store.update(pre + p, d),
    delete: (p) => store.delete(pre + p),
    list: (col) => store.list(pre + col),
    add: (col, d) => store.add(pre + col, d),
    flushNow: () => store.flushNow(),
  };
}

module.exports = { characters, charStore, altId };
