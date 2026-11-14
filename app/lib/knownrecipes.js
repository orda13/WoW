// Which of your characters knows which recipe: shared/knownrecipes, for the recipe book's "Known by", the profession
// guide and the in-game recipe tooltips (through Shared.lua). Built from each tracked character's own documents: the
// add-on's skills and recipe lists (state/addonskills) and Blizzard's professions (state/collections); the newer skill
// level wins, recipe lists are combined.
//   { byChar: { "talwyn bank": { name: "Talwyn Bank", profs: { Tailoring: { skill, max, recipes: [names] } } } }, updatedAt }
const titleName = (slug) => String(slug || "").split("-").filter(Boolean).map((w) => w[0].toUpperCase() + w.slice(1)).join(" ");

function charRecipes(cs) {
  const profs = {};
  const add = (name, skill, max, list, at) => {
    if (!name) return;
    const p = profs[name] || (profs[name] = { skill: null, max: null, at: -1, recipes: new Set() });
    if (skill != null && at >= p.at) { p.skill = skill; p.max = max || p.max; p.at = at; }
    for (const r of list || []) if (typeof r === "string" && r) p.recipes.add(r);
  };
  const coll = cs.get("state/collections") || {};
  for (const p of coll.professions || []) add(p.name, p.skill, p.max, p.recipes, coll.syncedAt || 0);
  const a = cs.get("state/addonskills") || {};
  for (const [n, v] of Object.entries(a.skills || {})) add(n, v && v.rank, v && v.max, [], a.skillsAt || 0);
  for (const [n, list] of Object.entries(a.recipes || {})) add(n, null, null, list, 0);
  const out = {};
  for (const [n, p] of Object.entries(profs)) out[n] = { skill: p.skill, max: p.max, recipes: [...p.recipes].sort() };
  return out;
}

// chars: the person's tracked characters ({ id, character }); storeOf(id) -> that character's store
function buildKnown(chars, storeOf) {
  const byChar = {};
  for (const c of chars) {
    if (!c.character) continue;
    const cs = storeOf(c.id);
    const profs = charRecipes(cs);
    if (!Object.keys(profs).length) continue;
    const name = titleName(c.character);
    byChar[name.toLowerCase()] = { name, profs };
  }
  return byChar;
}
function updateKnown(store, chars, storeOf) {
  const byChar = buildKnown(chars, storeOf);
  const prev = store.get("shared/knownrecipes") || {};
  if (JSON.stringify(prev.byChar || {}) === JSON.stringify(byChar)) return false;
  store.set("shared/knownrecipes", { byChar, updatedAt: Date.now() });
  return true;
}
// "Pattern: Red Woolen Bag" -> "Red Woolen Bag"
const recipeFromItem = (n) => String(n || "").replace(/^(Pattern|Recipe|Plans|Schematic|Formula|Manual|Design|Book|Blueprint):\s*/i, "");

module.exports = { buildKnown, updateKnown, charRecipes, titleName, recipeFromItem };
