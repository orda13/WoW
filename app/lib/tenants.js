// People with their own ledger on this hub. The owner (this PC, and the emails in Remote access) keeps the data where
// it always was; everyone the owner adds in Settings gets a private namespace in the same store: their documents sit
// under "u<8 hex>~" (from their email), so "state/character" is "u1a2b3c4~state/character" for them. A few documents
// are game data everyone shares: auction prices, item names and Blizzard's dungeon journal.
const crypto = require("crypto");
const path = require("path");

const POOLED = new Set(["shared/ahprices", "shared/items", "shared/journal"]);
const USER_DOC = /^u[0-9a-f]{8}~/;
const userId = (email) => "u" + crypto.createHash("sha1").update(String(email).trim().toLowerCase()).digest("hex").slice(0, 8);

// A view of the store for one person, with the methods the rest of the hub uses (get, set, update, delete, list, add)
// plus docs (their documents by their own paths) and keys().
function tenantStore(store, uid) {
  if (!uid) {
    // the owner: plain paths, minus the other people's documents
    return {
      uid: "",
      get: (p) => store.get(p), set: (p, d) => store.set(p, d), update: (p, d) => store.update(p, d), delete: (p) => store.delete(p),
      list: (col) => store.list(col), add: (col, d) => store.add(col, d), flushNow: () => store.flushNow(),
      keys: () => Object.keys(store.docs).filter((k) => !USER_DOC.test(k)),
      get docs() { const o = {}; for (const k of Object.keys(store.docs)) if (!USER_DOC.test(k)) o[k] = store.docs[k]; return o; },
    };
  }
  const pre = uid + "~";
  const at = (p) => (POOLED.has(p) ? p : pre + p);
  return {
    uid,
    get: (p) => store.get(at(p)), set: (p, d) => store.set(at(p), d), update: (p, d) => store.update(at(p), d), delete: (p) => store.delete(at(p)),
    list: (col) => store.list(pre + col), add: (col, d) => store.add(pre + col, d), flushNow: () => store.flushNow(),
    keys: () => Object.keys(store.docs).filter((k) => k.startsWith(pre)).map((k) => k.slice(pre.length)),
    get docs() { const o = {}; for (const k of Object.keys(store.docs)) if (k.startsWith(pre)) o[k.slice(pre.length)] = store.docs[k]; for (const p of POOLED) if (p in store.docs) o[p] = store.docs[p]; return o; },
  };
}
// A store change, as one person's page should see it: the path in their terms, or null when it isn't theirs
function viewPath(p, uid) {
  if (POOLED.has(p)) return p;
  if (!uid) return USER_DOC.test(p) ? null : p;
  return p.startsWith(uid + "~") ? p.slice(uid.length + 1) : null;
}

// The people the owner added: config.users = [{ email, id, character, alts, altsRemoved, tokens }]
function users(config) { return Array.isArray(config.users) ? config.users : []; }
// Who a request is: the owner (this PC, an email in Remote access, an owner device) or one of the people added
function tenantFor(config, req) {
  const email = String(req.userEmail || "").toLowerCase(), token = String(req.serviceToken || "").toLowerCase();
  if (email) { const u = users(config).find((x) => x.email === email); if (u && !(config.access.allowedEmails || []).map((e) => String(e).toLowerCase()).includes(email)) return u; }
  if (token) { const u = users(config).find((x) => (x.tokens || []).map((t) => String(t).toLowerCase()).includes(token)); if (u) return u; }
  return null; // the owner
}
// The sign-in check's settings: the owner's emails and devices plus everyone added and their devices
function accessConfig(config) {
  const a = config.access || {};
  return { ...a, allowedEmails: [...(a.allowedEmails || []), ...users(config).map((u) => u.email)],
    serviceTokens: [...(a.serviceTokens || []), ...users(config).flatMap((u) => u.tokens || [])] };
}
// The settings the character code reads (main character, alts, removed ones), for the owner or one person
function charConfig(config, u) {
  if (!u) return config;
  return { blizzard: { character: u.character || "" }, alts: u.alts || [], altsRemoved: u.altsRemoved || [] };
}
// Where a person's relays leave their files
const userDir = (dataDir, u) => path.join(dataDir, "users", u.id);

module.exports = { POOLED, USER_DOC, userId, tenantStore, viewPath, users, tenantFor, accessConfig, charConfig, userDir };
