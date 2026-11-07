# Turns a Wowhead tooltip (nether.wowhead.com, dataEnv=16 = Forever) into the compact item shape the ledger uses.
import re, html

STAT_RE = re.compile(r'^[+-](\d+) (Strength|Agility|Stamina|Intellect|Spirit|Armor|Arcane Resistance|Fire Resistance|Frost Resistance|Nature Resistance|Shadow Resistance)$')
SLOTS = {'Head', 'Neck', 'Shoulder', 'Back', 'Chest', 'Shirt', 'Tabard', 'Wrist', 'Hands', 'Waist', 'Legs', 'Feet', 'Finger', 'Trinket', 'One-Hand', 'Two-Hand',
         'Main Hand', 'Off Hand', 'Held In Off-hand', 'Ranged', 'Thrown', 'Relic', 'Bag'}

def text(s):
    s = re.sub(r'<br\s*/?>', '\n', s)
    s = re.sub(r'<(td|th)[^>]*>', '\t', s)
    s = re.sub(r'<[^>]+>', '', s)
    return html.unescape(s)

def parse(d):
    t = d.get('tooltip', '')
    o = {'n': d.get('name'), 'q': d.get('quality', 1), 'src': 'wowhead'}
    m = re.search(r'<!--ilvl-->(\d+)', t)
    if m: o['il'] = int(m.group(1))
    m = re.search(r'<!--rlvl-->(\d+)', t)
    if m: o['rl'] = int(m.group(1))
    m = re.search(r'Binds (when picked up|when equipped|when used)', t)
    if m: o['b'] = 'Binds ' + m.group(1)
    m = re.search(r'<table width="100%"><tr><td>([^<]+)</td>(?:<th[^>]*>(?:<!--[^>]*-->)*([^<]*)</th>)?', t)
    if m:
        if m.group(1).strip() in SLOTS: o['sl'] = m.group(1).strip()
        if m.group(2): o['sc'] = m.group(2).strip()
    m = re.search(r'<!--amr-->(\d+) Armor', t)
    if m: o['ar'] = int(m.group(1))
    m = re.search(r'(\d+) - (\d+)\s*(?:<[^>]*>)*\s*Damage', t)
    sp = re.search(r'Speed (?:<!--[^>]*-->)?([\d.]+)', t)
    dps = re.search(r'\(([\d.]+) damage per second\)', t)
    if m and sp: o['w'] = [int(m.group(1)), int(m.group(2)), float(sp.group(1)), float(dps.group(1)) if dps else 0]
    stats = []
    for raw in re.findall(r'<!--stat\d+-->([^<]+)', t):
        mm = STAT_RE.match(html.unescape(raw.strip()))
        if mm: stats.append([mm.group(2), int(mm.group(1))])
    if stats: o['st'] = stats
    fx = []
    for kind, body in re.findall(r'<span[^>]*class="q2"[^>]*>(Equip|Use|Chance on hit): (.*?)</span>', t):
        fx.append(f'{kind}: ' + re.sub(r'\s+', ' ', text(body)).strip())
    if fx: o['fx'] = fx
    m = re.search(r'whtt-droppedby">Dropped by: ([^<]+)</div>', t)
    if m: o['by'] = html.unescape(m.group(1)).strip()
    m = re.search(r'whtt-dropchance">Drop Chance: ([\d.]+)%', t)
    if m: o['chance'] = float(m.group(1))
    if not o.get('sl') and not o.get('sc'):
        m = re.search(r'<td>(Potion|Elixir|Flask|Food & Drink|Consumable|Reagent|Trade Goods|Quest Item)</td>', t)
        if m: o['cl'] = m.group(1)
    return o
