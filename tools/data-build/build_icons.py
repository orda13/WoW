# Builds app/public/icons-forever.json: icon names for every item (and the spells the page uses), from the game's own
# tables on wago.tools (Item, ItemModifiedAppearance, ItemAppearance, SpellMisc for product "wowf") and the community
# listfile (github.com/wowdev/wow-listfile), which names each icon file. The page loads the images by name from
# render.worldofwarcraft.com. Run from tools/data-build with the CSVs and community-listfile.csv in ./work.
import csv, json, re, glob, os
W, PUB = 'work', os.path.join('..', '..', 'app', 'public')
icons = {}
for line in open(os.path.join(W, 'community-listfile.csv'), encoding='utf-8', errors='replace'):
    fid, _, p = line.strip().partition(';')
    if p.startswith('interface/icons/'): icons[int(fid)] = re.sub(r'\.blp$', '', p[16:]).lower()
items = {}
for r in csv.DictReader(open(os.path.join(W, 'Item.csv'))):
    f = int(r.get('IconFileDataID') or 0)
    if f in icons: items[int(r['ID'])] = icons[f]
app = {int(r['ID']): int(r['DefaultIconFileDataID'] or 0) for r in csv.DictReader(open(os.path.join(W, 'ItemAppearance.csv')))}
best = {}
for r in csv.DictReader(open(os.path.join(W, 'ItemModifiedAppearance.csv'))):
    i, o, f = int(r['ItemID']), int(r['OrderIndex'] or 0), app.get(int(r['ItemAppearanceID']), 0)
    if f in icons and (i not in best or o < best[i][0]): best[i] = (o, icons[f])
for i, (_, n) in best.items(): items.setdefault(i, n)
spells = {int(r['SpellID']): icons[int(r['SpellIconFileDataID'])] for r in csv.DictReader(open(os.path.join(W, 'SpellMisc.csv'))) if int(r.get('SpellIconFileDataID') or 0) in icons}
nums = set()
for f in glob.glob(os.path.join(PUB, '*.json')):
    if 'icons-' in f: continue
    nums.update(int(m) for m in re.findall(r'(?<![\w.])(\d{2,7})(?![\w.])', open(f, encoding='utf-8').read()))
used_s = {i: spells[i] for i in nums if i in spells}
names = sorted(set(items.values()) | set(used_s.values())); idx = {n: k for k, n in enumerate(names)}
json.dump({'names': names, 'i': {str(k): idx[v] for k, v in sorted(items.items())}, 's': {str(k): idx[v] for k, v in sorted(used_s.items())}},
          open(os.path.join(PUB, 'icons-forever.json'), 'w'), separators=(',', ':'))
print('items', len(items), 'spells', len(used_s), 'icons', len(names))
