// Imports the Leveling Ledger add-on's SavedVariables file into the store.
// Same rules as the page's "Import from the add-on" panel.
const fs = require("fs");
const path = require("path");
const { parseLuaSaved, arr } = require("./lua");

let abilities = null;
function loadAbilities(publicDir) {
  if (!abilities) abilities = JSON.parse(fs.readFileSync(path.join(publicDir, "abilities-forever.json"), "utf8"));
  return abilities;
}

// Returns the character table for the ledger's character, or null if the file has none.
// hint: the character from config.json (e.g. "talwyn-orda"), used before Blizzard has filled in the character
function pickChar(data, store, hint) {
  if (!data || !data.chars) return null;
  const chars = Object.values(data.chars);
  const c = store.get("state/character");
  const last = store.get("state/addon");
  const want = ((c && c.name) || (hint || "").split("-")[0] || (last && last.char) || "").split(" ")[0].toLowerCase();
  if (!want) return chars[0] || null;
  return chars.find((x) => (x.name || "").toLowerCase() === want) || null;
}

function readSaved(text) {
  if (/CreateFrame\(|RegisterEvent\(/.test(text)) throw new Error("That's the add-on's own code, not its saved data.");
  return parseLuaSaved(text).LevelingLedgerDB;
}

function importAddon(text, store, publicDir, source, hint) {
  const data = readSaved(text);
  if (!data || !data.chars) throw new Error("That file has no Leveling Ledger data.");
  const ch = pickChar(data, store, hint);
  if (!ch) throw new Error("That file has no data for this ledger's character.");
  const S = {
    char: store.get("state/character") || null,
    xpt: store.get("state/xptable") || null,
    vendors: store.get("state/vendors") || null,
    sessions: store.list("sessions").map((d) => ({ ...d.data, _id: d.id })),
  };
  const done = []; let n;

  // 1. Sessions with exact XP and time (reload pieces less than 10 minutes apart are joined)
  n = 0;
  const merged = [];
  for (const s of arr(ch.sessions).filter((x) => x.start && x.stop).sort((a, b) => a.start - b.start)) {
    const m = merged[merged.length - 1];
    if (m && s.start - m.stop <= 600) {
      m.stop = s.stop; m.xpGained = (m.xpGained || 0) + (s.xpGained || 0); m.levels = (m.levels || 0) + (s.levels || 0);
      m.deaths = (m.deaths || 0) + (s.deaths || 0); m.quests = (m.quests || 0) + (s.quests || 0);
      m.endLevel = s.endLevel; m.endXP = s.endXP; m.zones = [...arr(m.zones), ...arr(s.zones).filter((z) => !arr(m.zones).includes(z))];
    } else merged.push({ ...s, zones: arr(s.zones) });
  }
  for (const s of merged) {
    if (s.stop - s.start < 60) continue;
    const bz = { gained: s.xpGained || 0, level: s.endLevel, xp: s.endXP, fromLevel: s.startLevel, fromXp: s.startXP, at: s.stop * 1000, src: "addon" };
    const overlap = S.sessions.find((p) => p.src !== "addon" && p.startedAt < s.stop * 1000 && (p.endedAt || 0) > s.start * 1000);
    if (overlap) {
      const ob = overlap.bz;
      if (ob && (ob.merged || ob.combined)) continue;
      const cur = store.get("sessions/" + overlap._id);
      if (cur && JSON.stringify(cur.bz) !== JSON.stringify(bz)) store.update("sessions/" + overlap._id, { bz });
    } else {
      const row = { startedAt: s.start * 1000, endedAt: s.stop * 1000, durationMs: (s.stop - s.start) * 1000, xp: s.xpGained || 0,
        levels: s.levels || 0, startLevel: s.startLevel, endLevel: s.endLevel, deaths: s.deaths || 0, quests: s.quests || 0, zones: arr(s.zones).slice(-10), src: "addon", bz };
      const key = "sessions/addon-" + s.start;
      if (JSON.stringify(store.get(key)) !== JSON.stringify(row)) store.set(key, row);
    }
    n++;
  }
  done.push(`${n} play session${n === 1 ? "" : "s"} with exact XP`);

  // 2. XP needed per level
  const xm = ch.xpMax || {}; const levels = { ...((S.xpt && S.xpt.levels) || {}) }; n = 0;
  for (const [lv, v] of Object.entries(xm)) if (v > 0 && levels[lv] !== v) { levels[lv] = v; n++; }
  if (n) store.set("state/xptable", { levels, updatedAt: Date.now() });
  if (Object.keys(xm).length) done.push(`XP needed for ${Object.keys(xm).length} level${Object.keys(xm).length === 1 ? "" : "s"}`);
  if (S.char && xm[S.char.level] && S.char.needsXpMax) store.update("state/character", { xpMax: xm[S.char.level], needsXpMax: false });

  // 2b. Rested XP and where you are, as of the add-on's last save
  if (ch.stateAt && S.char && ch.stateAt * 1000 >= (S.char.stateAt || 0)) {
    const st = { rested: Math.max(0, ch.rested || 0), zone: ch.zone || S.char.zone || "", subzone: ch.subzone || "", resting: !!ch.resting, stateAt: ch.stateAt * 1000 };
    if (["rested", "zone", "subzone", "resting"].some((k) => S.char[k] !== st[k])) store.update("state/character", st);
    done.push(`rested ${st.rested.toLocaleString("en-US")} XP${st.zone ? " in " + st.zone : ""}`);
  }

  // 3. Training costs, matched to the class's abilities by name and rank
  if (ch.trainer && Object.keys(ch.trainer).length) {
    const ab = loadAbilities(publicDir);
    const cls = ((S.char && S.char.cls) || (ch.class || "").toLowerCase().replace(/^\w/, (c) => c.toUpperCase())).split(/[ (]/)[0];
    const list = ab.classes[cls] || [];
    const costs = { ...((store.get("state/trainercosts") || {}).costs || {}) };
    n = 0;
    for (const t of Object.values(ch.trainer)) {
      if (t.cost == null) continue;
      const a = list.find((e) => e.n === t.n && (e.r || "") === (t.r || "")) || list.find((e) => e.n === t.n && !t.r);
      if (a && costs[a.id] !== t.cost) { costs[a.id] = t.cost; n++; }
    }
    if (n) store.set("state/trainercosts", { costs, updatedAt: Date.now() });
    done.push(`${n} training cost${n === 1 ? "" : "s"}`);
  }

  // 4. Vendor prices (gold and Merchant's Favor)
  if (ch.vendors && Object.keys(ch.vendors).length) {
    const cur = { ...((S.vendors && S.vendors.v) || {}) };
    for (const [id, v] of Object.entries(ch.vendors)) {
      const items = {};
      for (const [iid, it] of Object.entries(v.items || {})) {
        const e = { n: it.n, p: it.price || 0 };
        const c = arr(it.cur).map((x) => [x.n || "?", x.amount || 0]);
        if (c.length) e.c = c;
        if (it.limited != null) e.l = it.limited;
        items[iid] = e;
      }
      cur[id] = { n: v.name, z: v.zone, xy: v.x != null ? [v.x, v.y] : null, at: (v.at || 0) * 1000, items };
    }
    store.set("state/vendors", { v: cur, updatedAt: Date.now() });
    done.push(`prices from ${Object.keys(ch.vendors).length} vendor${Object.keys(ch.vendors).length === 1 ? "" : "s"}`);
  }

  // 5. Loot by creature (the add-on keeps running totals, so this replaces earlier imports)
  if (ch.loot && Object.keys(ch.loot).length) {
    const npcs = {};
    for (const [id, e] of Object.entries(ch.loot)) {
      const items = {};
      for (const [iid, it] of Object.entries(e.items || {})) items[iid] = [it.n || "", it.q ?? 1, it.c || 0];
      npcs[id] = { n: e.name || "", z: e.zone || "", i: e.instance ? 1 : 0, o: e.opens || 0, items };
    }
    store.set("state/loot", { npcs, updatedAt: Date.now() });
    done.push(`loot from ${Object.keys(npcs).length} creature${Object.keys(npcs).length === 1 ? "" : "s"}`);
  }

  // 6. Quests turned in
  const doneSet = new Set((store.get("state/quests") || {}).completed || []);
  const marks = store.get("state/questmarks") || {};
  const md = { ...(marks.done || {}) }; n = 0;
  for (const q of arr(ch.quests)) if (q.id && !doneSet.has(q.id) && !md[q.id]) { md[q.id] = 1; n++; }
  if (n) store.set("state/questmarks", { done: md, hidden: { ...(marks.hidden || {}) }, updatedAt: Date.now() });
  done.push(`${n} newly turned-in quest${n === 1 ? "" : "s"}`);

  const message = `Imported for ${ch.name || "your character"}: ` + done.join(", ") + ".";
  // the add-on logs its own Lua errors (db.errors: {at, err}); show the latest few on the page
  const errors = arr(data.errors).filter((e) => e && e.err).slice(-10).map((e) => ({ at: e.at || 0, err: String(e.err).slice(0, 300) }));
  store.set("state/addon", { importedAt: Date.now(), savedAt: (data.savedAt || 0) * 1000, char: ch.name || "", played: ch.played || 0, deaths: ch.deaths || 0, auto: !!source, file: source || "", message, errors });
  return { message, savedAt: (data.savedAt || 0) * 1000 };
}

module.exports = { importAddon, readSaved, pickChar };
