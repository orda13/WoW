// Starts the Leveling Ledger relay. This small file is never replaced by the relay's own updates:
// if an update leaves the relay unable to start (three tries), it puts the previous version back.
const fs = require("fs");
const path = require("path");

const dataDir = process.env.LL_RELAY_STATE ? path.dirname(process.env.LL_RELAY_STATE) : __dirname;
const UPDATE_FILE = path.join(dataDir, "relay-update.json");
const BACKUP_DIR = path.join(dataDir, "relay-backup");

let st = {};
try { st = JSON.parse(fs.readFileSync(UPDATE_FILE, "utf8")); } catch {}
if (st.pending) {
  st.tries = (st.tries || 0) + 1;
  if (st.tries > 3) {
    for (const rel of st.backedUp || []) {
      const from = path.join(BACKUP_DIR, rel), to = path.join(__dirname, rel);
      try { fs.mkdirSync(path.dirname(to), { recursive: true }); fs.copyFileSync(from, to); } catch {}
    }
    for (const rel of st.added || []) { try { fs.rmSync(path.join(__dirname, rel), { force: true }); } catch {} }
    console.log(new Date().toISOString() + ` The relay update to ${st.version} didn't start; went back to the previous version.`);
    st = { rolledBack: st.version, at: Date.now() };
  }
  try { fs.writeFileSync(UPDATE_FILE, JSON.stringify(st)); } catch {}
}
process.env.LL_RELAY_UPDATE_FILE = UPDATE_FILE;
process.env.LL_RELAY_BACKUP_DIR = BACKUP_DIR;
require("./relay.js");
