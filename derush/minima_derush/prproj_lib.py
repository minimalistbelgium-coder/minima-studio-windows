"""Lecture/écriture de la structure interne d'un projet Premiere (.prproj = XML gzippé)."""
import re, uuid, json, base64, copy

TPS = 254016000000
KEEPHASH = False
SHARED = {'VideoMediaSource', 'AudioMediaSource', 'VideoSequenceSource'}
OBJ_RE = re.compile(r'\n\t<(\w+) (ObjectID|ObjectUID)="([^"]+)"([^>]*)>(.*?)\n\t</\1>', re.S)


class Proj:
    def __init__(self, text):
        self.text = text
        self.objs = {}      # id -> [tag, kind, attrs, body]
        self.order = []
        for m in OBJ_RE.finditer(text):
            self.objs[m.group(3)] = [m.group(1), m.group(2), m.group(4), m.group(5)]
            self.order.append(m.group(3))
        self.head = text[:next(OBJ_RE.finditer(text)).start()]
        last = list(OBJ_RE.finditer(text))[-1]
        self.tail = text[last.end():]
        self.next_id = max(int(k) for k in self.objs if k.isdigit()) + 1
        ids = [int(x) for x in re.findall(r'<TrackItem Version="\d+">\s*<Node Version="1">.*?<ID>(\d+)</ID>', text, re.S)]
        self.next_node = max([i for i in ids if i < 2**31] or [0]) + 1000
        self.new = []

    def body(self, k):
        return self.objs[k][3]

    def setbody(self, k, b):
        self.objs[k][3] = b

    def tag(self, k):
        return self.objs[k][0]

    def dump(self):
        parts = [self.head]
        for k in self.order + self.new:
            t, kind, attrs, body = self.objs[k]
            parts.append(f'\n\t<{t} {kind}="{k}"{attrs}>{body}\n\t</{t}>')
        parts.append(self.tail)
        return ''.join(parts)

    # ---------- navigation
    def seq_by_name(self, name):
        for k, (t, kind, a, b) in self.objs.items():
            if t == 'Sequence':
                n = re.search(r'<Name>([^<]*)</Name>', b)
                if n and n.group(1) == name:
                    return k
        raise KeyError(name)

    def tracks(self, seq):
        """returns {'Video':[trackuid...], 'Audio':[...]}"""
        out = {'Video': [], 'Audio': []}
        for g in re.findall(r'<TrackGroup Version="\d+" Index="\d+">\s*<First>[^<]*</First>\s*<Second ObjectRef="(\d+)"/>', self.body(seq)):
            tg = self.objs[g]
            kind = 'Video' if tg[0].startswith('Video') else ('Audio' if tg[0].startswith('Audio') else None)
            if kind is None:
                continue
            out[kind] = re.findall(r'<Track Index="\d+" ObjectURef="([^"]+)"/>', tg[3])
        return out

    def items(self, track, which='ClipItems'):
        b = self.body(track)
        sec = re.search(rf'<{which} Version="\d+">\s*<TrackItems Version="1">(.*?)</TrackItems>', b, re.S)
        if not sec:
            return []
        res = []
        for r in re.findall(r'ObjectRef="(\d+)"', sec.group(1)):
            ib = self.body(r)
            st = int(re.search(r'<Start>(-?\d+)</Start>', ib).group(1)) if '<Start>' in ib else 0
            en = int(re.search(r'<End>(-?\d+)</End>', ib).group(1))
            sc = re.search(r'<SubClip ObjectRef="(\d+)"/>', ib)
            name = None
            if sc:
                nm = re.search(r'<Name>([^<]*)</Name>', self.body(sc.group(1)))
                name = nm.group(1) if nm else None
            res.append(dict(id=r, start=st / TPS, end=en / TPS, name=name))
        return res

    def set_items(self, track, ids, which='ClipItems'):
        b = self.body(track)
        lst = ''.join(f'\n\t\t\t\t\t<TrackItem Index="{i}" ObjectRef="{r}"/>' for i, r in enumerate(ids))
        pat = re.compile(rf'(<{which} Version="\d+">\s*)<TrackItems Version="1">.*?</TrackItems>', re.S)
        if pat.search(b):
            b = pat.sub(lambda m: m.group(1) + f'<TrackItems Version="1">{lst}\n\t\t\t\t</TrackItems>', b, count=1)
        else:
            pat2 = re.compile(rf'(<{which} Version="\d+">)', re.S)
            assert pat2.search(b), (track, which)
            b = pat2.sub(lambda m: m.group(1) + f'\n\t\t\t\t<TrackItems Version="1">{lst}\n\t\t\t\t</TrackItems>', b, count=1)
        self.setbody(track, b)

    # ---------- cloning
    def clone(self, root, mp=None):
        if mp is None:
            mp = {}
        reach, stack = [], [root]
        seen = set()
        while stack:
            k = stack.pop()
            if k in seen or k not in self.objs:
                continue
            seen.add(k)
            if self.tag(k) in SHARED:
                continue
            reach.append(k)
            stack.extend(re.findall(r'ObjectRef="(\d+)"', self.body(k)))
        reach = [k for k in reach if k not in mp]
        for k in reach:
            mp[k] = str(self.next_id)
            self.next_id += 1
        for k in reach:
            t, kind, a, b = self.objs[k]
            b = re.sub(r'ObjectRef="(\d+)"', lambda m: f'ObjectRef="{mp.get(m.group(1), m.group(1))}"', b)
            b = re.sub(r'<ClipID>[^<]*</ClipID>', lambda m: f'<ClipID>{uuid.uuid4()}</ClipID>', b)
            b = re.sub(r'<ID>[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}</ID>', lambda m: f'<ID>{uuid.uuid4()}</ID>', b)
            self.objs[mp[k]] = [t, kind, a, b]
            self.new.append(mp[k])
        for k in reach:
            if self.tag(mp[k]).endswith('TrackItem'):
                kb = self.body(mp[k])
                kb = re.sub(r'(<TrackItem Version="\d+">\s*<Node Version="1">.*?<ID>)(\d+)(</ID>)',
                            lambda m: m.group(1) + str(self._node()) + m.group(3), kb, count=1, flags=re.S)
                self.setbody(mp[k], kb)
        return mp[root]
        nb = self.body(mp[root])
        nb = re.sub(r'(<TrackItem Version="\d+">\s*<Node Version="1">.*?<ID>)(\d+)(</ID>)',
                    lambda m: m.group(1) + str(self._node()) + m.group(3), nb, count=1, flags=re.S)
        self.setbody(mp[root], nb)
        return mp[root]

    def _node(self):
        self.next_node += 1
        return self.next_node

    def retime(self, item, start, end):
        """Move item to [start,end] seconds; adjust clip out point when duration changes."""
        b = self.body(item)
        os_ = int(re.search(r'<Start>(-?\d+)</Start>', b).group(1)) if '<Start>' in b else 0
        oe = int(re.search(r'<End>(-?\d+)</End>', b).group(1))
        ns, ne = int(round(start * 25)) * (TPS // 25), int(round(end * 25)) * (TPS // 25)
        if '<Start>' in b:
            b = re.sub(r'<Start>-?\d+</Start>', f'<Start>{ns}</Start>', b, count=1)
        elif ns != 0:
            b = re.sub(r'(\s*)<End>', lambda m: f'{m.group(1)}<Start>{ns}</Start>{m.group(1)}<End>', b, count=1)
        b = re.sub(r'<End>-?\d+</End>', f'<End>{ne}</End>', b, count=1)
        self.setbody(item, b)
        d = (ne - ns) - (oe - os_)
        if d != 0:
            sc = re.search(r'<SubClip ObjectRef="(\d+)"/>', b)
            if sc:
                cl = re.search(r'<Clip ObjectRef="(\d+)"/>', self.body(sc.group(1)))
                if cl:
                    cb = self.body(cl.group(1))
                    op = re.search(r'<OutPoint>(-?\d+)</OutPoint>', cb)
                    if op:
                        cb = cb.replace(op.group(0), f'<OutPoint>{int(op.group(1)) + d}</OutPoint>', 1)
                        self.setbody(cl.group(1), cb)

