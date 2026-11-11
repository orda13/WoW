// Leveling Ledger, local edition. No packages to install: run with `node server.js`.
const http = require("http");
const fs = require("fs");
const path = require("path");
const { Store } = require("./lib/store");
const { startWatcher } = require("./lib/watcher");
const { syncBlizzard, resetToken } = require("./lib/blizzard");
const { checkJournal } = require("./lib/journal");
const { checkRequest, viaCloudflare } = require("./lib/access");
const { publicView, applyUpdate, saveConfig, newAlts } = require("./lib/settings");
const { exportData } = require("./lib/export");
const { importAddon } = require("./lib/addon-import");
const { startBackups } = require("./lib/backups");
const { startUpdater } = require("./lib/updater");
const { characters, charStore } = require("./lib/characters");
const { mergeInventories, tidyInventories } = require("./lib/inventory");
const { readSaved } = require("./lib/addon-import");
const { buildSummary, writeShared } = require("./lib/summary");
const { tenantStore, viewPath, users, tenantFor, accessConfig, charConfig, userDir } = require("./lib/tenants");
const { relayVersion, relayBundle } = require("./lib/relaybundle");

const APP = __dirname;
const CONFIG_FILE = process.env.LL_CONFIG || path.join(APP, "config.json");
const PUBLIC = path.join(APP, "public");
const VERSION = "1.0.0";

// Training costs the add-on read at a trainer can't be changed from the page: they're kept as the add-on recorded them.
function keepAddonCosts(st, dp, body) {
  if (!/(^|\.)state\/trainercosts$/.test(dp) || !body || typeof body !== "object") return body;
  const prev = st.get(dp) || {};
  const fromAddon = prev.fromAddon || {};
  const costs = { ...((body.costs && typeof body.costs === "object") ? body.costs : {}) };
  for (const id of Object.keys(fromAddon)) if (prev.costs && prev.costs[id] != null) costs[id] = prev.costs[id];
  return { ...body, costs, fromAddon };
}
function log(msg) { console.log(new Date().toISOString() + " " + msg); }
function loadConfig() {
  if (!fs.existsSync(CONFIG_FILE)) { log("No config.json yet; using defaults. Copy config.example.json to config.json."); return {}; }
  return JSON.parse(fs.readFileSync(CONFIG_FILE, "utf8").replace(/^\uFEFF/, "")); // Windows editors may add a byte-order mark
}
const config = loadConfig();
// these objects are shared with the watcher, sync and sign-in check, and updated in place by the Settings tab
config.blizzard = config.blizzard || {};
config.access = config.access || {};
const PORT = config.port || 8787;
const dataDir = config.dataDir ? path.resolve(APP, config.dataDir) : path.join(APP, "data");
const store = new Store(path.join(dataDir, "store.json"), path.join(dataDir, "seed.json"));

// ---------- daily backups (data/backups, last 14 days by default) ----------
const backups = startBackups({ store, dir: path.join(dataDir, "backups"), keepDays: () => config.backupDays || 14, log });

// ---------- page ----------
let pageCache = null, pageMtime = 0;
function page() {
  const f = path.join(PUBLIC, "leveling-ledger.html");
  const m = fs.statSync(f).mtimeMs;
  if (!pageCache || m !== pageMtime) {
    pageMtime = m;
    pageCache = '<!doctype html>\n<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">' +
      '<link rel="icon" href="data:,"><script src="local-shim.js"></script></head><body>\n' + fs.readFileSync(f, "utf8") + "\n</body></html>";
  }
  return pageCache;
}
const TYPES = { ".json": "application/json; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8", ".png": "image/png", ".svg": "image/svg+xml" };

// ---------- live updates (Server-Sent Events) ----------
// each page hears only its own person's changes (plus the shared game data), with the paths in that person's terms
const clients = new Map(); // res -> person id ("" for the owner)
store.on("change", (ev) => {
  for (const [res, uid] of clients) { const vp = viewPath(ev.path, uid); if (vp) res.write("data: " + JSON.stringify({ ...ev, path: vp }) + "\n\n"); }
});
setInterval(() => { for (const res of clients.keys()) res.write(": ping\n\n"); }, 25000);

// ---------- helpers ----------
function send(res, code, body, type) {
  res.writeHead(code, { "Content-Type": type || "application/json; charset=utf-8", "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "Referrer-Policy": "no-referrer" });
  res.end(typeof body === "string" || Buffer.isBuffer(body) ? body : JSON.stringify(body));
}
function readBody(req, limit = 8 * 1024 * 1024) {
  return new Promise((resolve, reject) => {
    let size = 0; const chunks = [];
    req.on("data", (c) => { size += c.length; if (size > limit) { reject(new Error("too large")); req.destroy(); } else chunks.push(c); });
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}
async function json(req) { const t = await readBody(req); const v = t ? JSON.parse(t) : {}; if (!v || typeof v !== "object" || Array.isArray(v)) throw new Error("expected an object"); return v; }

// ---------- Blizzard sync schedule ----------
const bcfg = config.blizzard;
// ---------- people and their characters ----------
// The owner (this PC and the emails in Remote access) and each person added in Settings; each has a view of the store,
// a main character and alts, and a relay folder. tenantOf(null) is the owner.
const tenantCache = new Map();
function readJsonFile(f) { try { return JSON.parse(fs.readFileSync(f, "utf8")); } catch { return {}; } }
function tenantOf(u) {
  const uid = u ? u.id : "";
  let t = tenantCache.get(uid);
  if (!t) {
    const rd = u ? path.join(userDir(dataDir, u), "relay") : path.join(dataDir, "relay");
    t = { uid, store: tenantStore(store, uid), relayDir: rd, devicesFile: path.join(rd, "devices.json"), devices: readJsonFile(path.join(rd, "devices.json")) };
    tenantCache.set(uid, t);
  }
  t.u = u || null; t.cfg = charConfig(config, u);
  t.label = u ? u.email : "your";
  return t;
}
const allTenants = () => [tenantOf(null), ...users(config).map(tenantOf)];
const charsOf = (t) => characters(t.cfg);
const findCharOf = (t, id) => charsOf(t).find((c) => c.id === (id || ""));
const storeOf = (t, id) => charStore(t.store, id || "");
// the owner's, for code that only ever concerns this PC's own game
const chars = () => charsOf(tenantOf(null));
// clear what earlier versions left in the characters lists (old first-name rows, the same character twice)
for (const t of allTenants()) { try { const n = tidyInventories(t.store); if (n) console.log(`Tidied ${t.label} characters list: ${n} stale row${n === 1 ? "" : "s"} removed`); } catch (e) { console.log("Couldn't tidy the characters list: " + e.message); } }
// Blizzard sync for one character, or everyone's, one after another
function syncOne(t, c, why) {
  log(`Blizzard sync for ${c.character || "the main character"}${t.uid ? " (" + t.label + ")" : ""} (${why})`);
  const st = storeOf(t, c.id), isNew = !st.get("state/character");
  // a newly added character: once Blizzard has set up its ledger, bring in its add-on data again (rested XP, zone, costs need the character)
  return syncBlizzard(st, { ...bcfg, character: c.character }, log).then((r) => { if (isNew && st.get("state/character")) watcher.importNow(); return r; });
}
async function sync(why) { for (const t of allTenants()) for (const c of charsOf(t)) { if (c.character) await syncOne(t, c, why).catch(() => {}); } }
setTimeout(() => sync("startup"), 15000);
let syncTimer;
function scheduleSync() {
  clearInterval(syncTimer);
  const h = config.syncEveryHours || 6;
  syncTimer = setInterval(() => sync("every " + h + " hours"), h * 3600 * 1000);
}
scheduleSync();
let afterImport = [];
function syncAfterPlay() {
  // Blizzard updates the character a little after you log out, so check twice
  afterImport.forEach(clearTimeout);
  afterImport = [setTimeout(() => sync("after play"), 60 * 1000), setTimeout(() => sync("after play, second check"), 6 * 60 * 1000)];
}

// ---------- files from relays (yours: data/relay/<device>/<account>/SavedVariables/LevelingLedger.lua; each person's
// under data/users/<id>/relay/...) ----------
const NAME_OK = /^[A-Za-z0-9 _#.()-]{1,60}$/;
function relayFilesOf(t) {
  const out = [];
  const dirs = (p) => { try { return fs.readdirSync(p, { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name); } catch { return []; } };
  for (const dev of dirs(t.relayDir)) for (const acc of dirs(path.join(t.relayDir, dev))) {
    const f = path.join(t.relayDir, dev, acc, "SavedVariables", "LevelingLedger.lua");
    if (fs.existsSync(f)) out.push(f);
  }
  return out;
}
const relayFiles = () => allTenants().flatMap(relayFilesOf);
// whose a file is: a person's relay folder, else the owner's (this PC's game, the owner's relays)
function fileTenant(file) {
  for (const u of users(config)) if (String(file).startsWith(userDir(dataDir, u) + path.sep)) return tenantOf(u);
  return tenantOf(null);
}
const filesOf = (t) => watcher.status.files.filter((f) => fileTenant(f) === t);

// ---------- add-on file watcher ----------
// Every character the add-on records gets its own page: new ones are tracked as soon as their file is read
// (before it's imported, so their data comes in with the same import).
function autoAlts(t, data) {
  // characters removed on the Ledger tab (shared/hiddenchars) aren't tracked again
  const gone = new Set(Object.values((t.store.get("shared/hiddenchars") || {}).ids || {}).map((h) => String((h && h.name) || "").toLowerCase()));
  const seen = Object.values(data.chars || {}).filter((c) => c && c.name && !gone.has([c.name, c.surname].filter(Boolean).join(" ").toLowerCase()));
  const draft = JSON.parse(JSON.stringify(config));
  const du = t.u ? draft.users.find((x) => x.id === t.u.id) : null;
  if (t.u && !du) return;
  // someone new: the character they played most recently becomes their main
  let main = null;
  if (du && !du.character) {
    const best = seen.filter((c) => c.surname).sort((a, b) => (b.stateAt || 0) - (a.stateAt || 0))[0];
    if (best) { main = [best.name, best.surname].join("-").toLowerCase().replace(/\s+/g, "-"); du.character = main; }
  }
  const add = newAlts(charConfig(draft, du), seen.map((c) => [c.name, c.surname].filter(Boolean).join(" ")));
  if (!add.length && !main) return;
  if (du) du.alts = [...(du.alts || []), ...add]; else draft.alts = [...(draft.alts || []), ...add];
  try { saveConfig(CONFIG_FILE, draft); } catch (e) { log("Couldn't save the new characters to config.json: " + e.message); return; }
  if (du) { const i = config.users.findIndex((x) => x.id === du.id); config.users[i] = du; } else config.alts = draft.alts;
  if (main) log(`${t.label}: main character ${main} (seen by the add-on)`);
  if (add.length) log((t.uid ? t.label + ": n" : "N") + "ow tracking " + add.join(", ") + " (seen by the add-on)");
  setTimeout(() => sync("characters added"), 1000);
}
// an add-on entry without a surname (before 1.0.46) goes to the main ledger, or to a character whose first name no
// other tracked character shares
const firstOf = (c) => String(c.character || "").split("-")[0];
// each file goes into the ledgers of the person it belongs to
const watcher = startWatcher({ targets: (file) => { const t = fileTenant(file), cs = charsOf(t); return cs.map((c) => ({ store: storeOf(t, c.id), hint: c.character,
  plainOk: c.main || cs.filter((x) => firstOf(x) === firstOf(c)).length === 1 })); }, publicDir: PUBLIC, config, log, onImported: syncAfterPlay,
  onFile: (data, file) => { const t = fileTenant(file); mergeInventories(t.store, data, file); autoAlts(t, data); }, // every character on every account: gold, bags, bank
  extraFiles: relayFiles });

// ---------- one-click updates ----------
// The add-on's folder is found next to the watched SavedVariables file: <game>\_forever_\Interface\AddOns\LevelingLedger
function addonDir() {
  for (const f of watcher.status.files) {
    const flavor = path.dirname(path.dirname(path.dirname(path.dirname(path.dirname(f)))));
    const d = path.join(flavor, "Interface", "AddOns", "LevelingLedger");
    if (fs.existsSync(path.join(d, "LevelingLedger.toc"))) return d;
  }
  return null;
}
const updater = startUpdater({ appDir: APP, dataDir, config, log, addonDir });
// keep this PC's in-game summary (Shared.lua in the add-on folder) current, a few seconds after the data changes
let sharedT;
function writeLocalShared() {
  try { const d = addonDir(); if (d && writeShared(d, buildSummary(tenantOf(null).store))) log("Updated the in-game character summary in " + d); }
  catch (e) { log("Couldn't write the in-game character summary: " + e.message); }
}
store.on("change", (ev) => { const vp = viewPath(ev.path, ""); if (vp && vp.startsWith("shared/")) { clearTimeout(sharedT); sharedT = setTimeout(writeLocalShared, 5000); } });
setTimeout(writeLocalShared, 20 * 1000);
function restartSoon() { setTimeout(() => { try { store.flushNow(); } catch {} process.exit(0); }, 800); } // NSSM starts the service again

// ---------- server ----------
const server = http.createServer(async (req, res) => {
  try {
    const denied = await checkRequest(req, accessConfig(config));
    if (denied) return send(res, 403, "<!doctype html><meta charset=utf-8><title>Not allowed</title><p style=\"font:16px system-ui;margin:2em\">" + denied.replace(/</g, "&lt;") + "</p>", "text/html; charset=utf-8");
    const url = new URL(req.url, "http://localhost");
    const p = decodeURIComponent(url.pathname);
    // a relay's service token may only upload and check in; nothing else on the hub
    if (req.serviceToken && !((p === "/api/relay/upload" && req.method === "POST") || p === "/api/relay/ping" || p === "/api/relay/summary" || p === "/api/relay/version" || p === "/api/relay/bundle")) return send(res, 403, { error: "device tokens can only upload, fetch the character summary and update the relay" });
    // Writes must carry this header; a page on another site can't add it without being refused by the browser.
    if (req.method !== "GET" && req.method !== "HEAD" && req.headers["x-ledger"] !== "1") return send(res, 403, { error: "missing header" });
    // whose ledger this is: the owner, or a person added in Settings (their own data only)
    const t = tenantOf(tenantFor(config, req)), st = t.store;
    // hub-wide things are the owner's alone
    const ownerOnly = /^\/api\/(backups|update|journal\/check|import-now|relay\/device)(\/|$)/.test(p) || (p === "/api/settings" && req.method !== "GET" && req.method !== "PUT");
    if (t.uid && ownerOnly) return send(res, 403, { error: "only the hub's owner can do that" });

    if (p === "/" || p === "/index.html" || p === "/leveling-ledger.html") return send(res, 200, page(), "text/html; charset=utf-8");

    if (p === "/api/events") {
      res.writeHead(200, { "Content-Type": "text/event-stream", "Cache-Control": "no-store", Connection: "keep-alive", "X-Accel-Buffering": "no" });
      res.write("retry: 3000\n\n");
      clients.set(res, t.uid); req.on("close", () => clients.delete(res));
      return;
    }
    if (p.startsWith("/api/doc/")) {
      const dp = p.slice(9);
      if (!Store.validPath(dp)) return send(res, 400, { error: "bad path" });
      if (req.method === "GET") { const d = st.get(dp); return send(res, 200, { exists: d !== undefined, data: d ?? null }); }
      if (req.method === "PUT") { st.set(dp, keepAddonCosts(st, dp, await json(req))); return send(res, 200, { ok: true }); }
      if (req.method === "PATCH") { if (/(^|\.)state\/trainercosts$/.test(dp)) return send(res, 400, { error: "replace the whole document" }); st.update(dp, await json(req)); return send(res, 200, { ok: true }); }
      if (req.method === "DELETE") { st.delete(dp); return send(res, 200, { ok: true }); }
    }
    if (p.startsWith("/api/col/")) {
      const col = p.slice(9);
      if (!/^[A-Za-z0-9_\-.~:@+]{1,200}$/.test(col)) return send(res, 400, { error: "bad collection" });
      if (req.method === "GET") return send(res, 200, { docs: st.list(col) });
      if (req.method === "POST") { const id = st.add(col, await json(req)); return send(res, 200, { id }); }
    }
    // export one character's data: /api/export?char=<id>&what=json|sessions|levels|characters|items|quests
    if (p === "/api/export" && req.method === "GET") {
      const c = findCharOf(t, url.searchParams.get("char"));
      if (!c) return send(res, 404, { error: "unknown character" });
      const cs = storeOf(t, c.id);
      const name = ((cs.get("state/character") || {}).name || c.character || "character").split(" ")[0];
      const out = exportData(st, cs, String(url.searchParams.get("what") || ""), name, PUBLIC);
      if (!out) return send(res, 400, { error: "unknown export" });
      res.writeHead(200, { "Content-Type": out.type, "Content-Disposition": `attachment; filename="${out.filename}"`, "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" });
      return res.end(out.body);
    }
    // start a character's ledger over: a backup first, then everything imported or synced goes and is read again from
    // the add-on and Blizzard; what you set yourself stays (to-do list, talent picks, ticks, quest marks, skipped recipes)
    if (p === "/api/char/reset" && req.method === "POST") {
      const c = findCharOf(t, url.searchParams.get("char"));
      if (!c) return send(res, 404, { error: "unknown character" });
      const backup = backups.now();
      const pre = c.id ? c.id + "." : "";
      const KEEP = /^(tasks\/|state\/talents(-[a-z]+)?$|state\/bookticks$|state\/profprefs$|state\/questmarks$)/;
      let n = 0;
      for (const k of st.keys()) {
        if (k.startsWith("shared/")) continue;
        const mine = pre ? k.startsWith(pre) : !/^c[0-9a-f]{8}\./.test(k);
        if (!mine) continue;
        const rel = pre ? k.slice(pre.length) : k;
        if (KEEP.test(rel)) continue;
        st.delete(k); n++;
      }
      log(`Reset ${c.character}'s ledger${t.uid ? " (" + t.label + ")" : ""}: ${n} documents removed (backup ${backup})`);
      watcher.importNow(); setTimeout(() => syncOne(t, c, "reset"), 1500);
      return send(res, 200, { ok: true, removed: n, backup });
    }
    if (p === "/api/backups" && req.method === "GET") return send(res, 200, { backups: backups.list(), keepDays: config.backupDays || 14 });
    if (p === "/api/backups/now" && req.method === "POST") return send(res, 200, { name: backups.now() });
    if (p === "/api/backups/restore" && req.method === "POST") {
      try { const b = await json(req); const safety = backups.restore(String(b.name || "")); return send(res, 200, { ok: true, safety }); }
      catch (e) { return send(res, 400, { ok: false, message: e.message }); }
    }
    if (p.startsWith("/api/backups/") && req.method === "GET") {
      const f = backups.resolve(p.slice(13));
      if (!f) return send(res, 404, { error: "not found" });
      res.writeHead(200, { "Content-Type": "application/json", "Content-Disposition": `attachment; filename="leveling-ledger-${path.basename(f)}"`, "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" });
      return fs.createReadStream(f).pipe(res);
    }
    if (p === "/api/update" && req.method === "GET") return send(res, 200, updater.view());
    if (p === "/api/update/check" && req.method === "POST") return send(res, 200, await updater.check());
    if (p === "/api/update" && req.method === "POST") {
      try { const r = await updater.update(); send(res, 200, r); restartSoon(); return; }
      catch (e) { log("Update failed: " + e.message); return send(res, 400, { ok: false, message: e.message }); }
    }
    if (p === "/api/update/undo" && req.method === "POST") {
      try { const r = updater.undo(); send(res, 200, r); restartSoon(); return; }
      catch (e) { return send(res, 400, { ok: false, message: e.message }); }
    }
    if (p === "/api/relay/ping") return send(res, 200, { ok: true, hub: VERSION });
    if (p === "/api/relay/summary") return send(res, 200, buildSummary(st));
    // relays update themselves to the relay and add-on files installed here
    if (p === "/api/relay/version") return send(res, 200, { version: relayVersion(APP, addonDir) });
    if (p === "/api/relay/bundle") return send(res, 200, relayBundle(APP, addonDir));
    if (p === "/api/relay/upload" && req.method === "POST") {
      const device = url.searchParams.get("device") || "", account = url.searchParams.get("account") || "";
      if (!NAME_OK.test(device) || !NAME_OK.test(account) || /^\.+$/.test(device) || /^\.+$/.test(account)) return send(res, 400, { error: "bad device or account name" });
      const text = await readBody(req, 30 * 1024 * 1024);
      try { const d = readSaved(text); if (!d || !d.chars) throw new Error("no Leveling Ledger data"); }
      catch (e) { return send(res, 400, { error: "That isn't a Leveling Ledger file: " + e.message }); }
      const dir = path.join(t.relayDir, device, account, "SavedVariables"), f = path.join(dir, "LevelingLedger.lua");
      fs.mkdirSync(dir, { recursive: true });
      const same = fs.existsSync(f) && fs.readFileSync(f, "utf8") === text;
      if (!same) { fs.writeFileSync(f + ".tmp", text); fs.renameSync(f + ".tmp", f); }
      const d = t.devices[device] || (t.devices[device] = { accounts: {} });
      d.lastUpload = Date.now(); d.token = req.serviceToken || "this PC"; d.accounts[account] = Date.now();
      fs.writeFileSync(t.devicesFile, JSON.stringify(t.devices));
      log(`Relay ${device} sent ${account}${t.uid ? " for " + t.label : ""}${same ? " (unchanged)" : ""}`);
      if (!same) watcher.scan(); // a new file is imported now; a changed one within a few seconds
      return send(res, 200, { ok: true, unchanged: same });
    }
    // a person added in Settings sees and changes only their own characters
    // a device that has sent data: forget it (its stored files go), or move its files to a person's ledger (for a
    // friend's PC whose token was listed among the owner's own devices); the owner's devices only
    if (p === "/api/relay/device" && req.method === "POST") {
      const device = url.searchParams.get("device") || "", action = url.searchParams.get("action") || "";
      if (!NAME_OK.test(device) || /^\.+$/.test(device) || !t.devices[device]) return send(res, 404, { error: "no such device" });
      const from = path.join(t.relayDir, device);
      if (action === "move") {
        const u = users(config).find((x) => x.id === url.searchParams.get("to"));
        if (!u) return send(res, 400, { error: "no such person" });
        const to = tenantOf(u), dest = path.join(to.relayDir, device);
        if (fs.existsSync(dest)) return send(res, 409, { error: "that person already has a device with this name" });
        fs.mkdirSync(to.relayDir, { recursive: true });
        if (fs.existsSync(from)) fs.renameSync(from, dest);
        to.devices[device] = t.devices[device]; fs.writeFileSync(to.devicesFile, JSON.stringify(to.devices));
        delete t.devices[device]; fs.writeFileSync(t.devicesFile, JSON.stringify(t.devices));
        log(`Moved device ${device}'s add-on data to ${u.email}`);
      } else if (action === "forget") {
        fs.rmSync(from, { recursive: true, force: true });
        delete t.devices[device]; fs.writeFileSync(t.devicesFile, JSON.stringify(t.devices));
        log(`Forgot device ${device} and its add-on data`);
      } else return send(res, 400, { error: "unknown action" });
      watcher.reset(); // stop watching the old files, find them in their new place
      return send(res, 200, { ok: true });
    }
    if (p === "/api/settings" && t.uid) {
      const u = t.u, me = () => ({ person: true, email: u.email, character: u.character || "", alts: u.alts || [], devices: (u.tokens || []).length });
      if (req.method === "GET") return send(res, 200, me());
      const draft = JSON.parse(JSON.stringify(config)), du = draft.users.find((x) => x.id === u.id);
      const body = await json(req), errors = {}, changed = [];
      const slug = (v) => String(v || "").trim().toLowerCase().replace(/\s+/g, "-");
      if (body.character != null) {
        const v = slug(body.character);
        if (v && !/^[\p{L}\p{N}'-]{2,60}$/u.test(v)) errors.character = 'Your character as Blizzard spells it: first name and surname, like "talwyn-orda".';
        else if (v !== (du.character || "")) { du.character = v; changed.push("character"); }
      }
      if (body.alts != null) {
        const list = [...new Set((Array.isArray(body.alts) ? body.alts : String(body.alts).split(/[\n,]+/)).map(slug).filter((x) => x && x !== du.character))];
        if (list.length > 10) errors.alts = "Up to 10 extra characters.";
        else if (list.some((x) => !/^[\p{L}\p{N}'-]{2,60}$/u.test(x))) errors.alts = 'Each character as Blizzard spells it, like "talwyn-bank".';
        else if (JSON.stringify(du.alts || []) !== JSON.stringify(list)) {
          const removed = new Set(du.altsRemoved || []);
          for (const x of du.alts || []) if (!list.includes(x)) removed.add(x);
          for (const x of list) removed.delete(x);
          du.altsRemoved = [...removed]; du.alts = list; changed.push("characters");
        }
      }
      if (Object.keys(errors).length) return send(res, 400, { ok: false, errors });
      if (changed.length) {
        try { saveConfig(CONFIG_FILE, draft); } catch (e) { return send(res, 500, { ok: false, message: "Couldn't save: " + e.message }); }
        config.users[config.users.findIndex((x) => x.id === u.id)] = du; t.u = du; t.cfg = charConfig(config, du);
        log(`${u.email} changed their ${changed.join(" and ")}`);
        watcher.importNow(); sync("characters changed");
      }
      return send(res, 200, { ok: true, changed, settings: me() });
    }
    if (p === "/api/settings" && req.method === "GET") return send(res, 200, publicView(config, !viaCloudflare(req)));
    if (p === "/api/settings" && req.method === "PUT") {
      const isLocal = !viaCloudflare(req);
      const draft = JSON.parse(JSON.stringify(config));
      const { changed, errors } = applyUpdate(draft, await json(req), isLocal);
      if (Object.keys(errors).length) return send(res, 400, { ok: false, errors });
      if (!changed.length) return send(res, 200, { ok: true, changed: [], settings: publicView(config, isLocal) });
      try { saveConfig(CONFIG_FILE, draft); }
      catch (e) {
        const perm = e.code === "EPERM" || e.code === "EACCES";
        return send(res, 500, { ok: false, message: perm ? "The service isn't allowed to save config.json yet. Run app\\scripts\\install.ps1 again once, then try again." : "Couldn't save config.json: " + e.message });
      }
      // switch the running service over
      const credsChanged = draft.blizzard.clientId !== bcfg.clientId || draft.blizzard.clientSecret !== bcfg.clientSecret;
      const folderChanged = draft.wowFolder !== config.wowFolder || draft.savedVariablesFile !== config.savedVariablesFile;
      const intervalChanged = draft.syncEveryHours !== config.syncEveryHours;
      const altsChanged = JSON.stringify(draft.alts || []) !== JSON.stringify(config.alts || []);
      Object.assign(bcfg, draft.blizzard);
      Object.assign(config.access, draft.access);
      const usersChanged = JSON.stringify(draft.users || []) !== JSON.stringify(config.users || []);
      for (const k of ["syncEveryHours", "backupDays", "wowFolder", "savedVariablesFile", "alts", "altsRemoved", "users"]) config[k] = draft[k];
      if (usersChanged) { watcher.scan(); sync("people changed"); }
      if (credsChanged) resetToken();
      if (intervalChanged) scheduleSync();
      if (folderChanged) watcher.reset();
      if (altsChanged) { watcher.importNow(); sync("characters changed"); }
      log("Settings saved: " + changed.join(", ") + (req.userEmail ? " (by " + req.userEmail + ")" : ""));
      return send(res, 200, { ok: true, changed, settings: publicView(config, isLocal) });
    }
    if (p === "/api/journal/check" && req.method === "POST") { checkJournal(store, bcfg, log); return send(res, 200, { ok: true }); }
    if (p === "/api/sync" && req.method === "POST") {
      const c = findCharOf(t, url.searchParams.get("char"));
      if (!c) return send(res, 404, { error: "unknown character" });
      syncOne(t, c, "Sync button"); return send(res, 200, { ok: true });
    }
    if (p === "/api/import" && req.method === "POST") {
      const c = findCharOf(t, url.searchParams.get("char"));
      if (!c) return send(res, 404, { error: "unknown character" });
      try { const r = importAddon(await readBody(req), storeOf(t, c.id), PUBLIC, "", c.character); syncAfterPlay(); return send(res, 200, { ok: true, message: r.message }); }
      catch (e) { return send(res, 400, { ok: false, message: e.message }); }
    }
    if (p === "/api/import-now" && req.method === "POST") { watcher.scan(); watcher.importNow(); return send(res, 200, { ok: true }); }
    if (p === "/api/status") {
      const lastBackup = backups.list().find((b) => b.kind === "daily");
      const mine = filesOf(t);
      return send(res, 200, { version: VERSION, files: mine, lastCheck: watcher.status.lastCheck, lastError: t.uid ? "" : watcher.status.lastError,
        account: { owner: !t.uid, email: t.u ? t.u.email : null, people: t.uid ? undefined : users(config).length },
        blizzard: !!(bcfg.clientId && bcfg.clientSecret), syncEveryHours: config.syncEveryHours || 6, remote: !!(config.access && config.access.aud),
        via: viaCloudflare(req) ? "cloudflare" : "local", user: req.userEmail || null, lastBackup: lastBackup ? lastBackup.at : null,
        updateAvailable: updater.view().available,
        characters: charsOf(t).map((c) => { const d = storeOf(t, c.id).get("state/character") || {}; return { id: c.id, character: c.character, main: c.main, name: d.name || "", level: d.level || null, cls: d.cls || "" }; }),
        seen: Object.values(watcher.status.seen).filter((x) => mine.includes(x.file)).map(({ name, level, cls }) => ({ name, level, cls })),
        devices: Object.entries(t.devices).map(([name, d]) => ({ name, lastUpload: d.lastUpload, accounts: Object.keys(d.accounts || {}) })) });
    }

    // static data files
    if (req.method === "GET" && /^\/[A-Za-z0-9_\-.]+$/.test(p) && TYPES[path.extname(p)]) {
      const f = path.join(PUBLIC, p.slice(1));
      if (fs.existsSync(f)) return send(res, 200, fs.readFileSync(f), TYPES[path.extname(p)]);
    }
    send(res, 404, { error: "not found" });
  } catch (e) {
    log("Error " + req.method + " " + req.url + ": " + e.message);
    if (!res.headersSent) send(res, 500, { error: e.message });
  }
});
// Listen on this PC only. Cloudflare Tunnel connects from here too, so nothing is exposed to your network.
server.listen(PORT, "127.0.0.1", () => log(`Leveling Ledger ${VERSION} on http://localhost:${PORT}`));
function shutdown() { log("Stopping"); try { store.flushNow(); } catch {} process.exit(0); }
process.on("SIGINT", shutdown); process.on("SIGTERM", shutdown);
