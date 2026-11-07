// Settings for the Settings tab: what the page may see, and checked updates written back to config.json.
const fs = require("fs");

const EMAIL = /^[^\s@<>()",;:]+@[^\s@<>()",;:]+\.[a-z]{2,}$/i;

// What the page sees. The Blizzard secret is never sent, only whether one is saved.
function publicView(config, isLocal) {
  const b = config.blizzard || {}, a = config.access || {};
  return {
    blizzard: { clientId: b.clientId || "", hasSecret: !!b.clientSecret, character: b.character || "", namespace: b.namespace || "profile-forever-us" },
    syncEveryHours: config.syncEveryHours || 6,
    backupDays: config.backupDays || 14,
    wowFolder: config.wowFolder || "",
    savedVariablesFile: config.savedVariablesFile || "",
    port: config.port || 8787,
    alts: config.alts || [],
    access: { teamDomain: a.teamDomain || "", aud: a.aud || "", allowedEmails: a.allowedEmails || [] },
    canEditAccess: isLocal,
  };
}

// Checks every field and applies the valid ones to config (in place). Returns { changed, errors }.
function applyUpdate(config, body, isLocal) {
  const errors = {}, changed = [];
  const set = (obj, key, value, label) => { if (obj[key] !== value) { obj[key] = value; changed.push(label); } };
  const str = (v, max) => (typeof v === "string" ? v.trim().slice(0, max) : null);
  // a field sent back exactly as it is now is left alone (never blocks a save, even if it predates these checks)
  const same = (cur, v) => (cur || "") === (typeof v === "string" ? v.trim() : v);

  if (body.blizzard && typeof body.blizzard === "object") {
    const b = (config.blizzard = config.blizzard || {});
    const nb = body.blizzard;
    if (nb.clientId != null && !same(b.clientId, nb.clientId)) {
      const v = str(nb.clientId, 100);
      if (v === null || (v && !/^[A-Za-z0-9]+$/.test(v))) errors.clientId = "Client ID is letters and numbers only.";
      else set(b, "clientId", v, "Blizzard client ID");
    }
    if (nb.clientSecret) { // blank keeps the saved secret
      const v = str(nb.clientSecret, 100);
      if (!v || !/^[A-Za-z0-9]+$/.test(v)) errors.clientSecret = "Client secret is letters and numbers only.";
      else set(b, "clientSecret", v, "Blizzard client secret");
    }
    if (nb.character != null) {
      const v = (str(nb.character, 60) || "").toLowerCase().replace(/\s+/g, "-");
      if (!/^[\p{L}\p{N}'-]+$/u.test(v)) errors.character = 'Character as Blizzard spells it, like "talwyn-orda".';
      else set(b, "character", v, "character");
    }
  }
  if (body.alts != null) {
    // extra characters, as Blizzard spells them ("bob-smith"); their data is kept if one is removed and added again
    const main = (config.blizzard && config.blizzard.character) || "";
    const raw = Array.isArray(body.alts) ? body.alts : String(body.alts).split(/[\n,]+/);
    const list = [...new Set(raw.map((x) => String(x).trim().toLowerCase().replace(/\s+/g, "-")).filter((x) => x && x !== main))];
    if (list.length > 10) errors.alts = "Up to 10 extra characters.";
    else if (list.some((x) => !/^[\p{L}\p{N}'-]+$/u.test(x) || x.length > 60)) errors.alts = 'Each character as Blizzard spells it, like "bob-smith".';
    else if (JSON.stringify(config.alts || []) !== JSON.stringify(list)) { config.alts = list; changed.push("characters"); }
  }
  if (body.syncEveryHours != null) {
    const v = Number(body.syncEveryHours);
    if (!(v >= 1 && v <= 24)) errors.syncEveryHours = "Between 1 and 24 hours.";
    else set(config, "syncEveryHours", Math.round(v * 2) / 2, "sync interval");
  }
  if (body.backupDays != null) {
    const v = Number(body.backupDays);
    if (!(Number.isInteger(v) && v >= 1 && v <= 90)) errors.backupDays = "A whole number of days, 1 to 90.";
    else set(config, "backupDays", v, "backups kept");
  }
  if (body.wowFolder != null && !same(config.wowFolder, body.wowFolder)) {
    const v = str(body.wowFolder, 260);
    if (v === null || /[<>"|?*]/.test(v)) errors.wowFolder = "That isn't a folder path.";
    else set(config, "wowFolder", v, "World of Warcraft folder");
  }
  if (body.savedVariablesFile != null && !same(config.savedVariablesFile, body.savedVariablesFile)) {
    const v = str(body.savedVariablesFile, 320);
    if (v === null || (v && (!/\.lua$/i.test(v) || /[<>"|?*]/.test(v)))) errors.savedVariablesFile = "Leave blank, or the full path to LevelingLedger.lua.";
    else set(config, "savedVariablesFile", v, "add-on file");
  }
  if (body.access && typeof body.access === "object") {
    if (!isLocal) errors.access = "Remote-access settings can only be changed on the PC running the ledger.";
    else {
      const a = (config.access = config.access || {});
      const na = body.access;
      if (na.teamDomain != null && !same(a.teamDomain, na.teamDomain)) {
        const v = (str(na.teamDomain, 120) || "").toLowerCase().replace(/^https?:\/\//, "").replace(/\/.*$/, "");
        if (v && !/^[a-z0-9-]+\.cloudflareaccess\.com$/.test(v)) errors.teamDomain = 'Like "yourteam.cloudflareaccess.com".';
        else set(a, "teamDomain", v, "Cloudflare team domain");
      }
      if (na.aud != null && !same(a.aud, na.aud)) {
        const v = (str(na.aud, 100) || "").toLowerCase();
        if (v && !/^[a-f0-9]{64}$/.test(v)) errors.aud = "The Application Audience (AUD) tag is 64 letters and numbers.";
        else set(a, "aud", v, "Cloudflare application tag");
      }
      if (na.allowedEmails != null) {
        const list = (Array.isArray(na.allowedEmails) ? na.allowedEmails : String(na.allowedEmails).split(/[\s,;]+/))
          .map((e) => String(e).trim().toLowerCase()).filter(Boolean);
        if (list.length > 20 || list.some((e) => !EMAIL.test(e))) errors.allowedEmails = "One email address per line (up to 20).";
        else if (JSON.stringify(a.allowedEmails || []) !== JSON.stringify(list)) { a.allowedEmails = list; changed.push("allowed emails"); }
      }
    }
  }
  return { changed, errors };
}

// config.json is written in place: the service may not create files next to it.
function saveConfig(file, config) {
  fs.writeFileSync(file, JSON.stringify(config, null, 2) + "\n");
}

module.exports = { publicView, applyUpdate, saveConfig };
