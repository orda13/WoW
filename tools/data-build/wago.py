# Reads Forever game tables (wago.tools, build 1.60.1.70790) and renders spell text.
import csv, re, collections
S = './work/sk/'
def rows(t):
    with open(S + f't_{t}.csv', newline='', encoding='utf-8') as f: yield from csv.DictReader(f)
NAMES = {}
with open(S + 'spellname.csv', newline='', encoding='utf-8') as f:
    for r in csv.DictReader(f): NAMES[int(r['ID'])] = r['Name_lang']
SPELL = {int(r['ID']): r for r in rows('Spell')}
EFF = collections.defaultdict(dict)
for r in rows('SpellEffect'):
    try: EFF[int(r['SpellID'])][int(r['EffectIndex'])] = r
    except (KeyError, ValueError): pass
LEVELS = {}
for r in rows('SpellLevels'):
    if r['DifficultyID'] == '0': LEVELS[int(r['SpellID'])] = (int(r['BaseLevel']), int(r['SpellLevel']), int(r['MaxLevel']))
DUR = {int(r['ID']): int(r['Duration']) for r in rows('SpellDuration')}
MISC = {}
for r in rows('SpellMisc'):
    try:
        if r.get('DifficultyID', '0') == '0': MISC[int(r['SpellID'])] = int(r.get('DurationIndex') or 0)
    except ValueError: pass
def dur(sid):
    ms = DUR.get(MISC.get(sid, 0), 0)
    if ms <= 0: return None
    s = ms // 1000
    if s >= 3600 and s % 3600 == 0: return f'{s // 3600} hour' + ('s' if s > 3600 else '')
    if s >= 60 and s % 60 == 0: return f'{s // 60} min'
    return f'{s} sec'
def effval(sid, idx):
    e = EFF.get(sid, {}).get(idx)
    if not e: return None
    base = float(e.get('EffectBasePointsF') or e.get('EffectBasePoints') or 0)
    die = int(float(e.get('EffectDieSides') or 0))
    v = abs(base)
    if die > 1: return f'{int(v) + 1} to {int(v) + die}'
    return str(int(v) if float(v).is_integer() else round(v, 1))
import ast, operator as _op
_OPS = {ast.Add: _op.add, ast.Sub: _op.sub, ast.Mult: _op.mul, ast.Div: _op.truediv, ast.USub: _op.neg, ast.UAdd: _op.pos}
def calc(expr):
    # Arithmetic only (numbers, + - * / and brackets); anything else raises.
    def ev(n):
        if isinstance(n, ast.Expression): return ev(n.body)
        if isinstance(n, ast.Constant) and isinstance(n.value, (int, float)): return n.value
        if isinstance(n, ast.BinOp) and type(n.op) in _OPS: return _OPS[type(n.op)](ev(n.left), ev(n.right))
        if isinstance(n, ast.UnaryOp) and type(n.op) in _OPS: return _OPS[type(n.op)](ev(n.operand))
        raise ValueError('not arithmetic')
    return ev(ast.parse(expr, mode='eval'))
def text(sid, field='Description_lang'):
    r = SPELL.get(sid)
    if not r: return ''
    t = r.get(field) or ''
    def sub(m):
        other, kind, idx = m.group(1), m.group(2), int(m.group(3))
        s = int(other) if other else sid
        v = effval(s, idx - 1)
        if v is not None and kind in 'oO':
            e = EFF.get(s, {}).get(idx - 1) or {}
            per = int(float(e.get('EffectAuraPeriod') or 0)); total = DUR.get(MISC.get(s, 0), 0)
            try:
                if per > 0 and total > 0: v = str(int(float(v) * (total // per)))
            except ValueError: pass
        return v if v is not None else '?'
    def div(m):
        v = effval(sid, int(m.group(3)) - 1)
        try: return str(round(float(v) / int(m.group(1)), 2)).rstrip('0').rstrip('.')
        except (TypeError, ValueError): return '?'
    t = re.sub(r'\$/(\d+);(\d+)?[sSmM](\d)', div, t)
    t = re.sub(r'\$(\d+)?d\b', lambda m: dur(int(m.group(1)) if m.group(1) else sid) or '?', t)
    t = re.sub(r'\$(\d+)?([smoSMO])(\d)', sub, t)
    t = re.sub(r'\$[lLgG]([^:;]+):([^;]+);', lambda m: m.group(1), t)  # singular/plural and gendered words
    def formula(m):
        expr, fmt = m.group(1), m.group(2)
        def tok(mm):
            o = int(mm.group(1)) if mm.group(1) else sid
            e = EFF.get(o, {}).get(int(mm.group(3)) - 1)
            return str(float(e.get('EffectBasePointsF') or 0)) if e else 'x'
        expr = re.sub(r'\$(\d+)?([smSM])(\d)', tok, expr)
        if not re.fullmatch(r'[\d.+\-*/() ]+', expr): return '?'
        try: v = abs(calc(expr))
        except Exception: return '?'
        if fmt: return f'{v:.{int(fmt[1:])}f}'
        return str(int(v)) if float(v).is_integer() else str(round(v, 2))
    t = re.sub(r'\$\{([^}]*)\}(\.\d)?', formula, t)
    t = re.sub(r'\$\{[^}]*\}', '?', t)
    t = re.sub(r'\$[a-zA-Z]+\d*', '', t)
    return re.sub(r'\s+', ' ', t).strip()
