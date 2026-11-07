// Daily copies of the ledger's data file, kept for a set number of days, with restore.
const fs = require("fs");
const path = require("path");

const DAILY = /^store-(\d{4}-\d{2}-\d{2})\.json$/;
const BEFORE = /^store-before-restore-(\d+)\.json$/;
const NAME_OK = /^store-[A-Za-z0-9-]+\.json$/;

function localDate(d = new Date()) {
  const p = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

function startBackups({ store, dir, keepDays = 14, log }) {
  fs.mkdirSync(dir, { recursive: true });

  function list() {
    return fs.readdirSync(dir).filter((n) => DAILY.test(n) || BEFORE.test(n)).map((n) => {
      const st = fs.statSync(path.join(dir, n));
      return { name: n, size: st.size, at: st.mtimeMs, kind: DAILY.test(n) ? "daily" : "before-restore" };
    }).sort((a, b) => b.at - a.at);
  }

  function write(name) {
    store.flushNow(); // make sure the file on disk is current
    const tmp = path.join(dir, name + ".tmp");
    fs.copyFileSync(store.file, tmp);
    fs.renameSync(tmp, path.join(dir, name));
  }

  function prune() {
    const daily = list().filter((b) => b.kind === "daily");
    for (const b of daily.slice(typeof keepDays === "function" ? keepDays() : keepDays)) fs.unlinkSync(path.join(dir, b.name));
    const before = list().filter((b) => b.kind === "before-restore");
    for (const b of before.slice(5)) fs.unlinkSync(path.join(dir, b.name));
  }

  function daily() {
    try {
      const name = `store-${localDate()}.json`;
      if (fs.existsSync(path.join(dir, name)) || !fs.existsSync(store.file)) return;
      write(name);
      prune();
      log("Backup saved: " + name);
    } catch (e) { log("Backup failed: " + e.message); }
  }

  function resolve(name) {
    if (!NAME_OK.test(name || "")) return null;
    const f = path.join(dir, name);
    return fs.existsSync(f) ? f : null;
  }

  // Replace all data with a backup; the current data is saved first so this can be undone.
  function restore(name) {
    const f = resolve(name);
    if (!f) throw new Error("No backup by that name.");
    const docs = JSON.parse(fs.readFileSync(f, "utf8"));
    if (!docs || typeof docs !== "object" || Array.isArray(docs)) throw new Error("That backup isn't a ledger data file.");
    const safety = `store-before-restore-${Date.now()}.json`;
    write(safety);
    store.replaceAll(docs);
    prune();
    log(`Restored ${name} (previous data saved as ${safety})`);
    return safety;
  }

  // "Back up now": today's backup, replaced with the data as it is right now
  function now() { const name = `store-${localDate()}.json`; write(name); prune(); log("Backup saved: " + name); return name; }

  daily();
  setInterval(daily, 60 * 60 * 1000); // checks hourly; writes once per day
  return { list, restore, resolve, daily, now };
}

module.exports = { startBackups, localDate };
