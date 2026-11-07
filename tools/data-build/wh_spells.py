# Adds cost, range, cast time, cooldown, requirement and Wowhead's description to every class's abilities.
import json, glob, re, html, sys
sys.path.insert(0, './work')
from wago import calc
S = './work/'
def clean(s):
    s = re.sub(r'<!--.*?-->', '', s); s = re.sub(r'<br\s*/?>', ' ', s); s = re.sub(r'<[^>]+>', '', s)
    return re.sub(r'\s+', ' ', html.unescape(s)).strip()
def parse(t):
    o = {}
    head = re.sub(r'\s+', ' ', html.unescape(re.sub(r'<[^>]+>', ' | ', re.sub(r'<!--.*?-->', '', t.split('<div class="wowhead-tooltip-requirements">')[0]))))
    m = re.search(r'(?<![\d.])(\d+% of base mana|\d+ (?:Mana|Rage|Energy|Focus))', head)
    if m: o['cost'] = m.group(1)
    m = re.search(r'(\d+ yd range|Melee Range)', head)
    if m: o['range'] = m.group(1)
    m = re.search(r'(Instant|[\d.]+ sec cast|Channeled|Next melee)', head)
    if m: o['cast'] = m.group(1)
    m = re.search(r'([\d.]+ (?:sec|min)) cooldown', head)
    if m: o['cd'] = m.group(1)
    CLASSES = r'(?:Warrior|Paladin|Hunter|Rogue|Priest|Shaman|Mage|Warlock|Druid)'
    for req in re.findall(r'wowhead-tooltip-requirements">Requires ([^<]+)<', t):
        req = req.strip()
        if re.fullmatch(CLASSES, req) or req.startswith('level '): continue
        o['form'] = req; break
    m = re.search(r'<div class="q">(.*?)</div>', t, re.S)
    if m: o['d'] = clean(m.group(1))
    return o
p = S + 'leveling/abilities-forever.json'; ab = json.load(open(p)); n = 0
for e in (e for v in ab['classes'].values() for e in v):
    try: d = json.load(open(S + f"wh/spells/{e['id']}.json"))
    except Exception: continue
    if 'tooltip' not in d: continue
    w = parse(d['tooltip'])
    for k in ('cost', 'range', 'cast', 'cd', 'form'):
        if w.get(k): e[k] = w[k]
    if w.get('d'):
        e['wh'] = 1
        txt = re.sub(r'\(([\d.\s*/+-]+)\)', lambda m: str(round(calc(m.group(1)))) if re.search(r'[*/+]', m.group(1)) else m.group(0), w['d'])
        if not re.search(r'\(\s*[\d.]+\s*[*/]', txt): e['gd'] = e.get('d', ''); e['d'] = txt
    n += 1
ab['wowhead'] = 'Ability costs, range, cast time, cooldown and descriptions from Wowhead tooltips (Forever).'
json.dump(ab, open(p, 'w'), separators=(',', ':'), ensure_ascii=False)
print('abilities enriched:', n, {c: sum(1 for e in v if e.get('wh')) for c, v in ab['classes'].items()})
for e in (e for v in ab['classes'].values() for e in v):
    if e['n'] in ('Regrowth', 'Bash', 'Heroic Strike', 'Sinister Strike', 'Frostbolt', 'Stealth', 'Overpower') and e.get('r', '') in ('Rank 1', ''):
        print({k: e.get(k) for k in ('n', 'r', 'lv', 'cost', 'range', 'cast', 'cd', 'form', 'd')})
