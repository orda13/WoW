# Builds leveling/abilities-forever.json: spells each class learns by level (Forever game tables via wago.tools).
import sys, csv, json, os, collections
sys.path.insert(0, './work')
import wago
CLASSES = {1: 'Warrior', 2: 'Paladin', 3: 'Hunter', 4: 'Rogue', 5: 'Priest', 7: 'Shaman', 8: 'Mage', 9: 'Warlock', 11: 'Druid'}
lines = {int(r['ID']): r['DisplayName_lang'] for r in wago.rows('SkillLine') if r['CategoryID'] == '7'}
out = collections.defaultdict(list); seen = set()
for r in csv.DictReader(open(wago.S + 'sla.csv', encoding='utf-8')):
    sl = int(r['SkillLine'])
    if sl not in lines or r['AcquireMethod'] not in ('0', '2'): continue
    mask = int(r['ClassMask']); sid = int(r['Spell'])
    lv = wago.LEVELS.get(sid)
    if not mask or not lv or lv[0] <= 0: continue
    name = wago.NAMES.get(sid)
    if not name: continue
    for cid, cname in CLASSES.items():
        if mask & (1 << (cid - 1)) and (cid, sid) not in seen:
            seen.add((cid, sid))
            sp = wago.SPELL.get(sid, {})
            e = {'id': sid, 'n': name, 'lv': lv[0], 't': lines[sl]}
            rk = sp.get('NameSubtext_lang') or ''
            if rk == 'Passive' and '(Passive)' in name: continue
            if rk: e['r'] = rk
            d = wago.text(sid)
            if d: e['d'] = d
            if r['AcquireMethod'] == '2': e['auto'] = 1
            out[cname].append(e)
for c in out: out[c].sort(key=lambda e: (e['lv'], e['n'], e.get('r', '')))
json.dump({'source': 'Forever game tables (SkillLineAbility, SpellLevels, Spell) build 1.60.1.70790 via wago.tools', 'fetched': '2026-11-06', 'classes': out},
          open('./work/leveling/abilities-forever.json', 'w'), separators=(',', ':'), ensure_ascii=False)
print({c: len(v) for c, v in out.items()}, os.path.getsize('./work/leveling/abilities-forever.json'))
for e in out['Druid']:
    if 12 <= e['lv'] <= 16: print(e['lv'], e['n'], e.get('r', ''), '|', e.get('d', '')[:80])
