// Checks Cloudflare Access sign-ins. Requests arriving through Cloudflare must carry a valid Access token
// (issued after Google sign-in) for an allowed email. Requests made directly on this PC (localhost) are allowed.
const crypto = require("crypto");

let keys = {}, keysAt = 0;
async function loadKeys(cfg) {
  if (Date.now() - keysAt < 60 * 60 * 1000 && Object.keys(keys).length) return keys;
  const url = cfg.certsUrl || `https://${cfg.teamDomain}/cdn-cgi/access/certs`;
  const r = await fetch(url);
  if (!r.ok) throw new Error("Couldn't load Cloudflare Access keys (HTTP " + r.status + ")");
  const j = await r.json();
  const next = {};
  for (const k of j.keys || []) next[k.kid] = crypto.createPublicKey({ key: k, format: "jwk" });
  keys = next; keysAt = Date.now();
  return keys;
}
const b64 = (s) => Buffer.from(s.replace(/-/g, "+").replace(/_/g, "/"), "base64");

async function verifyAccessJwt(token, cfg) {
  const parts = (token || "").split(".");
  if (parts.length !== 3) throw new Error("no sign-in token");
  const header = JSON.parse(b64(parts[0]).toString("utf8"));
  const payload = JSON.parse(b64(parts[1]).toString("utf8"));
  if (header.alg !== "RS256") throw new Error("unexpected token type");
  let ks = await loadKeys(cfg);
  if (!ks[header.kid]) { keysAt = 0; ks = await loadKeys(cfg); } // keys rotate
  const key = ks[header.kid];
  if (!key) throw new Error("unknown signing key");
  const ok = crypto.verify("RSA-SHA256", Buffer.from(parts[0] + "." + parts[1]), key, b64(parts[2]));
  if (!ok) throw new Error("bad signature");
  const now = Math.floor(Date.now() / 1000);
  if (payload.exp && payload.exp < now - 30) throw new Error("sign-in expired");
  if (payload.nbf && payload.nbf > now + 30) throw new Error("token not valid yet");
  const auds = [].concat(payload.aud || []);
  if (!auds.includes(cfg.aud)) throw new Error("token is for a different application");
  const iss = cfg.issuer || `https://${cfg.teamDomain}`;
  if (payload.iss !== iss) throw new Error("token from a different team");
  const email = String(payload.email || "").toLowerCase();
  const allowed = (cfg.allowedEmails || []).map((e) => String(e).toLowerCase());
  if (!email || !allowed.includes(email)) throw new Error("this Google account isn't allowed");
  return email;
}

function cookie(req, name) {
  const m = new RegExp("(?:^|;\\s*)" + name + "=([^;]+)").exec(req.headers.cookie || "");
  return m ? decodeURIComponent(m[1]) : null;
}

// Returns null if the request may proceed, or an error message.
async function checkRequest(req, cfg) {
  const viaCloudflare = !!(req.headers["cf-ray"] || req.headers["cf-connecting-ip"] || req.headers["cf-access-jwt-assertion"]);
  const remote = req.socket.remoteAddress || "";
  const local = remote === "127.0.0.1" || remote === "::1" || remote === "::ffff:127.0.0.1";
  if (!local) return "Only this PC and Cloudflare may connect.";
  if (!viaCloudflare) {
    // Direct use on this PC must name this PC, which stops websites that re-point their own address at 127.0.0.1
    const host = String(req.headers.host || "").replace(/:\d+$/, "").toLowerCase();
    return host === "localhost" || host === "127.0.0.1" || host === "[::1]" ? null : "Open the ledger at http://localhost on this PC, or through your Cloudflare address.";
  }
  if (!cfg || !cfg.teamDomain || !cfg.aud || !(cfg.allowedEmails || []).length)
    return "Remote access isn't configured yet: set access.teamDomain, access.aud and access.allowedEmails in config.json.";
  try {
    req.userEmail = await verifyAccessJwt(req.headers["cf-access-jwt-assertion"] || cookie(req, "CF_Authorization"), cfg);
    return null;
  } catch (e) { return "Sign-in check failed: " + e.message; }
}

module.exports = { checkRequest, verifyAccessJwt };
