// Reads WoW SavedVariables files (Lua table literals only). Nothing in the file is run.
function parseLuaSaved(src) {
  let i = 0; const n = src.length;
  const ws = () => {
    while (i < n) {
      const c = src[i];
      if (c === " " || c === "\t" || c === "\n" || c === "\r" || c === ",") i++;
      else if (src.startsWith("--", i)) { const j = src.indexOf("\n", i); i = j < 0 ? n : j + 1; }
      else break;
    }
  };
  const str = () => {
    const q = src[i++]; let out = "";
    while (i < n && src[i] !== q) {
      if (src[i] === "\\") {
        const c = src[i + 1];
        if (/\d/.test(c)) { const m = /^\d{1,3}/.exec(src.slice(i + 1)); out += String.fromCharCode(+m[0]); i += 1 + m[0].length; continue; }
        out += { n: "\n", t: "\t", r: "\r", "\n": "\n" }[c] ?? c; i += 2;
      } else out += src[i++];
    }
    i++; return out;
  };
  const val = () => {
    ws(); const c = src[i];
    if (c === "{") return table();
    if (c === '"' || c === "'") return str();
    const m = /^-?(?:\d+\.?\d*(?:[eE][-+]?\d+)?|\.\d+)/.exec(src.slice(i, i + 40));
    if (m) { i += m[0].length; return +m[0]; }
    for (const [w, v] of [["true", true], ["false", false], ["nil", null]]) if (src.startsWith(w, i)) { i += w.length; return v; }
    throw new Error("Unexpected text near character " + i);
  };
  const table = () => {
    i++; const obj = {}; let pos = 1;
    while (true) {
      ws();
      if (src[i] === "}") { i++; return obj; }
      if (src[i] === "[") { i++; const k = val(); ws(); i++; ws(); if (src[i] === "=") i++; obj[k] = val(); continue; }
      const m = /^([A-Za-z_]\w*)\s*=/.exec(src.slice(i, i + 80));
      if (m) { i += m[0].length; obj[m[1]] = val(); continue; }
      obj[pos++] = val();
    }
  };
  const out = {};
  while (true) {
    ws(); if (i >= n) break;
    const m = /^([A-Za-z_]\w*)\s*=/.exec(src.slice(i, i + 80));
    if (!m) throw new Error("This doesn't look like a SavedVariables file.");
    i += m[0].length; out[m[1]] = val();
  }
  return out;
}
const arr = (o) => (Array.isArray(o) ? o : o && typeof o === "object" ? Object.keys(o).sort((a, b) => a - b).map((k) => o[k]) : []);

module.exports = { parseLuaSaved, arr };
