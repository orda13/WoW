// Leveling Ledger, local edition. No packages to install: run with `node server.js`.
const http = require("http");
const fs = require("fs");
const path = require("path");
const { Store } = require("./lib/store");
const { startWatcher } = require("./lib/watcher");
const { syncBlizzard, resetToken } = require("./lib/blizzard");
const { checkRequest, viaCloudflare } = require("./lib/access");
const { publicView, applyUpdate, saveConfig } = require("./lib/settings");
const { importAddon } = require("./lib/addon-import");
const { startBackups } = require("./lib/backups");
const { startUpdater } = require("./lib/updater");
const { characters, charStore } = require("./lib/characters");
const { mergeInventories } = require("./lib/inventory");
const { readSaved } = require("./lib/addon-import");
const { buildSummary, writeShared } = require("./lib/summary");

const APP = __dirname;
const CONFIG_FILE = process.env.LL_CONFIG || path.join(APP, "config.json");
const PUBLIC = path.join(APP, "public");
const VERSION = "1.0.0";

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
const clients = new Set();
store.on("change", (ev) => { const line = "data: " + JSON.stringify(ev) + "\n\n"; for (const res of clients) res.write(line); });
setInterval(() => { for (const res of clients) res.write(": ping\n\n"); }, 25000);

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
// ---------- characters (main + alts) ----------
const chars = () => characters(config);
const findChar = (id) => chars().find((c) => c.id === (id || ""));
const storeFor = (id) => charStore(store, id || "");
// Blizzard sync for one character, or all of them one after another
function syncOne(c, why) {
  log(`Blizzard sync for ${c.character || "the main character"} (${why})`);
  const st = storeFor(c.id), isNew = !st.get("state/character");
  // a newly added character: once Blizzard has set up its ledger, bring in its add-on data again (rested XP, zone, costs need the character)
  return syncBlizzard(st, { ...bcfg, character: c.character }, log).then((r) => { if (isNew && st.get("state/character")) watcher.importNow(); return r; });
}
async function sync(why) { for (const c of chars()) { if (c.character) await syncOne(c, why).catch(() => {}); } }
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

// ---------- files from relays on your other PCs (data/relay/<device>/<account>/SavedVariables/LevelingLedger.lua) ----------
const relayDir = path.join(dataDir, "relay");
const NAME_OK = /^[A-Za-z0-9 _#.()-]{1,60}$/;
function relayFiles() {
  const out = [];
  const dirs = (p) => { try { return fs.readdirSync(p, { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name); } catch { return []; } };
  for (const dev of dirs(relayDir)) for (const acc of dirs(path.join(relayDir, dev))) {
    const f = path.join(relayDir, dev, acc, "SavedVariables", "LevelingLedger.lua");
    if (fs.existsSync(f)) out.push(f);
  }
  return out;
}
const devicesFile = path.join(relayDir, "devices.json");
const devices = (() => { try { return JSON.parse(fs.readFileSync(devicesFile, "utf8")); } catch { return {}; } })();

// ---------- add-on file watcher ----------
const watcher = startWatcher({ targets: () => chars().map((c) => ({ store: storeFor(c.id), hint: c.character })), publicDir: PUBLIC, config, log, onImported: syncAfterPlay,
  onFile: (data, file) => mergeInventories(store, data, file), // every character on every account: gold, bags, bank
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
  try { const d = addonDir(); if (d && writeShared(d, buildSummary(store))) log("Updated the in-game character summary in " + d); }
  catch (e) { log("Couldn't write the in-game character summary: " + e.message); }
}
store.on("change", (ev) => { if (ev.path.startsWith("shared/")) { clearTimeout(sharedT); sharedT = setTimeout(writeLocalShared, 5000); } });
setTimeout(writeLocalShared, 20 * 1000);
function restartSoon() { setTimeout(() => { try { store.flushNow(); } catch {} process.exit(0); }, 800); } // NSSM starts the service again

// ---------- server ----------
const server = http.createServer(async (req, res) => {
  try {
    const denied = await checkRequest(req, config.access);
    if (denied) return send(res, 403, "<!doctype html><meta charset=utf-8><title>Not allowed</title><p style=\"font:16px system-ui;margin:2em\">" + denied.replace(/</g, "&lt;") + "</p>", "text/html; charset=utf-8");
    const url = new URL(req.url, "http://localhost");
    const p = decodeURIComponent(url.pathname);
    // a relay's service token may only upload and check in; nothing else on the hub
    if (req.serviceToken && !((p === "/api/relay/upload" && req.method === "POST") || p === "/api/relay/ping" || p === "/api/relay/summary")) return send(res, 403, { error: "device tokens can only upload and fetch the character summary" });
    // Writes must carry this header; a page on another site can't add it without being refused by the browser.
    if (req.method !== "GET" && req.method !== "HEAD" && req.headers["x-ledger"] !== "1") return send(res, 403, { error: "missing header" });

    if (p === "/" || p === "/index.html" || p === "/leveling-ledger.html") return send(res, 200, page(), "text/html; charset=utf-8");

    if (p === "/api/events") {
      res.writeHead(200, { "Content-Type": "text/event-stream", "Cache-Control": "no-store", Connection: "keep-alive", "X-Accel-Buffering": "no" });
      res.write("retry: 3000\n\n");
      clients.add(res); req.on("close", () => clients.delete(res));
      return;
    }
    if (p.startsWith("/api/doc/")) {
      const dp = p.slice(9);
      if (!Store.validPath(dp)) return send(res, 400, { error: "bad path" });
      if (req.method === "GET") { const d = store.get(dp); return send(res, 200, { exists: d !== undefined, data: d ?? null }); }
      if (req.method === "PUT") { store.set(dp, await json(req)); return send(res, 200, { ok: true }); }
      if (req.method === "PATCH") { store.update(dp, await json(req)); return send(res, 200, { ok: true }); }
      if (req.method === "DELETE") { store.delete(dp); return send(res, 200, { ok: true }); }
    }
    if (p.startsWith("/api/col/")) {
      const col = p.slice(9);
      if (!/^[A-Za-z0-9_\-.~:@+]{1,200}$/.test(col)) return send(res, 400, { error: "bad collection" });
      if (req.method === "GET") return send(res, 200, { docs: store.list(col) });
      if (req.method === "POST") { const id = store.add(col, await json(req)); return send(res, 200, { id }); }
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
    if (p === "/api/relay/summary") return send(res, 200, buildSummary(store));
    if (p === "/api/relay/upload" && req.method === "POST") {
      const device = url.searchParams.get("device") || "", account = url.searchParams.get("account") || "";
      if (!NAME_OK.test(device) || !NAME_OK.test(account) || /^\.+$/.test(device) || /^\.+$/.test(account)) return send(res, 400, { error: "bad device or account name" });
      const text = await readBody(req, 30 * 1024 * 1024);
      try { const d = readSaved(text); if (!d || !d.chars) throw new Error("no Leveling Ledger data"); }
      catch (e) { return send(res, 400, { error: "That isn't a Leveling Ledger file: " + e.message }); }
      const dir = path.join(relayDir, device, account, "SavedVariables"), f = path.join(dir, "LevelingLedger.lua");
      fs.mkdirSync(dir, { recursive: true });
      const same = fs.existsSync(f) && fs.readFileSync(f, "utf8") === text;
      if (!same) { fs.writeFileSync(f + ".tmp", text); fs.renameSync(f + ".tmp", f); }
      const d = devices[device] || (devices[device] = { accounts: {} });
      d.lastUpload = Date.now(); d.token = req.serviceToken || "this PC"; d.accounts[account] = Date.now();
      fs.writeFileSync(devicesFile, JSON.stringify(devices));
      log(`Relay ${device} sent ${account}${same ? " (unchanged)" : ""}`);
      if (!same) watcher.scan(); // a new file is imported now; a changed one within a few seconds
      return send(res, 200, { ok: true, unchanged: same });
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
      for (const k of ["syncEveryHours", "backupDays", "wowFolder", "savedVariablesFile", "alts"]) config[k] = draft[k];
      if (credsChanged) resetToken();
      if (intervalChanged) scheduleSync();
      if (folderChanged) watcher.reset();
      if (altsChanged) { watcher.importNow(); sync("characters changed"); }
      log("Settings saved: " + changed.join(", ") + (req.userEmail ? " (by " + req.userEmail + ")" : ""));
      return send(res, 200, { ok: true, changed, settings: publicView(config, isLocal) });
    }
    if (p === "/api/sync" && req.method === "POST") {
      const c = findChar(url.searchParams.get("char"));
      if (!c) return send(res, 404, { error: "unknown character" });
      syncOne(c, "Sync button"); return send(res, 200, { ok: true });
    }
    if (p === "/api/import" && req.method === "POST") {
      const c = findChar(url.searchParams.get("char"));
      if (!c) return send(res, 404, { error: "unknown character" });
      try { const r = importAddon(await readBody(req), storeFor(c.id), PUBLIC, "", c.character); syncAfterPlay(); return send(res, 200, { ok: true, message: r.message }); }
      catch (e) { return send(res, 400, { ok: false, message: e.message }); }
    }
    if (p === "/api/import-now" && req.method === "POST") { watcher.scan(); watcher.importNow(); return send(res, 200, { ok: true }); }
    if (p === "/api/status") {
      const lastBackup = backups.list().find((b) => b.kind === "daily");
      return send(res, 200, { version: VERSION, files: watcher.status.files, lastCheck: watcher.status.lastCheck, lastError: watcher.status.lastError,
        blizzard: !!(bcfg.clientId && bcfg.clientSecret), syncEveryHours: config.syncEveryHours || 6, remote: !!(config.access && config.access.aud),
        via: viaCloudflare(req) ? "cloudflare" : "local", user: req.userEmail || null, lastBackup: lastBackup ? lastBackup.at : null,
        updateAvailable: updater.view().available,
        characters: chars().map((c) => { const d = storeFor(c.id).get("state/character") || {}; return { id: c.id, character: c.character, main: c.main, name: d.name || "", level: d.level || null, cls: d.cls || "" }; }),
        seen: Object.values(watcher.status.seen).map(({ name, level, cls }) => ({ name, level, cls })),
        devices: Object.entries(devices).map(([name, d]) => ({ name, lastUpload: d.lastUpload, accounts: Object.keys(d.accounts || {}) })) });
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
