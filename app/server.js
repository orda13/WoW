// Leveling Ledger, local edition. No packages to install: run with `node server.js`.
const http = require("http");
const fs = require("fs");
const path = require("path");
const { Store } = require("./lib/store");
const { startWatcher } = require("./lib/watcher");
const { syncBlizzard } = require("./lib/blizzard");
const { checkRequest } = require("./lib/access");
const { importAddon } = require("./lib/addon-import");
const { startBackups } = require("./lib/backups");

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
const PORT = config.port || 8787;
const dataDir = config.dataDir ? path.resolve(APP, config.dataDir) : path.join(APP, "data");
const store = new Store(path.join(dataDir, "store.json"), path.join(dataDir, "seed.json"));

// ---------- daily backups (data/backups, last 14 days by default) ----------
const backups = startBackups({ store, dir: path.join(dataDir, "backups"), keepDays: config.backupDays || 14, log });

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
const bcfg = config.blizzard || {};
function sync(why) { log("Blizzard sync (" + why + ")"); return syncBlizzard(store, bcfg, log); }
setTimeout(() => sync("startup"), 15000);
setInterval(() => sync("every " + (config.syncEveryHours || 6) + " hours"), (config.syncEveryHours || 6) * 3600 * 1000);
let afterImport = [];
function syncAfterPlay() {
  // Blizzard updates the character a little after you log out, so check twice
  afterImport.forEach(clearTimeout);
  afterImport = [setTimeout(() => sync("after play"), 60 * 1000), setTimeout(() => sync("after play, second check"), 6 * 60 * 1000)];
}

// ---------- add-on file watcher ----------
const watcher = startWatcher({ store, publicDir: PUBLIC, config, log, onImported: syncAfterPlay });

// ---------- server ----------
const server = http.createServer(async (req, res) => {
  try {
    const denied = await checkRequest(req, config.access);
    if (denied) return send(res, 403, "<!doctype html><meta charset=utf-8><title>Not allowed</title><p style=\"font:16px system-ui;margin:2em\">" + denied.replace(/</g, "&lt;") + "</p>", "text/html; charset=utf-8");
    const url = new URL(req.url, "http://localhost");
    const p = decodeURIComponent(url.pathname);
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
    if (p === "/api/sync" && req.method === "POST") { sync("Sync button"); return send(res, 200, { ok: true }); }
    if (p === "/api/import" && req.method === "POST") {
      try { const r = importAddon(await readBody(req), store, PUBLIC, "", bcfg.character); syncAfterPlay(); return send(res, 200, { ok: true, message: r.message }); }
      catch (e) { return send(res, 400, { ok: false, message: e.message }); }
    }
    if (p === "/api/import-now" && req.method === "POST") { watcher.scan(); watcher.importNow(); return send(res, 200, { ok: true }); }
    if (p === "/api/status") return send(res, 200, { version: VERSION, files: watcher.status.files, lastCheck: watcher.status.lastCheck, lastError: watcher.status.lastError,
      blizzard: !!(bcfg.clientId && bcfg.clientSecret), remote: !!(config.access && config.access.aud), user: req.userEmail || null });

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
