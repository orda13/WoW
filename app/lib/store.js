// A small document store kept in one JSON file. Paths look like "state/character" or "sessions/abc123".
const fs = require("fs");
const path = require("path");
const { EventEmitter } = require("events");

const PATH_RE = /^[A-Za-z0-9_\-.~:@+]{1,200}\/[A-Za-z0-9_\-.~:@+]{1,200}$/;

class Store extends EventEmitter {
  constructor(file, seedFile) {
    super();
    this.file = file;
    this.docs = {};
    if (fs.existsSync(file)) {
      this.docs = JSON.parse(fs.readFileSync(file, "utf8"));
    } else if (seedFile && fs.existsSync(seedFile)) {
      this.docs = JSON.parse(fs.readFileSync(seedFile, "utf8"));
      this.flushNow();
    }
    this.timer = null;
  }
  static validPath(p) { return typeof p === "string" && PATH_RE.test(p); }
  get(p) { return Object.prototype.hasOwnProperty.call(this.docs, p) ? this.docs[p] : undefined; }
  list(col) {
    const pre = col + "/";
    return Object.keys(this.docs).filter((k) => k.startsWith(pre)).map((k) => ({ id: k.slice(pre.length), data: this.docs[k] }));
  }
  set(p, data) { this.docs[p] = data; this.changed(p); }
  update(p, data) { this.docs[p] = { ...(this.docs[p] || {}), ...data }; this.changed(p); }
  delete(p) { delete this.docs[p]; this.changed(p); }
  // Swap in a whole new set of documents (used by restore); every changed or removed path is announced
  replaceAll(docs) {
    const old = this.docs;
    this.docs = { ...docs };
    for (const p of new Set([...Object.keys(old), ...Object.keys(this.docs)]))
      if (JSON.stringify(old[p]) !== JSON.stringify(this.docs[p])) this.emit("change", { path: p, exists: p in this.docs, data: this.docs[p] ?? null });
    this.flushNow();
  }
  add(col, data) { const id = Date.now().toString(36) + Math.random().toString(36).slice(2, 8); this.set(col + "/" + id, data); return id; }
  changed(p) {
    this.emit("change", { path: p, exists: p in this.docs, data: this.docs[p] ?? null });
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.flushNow(), 300);
  }
  // write to a temp file, keep the previous version as .bak, then swap in, so a crash never leaves a half-written file
  flushNow() {
    fs.mkdirSync(path.dirname(this.file), { recursive: true });
    const tmp = this.file + ".tmp";
    fs.writeFileSync(tmp, JSON.stringify(this.docs));
    if (fs.existsSync(this.file)) fs.copyFileSync(this.file, this.file + ".bak");
    fs.renameSync(tmp, this.file);
  }
}
module.exports = { Store };
