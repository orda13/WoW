// Finds the add-on's SavedVariables file(s) and imports them whenever the game saves (log out or /reload).
const fs = require("fs");
const path = require("path");
const { importAddon, readSaved, pickChar } = require("./addon-import");

// Every WTF\Account\<account>\SavedVariables\LevelingLedger.lua under the game folder(s)
function findFiles(roots) {
  const out = [];
  for (const root of roots) {
    if (!root || !fs.existsSync(root)) continue;
    // root may be the World of Warcraft folder (with _forever_, _classic_era_, ...), a flavor folder, or a WTF folder
    const flavors = [];
    const has = (p) => fs.existsSync(path.join(p, "WTF", "Account"));
    if (has(root)) flavors.push(root);
    else if (fs.existsSync(path.join(root, "Account"))) flavors.push(path.dirname(root));
    else for (const d of safeDir(root)) if (d.startsWith("_") && has(path.join(root, d))) flavors.push(path.join(root, d));
    for (const fl of flavors) {
      const acc = path.join(fl, "WTF", "Account");
      for (const a of safeDir(acc)) {
        const f = path.join(acc, a, "SavedVariables", "LevelingLedger.lua");
        if (fs.existsSync(f)) out.push(f);
      }
    }
  }
  return [...new Set(out)];
}
function safeDir(p) { try { return fs.readdirSync(p, { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name); } catch { return []; } }

const DEFAULT_ROOTS = [
  "C:\\Program Files (x86)\\World of Warcraft",
  "C:\\Program Files\\World of Warcraft",
  "D:\\World of Warcraft", "D:\\Games\\World of Warcraft", "E:\\World of Warcraft",
];

function startWatcher({ store, publicDir, config, log, onImported }) {
  const roots = () => [].concat(config.wowFolder || [], config.wowFolder ? [] : DEFAULT_ROOTS);
  const watched = new Map(); // file -> last mtime handled
  const status = { files: [], lastCheck: 0, lastError: "" };

  function tryImport(file, why) {
    let text;
    try { text = fs.readFileSync(file, "utf8"); } catch (e) { status.lastError = `Couldn't read ${file}: ${e.message}`; return; }
    let data;
    try { data = readSaved(text); } catch (e) { status.lastError = `${file}: ${e.message}`; log(status.lastError); return; }
    const hint = (config.blizzard || {}).character;
    if (!pickChar(data, store, hint)) return; // another account's or character's file
    const have = (store.get("state/addon") || {}).savedAt || 0;
    if ((data.savedAt || 0) * 1000 <= have && why !== "manual") return;
    try {
      const r = importAddon(text, store, publicDir, file, hint);
      log(`Imported ${file} (${why}): ${r.message}`);
      status.lastError = "";
      if (onImported) onImported(r);
    } catch (e) { status.lastError = `Import of ${file} failed: ${e.message}`; log(status.lastError); }
  }

  function scan() {
    status.lastCheck = Date.now();
    const files = config.savedVariablesFile ? [config.savedVariablesFile] : findFiles(roots());
    status.files = files;
    for (const f of files) {
      if (watched.has(f)) continue;
      watched.set(f, 0);
      log("Watching " + f);
      // Polling is the most reliable way to see the game replace the file on Windows
      fs.watchFile(f, { interval: 2000 }, (cur, prev) => {
        if (cur.mtimeMs === prev.mtimeMs || !cur.mtimeMs) return;
        clearTimeout(watched.get(f + ":t"));
        // give the game a moment to finish writing
        watched.set(f + ":t", setTimeout(() => tryImport(f, "game saved"), 1500));
      });
      tryImport(f, "startup");
    }
    if (!files.length) status.lastError = "Couldn't find LevelingLedger.lua yet. If the game is installed somewhere else, set its folder on the Settings tab.";
  }
  scan();
  setInterval(scan, 5 * 60 * 1000); // pick up a file created after the first log-out
  // after the folder settings change: stop watching everything and look again
  function reset() {
    for (const f of [...watched.keys()]) { if (!f.endsWith(":t")) fs.unwatchFile(f); else clearTimeout(watched.get(f)); }
    watched.clear(); status.lastError = ""; scan();
  }
  return { status, scan, reset, importNow: () => { for (const f of status.files) tryImport(f, "manual"); } };
}

module.exports = { startWatcher, findFiles };
