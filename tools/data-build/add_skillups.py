# Adds skill-up colors to leveling/recipebook-forever.json from Forever's SkillLineAbility table (wago.tools, build 1.60.1.70790).
import csv, json, collections
S = './work/'
names = {}
with open(S + 'sk/spellname.csv', newline='', encoding='utf-8') as f:
    for r in csv.DictReader(f): names[int(r['ID'])] = r['Name_lang']
PROF = {171: 'Alchemy', 164: 'Blacksmithing', 185: 'Cooking', 333: 'Enchanting', 202: 'Engineering', 129: 'First Aid', 165: 'Leatherworking', 186: 'Mining', 197: 'Tailoring'}
rows = collections.defaultdict(list)
with open(S + 'sk/sla.csv', newline='', encoding='utf-8') as f:
    for r in csv.DictReader(f):
        sl = int(r['SkillLine'])
        if sl in PROF: rows[(PROF[sl], names.get(int(r['Spell']), '').lower())].append({k: int(r[k]) for k in ('Spell', 'TrivialSkillLineRankLow', 'TrivialSkillLineRankHigh', 'NumSkillUps')})
p = S + 'leveling/recipebook-forever.json'; book = json.load(open(p))
n = 0
for r in book['recipes']:
    cand = rows.get((r['p'], r['n'].lower()))
    if not cand: continue
    # Season of Discovery copies use high spell IDs; take the lowest ID for normal recipes, the highest for SoD ones.
    cand = sorted(cand, key=lambda x: x['Spell'])
    c = cand[-1] if r.get('sod') else cand[0]
    lo, hi = c['TrivialSkillLineRankLow'], c['TrivialSkillLineRankHigh']
    if hi <= 0: continue
    r['su'] = [lo, (lo + hi) // 2, hi]
    if c['NumSkillUps'] > 1: r['sun'] = c['NumSkillUps']
    r['sp'] = c['Spell']
    n += 1
book['skillups'] = 'Skill-up colors: SkillLineAbility from World of Warcraft: Forever build 1.60.1.70790 (wago.tools).'
json.dump(book, open(p, 'w'), separators=(',', ':'), ensure_ascii=False)
print('recipes with skill-up colors:', n)
for nm in ('Heavy Woolen Cloak', 'Moonsteel Broadsword', 'Elixir of Giant Growth', 'Copper Bar', 'Smelt Copper', 'Linen Bandage'):
    x = next((r for r in book['recipes'] if r['n'] == nm and not r.get('sod')), None); print(nm, x and (x.get('su'), x.get('sk'), x.get('sun')))
