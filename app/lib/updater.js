// One-click updates from the project's GitHub repository.
// Checks the latest commit, downloads that exact commit, checks it, keeps the current version for undo,
// copies the new files in and lets the service restart (NSSM starts it again).
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");
const vm = require("vm");

// What an update may replace, relative to the repository root -> relative to the app folder.
// The install scripts and tools are never touched: they run with administrator rights.
const APP_FILES = /^app\/(server\.js|relay\.js|relay-boot\.js|package\.json|README\.md|config\.example\.json|lib\/[A-Za-z0-9_.-]+\.js|public\/[A-Za-z0-9_.-]+\.(html|js|json|css|png|svg))$/;
// Shared.lua is written on each device (the in-game summary), so an update never replaces it
const ADDON_FILES = /^addon\/LevelingLedger\/(?!Shared\.lua$)[A-Za-z0-9_.-]+\.(lua|toc|xml|txt)$/;

function startUpdater({ appDir, dataDir, config, log, addonDir }) {
  const repo = () => config.updateRepo || "orda13/wow";
  const branch = () => config.updateBranch || "main";
  const api = () => config.updateApi || "https://api.github.com";
  const stateFile = path.join(dataDir, "installed.json");
  const backupDir = path.join(dataDir, "update-backup");
  const state = { installed: readJSON(stateFile), latest: null, changes: [], checkedAt: 0, error: "", busy: false };

  function readJSON(f) { try { return JSON.parse(fs.readFileSync(f, "utf8")); } catch { return null; } }
  const headers = { "User-Agent": "leveling-ledger-updater", Accept: "application/vnd.github+json" };

  async function check() {
    try {
      const r = await fetch(`${api()}/repos/${repo()}/commits/${branch()}`, { headers });
      if (!r.ok) throw new Error(`GitHub answered ${r.status}`);
      const c = await r.json();
      state.latest = { sha: c.sha, at: Date.parse(c.commit.committer.date), message: c.commit.message.split("\n")[0] };
      state.changes = [];
      const have = state.installed && state.installed.sha;
      if (have && have !== c.sha) {
        const cr = await fetch(`${api()}/repos/${repo()}/compare/${have}...${c.sha}`, { headers });
        if (cr.ok) { const cj = await cr.json(); state.changes = (cj.commits || []).map((x) => ({ sha: x.sha, message: x.commit.message.split("\n")[0], at: Date.parse(x.commit.committer.date) })).reverse().slice(0, 30); }
      } else if (!have) state.changes = [{ sha: c.sha, message: state.latest.message, at: state.latest.at }];
      state.error = "";
    } catch (e) { state.error = "Couldn't check for updates: " + e.message; }
    state.checkedAt = Date.now();
    return view();
  }

  function view() {
    const have = state.installed && state.installed.sha;
    return {
      repo: repo(), branch: branch(), installed: state.installed, latest: state.latest, changes: state.changes,
      available: !!(state.latest && state.latest.sha !== have), checkedAt: state.checkedAt, error: state.error, busy: state.busy,
      canUndo: fs.existsSync(path.join(backupDir, "files.json")),
    };
  }

  // Minimal tar reader (GitHub's tarballs: ustar with pax headers)
  function untar(buf) {
    const files = []; let i = 0, longName = null, pax = {};
    const str = (b, s, l) => b.toString("utf8", s, s + l).replace(/\0.*$/s, "");
    while (i + 512 <= buf.length) {
      const h = buf.subarray(i, i + 512);
      if (h.every((x) => x === 0)) break;
      let name = str(h, 0, 100); const prefix = str(h, 345, 155);
      if (prefix) name = prefix + "/" + name;
      const size = parseInt(str(h, 124, 12).trim() || "0", 8);
      const type = String.fromCharCode(h[156] || 48);
      const body = buf.subarray(i + 512, i + 512 + size);
      i += 512 + Math.ceil(size / 512) * 512;
      if (type === "x" || type === "g") { // pax: path=..., comment=<commit>
        for (const line of body.toString("utf8").split("\n")) { const m = /^\d+ ([^=]+)=(.*)$/.exec(line); if (m) (type === "g" ? (pax.global = pax.global || {}) : pax)[m[1]] = m[2]; }
        continue;
      }
      if (type === "L") { longName = body.toString("utf8").replace(/\0.*$/s, ""); continue; }
      if (pax.path) name = pax.path; if (longName) name = longName;
      pax = { global: pax.global }; longName = null;
      if (type === "0" || type === "\0" || type === "7") files.push({ name, data: Buffer.from(body) });
    }
    return { files, commit: pax.global && pax.global.comment };
  }

  async function update() {
    if (state.busy) throw new Error("An update is already running.");
    state.busy = true;
    try {
      const target = state.latest || (await check(), state.latest);
      if (!target) throw new Error(state.error || "No version to update to.");
      const url = config.updateTarball ? config.updateTarball : `${api()}/repos/${repo()}/tarball/${target.sha}`;
      const r = await fetch(url, { headers, redirect: "follow" });
      if (!r.ok) throw new Error(`Download failed (${r.status})`);
      const gz = Buffer.from(await r.arrayBuffer());
      if (gz.length > 60 * 1024 * 1024) throw new Error("Download is unexpectedly large.");
      const { files, commit } = untar(zlib.gunzipSync(gz));
      if (commit && commit !== target.sha) throw new Error("The download doesn't match the expected version.");
      // strip GitHub's top folder ("owner-repo-sha/") and keep only what an update may replace
      const appOut = [], addonOut = [];
      for (const f of files) {
        const rel = f.name.replace(/^[^/]+\//, "");
        if (rel.includes("..") || rel.includes("\\")) continue;
        if (APP_FILES.test(rel)) appOut.push({ rel: rel.slice(4), data: f.data });
        else if (ADDON_FILES.test(rel)) addonOut.push({ rel: rel.slice("addon/LevelingLedger/".length), data: f.data });
      }
      // the hub also keeps a copy of the add-on in its own folder, to hand to relays on your other devices
      for (const f of addonOut) appOut.push({ rel: "addon/LevelingLedger/" + f.rel, data: f.data });
      const must = ["server.js", "lib/store.js", "public/leveling-ledger.html", "public/local-shim.js"];
      for (const m of must) if (!appOut.some((f) => f.rel === m)) throw new Error("The download is missing " + m + ".");
      // every script must at least parse
      for (const f of appOut.filter((x) => x.rel.endsWith(".js"))) {
        try { new vm.Script(f.data.toString("utf8"), { filename: f.rel }); } catch (e) { throw new Error(`${f.rel} doesn't parse: ${e.message}`); }
      }
      // keep the current version for undo
      fs.rmSync(backupDir, { recursive: true, force: true });
      const saved = [];
      for (const f of appOut) {
        const cur = path.join(appDir, f.rel);
        if (fs.existsSync(cur)) { const b = path.join(backupDir, "app", f.rel); fs.mkdirSync(path.dirname(b), { recursive: true }); fs.copyFileSync(cur, b); saved.push({ rel: f.rel, existed: true }); }
        else saved.push({ rel: f.rel, existed: false });
      }
      const addonTarget = addonDir();
      const savedAddon = [];
      if (addonTarget) for (const f of addonOut) {
        const cur = path.join(addonTarget, f.rel);
        if (fs.existsSync(cur)) { const b = path.join(backupDir, "addon", f.rel); fs.mkdirSync(path.dirname(b), { recursive: true }); fs.copyFileSync(cur, b); savedAddon.push({ rel: f.rel, existed: true }); }
        else savedAddon.push({ rel: f.rel, existed: false });
      }
      fs.writeFileSync(path.join(backupDir, "files.json"), JSON.stringify({ app: saved, addon: savedAddon, addonDir: addonTarget, previous: state.installed }));
      // copy in
      for (const f of appOut) { const d = path.join(appDir, f.rel); fs.mkdirSync(path.dirname(d), { recursive: true }); fs.writeFileSync(d, f.data); }
      let addonNote = "";
      if (addonTarget) { for (const f of addonOut) fs.writeFileSync(path.join(addonTarget, f.rel), f.data); addonNote = " The add-on was updated too; type /reload in game to load it."; }
      else if (addonOut.length) addonNote = " The add-on wasn't found in your game's AddOns folder, so copy addon\\LevelingLedger there yourself.";
      state.installed = { sha: target.sha, at: Date.now(), message: target.message };
      fs.writeFileSync(stateFile, JSON.stringify(state.installed));
      log(`Updated to ${target.sha.slice(0, 7)} (${appOut.length} app files, ${addonTarget ? addonOut.length : 0} add-on files); restarting`);
      return { ok: true, message: `Updated to ${target.sha.slice(0, 7)}. The service is restarting; the page reloads in a moment.` + addonNote };
    } finally { state.busy = false; }
  }

  function undo() {
    const list = readJSON(path.join(backupDir, "files.json"));
    if (!list) throw new Error("There's no update to undo.");
    for (const f of list.app) {
      const d = path.join(appDir, f.rel);
      if (f.existed) fs.copyFileSync(path.join(backupDir, "app", f.rel), d); else fs.rmSync(d, { force: true });
    }
    if (list.addonDir) for (const f of list.addon) {
      const d = path.join(list.addonDir, f.rel);
      if (f.existed) fs.copyFileSync(path.join(backupDir, "addon", f.rel), d); else fs.rmSync(d, { force: true });
    }
    state.installed = list.previous || null;
    if (state.installed) fs.writeFileSync(stateFile, JSON.stringify(state.installed)); else fs.rmSync(stateFile, { force: true });
    fs.rmSync(backupDir, { recursive: true, force: true });
    log("Undid the last update; restarting");
    return { ok: true, message: "Went back to the previous version. The service is restarting; the page reloads in a moment." };
  }

  setTimeout(check, 30 * 1000);
  setInterval(check, 6 * 3600 * 1000);
  return { check, update, undo, view };
}

module.exports = { startUpdater };
