// Leveling Ledger relay: sends this PC's (or Steam Deck's) add-on file to your hub, through your Cloudflare address.
// Runs as a background service. When the hub can't be reached (travelling, offline), it keeps trying until it can.
//   node relay.js           run
//   node relay.js --test    check the settings, the add-on files and the connection, then exit
const fs = require("fs");
const path = require("path");
const os = require("os");
const crypto = require("crypto");
const { findFiles } = require("./lib/watcher");
const { writeShared } = require("./lib/summary");
const { RELAY_NAME, fingerprint } = require("./lib/relaybundle");
const vm = require("vm");
const { execFileSync } = require("child_process");

const CONFIG_FILE = process.env.LL_RELAY_CONFIG || path.join(__dirname, "relay.json");
const STATE_FILE = process.env.LL_RELAY_STATE || path.join(path.dirname(CONFIG_FILE), "relay-state.json");
const log = (m) => console.log(new Date().toISOString() + " " + m);
const UPDATE_FILE = process.env.LL_RELAY_UPDATE_FILE || path.join(path.dirname(STATE_FILE), "relay-update.json");
const BACKUP_DIR = process.env.LL_RELAY_BACKUP_DIR || path.join(path.dirname(STATE_FILE), "relay-backup");
const readJSON = (f) => { try { return JSON.parse(fs.readFileSync(f, "utf8")); } catch { return {}; } };

function loadConfig() {
  const c = JSON.parse(fs.readFileSync(CONFIG_FILE, "utf8").replace(/^\uFEFF/, ""));
  if (!c.hubUrl) throw new Error("relay.json needs hubUrl, your Cloudflare address (https://ledger.example.com)");
  c.hubUrl = c.hubUrl.replace(/\/+$/, "");
  c.device = (c.device || os.hostname()).replace(/[^A-Za-z0-9 _#.()-]/g, "-").slice(0, 60);
  return c;
}

// Where World of Warcraft usually lives: Windows, and the Steam Deck / Linux through Proton, Lutris or Bottles
function defaultRoots() {
  if (process.platform === "win32") return ["C:\\Program Files (x86)\\World of Warcraft", "C:\\Program Files\\World of Warcraft", "D:\\World of Warcraft", "D:\\Games\\World of Warcraft", "E:\\World of Warcraft"];
  const home = os.homedir(), out = [];
  const pf = path.join("drive_c", "Program Files (x86)", "World of Warcraft");
  const kids = (p) => { try { return fs.readdirSync(p); } catch { return []; } };
  for (const steam of [path.join(home, ".local/share/Steam"), path.join(home, ".steam/steam")]) {
    const cd = path.join(steam, "steamapps", "compatdata");
    for (const id of kids(cd)) out.push(path.join(cd, id, "pfx", pf));
  }
  // SD cards and other Steam libraries
  for (const m of kids("/run/media")) for (const d of [path.join("/run/media", m), ...kids(path.join("/run/media", m)).map((x) => path.join("/run/media", m, x))]) {
    const cd = path.join(d, "steamapps", "compatdata");
    for (const id of kids(cd)) out.push(path.join(cd, id, "pfx", pf));
  }
  for (const g of kids(path.join(home, "Games"))) out.push(path.join(home, "Games", g, pf));
  const bottles = path.join(home, ".var/app/com.usebottles.bottles/data/bottles/bottles");
  for (const b of kids(bottles)) out.push(path.join(bottles, b, pf));
  return out.filter((p) => fs.existsSync(p));
}

function files(cfg) {
  if (cfg.savedVariablesFile) return [cfg.savedVariablesFile].filter((f) => fs.existsSync(f));
  return findFiles(cfg.wowFolder ? [].concat(cfg.wowFolder) : defaultRoots());
}
const accountOf = (f) => path.basename(path.dirname(path.dirname(f)));
const headers = (cfg, extra) => ({ "X-Ledger": "1", "CF-Access-Client-Id": cfg.clientId || "", "CF-Access-Client-Secret": cfg.clientSecret || "", "User-Agent": "leveling-ledger-relay", ...extra });

async function send(cfg, file) {
  const text = fs.readFileSync(file, "utf8");
  const q = `device=${encodeURIComponent(cfg.device)}&account=${encodeURIComponent(accountOf(file))}`;
  const r = await fetch(`${cfg.hubUrl}/api/relay/upload?${q}`, { method: "POST", headers: headers(cfg, { "Content-Type": "text/plain; charset=utf-8" }), body: text, redirect: "manual" });
  if (r.status >= 300 && r.status < 400) throw new Error("Cloudflare asked for a sign-in: check the service token's Client ID and Secret, and that the Leveling Ledger application allows it (Service Auth).");
  if (!r.ok) throw new Error(`hub answered ${r.status}: ${(await r.text()).slice(0, 200)}`);
  return crypto.createHash("sha1").update(text).digest("hex");
}

// The in-game summary: fetch every character's bags, bank and gold from the hub and write Shared.lua
// next to the add-on (<game>\_forever_\Interface\AddOns\LevelingLedger), for each game folder found.
const addonDirOf = (f) => path.join(path.dirname(path.dirname(path.dirname(path.dirname(path.dirname(f))))), "Interface", "AddOns", "LevelingLedger");
async function pullSummary(cfg, fl) {
  const r = await fetch(`${cfg.hubUrl}/api/relay/summary`, { headers: headers(cfg), redirect: "manual" });
  if (!r.ok) throw new Error(r.status >= 300 && r.status < 400 ? "Cloudflare asked for a sign-in" : `hub answered ${r.status}`);
  const sum = await r.json();
  let wrote = 0, found = 0;
  for (const d of [...new Set(fl.map(addonDirOf))]) { if (fs.existsSync(path.join(d, "LevelingLedger.toc"))) { found++; if (writeShared(d, sum)) wrote++; } }
  return { chars: Object.keys(sum.chars || {}).length, wrote, found };
}

// ---------- updating itself to the hub's version ----------
// Is World of Warcraft running? (Windows, and Proton / Wine on the Steam Deck and Linux.) Add-on files wait until it's closed.
function wowRunning() {
  try {
    if (process.platform === "win32") return /"wow[^"]*\.exe"/i.test(execFileSync("tasklist", ["/FO", "CSV", "/NH"], { encoding: "utf8", windowsHide: true }));
    if (process.platform === "linux") {
      for (const pid of fs.readdirSync("/proc")) {
        if (!/^\d+$/.test(pid) || +pid === process.pid) continue;
        let c = ""; try { c = fs.readFileSync(`/proc/${pid}/cmdline`, "latin1"); } catch { continue; }
        if (/(^|[\\/\0])wow[^\\/\0]*\.exe/i.test(c)) return true;
      }
    }
  } catch {}
  return false;
}
const same = (f, buf) => { try { return Buffer.compare(fs.readFileSync(f), buf) === 0; } catch { return false; } };
function writeAtomic(f, buf) { fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(f + ".tmp", buf); fs.renameSync(f + ".tmp", f); }

let waitingForWow = false;
async function selfUpdate(cfg, addonDirs) {
  if (cfg.autoUpdate === false) return;
  const st = readJSON(UPDATE_FILE);
  const vr = await fetch(`${cfg.hubUrl}/api/relay/version`, { headers: headers(cfg), redirect: "manual" });
  if (!vr.ok) return;
  const { version } = await vr.json();
  if (!version || (st.version === version && !st.addonPending)) return;
  // a version that had to be rolled back isn't tried again; the next one from the hub is
  if (st.rolledBack === version) { if (!st.toldRolledBack) { log(`Skipping relay update ${version}: it didn't start before. Waiting for the next one.`); fs.writeFileSync(UPDATE_FILE, JSON.stringify({ ...st, toldRolledBack: true })); } return; }
  const br = await fetch(`${cfg.hubUrl}/api/relay/bundle`, { headers: headers(cfg), redirect: "manual" });
  if (!br.ok) throw new Error(`hub answered ${br.status}`);
  const b = await br.json();
  // check everything before touching anything
  const files = {};
  for (const [name, b64] of Object.entries(b.files || {})) {
    if (!RELAY_NAME.test(name)) throw new Error("unexpected file in the update: " + name);
    const buf = Buffer.from(String(b64), "base64");
    if (buf.length > 2 * 1024 * 1024) throw new Error(name + " is unexpectedly large");
    if (name.endsWith(".js")) { try { new vm.Script(buf.toString("utf8"), { filename: name }); } catch (e) { throw new Error(`${name} doesn't parse: ${e.message}`); } }
    files[name] = buf;
  }
  if (!files["relay.js"] || fingerprint(files) !== b.version || b.version !== version) throw new Error("the update didn't match what the hub announced");
  // the add-on: only while WoW is closed
  const addon = Object.entries(files).filter(([n]) => n.startsWith("addon/LevelingLedger/"));
  const todo = addonDirs.filter((d) => addon.some(([n, buf]) => !same(path.join(d, n.slice(21)), buf)));
  let addonPending = false;
  if (todo.length) {
    if (wowRunning()) { addonPending = true; if (!waitingForWow) log("An add-on update is ready; it installs once WoW is closed."); waitingForWow = true; }
    else { for (const d of todo) for (const [n, buf] of addon) writeAtomic(path.join(d, n.slice(21)), buf); waitingForWow = false; log(`Updated the add-on in ${todo.length} game folder${todo.length === 1 ? "" : "s"}`); }
  }
  // the relay itself: keep the current files, write the new ones, restart (the service manager starts it again)
  const code = Object.entries(files).filter(([n]) => !n.startsWith("addon/"));
  const changed = code.filter(([n, buf]) => !same(path.join(__dirname, n), buf));
  if (changed.length) {
    fs.rmSync(BACKUP_DIR, { recursive: true, force: true });
    const backedUp = [], added = [];
    for (const [n] of changed) {
      const cur = path.join(__dirname, n);
      if (fs.existsSync(cur)) { fs.mkdirSync(path.dirname(path.join(BACKUP_DIR, n)), { recursive: true }); fs.copyFileSync(cur, path.join(BACKUP_DIR, n)); backedUp.push(n); }
      else added.push(n);
    }
    for (const [n, buf] of changed) writeAtomic(path.join(__dirname, n), buf);
    fs.writeFileSync(UPDATE_FILE, JSON.stringify({ version, pending: true, tries: 0, backedUp, added, addonPending, previous: st.version || null }));
    log(`Updated the relay to ${version} (${changed.length} file${changed.length === 1 ? "" : "s"}); restarting`);
    setTimeout(() => process.exit(0), 500);
    return;
  }
  // keep any "just updated" record (the starter's rollback check) and note the add-on's state
  fs.writeFileSync(UPDATE_FILE, JSON.stringify({ ...st, version: addonPending ? st.version || null : version, addonPending, at: Date.now() }));
}

async function test() {
  const cfg = loadConfig();
  console.log(`Device name: ${cfg.device}`);
  console.log(`Hub: ${cfg.hubUrl}`);
  const fl = files(cfg);
  console.log(fl.length ? "Add-on files found:\n  " + fl.join("\n  ") : "No LevelingLedger.lua found yet. Play with the add-on enabled and log out or /reload once, or set wowFolder in relay.json.");
  try {
    const r = await fetch(`${cfg.hubUrl}/api/relay/ping`, { headers: headers(cfg), redirect: "manual" });
    if (r.status >= 300 && r.status < 400) throw new Error("Cloudflare asked for a sign-in (check the service token and the Service Auth policy)");
    if (!r.ok) throw new Error(`hub answered ${r.status}`);
    console.log("Hub reached: OK");
    for (const f of fl) { await send(cfg, f); console.log(`Sent ${accountOf(f)}: OK`); }
    const s = await pullSummary(cfg, fl);
    console.log(s.found ? `In-game summary: ${s.chars} characters, written to ${s.found} add-on folder${s.found === 1 ? "" : "s"}` : "In-game summary: the add-on wasn't found next to the game's files, so there's nowhere to write it yet.");
  } catch (e) { console.log("Couldn't reach the hub: " + e.message); process.exitCode = 1; }
}

function run() {
  const cfg = loadConfig();
  let state = {};
  try { state = JSON.parse(fs.readFileSync(STATE_FILE, "utf8")); } catch {}
  const saveState = () => { try { fs.writeFileSync(STATE_FILE, JSON.stringify(state)); } catch (e) { log("Couldn't save relay-state.json: " + e.message); } };
  const pending = new Set();
  const watched = new Set();
  let delay = (cfg.retrySeconds || 60) * 1000, timer = null;

  async function flush() {
    clearTimeout(timer); timer = null;
    for (const f of [...pending]) {
      try {
        const hash = crypto.createHash("sha1").update(fs.readFileSync(f, "utf8")).digest("hex");
        if (state[f] && state[f].hash === hash) { pending.delete(f); continue; } // already sent
        await send(cfg, f);
        state[f] = { hash, sentAt: Date.now() }; saveState(); pending.delete(f);
        log(`Sent ${accountOf(f)} to the hub`);
        setTimeout(summary, 8000); // the hub needs a moment to import it
        delay = (cfg.retrySeconds || 60) * 1000;
      } catch (e) {
        log(`Couldn't send ${accountOf(f)} (${e.message}); trying again in ${delay < 60000 ? Math.round(delay / 1000) + " s" : Math.round(delay / 60000) + " min"}`);
        timer = setTimeout(flush, delay);
        delay = Math.min(delay * 2, 15 * 60 * 1000); // back off to every 15 minutes while away
        return;
      }
    }
  }
  function scan() {
    for (const f of files(cfg)) {
      if (watched.has(f)) continue;
      watched.add(f); log("Watching " + f);
      fs.watchFile(f, { interval: 3000 }, (cur, prev) => {
        if (cur.mtimeMs === prev.mtimeMs || !cur.mtimeMs) return;
        pending.add(f); setTimeout(flush, 2000); // let the game finish writing
      });
      pending.add(f);
    }
    if (pending.size && !timer) flush();
  }
  // the in-game summary: after each upload, and every 15 minutes
  let pulling = false;
  async function summary() {
    if (pulling) return; pulling = true;
    try { const s = await pullSummary(cfg, [...watched]); if (s.wrote) log(`Updated the in-game summary (${s.chars} characters)`); }
    catch (e) { log("Couldn't get the in-game summary: " + e.message); }
    finally { pulling = false; }
  }
  setInterval(summary, 15 * 60 * 1000);
  setTimeout(summary, 10 * 1000);
  // self-update: every 15 minutes; an add-on update waiting for WoW to close is tried every minute
  const update = () => selfUpdate(cfg, [...new Set([...watched].map(addonDirOf))].filter((d) => fs.existsSync(path.join(d, "LevelingLedger.toc"))))
    .catch((e) => log("Couldn't update the relay: " + e.message));
  setTimeout(update, 30 * 1000);
  setInterval(update, 15 * 60 * 1000);
  setInterval(() => { if (waitingForWow) update(); }, 60 * 1000);
  // a fresh update counts as good once the relay has run for two minutes
  setTimeout(() => {
    const st = readJSON(UPDATE_FILE);
    if (st.pending) { st.pending = false; st.tries = 0; try { fs.writeFileSync(UPDATE_FILE, JSON.stringify(st)); } catch {} log("Relay update to " + st.version + " is running fine"); }
  }, 2 * 60 * 1000);
  log(`Leveling Ledger relay for "${cfg.device}" sending to ${cfg.hubUrl}`);
  scan();
  if (!watched.size) log("No LevelingLedger.lua found yet; looking again every 5 minutes.");
  setInterval(scan, 5 * 60 * 1000);
  setInterval(() => { if (pending.size && !timer) flush(); }, 60 * 1000);
}

if (process.argv.includes("--test")) test(); else run();
