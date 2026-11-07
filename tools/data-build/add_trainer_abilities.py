# Adds class abilities that trainers sell but build_abilities.py misses, to leveling/abilities-forever.json.
# Why they're missed: some rows have BaseLevel 0 (only SpellLevel says when they're learned), and some sit on a
# class skill line with ClassMask 0. Loosening those rules for everything would also pull in engravings and pet
# abilities, so the spells are listed here by id, as seen at an in-game trainer.
# Run from the folder that holds work/sk (the wago.tools tables):  python3 add_trainer_abilities.py <abilities json>
import sys, json, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wago

ADD = {
    'Druid': {
        1850: 'Feral Combat', 9821: 'Feral Combat',  # Dash ranks 1 and 2
        16864: 'Balance',                            # Omen of Clarity
        29166: 'Restoration',                        # Innervate
        5225: 'Feral Combat',                        # Track Humanoids
        20719: 'Feral Combat',                       # Feline Grace (passive)
        1328829: 'Feral Combat',                     # Poised (passive, Forever)
    },
}

path = sys.argv[1]
data = json.load(open(path, encoding='utf-8'))
added = 0
for cls, spells in ADD.items():
    have = {e['id'] for e in data['classes'][cls]}
    for sid, tree in spells.items():
        if sid in have: continue
        base, lvl, _ = wago.LEVELS[sid]
        e = {'id': sid, 'n': wago.NAMES[sid], 'lv': base if base > 0 else lvl, 't': tree}
        rk = wago.SPELL.get(sid, {}).get('NameSubtext_lang') or ''
        if rk: e['r'] = rk
        d = wago.text(sid)
        if d: e['d'] = d
        data['classes'][cls].append(e); added += 1
    data['classes'][cls].sort(key=lambda e: (e['lv'], e['n'], e.get('r', '')))
json.dump(data, open(path, 'w', encoding='utf-8'), separators=(',', ':'), ensure_ascii=False)
print('added', added)
