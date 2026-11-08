// Blizzard's dungeon journal for WoW Forever: each instance's bosses and the loot the game itself lists for them,
// from the Game Data API (journal-instance and journal-encounter, static namespace). Run from the Dungeons tab;
// the result is kept in shared/journal and merged into the dungeon cards. If Forever's data has no journal, the
// status says so.
const { getToken } = require("./blizzard");

let running = null;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function checkJournal(store, cfg, log) {
  if (running) return running;
  running = (async () => {
    const started = Date.now();
    const prev = store.get("shared/journal") || {};
    const status = (o) => store.set("shared/journal", { ...prev, ...o, checkedAt: Date.now() });
    status({ pending: true, message: "Asking Blizzard for the dungeon journal…" });
    try {
      if (!cfg.clientId || !cfg.clientSecret) throw Object.assign(new Error("Add your Blizzard keys on the Settings tab first."), { plain: true });
      const t = await getToken(cfg);
      const base = cfg.apiBase || "https://us.api.blizzard.com";
      const ns = cfg.staticNamespace || "static-forever-us";
      const get = async (path) => {
        await sleep(60); // well under Blizzard's request limits
        const r = await fetch(base + path + (path.includes("?") ? "&" : "?") + "locale=en_US", { headers: { Authorization: "Bearer " + t, "Battlenet-Namespace": ns } });
        if (!r.ok) throw Object.assign(new Error("HTTP " + r.status), { status: r.status });
        return r.json();
      };
      let idx;
      try { idx = await get("/data/wow/journal-instance/index"); }
      catch (e) {
        status({ pending: false, ok: false, message: e.status === 404 ? `Blizzard's API has no dungeon journal for WoW Forever (${ns}). Nothing changed.` : `Couldn't read the journal (${e.message}). Nothing changed.` });
        return;
      }
      const instances = {};
      let encN = 0, itemN = 0, failed = 0;
      for (const inst of idx.instances || []) {
        let j; try { j = await get(`/data/wow/journal-instance/${inst.id}`); } catch { failed++; continue; }
        const encounters = [];
        for (const enc of j.encounters || []) {
          let e; try { e = await get(`/data/wow/journal-encounter/${enc.id}`); } catch { failed++; continue; }
          const items = (e.items || []).map((x) => x && x.item && [x.item.id, x.item.name || ""]).filter(Boolean);
          encounters.push({ id: enc.id, n: enc.name || e.name || "", items });
          encN++; itemN += items.length;
        }
        instances[inst.name] = { id: inst.id, mode: j.category && j.category.type, encounters };
      }
      const n = Object.keys(instances).length;
      status({ pending: false, ok: n > 0, instances, message: n ? `${n} instances, ${encN} bosses, ${itemN} items from Blizzard's journal${failed ? ` (${failed} requests failed)` : ""}.` : "Blizzard's journal for WoW Forever is empty. Nothing changed.", tookMs: Date.now() - started });
      log("Dungeon journal: " + (n ? `${n} instances, ${encN} bosses, ${itemN} items` : "empty"));
    } catch (e) {
      status({ pending: false, ok: false, message: e.plain ? e.message : "Couldn't check the journal: " + e.message });
    }
  })().finally(() => { running = null; });
  return running;
}

module.exports = { checkJournal };
