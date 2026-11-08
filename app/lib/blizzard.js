// Syncs the character from Blizzard's API into the store (same steps the claude.ai scheduled task used).
const SECTIONS = ["", "professions", "collections/mounts", "collections/pets", "collections/toys", "collections/heirlooms",
  "collections/transmogs", "achievements", "reputations", "titles", "quests/completed", "equipment"];
const QUAL = { POOR: 0, COMMON: 1, UNCOMMON: 2, RARE: 3, EPIC: 4, LEGENDARY: 5 };

let token = null, tokenExp = 0;
async function getToken(cfg) {
  if (token && Date.now() < tokenExp - 60000) return token;
  const basic = Buffer.from(`${cfg.clientId}:${cfg.clientSecret}`).toString("base64");
  const r = await fetch(cfg.oauthUrl || "https://oauth.battle.net/token", {
    method: "POST", headers: { Authorization: "Basic " + basic, "Content-Type": "application/x-www-form-urlencoded" }, body: "grant_type=client_credentials",
  });
  if (!r.ok) throw new Error(`Blizzard sign-in failed (HTTP ${r.status}). Check the Blizzard keys on the Settings tab.`);
  const j = await r.json();
  token = j.access_token; tokenExp = Date.now() + (j.expires_in || 3600) * 1000;
  return token;
}

async function fetchAll(cfg) {
  const t = await getToken(cfg);
  const base = (cfg.apiBase || "https://us.api.blizzard.com") + "/profile/wow/character/" + cfg.character;
  const out = {};
  await Promise.all(SECTIONS.map(async (p) => {
    const r = await fetch(base + (p ? "/" + p : "") + "?locale=en_US", { headers: { Authorization: "Bearer " + t, "Battlenet-Namespace": cfg.namespace || "profile-forever-us" } });
    out[p || "profile"] = { status: r.status, json: r.ok ? await r.json() : null };
  }));
  return out;
}

function build(sec, now) {
  const L = (k) => (sec[k] && sec[k].json) || {};
  const profs = [];
  for (const [group, kind] of [["primaries", "primary"], ["secondaries", "secondary"]])
    for (const x of L("professions")[group] || [])
      for (const t of x.tiers || [])
        profs.push({ name: x.profession.name, kind, skill: t.skill_points || 0, max: t.max_skill_points || 0, recipes: (t.known_recipes || []).map((r) => r.name).sort() });
  const reps = (L("reputations").reputations || []).map((r) => ({ name: r.faction.name, standing: r.standing.name, value: r.standing.value || 0, max: r.standing.max || 0, tier: r.standing.tier || 0 }));
  reps.sort((a, b) => b.tier - a.tier || b.value - a.value);
  const tm = {}; for (const s of L("collections/transmogs").slots || []) tm[s.slot.name] = (s.appearances || []).length;
  const ach = L("achievements");
  const quests = (L("quests/completed").quests || []).map((q) => q.id).sort((a, b) => a - b);
  const sortS = (a) => a.sort((x, y) => (x < y ? -1 : x > y ? 1 : 0));
  const collections = {
    professions: profs,
    mounts: sortS((L("collections/mounts").mounts || []).map((m) => m.mount.name)),
    pets: sortS([...new Set((L("collections/pets").pets || []).map((p) => p.species.name))]),
    toys: sortS((L("collections/toys").toys || []).map((t) => t.toy.name)),
    heirlooms: sortS((L("collections/heirlooms").heirlooms || []).filter((h) => h.heirloom).map((h) => h.heirloom.name)),
    titles: sortS((L("titles").titles || []).filter((t) => t.name).map((t) => t.name)),
    reputations: reps, transmogBySlot: tm, transmogTotal: Object.values(tm).reduce((a, b) => a + b, 0),
    questsCompleted: quests.length, achievements: ach.total_quantity || 0, achievementPoints: ach.total_points || 0, syncedAt: now,
  };
  const gear = [];
  for (const it of L("equipment").equipped_items || []) {
    const o = { slot: it.slot.type, sn: it.slot.name, id: it.item.id, n: it.name, q: QUAL[(it.quality || {}).type] ?? 1,
      il: (it.level || {}).value || 0, sl: (it.inventory_type || {}).name, sc: (it.item_subclass || {}).name };
    if ((it.armor || {}).value) o.ar = it.armor.value;
    const w = it.weapon;
    if (w && w.damage) o.w = [w.damage.min_value || 0, w.damage.max_value || 0, Math.round(((w.attack_speed || {}).value || 0) / 10) / 100, Math.round(((w.dps || {}).value || 0) * 10) / 10];
    const st = (it.stats || []).filter((s) => s.type).map((s) => [s.type.name, s.value]); if (st.length) o.st = st;
    const fx = (it.spells || []).map((s) => s.description).filter(Boolean); if (fx.length) o.fx = fx;
    if (it.durability && it.durability.value != null) o.du = [it.durability.value, it.durability.max_value];
    gear.push(o);
  }
  return { collections, quests: { completed: quests, syncedAt: now }, gear: { items: gear, syncedAt: now } };
}

// One short line naming what changed, e.g. "Level 13 → 14, +9 quests, Alchemy 67 → 82"
function summarize(old, nw, oldLevel, newLevel) {
  const bits = [];
  if (newLevel !== oldLevel && oldLevel != null) bits.push(`Level ${oldLevel} → ${newLevel}`);
  const oq = (old.quests && old.quests.completed || []).length, nq = nw.quests.completed.length;
  if (old.quests && nq > oq) bits.push(`+${nq - oq} quest${nq - oq === 1 ? "" : "s"}`);
  const op = Object.fromEntries(((old.collections || {}).professions || []).map((p) => [p.name + p.max, p.skill]));
  for (const p of nw.collections.professions) { const o = op[p.name + p.max]; if (o != null && o !== p.skill) bits.push(`${p.name} ${o} → ${p.skill}`); }
  for (const k of ["mounts", "pets", "toys", "titles"]) {
    const before = new Set((old.collections || {})[k] || []); const added = nw.collections[k].filter((x) => !before.has(x));
    if (old.collections && added.length) bits.push(`+${added.length} ${k.replace(/s$/, added.length === 1 ? "" : "s")} (${added.slice(0, 3).join(", ")})`);
  }
  const ors = Object.fromEntries(((old.collections || {}).reputations || []).map((r) => [r.name, r.standing]));
  for (const r of nw.collections.reputations) if (ors[r.name] && ors[r.name] !== r.standing) bits.push(`${r.name} ${ors[r.name]} → ${r.standing}`);
  const og = new Set(((old.gear || {}).items || []).map((g) => g.id));
  if (old.gear && nw.gear.items.some((g) => !og.has(g.id))) bits.push("new gear");
  return bits.join(", ") || "Updated from Blizzard";
}

const running = new Map(); // character -> promise
function syncBlizzard(store, cfg, log) {
  if (running.has(cfg.character)) return running.get(cfg.character);
  const job = (async () => {
    const now = Date.now();
    const status = (s) => store.set("state/syncstatus", { pending: false, at: Date.now(), ...s });
    try {
      if (!cfg || !cfg.clientId || !cfg.clientSecret) { status({ ok: false, changed: false, message: "Blizzard API keys aren't set yet. Add them on the Settings tab.", lastLogin: null }); return; }
      store.set("state/syncstatus", { ...(store.get("state/syncstatus") || {}), pending: true, startedAt: now });
      const sec = await fetchAll(cfg);
      const p = sec.profile;
      if (p.status !== 200) {
        const low = p.status === 404 && store.get("state/character");
        status({ ok: false, changed: false, message: low ? "Blizzard doesn't show this character yet (it lists characters from level 10, after they log out). Until then the ledger uses the add-on's data." : `Blizzard didn't return the character (HTTP ${p.status}). Try again later.`, lastLogin: null });
        return;
      }
      const pr = p.json;
      // a character added on the Settings tab: start its ledger from what Blizzard knows
      if (!store.get("state/character")) {
        store.set("state/character", { name: pr.name || cfg.character, version: "World of Warcraft: Forever", maxLevel: 60, level: pr.level, xp: pr.experience || 0,
          xpMax: 0, needsXpMax: true, rested: 0, zone: "", trackedMs: 0, faction: pr.faction && pr.faction.name, region: (cfg.region || "US"),
          race: pr.race && pr.race.name, cls: pr.character_class && pr.character_class.name, blizzardId: pr.id });
        store.set("dings/start-" + pr.level, { level: pr.level, at: Date.now(), trackedMs: 0 });
        log(`Set up the ledger for ${pr.name || cfg.character}`);
      }
      const c = store.get("state/character") || {};
      const old = { collections: store.get("state/collections"), quests: store.get("state/quests"), gear: store.get("state/gear") };
      if (pr.last_login_timestamp === c.lastLogin && pr.level === c.level && pr.experience === c.xp && old.collections && old.quests && old.gear) {
        status({ ok: true, changed: false, message: "No new play session from Blizzard yet. Blizzard updates your character after you log out of the game.", lastLogin: pr.last_login_timestamp });
        return;
      }
      const nw = build(sec, now);
      const message = summarize(old, nw, c.level, pr.level);
      store.set("state/collections", nw.collections);
      if (sec["quests/completed"].status === 200) store.set("state/quests", nw.quests);
      if (sec.equipment.status === 200) store.set("state/gear", nw.gear);
      const upd = { level: pr.level, xp: pr.experience, equippedItemLevel: pr.equipped_item_level, achievementPoints: pr.achievement_points,
        lastLogin: pr.last_login_timestamp, syncedAt: now, race: pr.race && pr.race.name, cls: pr.character_class && pr.character_class.name, src: "blizzard" };
      if (c.level != null && pr.level > c.level) {
        upd.needsXpMax = true;
        const xt = (store.get("state/xptable") || {}).levels || {};
        if (xt[pr.level]) { upd.xpMax = xt[pr.level]; upd.needsXpMax = false; }
        for (let lv = c.level + 1; lv <= pr.level; lv++) store.set(`dings/sync-${lv}-${now}`, { level: lv, at: pr.last_login_timestamp, trackedMs: c.trackedMs || 0 });
      }
      store.update("state/character", upd);
      status({ ok: true, changed: true, message, lastLogin: pr.last_login_timestamp });
      log("Blizzard sync: " + message);
    } catch (e) {
      status({ ok: false, changed: false, message: "Couldn't reach Blizzard: " + e.message, lastLogin: null });
      log("Blizzard sync failed: " + e.message);
    }
  })().finally(() => { running.delete(cfg.character); });
  running.set(cfg.character, job);
  return job;
}

// after new API keys are saved
function resetToken() { token = null; tokenExp = 0; }

module.exports = { syncBlizzard, build, summarize, resetToken };
