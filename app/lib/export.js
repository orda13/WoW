// Export: one character's data as JSON (everything, for safekeeping) or as CSV tables for spreadsheets.
//   json        every document of this character, plus the shared ones (all characters' bags, prices, ticks)
//   sessions    one row per play session: time, levels, XP and XP per hour, kills, quests, deaths, gold in and out, zones
//   levels      when each level was reached and the play time it took
//   characters  every character the add-on knows: level, class, gold, rested XP, where, last played, professions
//   items       every item in every character's bags and bank
//   quests      quests completed (Blizzard and the add-on) and the ones in the quest log, with titles and zones
const fs = require("fs");
const path = require("path");

const KINDS = ["json", "sessions", "levels", "characters", "items", "quests"];
const ALT_PREFIX = /^c[0-9a-f]{8}\./;

// a CSV cell: quoted when needed; text that a spreadsheet would read as a formula gets a leading apostrophe
function cell(v) {
  if (v == null) return "";
  let s = typeof v === "number" ? (Number.isFinite(v) ? String(v) : "") : String(v);
  if (typeof v !== "number" && /^[=+\-@\t\r]/.test(s)) s = "'" + s;
  return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
}
const csv = (head, rows) => "﻿" + [head, ...rows].map((r) => r.map(cell).join(",")).join("\r\n") + "\r\n";
const iso = (ms) => (ms ? new Date(ms).toISOString().replace("T", " ").slice(0, 16) : "");
const gold = (copper) => (copper == null ? "" : Math.round(copper) / 10000);
const sum = (o) => Object.values(o || {}).reduce((a, b) => a + (Number(b) || 0), 0);
const hidden = (store) => (store.get("shared/hiddenchars") || {}).ids || {};

// quest titles and zones from the page's own quest data
let questNames = null;
function questInfo(publicDir) {
  if (questNames) return questNames;
  questNames = new Map();
  for (const f of ["quests-forever.json", "quests-att-forever.json"]) {
    try {
      for (const z of JSON.parse(fs.readFileSync(path.join(publicDir, f), "utf8")).zones || [])
        for (const q of z.q || []) if (!questNames.has(q.i)) questNames.set(q.i, { t: q.t, z: z.z });
    } catch { /* missing file: ids only */ }
  }
  return questNames;
}

// item names the game hasn't reported yet: from the page's item and materials data
let itemNames = null;
function itemInfo(publicDir) {
  if (itemNames) return itemNames;
  itemNames = new Map();
  for (const [f, key] of [["items-forever.json", "items"], ["materials-forever.json", "materials"]]) {
    try { for (const [id, v] of Object.entries(JSON.parse(fs.readFileSync(path.join(publicDir, f), "utf8"))[key] || {})) if (v && v.n && !itemNames.has(id)) itemNames.set(id, v.n); }
    catch { /* missing file: names from the game only */ }
  }
  return itemNames;
}
const titleCase = (s) => String(s || "").toLowerCase().replace(/\b[a-z]/g, (c) => c.toUpperCase());

function build(store, cs, kind, name, publicDir) {
  if (kind === "json") {
    const pre = cs.id ? cs.id + "." : "";
    const docs = {}, shared = {};
    for (const k of Object.keys(store.docs || {}).sort()) {
      if (k.startsWith("shared/")) shared[k] = store.docs[k];
      else if (pre ? k.startsWith(pre) : !ALT_PREFIX.test(k)) docs[pre ? k.slice(pre.length) : k] = store.docs[k];
    }
    return JSON.stringify({ exported: new Date().toISOString(), character: name, docs, shared }, null, 1);
  }
  if (kind === "sessions") {
    const rows = cs.list("sessions").map((d) => d.data).filter((s) => s && s.startedAt).sort((a, b) => a.startedAt - b.startedAt).map((s) => {
      const ms = s.durationMs || ((s.endedAt || s.startedAt) - s.startedAt), xp = s.xp || (s.bz && s.bz.gained) || 0;
      return [iso(s.startedAt), iso(s.endedAt), Math.round(ms / 60000), s.startLevel ?? "", s.endLevel ?? "", s.levels || 0, xp,
        ms > 0 ? Math.round(xp / (ms / 3600000)) : "", s.kills ?? "", s.killXP ?? "", s.questXP ?? "", s.quests || 0, s.deaths || 0,
        s.moneyIn ? gold(sum(s.moneyIn)) : "", s.moneyOut ? gold(sum(s.moneyOut)) : "", (s.zones || []).join("; "), s.src === "addon" ? "add-on" : s.src || "page"];
    });
    return csv(["Started", "Ended", "Minutes", "Start level", "End level", "Levels gained", "XP", "XP per hour", "Kills", "Kill XP", "Quest XP",
      "Quests", "Deaths", "Gold earned", "Gold spent", "Zones", "Recorded by"], rows);
  }
  if (kind === "levels") {
    const by = new Map();
    for (const { data: d } of cs.list("dings")) if (d && d.level && (!by.has(d.level) || (d.at && d.at < by.get(d.level).at))) by.set(d.level, d);
    const rows = [...by.values()].sort((a, b) => a.level - b.level).map((d) => [d.level, iso(d.at), d.trackedMs ? Math.round(d.trackedMs / 360000) / 10 : ""]);
    return csv(["Level", "Reached", "Hours played to reach it"], rows);
  }
  if (kind === "characters" || kind === "items") {
    const inv = Object.entries((store.get("shared/inventories") || {}).chars || {}).filter(([id]) => !hidden(store)[id]).map(([, c]) => c)
      .sort((a, b) => (b.level || 0) - (a.level || 0) || String(a.name).localeCompare(String(b.name)));
    if (kind === "characters") {
      const rows = inv.map((c) => [c.name, c.account, c.level, titleCase(c.cls), c.faction, gold(c.money), c.rested || 0, c.resting ? "yes" : "no",
        [c.zone, c.subzone && c.subzone !== c.zone ? c.subzone : ""].filter(Boolean).join(", "), iso(c.at), sum(c.bags), sum(c.bank),
        Object.entries(c.professions || {}).map(([n, r]) => `${n} ${r}`).join("; ")]);
      return csv(["Character", "WoW account", "Level", "Class", "Faction", "Gold", "Rested XP", "Resting", "Where", "Last played", "Items in bags", "Items in bank", "Professions"], rows);
    }
    const names = (store.get("shared/items") || {}).items || {}, known = itemInfo(publicDir);
    const rows = [];
    for (const c of inv) {
      for (const id of [...new Set([...Object.keys(c.bags || {}), ...Object.keys(c.bank || {})])].sort((a, b) => a - b)) {
        const n = names[id];
        rows.push([c.name, c.account, Number(id), (Array.isArray(n) ? n[0] : n && n.n) || known.get(id) || "", (c.bags || {})[id] || 0, (c.bank || {})[id] || 0]);
      }
    }
    return csv(["Character", "WoW account", "Item ID", "Item", "In bags", "In bank"], rows);
  }
  if (kind === "quests") {
    const info = questInfo(publicDir);
    const done = new Set([...((cs.get("state/quests") || {}).completed || []), ...Object.keys((cs.get("state/questmarks") || {}).done || {}).map(Number)]);
    const log = ((cs.get("state/questlog") || {}).quests || []).filter((q) => q && q.id);
    const rows = [...done].filter((id) => id > 0).sort((a, b) => a - b).map((id) => [id, (info.get(id) || {}).t || "", (info.get(id) || {}).z || "", "completed", ""]);
    for (const q of log) if (!done.has(q.id)) rows.push([q.id, q.t || (info.get(q.id) || {}).t || "", (info.get(q.id) || {}).z || "", q.done ? "ready to turn in" : "in the quest log", iso(q.at)]);
    return csv(["Quest ID", "Quest", "Zone", "Status", "Accepted"], rows);
  }
  return null;
}

// -> { body, type, filename } or null for an unknown kind
function exportData(store, cs, kind, name, publicDir) {
  if (!KINDS.includes(kind)) return null;
  const body = build(store, cs, kind, name, publicDir);
  const who = String(name || "character").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "character";
  const day = new Date().toISOString().slice(0, 10);
  return { body, type: kind === "json" ? "application/json; charset=utf-8" : "text/csv; charset=utf-8", filename: `leveling-ledger-${who}-${kind}-${day}.${kind === "json" ? "json" : "csv"}` };
}

module.exports = { exportData, KINDS };
