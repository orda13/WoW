// What relays on your other devices update themselves to: the relay's own files and the add-on,
// exactly as installed on the hub. The version is a fingerprint of the files, so it changes with any of them.
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

// The relay never replaces its starter (relay-boot.js) or the in-game summary (Shared.lua)
const RELAY_NAME = /^(relay\.js|lib\/[A-Za-z0-9_.-]+\.js|addon\/LevelingLedger\/(?!Shared\.lua$)[A-Za-z0-9_.-]+\.(lua|toc|xml|txt))$/;

function collect(appDir, addonDir) {
  const files = {};
  const add = (name, file) => { if (RELAY_NAME.test(name) && fs.existsSync(file)) files[name] = fs.readFileSync(file); };
  add("relay.js", path.join(appDir, "relay.js"));
  for (const f of fs.readdirSync(path.join(appDir, "lib"))) if (f.endsWith(".js")) add("lib/" + f, path.join(appDir, "lib", f));
  // the add-on: the hub's own copy (kept by installs and updates), else the one in the game folder
  let ad = path.join(appDir, "addon", "LevelingLedger");
  if (!fs.existsSync(path.join(ad, "LevelingLedger.toc"))) ad = addonDir();
  if (ad && fs.existsSync(ad)) for (const f of fs.readdirSync(ad)) add("addon/LevelingLedger/" + f, path.join(ad, f));
  return files;
}
function fingerprint(files) {
  const h = crypto.createHash("sha256");
  for (const name of Object.keys(files).sort()) { h.update(name + "\0"); h.update(files[name]); h.update("\0"); }
  return h.digest("hex").slice(0, 16);
}
function relayVersion(appDir, addonDir) { return fingerprint(collect(appDir, addonDir)); }
function relayBundle(appDir, addonDir) {
  const files = collect(appDir, addonDir);
  return { version: fingerprint(files), files: Object.fromEntries(Object.entries(files).map(([n, b]) => [n, b.toString("base64")])) };
}

module.exports = { relayVersion, relayBundle, RELAY_NAME, fingerprint };
