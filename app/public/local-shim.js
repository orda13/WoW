// The page's storage interface (documents and collections with live snapshots), backed by this PC's server.
(() => {
  const H = { "Content-Type": "application/json", "X-Ledger": "1" };
  // Which character this page shows: ?char= in the address, else the last one picked. "" is the main character.
  const CHAR = (() => {
    let c = new URLSearchParams(location.search).get("char");
    if (c !== null) { try { localStorage.setItem("ll-char", c); } catch {} }
    else { try { c = localStorage.getItem("ll-char") || ""; } catch { c = ""; } }
    return /^c[0-9a-f]{8}$/.test(c) ? c : "";
  })();
  // each alt's documents live under its own prefix; "shared/..." (all characters' bags and bank) is the same for every ledger
  const pre = (path) => (CHAR && !path.startsWith("shared/") && path !== "shared" ? CHAR + "." : "");
  const PRE = CHAR ? CHAR + "." : "";
  window.LL_CHAR = CHAR;
  const meta = { fromCache: false, hasPendingWrites: false };
  async function call(method, url, body) {
    const r = await fetch(url, { method, headers: H, body: body === undefined ? undefined : JSON.stringify(body) });
    if (!r.ok) { const e = new Error((await r.text()).slice(0, 200) || "HTTP " + r.status); e.code = "http_" + r.status; throw e; }
    return r.json();
  }
  const docSnap = (path, j) => ({ id: path.split("/").pop(), exists: j.exists, data: () => j.data, metadata: meta });
  const docSubs = new Map(); // path -> Set(fn)
  const colSubs = new Map(); // collection -> Set(fn)

  function docRef(path) {
    return {
      id: path.split("/").pop(), path,
      get: async () => docSnap(path, await call("GET", "/api/doc/" + pre(path) + path)),
      set: (d) => call("PUT", "/api/doc/" + pre(path) + path, d).then(() => undefined),
      update: (d) => call("PATCH", "/api/doc/" + pre(path) + path, d).then(() => undefined),
      delete: () => call("DELETE", "/api/doc/" + pre(path) + path).then(() => undefined),
      onSnapshot(next, err) {
        const f = async () => { try { next(docSnap(path, await call("GET", "/api/doc/" + pre(path) + path))); } catch (e) { if (err) err(e); } };
        if (!docSubs.has(path)) docSubs.set(path, new Set());
        docSubs.get(path).add(f); f();
        return () => docSubs.get(path).delete(f);
      },
    };
  }
  function colRef(col) {
    let order = null, lim = null;
    const q = {
      orderBy(field, dir) { order = [field, dir === "desc" ? -1 : 1]; return q; },
      limit(n) { lim = n; return q; },
      where() { return q; },
      doc: (id) => docRef(col + "/" + (id || Date.now().toString(36) + Math.random().toString(36).slice(2, 8))),
      add: async (d) => { const r = await call("POST", "/api/col/" + PRE + col, d); return docRef(col + "/" + r.id); },
      onSnapshot(next, err) {
        const f = async () => {
          try {
            let docs = (await call("GET", "/api/col/" + PRE + col)).docs;
            if (order) docs.sort((a, b) => { const x = a.data[order[0]], y = b.data[order[0]]; return (x > y ? 1 : x < y ? -1 : 0) * order[1]; });
            if (lim) docs = docs.slice(0, lim);
            const out = docs.map((d) => ({ id: d.id, exists: true, data: () => d.data, metadata: meta }));
            next({ docs: out, size: out.length, empty: !out.length, metadata: meta });
          } catch (e) { if (err) err(e); }
        };
        if (!colSubs.has(col)) colSubs.set(col, new Set());
        colSubs.get(col).add(f); f();
        return () => colSubs.get(col).delete(f);
      },
    };
    return q;
  }
  // Live updates: re-read whatever changed
  let opened = false;
  const es = new EventSource("/api/events");
  es.onmessage = (m) => {
    let ev; try { ev = JSON.parse(m.data); } catch { return; }
    // only this character's documents
    let p = ev.path;
    if (p.startsWith("shared/")) { /* the same for every character */ }
    else if (PRE) { if (!p.startsWith(PRE)) return; p = p.slice(PRE.length); }
    else if (p.split("/")[0].includes(".")) return;
    (docSubs.get(p) || []).forEach((f) => f());
    (colSubs.get(p.split("/")[0]) || []).forEach((f) => f());
  };
  const refreshAll = () => { docSubs.forEach((s) => s.forEach((f) => f())); colSubs.forEach((s) => s.forEach((f) => f())); };
  // connection state for the page's health line
  window.LL_CONN = { ok: false };
  const conn = (ok) => { if (window.LL_CONN.ok !== ok) { window.LL_CONN.ok = ok; window.dispatchEvent(new Event("ll-conn")); } };
  es.onopen = () => { conn(true); if (opened) refreshAll(); opened = true; };
  es.onerror = () => conn(false);
  // Backup in case a network in between holds back live updates
  setInterval(() => { if (document.visibilityState === "visible") refreshAll(); }, 60000);
  document.addEventListener("visibilitychange", () => { if (document.visibilityState === "visible") refreshAll(); });

  window.LL_LOCAL = true;
  window.claude = { use: async (n) => (n === "db" ? { doc: docRef, collection: colRef } : null) };
})();
