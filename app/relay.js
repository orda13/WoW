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

const CONFIG_FILE = process.env.LL_RELAY_CONFIG || path.join(__dirname, "relay.json");
const STATE_FILE = process.env.LL_RELAY_STATE || path.join(path.dirname(CONFIG_FILE), "relay-state.json");
const log = (m) => console.log(new Date().toISOString() + " " + m);

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
  log(`Leveling Ledger relay for "${cfg.device}" sending to ${cfg.hubUrl}`);
  scan();
  if (!watched.size) log("No LevelingLedger.lua found yet; looking again every 5 minutes.");
  setInterval(scan, 5 * 60 * 1000);
  setInterval(() => { if (pending.size && !timer) flush(); }, 60 * 1000);
}

if (process.argv.includes("--test")) test(); else run();
