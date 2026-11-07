# Minimal reader for Lua table literals (QuestieDB data files). Parses data only; executes nothing.
import re
class P:
    def __init__(s, t): s.t, s.i, s.n = t, 0, len(t)
    def ws(s):
        t, n = s.t, s.n
        while s.i < n:
            c = t[s.i]
            if c in ' \t\r\n,;': s.i += 1
            elif t.startswith('--', s.i):
                if t.startswith('--[[', s.i): s.i = t.index(']]', s.i) + 2
                else:
                    j = t.find('\n', s.i); s.i = n if j < 0 else j + 1
            else: break
    def val(s):
        s.ws(); t = s.t; c = t[s.i]
        if c == '{': return s.table()
        if c in '\'"': return s.string(c)
        if t.startswith('[[', s.i):
            j = t.index(']]', s.i); v = t[s.i+2:j]; s.i = j + 2; return v
        m = re.compile(r'-?(?:0x[0-9a-fA-F]+|\d+\.?\d*(?:[eE][-+]?\d+)?)').match(t, s.i)
        if m: s.i = m.end(); x = m.group(); return int(x, 16) if 'x' in x else (float(x) if any(ch in x for ch in '.eE') else int(x))
        m = re.compile(r'[A-Za-z_][\w.]*').match(t, s.i)
        if m:
            s.i = m.end(); w = m.group()
            if w == 'nil': return None
            if w == 'true': return True
            if w == 'false': return False
            # simple arithmetic between constants (e.g. a + b) is kept as text
            return ('id', w)
        raise ValueError(f'unexpected {t[s.i:s.i+30]!r}')
    def valexpr(s):
        v = s.val(); s.ws()
        while s.i < s.n and s.t[s.i] in '+-*' and not s.t.startswith('--', s.i):
            op = s.t[s.i]; s.i += 1; r = s.val(); v = ('expr', (v, op, r)); s.ws()
        return v
    def string(s, q):
        t = s.t; s.i += 1; out = []
        while t[s.i] != q:
            if t[s.i] == '\\':
                nx = t[s.i+1]; out.append({'n': '\n', 't': '\t'}.get(nx, nx)); s.i += 2
            else: out.append(t[s.i]); s.i += 1
        s.i += 1; return ''.join(out)
    def table(s):
        s.i += 1; arr = []; kv = {}; pos = 1
        while True:
            s.ws()
            if s.t[s.i] == '}': s.i += 1; break
            if s.t[s.i] == '[' and not s.t.startswith('[[', s.i):
                s.i += 1; k = s.val(); s.ws(); assert s.t[s.i] == ']'; s.i += 1; s.ws(); assert s.t[s.i] == '='; s.i += 1
                kv[k] = s.valexpr(); continue
            m = re.compile(r'([A-Za-z_]\w*)\s*=(?!=)').match(s.t, s.i)
            if m: s.i = m.end(); kv[m.group(1)] = s.valexpr(); continue
            kv[pos] = s.valexpr(); pos += 1
        if kv and all(isinstance(k, int) for k in kv) and sorted(kv) == list(range(1, len(kv) + 1)): return [kv[k] for k in range(1, len(kv) + 1)]
        if not kv: return []
        return kv
def parse_data_string(text, var):
    """QuestieDB.<var> = [[return { ... }]]"""
    i = text.index(var + ' = [[return'); j = text.index('{', i); k = text.index(']]', j)
    return P(text[j:k]).val()
def parse_return_table(text, after=None):
    i = text.index(after) if after else 0
    j = text.index('return {', i) + len('return ')
    return P(text[j:]).val()
