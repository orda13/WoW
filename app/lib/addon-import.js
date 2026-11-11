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
// hint: the character from the settings (e.g. "talwyn-orda"), used before Blizzard has filled in the character
function pickChar(data, store, hint) {
  if (!data || !data.chars) return null;
  const chars = Object.values(data.chars);
  const c = store.get("state/character");
  const last = store.get("state/addon");
  const want = ((c && c.name) || (hint || "").split("-")[0] || (last && last.char) || "").split(" ")[0].toLowerCase();
  if (!want) return chars[0] || null;
  // the same name can appear more than once (another realm, or the realm's name changed): take the one played most recently
  const same = chars.filter((x) => (x.name || "").toLowerCase() === want);
  return same.sort((a, b) => lastActive(b) - lastActive(a))[0] || null;
}
function lastActive(c) {
  let t = c.skillsAt || 0;
  for (const s of arr(c.sessions)) t = Math.max(t, s.stop || 0, s.start || 0);
  for (const x of Object.values(c.trainer || {})) t = Math.max(t, (x && x.at) || 0);
  return t;
}

// Which PC a file came from: files sent by a relay are kept in data/relay/<device>/<account>/SavedVariables/
function sourceKey(file) {
  const parts = String(file || "").split(/[\\/]+/);
  const acc = parts.length >= 3 ? parts[parts.length - 3] : "";
  const r = parts.lastIndexOf("relay");
  if (r >= 0 && parts.length > r + 2) return `${parts[r + 1]}/${parts[r + 2]}`;
  return `This PC/${acc}`;
}

function readSaved(text) {
  if (/CreateFrame\(|RegisterEvent\(/.test(text)) throw new Error("That's the add-on's own code, not its saved data.");
  return parseLuaSaved(text).LevelingLedgerDB;
}

// Kills, where the XP came from, and gold (older saves have only some of these)
function splitOf(s) {
  const o = {};
  if (s.killXP != null || s.questXP != null) { o.kills = s.kills || 0; o.killXP = s.killXP || 0; o.questXP = s.questXP || 0; }
  // profession skill-ups and recipes learned (1.0.6+)
  if (s.skillups && Object.keys(s.skillups).length) o.skillups = Object.fromEntries(Object.entries(s.skillups).map(([n, v]) => [n, { from: v.from, to: v.to }]));
  if (s.recipesLearned) { const r = arr(s.recipesLearned); if (r.length) o.recipesLearned = r; }
  // reputation gains (1.0.7+): running totals, so gained = to - from
  if (s.repGains && Object.keys(s.repGains).length) o.repGains = Object.fromEntries(Object.entries(s.repGains).map(([n, v]) => [n, { from: v.from, to: v.to, fromStanding: v.fromStanding, toStanding: v.toStanding, min: v.min, max: v.max }]));
  // XP and seconds per zone and per level (1.0.26+), for the leveling report
  for (const k of ["byZone", "byLevel"]) if (s[k] && typeof s[k] === "object") {
    const m = {};
    for (const [key, v] of Object.entries(s[k])) if (v && (v.sec > 0 || v.xp > 0)) m[key] = { xp: Math.max(0, v.xp || 0), sec: Math.max(0, v.sec || 0) };
    if (Object.keys(m).length) o[k] = m;
  }
  // gold, in copper: start and end money (add-on 1.0.2+), and where it came from and went (1.0.5+)
  if (s.startMoney != null && s.endMoney != null) {
    o.gold = { start: s.startMoney, end: s.endMoney };
    if (s.moneyIn || s.moneyOut) { o.gold.in = { ...(s.moneyIn || {}) }; o.gold.out = { ...(s.moneyOut || {}) }; }
  }
  return o;
}

function importAddon(text, store, publicDir, source, hint) {
  const data = readSaved(text);
  if (!data || !data.chars) throw new Error("That file has no Leveling Ledger data.");
  const ch = pickChar(data, store, hint);
  if (!ch) throw new Error("That file has no data for this ledger's character.");
  // 0. A character Blizzard doesn't serve yet (under level 10, or not synced): start its ledger from the add-on,
  //    and keep its level and XP current from the add-on whenever that's newer. A Blizzard sync later fills in the rest.
  const nice = (t) => String(t || "").toLowerCase().replace(/(^|_)(\w)/g, (m, a, b) => (a ? " " : "") + b.toUpperCase());
  const spaced = (t) => String(t || "").replace(/([a-z])([A-Z])/g, "$1 $2");
  let have = store.get("state/character");
  if (!have && ch.name) {
    have = { name: ch.name, version: "World of Warcraft: Forever", maxLevel: 60, level: ch.level || 1, xp: ch.lastXP || 0,
      xpMax: (ch.xpMax && ch.xpMax[ch.level]) || 0, needsXpMax: !(ch.xpMax && ch.xpMax[ch.level]), rested: ch.rested || 0, zone: ch.zone || "",
      trackedMs: 0, faction: ch.faction || "", region: "US", race: spaced(ch.race), cls: nice(ch.class), src: "addon" };
    store.set("state/character", have);
    store.set("dings/start-" + have.level, { level: have.level, at: Date.now(), trackedMs: 0 });
  } else if (have && ch.level && ch.level > (have.level || 0)) {
    for (let lv = (have.level || 0) + 1; lv <= ch.level; lv++) {
      const at = ch.levels && ch.levels[lv] && ch.levels[lv].at ? ch.levels[lv].at * 1000 : Date.now();
      store.set(`dings/addon-${lv}`, { level: lv, at, trackedMs: have.trackedMs || 0 });
    }
    const xmax = ch.xpMax && ch.xpMax[ch.level];
    store.update("state/character", { level: ch.level, xp: ch.lastXP || 0, xpMax: xmax || 0, needsXpMax: !xmax });
  } else if (have && have.src === "addon" && ch.level === have.level && ch.lastXP != null && ch.lastXP !== have.xp) {
    store.update("state/character", { xp: ch.lastXP });
  }
  const S = {
    char: store.get("state/character") || null,
    xpt: store.get("state/xptable") || null,
    vendors: store.get("state/vendors") || null,
    sessions: store.list("sessions").map((d) => ({ ...d.data, _id: d.id })),
  };
  const done = []; let n;
  const src = sourceKey(source);

  // 1. Sessions with exact XP and time (reload pieces less than 10 minutes apart are joined)
  n = 0;
  const merged = [];
  for (const s of arr(ch.sessions).filter((x) => x.start && x.stop).sort((a, b) => a.start - b.start)) {
    const m = merged[merged.length - 1];
    if (m && s.start - m.stop <= 600) {
      m.stop = s.stop; m.xpGained = (m.xpGained || 0) + (s.xpGained || 0); m.levels = (m.levels || 0) + (s.levels || 0);
      m.deaths = (m.deaths || 0) + (s.deaths || 0); m.quests = (m.quests || 0) + (s.quests || 0);
      for (const k of ["kills", "killXP", "questXP"]) if (s[k] != null) m[k] = (m[k] || 0) + s[k];
      if (s.endMoney != null) m.endMoney = s.endMoney;
      if (s.skillups) { m.skillups = { ...(m.skillups || {}) }; for (const [n, v] of Object.entries(s.skillups)) m.skillups[n] = { from: m.skillups[n] ? m.skillups[n].from : v.from, to: v.to }; }
      if (s.repGains) { m.repGains = { ...(m.repGains || {}) }; for (const [n, v] of Object.entries(s.repGains)) { const p = m.repGains[n]; m.repGains[n] = p ? { ...v, from: p.from, fromStanding: p.fromStanding } : v; } }
      if (s.recipesLearned) m.recipesLearned = [...arr(m.recipesLearned), ...arr(s.recipesLearned)];
      for (const k of ["byZone", "byLevel"]) if (s[k]) { m[k] = { ...(m[k] || {}) }; for (const [key, v] of Object.entries(s[k])) { const p = m[k][key] || { xp: 0, sec: 0 }; m[k][key] = { xp: (p.xp || 0) + (v.xp || 0), sec: (p.sec || 0) + (v.sec || 0) }; } }
      for (const k of ["moneyIn", "moneyOut"]) if (s[k]) { m[k] = { ...(m[k] || {}) }; for (const [kind, v] of Object.entries(s[k])) m[k][kind] = (m[k][kind] || 0) + v; }
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
      const upd = { bz, ...splitOf(s) };
      if (cur && Object.keys(upd).some((k) => JSON.stringify(cur[k]) !== JSON.stringify(upd[k]))) store.update("sessions/" + overlap._id, upd);
    } else {
      const row = { startedAt: s.start * 1000, endedAt: s.stop * 1000, durationMs: (s.stop - s.start) * 1000, xp: s.xpGained || 0,
        levels: s.levels || 0, startLevel: s.startLevel, endLevel: s.endLevel, deaths: s.deaths || 0, quests: s.quests || 0, zones: arr(s.zones).slice(-10), src: "addon", bz, ...splitOf(s) };
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

  // 2c. Professions: skill levels, known recipes per profession, recipes learned (1.0.6+)
  if (ch.skillsAt || ch.recipesAt) {
    // several PCs: skill levels from whichever saved most recently; recipe lists and learned recipes combined
    const prev = store.get("state/addonskills") || {};
    const recipes = { ...(prev.recipes || {}) };
    for (const [prof, list] of Object.entries(ch.recipes || {})) recipes[prof] = [...new Set([...(recipes[prof] || []), ...arr(list)])].sort();
    const newer = (ch.skillsAt || 0) * 1000 >= (prev.skillsAt || 0);
    const learned = new Map((prev.learned || []).map((x) => [x.n + "@" + x.at, x]));
    for (const x of arr(ch.learned)) learned.set(x.n + "@" + (x.at || 0) * 1000, { n: x.n, at: (x.at || 0) * 1000 });
    const doc = {
      skills: newer ? (ch.skills || prev.skills || {}) : (prev.skills || {}), skillsAt: Math.max((ch.skillsAt || 0) * 1000, prev.skillsAt || 0),
      recipes, recipesAt: Math.max((ch.recipesAt || 0) * 1000, prev.recipesAt || 0),
      learned: [...learned.values()].sort((a, b) => a.at - b.at).slice(-200),
    };
    if (JSON.stringify(doc) !== JSON.stringify(prev)) store.set("state/addonskills", doc);
    const nSk = Object.keys(doc.skills).length;
    done.push(`${nSk} profession${nSk === 1 ? "" : "s"}`);
  }

  // 2d. Reputation standings (1.0.7+)
  if (ch.repsAt && ch.reps) {
    const doc = { reps: ch.reps, at: ch.repsAt * 1000 };
    const prev = store.get("state/addonreps");
    if ((!prev || doc.at >= (prev.at || 0)) && JSON.stringify(doc) !== JSON.stringify(prev)) store.set("state/addonreps", doc);
  }

  // 2f. Library Books this character has handed in or holds (Collections.lua; the newest copy wins)
  if (ch.books && ch.books.at) {
    const list = (v) => (Array.isArray(v) ? v : v && typeof v === "object" ? Object.values(v) : []).map(Number).filter((n) => n > 0 && n < 1000);
    const doc = { done: list(ch.books.done), bags: list(ch.books.bags), at: ch.books.at * 1000 };
    const prev = store.get("state/books");
    if (!prev || doc.at > (prev.at || 0)) { store.set("state/books", doc); done.push(`${doc.done.length} Library Book${doc.done.length === 1 ? "" : "s"}`); }
  }

  // 2g. quest chains' quests (Cozy Sleeping Bag): completed, or in the quest log (Collections.lua)
  if (ch.chainq && ch.chainq.at) {
    const ids = (v) => (Array.isArray(v) ? v : v && typeof v === "object" ? Object.values(v) : []).map(Number).filter((n) => n > 0);
    const doc = { done: ids(ch.chainq.done), log: ids(ch.chainq.log), at: ch.chainq.at * 1000 };
    const prev = store.get("state/chainq");
    if (!prev || doc.at > (prev.at || 0)) store.set("state/chainq", doc);
  }

  // 2h. WoW Forever secrets the game shows done (Collections.lua): ids like "torch"; kept once seen
  if (ch.secrets && ch.secrets.at) {
    const ids = (Array.isArray(ch.secrets.done) ? ch.secrets.done : ch.secrets.done && typeof ch.secrets.done === "object" ? Object.values(ch.secrets.done) : [])
      .map(String).filter((x) => /^[a-z0-9-]{1,40}$/.test(x));
    const prev = store.get("state/secrets");
    const doc = { done: [...new Set([...((prev && prev.done) || []), ...ids])].sort(), at: ch.secrets.at * 1000 };
    if (!prev || (doc.at > (prev.at || 0) && JSON.stringify(doc.done) !== JSON.stringify(prev.done))) { store.set("state/secrets", doc); done.push(`${doc.done.length} secret${doc.done.length === 1 ? "" : "s"}`); }
  }

  // 2e. Ask Mr. Robot's gear setups and sell list, copied by MrRobot.lua from its add-on (the newest copy wins)
  if (ch.amr && ch.amr.at) {
    const list = (v) => Array.isArray(v) ? v : v && typeof v === "object" ? Object.values(v) : [];
    const ids = (v) => list(v).map(Number).filter((n) => n > 0);
    const doc = {
      at: ch.amr.at * 1000,
      setups: list(ch.amr.setups).map((s) => ({
        label: String(s.label || "Setup").slice(0, 80), spec: Number(s.spec) || 0, bib: !!Number(s.bib),
        gear: list(s.gear).map((g) => list(g).map(Number)).filter((g) => g[0] > 0 && g[1] > 0).map(([slot, id, ench]) => ({ slot, id, ench: ench || 0 })),
      })).filter((s) => s.gear.length),
      junk: ids(ch.amr.junk), keep: ids(ch.amr.keep), names: {},
    };
    for (const [k, v] of Object.entries(ch.amr.names || {})) if (Number(k) > 0 && typeof v === "string") doc.names[Number(k)] = v.slice(0, 100);
    const prev = store.get("state/amr");
    if (!prev || doc.at > (prev.at || 0)) { store.set("state/amr", doc); done.push(`Ask Mr. Robot: ${doc.setups.length} gear setup${doc.setups.length === 1 ? "" : "s"}`); }
  }

  // 3. Trainers: class ability costs (matched by name and rank), and what profession trainers teach.
  //    Costs seen at a trainer are marked as coming from the add-on (the page shows them read-only).
  if (ch.trainer && Object.keys(ch.trainer).length) {
    const ab = loadAbilities(publicDir);
    const cls = ((S.char && S.char.cls) || (ch.class || "").toLowerCase().replace(/^\w/, (c) => c.toUpperCase())).split(/[ (]/)[0];
    const list = ab.classes[cls] || [];
    const prev = store.get("state/trainercosts") || {};
    const costs = { ...(prev.costs || {}) }, fromAddon = { ...(prev.fromAddon || {}) };
    const recipes = { ...((store.get("state/trainerrecipes") || {}).byName || {}) };
    let nA = 0, nR = 0, noCost = 0, older = 0, same = 0, unmatched = 0, cleaned = 0;
    const matched = new Set();
    // Add-on 1.0.19 and older stored this client's status word (available, unavailable, used) as the rank
    const STATUS = new Set(["available", "unavailable", "used", "header"]);
    const entries = Object.values(ch.trainer).filter(Boolean).map((t) => STATUS.has(t.r) ? { ...t, r: "", state: t.r } : t).filter((t) => t.state !== "header");
    // class spells an earlier import filed as profession recipes
    for (const [k, v] of Object.entries(recipes)) if (list.some((e) => e.n === (v && v.n))) { delete recipes[k]; cleaned++; }
    // Ranks you've already learned show level 0 and share one entry: it's the highest rank up to your level that
    // the same trainer visit doesn't still offer (those come with their level).
    const lvl = ch.level || (S.char && S.char.level) || 0;
    const offered = new Set(entries.filter((t) => t.lv && t.state !== "used").map((t) => `${t.n}|${t.lv}|${t.at}`));
    const learnedRank = (byName, t) => byName.filter((e) => !e.auto && e.lv <= lvl && !offered.has(`${t.n}|${e.lv}|${t.at}`)).sort((x, y) => y.lv - x.lv)[0] || null;
    for (const t of entries) {
      if (t.cost == null || !t.n) { noCost++; continue; }
      const at = (t.at || 0) * 1000;
      // Each rank needs its own level, so name + level picks the exact rank (this client's trainer gives no rank text).
      // Name + rank is the fallback for entries without a level; a bare name only matches a spell with a single rank.
      const byName = list.filter((e) => e.n === t.n);
      const a = (t.lv ? byName.find((e) => e.lv === t.lv) : null)
        || (t.state === "used" && !t.lv ? learnedRank(byName, t) : null)
        || (t.r ? byName.find((e) => (e.r || "") === t.r) : null)
        || (!t.lv && !t.r && byName.length === 1 ? byName[0] : null);
      if (a) matched.add(String(a.id));
      else if (byName.length) { unmatched++; continue; } // a class spell we can't place: don't guess its rank
      if (a) {
        const f = fromAddon[a.id];
        if (f && (f.at || 0) > at) { older++; continue; } // another device saw this trainer more recently
        // lv: the rank's own level (marks a placed match); state: available / unavailable / used at that visit
        const state = t.state === "available" || t.state === "unavailable" || t.state === "used" ? t.state : "";
        if (costs[a.id] !== t.cost || !f || !f.lv || (state && f.state !== state)) { costs[a.id] = t.cost; fromAddon[a.id] = { at, npc: t.npc || null, by: t.npcName || "", lv: a.lv, state }; nA++; } else same++;
      } else {
        const k = t.n.toLowerCase() + (t.r ? "|" + String(t.r).toLowerCase() : "");
        const cur = recipes[k];
        if (cur && (cur.at || 0) > at) { older++; continue; }
        const v = { n: t.n, r: t.r || "", cost: t.cost, npc: t.npc || null, by: t.npcName || "", line: t.line || "", sk: t.sk || "", skr: t.skr || 0, lv: t.lv || 0, at };
        if (JSON.stringify(cur) !== JSON.stringify(v)) { recipes[k] = v; nR++; } else same++;
      }
    }
    // Earlier imports matched rankless entries to Rank 1 with another rank's price. Those matches have no level;
    // drop them where this file places the spell by level, so the page doesn't show a wrong locked price.
    const covered = new Set(entries.filter((t) => t.lv && t.n).map((t) => t.n));
    let fixed = 0;
    for (const id of Object.keys(fromAddon)) {
      const e = list.find((x) => String(x.id) === id);
      if (e && covered.has(e.n) && !matched.has(id) && !fromAddon[id].lv) { delete fromAddon[id]; delete costs[id]; fixed++; }
    }
    if (nA || fixed) store.set("state/trainercosts", { costs, fromAddon, updatedAt: Date.now() });
    if (nR || cleaned) store.set("state/trainerrecipes", { byName: recipes, updatedAt: Date.now() });
    const total = entries.length;
    const why = !nA && !nR ? ` (${total} trainer entries: ${[same && `${same} already imported`, noCost && `${noCost} without a price`, older && `${older} older than what's saved`, unmatched && `${unmatched} not matched to a rank`].filter(Boolean).join(", ") || "none usable"})` : "";
    done.push((!nA && same && !unmatched ? "training costs up to date" : `${nA} training cost${nA === 1 ? "" : "s"}`) + (nR ? `, ${nR} trainer price${nR === 1 ? "" : "s"} for recipes` : "") + why);
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
      const at = (v.at || 0) * 1000;
      if (cur[id] && (cur[id].at || 0) > at) continue; // another PC saw this vendor more recently
      cur[id] = { n: v.name, z: v.zone, xy: v.x != null ? [v.x, v.y] : null, at, items };
    }
    store.set("state/vendors", { v: cur, updatedAt: Date.now() });
    done.push(`prices from ${Object.keys(ch.vendors).length} vendor${Object.keys(ch.vendors).length === 1 ? "" : "s"}`);
  }

  // 5. Loot by creature. Each PC's add-on keeps its own running totals, so they're kept per PC and added together.
  if (ch.loot && Object.keys(ch.loot).length) {
    const mine = {};
    for (const [id, e] of Object.entries(ch.loot)) {
      const items = {};
      for (const [iid, it] of Object.entries(e.items || {})) items[iid] = [it.n || "", it.q ?? 1, it.c || 0];
      mine[id] = { n: e.name || "", z: e.zone || "", i: e.instance ? 1 : 0, o: e.opens || 0, items };
    }
    const prev = store.get("state/loot") || {};
    const sources = { ...(prev.sources || {}), [src]: mine };
    const npcs = {};
    for (const one of Object.values(sources)) for (const [id, e] of Object.entries(one)) {
      const t = npcs[id] || (npcs[id] = { n: e.n, z: e.z, i: e.i, o: 0, items: {} });
      if (!t.n && e.n) t.n = e.n;
      t.o += e.o || 0;
      for (const [iid, [n, q, c]] of Object.entries(e.items)) { const x = t.items[iid] || (t.items[iid] = [n, q, 0]); x[2] += c; }
    }
    store.set("state/loot", { npcs, sources, updatedAt: Date.now() });
    done.push(`loot from ${Object.keys(mine).length} creature${Object.keys(mine).length === 1 ? "" : "s"}`);
  }

  // 6. Quests turned in
  const doneSet = new Set((store.get("state/quests") || {}).completed || []);
  const marks = store.get("state/questmarks") || {};
  const md = { ...(marks.done || {}) }; n = 0;
  for (const q of arr(ch.quests)) if (q.id && !doneSet.has(q.id) && !md[q.id]) { md[q.id] = 1; n++; }
  if (n) store.set("state/questmarks", { done: md, hidden: { ...(marks.hidden || {}) }, updatedAt: Date.now() });
  done.push(`${n} newly turned-in quest${n === 1 ? "" : "s"}`);

  // 7. Quests in progress (from the quest log), and how long recent turn-ins took. The newest log of any device wins.
  if (ch.questLog && typeof ch.questLog === "object") {
    const at = (ch.questLogAt || 0) * 1000, prev = store.get("state/questlog") || {};
    if (at >= (prev.at || 0)) {
      const quests = Object.entries(ch.questLog).filter(([id, q]) => /^\d+$/.test(id) && q).map(([id, q]) => ({
        id: +id, t: q.t || "", lv: q.lv || null, at: (q.at || 0) * 1000, done: !!q.done,
        ob: arr(q.ob).map((o) => ({ text: o.text || "", have: o.have ?? null, need: o.need ?? null, done: !!o.done })),
      }));
      const took = { ...(prev.took || {}) };
      for (const q of arr(ch.quests)) if (q.id && q.took > 0) took[q.id] = { s: q.took, at: (q.at || 0) * 1000, xp: q.xp || 0 };
      store.set("state/questlog", { quests, took, at, updatedAt: Date.now() });
      done.push(`${quests.length} quest${quests.length === 1 ? "" : "s"} in progress`);
    }
  }

  // 8. Where you gathered (herbs, ore and other objects, with map position), merged across devices
  if (Array.isArray(arr(ch.gathers)) && arr(ch.gathers).length) {
    const prev = (store.get("state/gathers") || {}).list || [];
    const seen = new Set(prev.map((g) => `${g.o}|${g.at}|${g.x}|${g.y}`));
    let added = 0; const list = prev.slice();
    for (const g of arr(ch.gathers)) {
      if (!g || !g.o || g.x == null || g.y == null) continue;
      const e = { o: g.o, z: String(g.z || ""), x: +g.x, y: +g.y, at: (g.at || 0) * 1000 };
      if (g.s) e.s = 1; // skinned (o is a creature), not an object
      const k = `${e.o}|${e.at}|${e.x}|${e.y}`; if (seen.has(k)) continue;
      seen.add(k); list.push(e); added++;
    }
    if (added) { list.sort((a, b) => a.at - b.at); store.set("state/gathers", { list: list.slice(-5000), updatedAt: Date.now() }); done.push(`${added} gathering spot${added === 1 ? "" : "s"}`); }
  }

  const message = `Imported for ${ch.name || "your character"}: ` + done.join(", ") + ".";
  // the add-on logs its own Lua errors (db.errors: {at, err}); show the latest few on the page
  const errors = arr(data.errors).filter((e) => e && e.err).slice(-10).map((e) => ({ at: e.at || 0, err: String(e.err).slice(0, 300) }));
  // per PC: when its file was last saved and imported (the watcher skips a PC's file that hasn't changed)
  const prevAddon = store.get("state/addon") || {};
  const savedAt = (data.savedAt || 0) * 1000;
  const sources = { ...(prevAddon.sources || {}), [src]: { savedAt, importedAt: Date.now() } };
  const newest = Math.max(savedAt, prevAddon.savedAt || 0);
  store.set("state/addon", { importedAt: Date.now(), savedAt: newest, char: ch.name || "", played: Math.max(ch.played || 0, prevAddon.played || 0), deaths: Math.max(ch.deaths || 0, prevAddon.deaths || 0), auto: !!source, file: source || "", from: src, message, errors, sources });
  return { message, savedAt: (data.savedAt || 0) * 1000 };
}

module.exports = { importAddon, readSaved, pickChar, sourceKey };
