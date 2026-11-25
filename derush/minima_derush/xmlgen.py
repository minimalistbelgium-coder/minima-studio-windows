"""XML Final Cut Pro 7 (xmeml v4) lisible par Premiere : SYNCRO, MULTICAM source, MONTAGE."""
import os, urllib.parse
from xml.sax.saxutils import escape


class Timebase:
    def __init__(self, fps):
        table = {23.976: (24, True), 23.98: (24, True), 29.97: (30, True), 59.94: (60, True)}
        r = min(table, key=lambda k: abs(k - fps)) if any(abs(k - fps) < 0.02 for k in table) else None
        self.tb, self.ntsc = table[r] if r else (int(round(fps)), False)
        self.fps = self.tb * (1000 / 1001 if self.ntsc else 1)

    def fr(self, t):
        return int(round(t * self.fps))

    def rate(self):
        return f'<rate><timebase>{self.tb}</timebase><ntsc>{"TRUE" if self.ntsc else "FALSE"}</ntsc></rate>'


def pathurl(p):
    p = os.path.abspath(p)
    if os.name == 'nt' or (len(p) > 1 and p[1] == ':'):
        p = p.replace('\\', '/')
        return 'file://localhost/' + urllib.parse.quote(p, safe='/:')
    return 'file://localhost' + urllib.parse.quote(p)


class Doc:
    def __init__(self, fps, width, height):
        self.T = Timebase(fps)
        self.w, self.h = width, height
        self.files = {}
        self.written = set()
        self.cid = 0

    def file_ref(self, f):
        """f : dict(path, name, dur, video(bool), ach, depth)"""
        p = f['path']
        if p not in self.files:
            self.files[p] = f'file-{len(self.files) + 1}'
        fid = self.files[p]
        if p in self.written:
            return f'<file id="{fid}"/>'
        self.written.add(p)
        T = self.T
        media = ''
        if f.get('video'):
            media += (f'<video><samplecharacteristics>{T.rate()}<width>{f.get("width", self.w)}</width>'
                      f'<height>{f.get("height", self.h)}</height><pixelaspectratio>square</pixelaspectratio>'
                      '</samplecharacteristics></video>')
        if f.get('ach', 0):
            media += (f'<audio><samplecharacteristics><depth>{f.get("depth", 16)}</depth><samplerate>{f.get("rate", 48000)}</samplerate>'
                      f'</samplecharacteristics><channelcount>{f["ach"]}</channelcount></audio>')
        return (f'<file id="{fid}"><name>{escape(f["name"])}</name><pathurl>{pathurl(p)}</pathurl>'
                f'{T.rate()}<duration>{T.fr(f["dur"])}</duration><media>{media}</media></file>')

    def clip(self, f, start, end, inp, kind, enabled=True, ch=1, name=None):
        self.cid += 1
        T = self.T
        s, e, i = T.fr(start), T.fr(end), T.fr(inp)
        src = f'<sourcetrack><mediatype>audio</mediatype><trackindex>{ch}</trackindex></sourcetrack>' if kind == 'audio' else ''
        return (f'<clipitem id="clipitem-{self.cid}"><name>{escape(name or f["name"])}</name>'
                f'<enabled>{"TRUE" if enabled else "FALSE"}</enabled><duration>{T.fr(f["dur"])}</duration>{T.rate()}'
                f'<start>{s}</start><end>{e}</end><in>{i}</in><out>{i + e - s}</out>{self.file_ref(f)}{src}</clipitem>')

    def nested(self, seqid, seqname, seqdur, start, end, inp):
        self.cid += 1
        T = self.T
        s, e, i = T.fr(start), T.fr(end), T.fr(inp)
        return (f'<clipitem id="clipitem-{self.cid}"><name>{escape(seqname)}</name><enabled>TRUE</enabled>'
                f'<duration>{T.fr(seqdur)}</duration>{T.rate()}<start>{s}</start><end>{e}</end><in>{i}</in><out>{i + e - s}</out>'
                f'<sequence id="{seqid}"/></clipitem>')

    def sequence(self, seqid, name, dur, vtracks, atracks):
        T = self.T
        v = ''.join(f'<track><enabled>TRUE</enabled>{"".join(t)}</track>' for t in vtracks)
        a = ''.join(f'<track><enabled>TRUE</enabled>{"".join(t)}</track>' for t in atracks)
        return (f'<sequence id="{seqid}"><name>{escape(name)}</name><duration>{T.fr(dur)}</duration>{T.rate()}'
                f'<timecode>{T.rate()}<string>00:00:00:00</string><frame>0</frame><displayformat>NDF</displayformat></timecode>'
                f'<media><video><format><samplecharacteristics>{T.rate()}<width>{self.w}</width><height>{self.h}</height>'
                f'<pixelaspectratio>square</pixelaspectratio></samplecharacteristics></format>{v}</video>'
                f'<audio><numOutputChannels>2</numOutputChannels>{a}</audio></media></sequence>')


def chunks(cam_file, r0, r1, chunk=300.0):
    """Morceaux (début_ref, fin_ref, entrée_média) couvrant [r0, r1] avec correction de dérive."""
    off, slope, ln = cam_file['off0'], cam_file['slope'], cam_file['dur']
    a = max(r0, off); b = min(r1, off + ln * (1 + slope))
    out, t = [], a
    while t < b - 0.04:
        u = min(b, t + chunk)
        out.append((t, u, (t - off) / (1 + slope)))
        t = u
    return out


def build(plan):
    """plan : dict produit par engine.analyse()."""
    vid = plan['video']
    D = Doc(vid['fps'], vid['width'], vid['height'])
    name, dur = plan['name'], plan['duration']
    cams, mics = plan['cams'], plan['mics']

    def cam_tracks(r0, r1, shift, enabled):
        vt, at = [], []
        for c in cams:
            vt.append([D.clip(f, a - r0 + shift, b - r0 + shift, m, 'video', enabled) for f in c['files'] for a, b, m in chunks(f, r0, r1)])
        for c in cams:
            for ch in range(1, max(f['ach'] for f in c['files']) + 1 if c['files'] else 1):
                at.append([D.clip(f, a - r0 + shift, b - r0 + shift, m, 'audio', False, ch) for f in c['files'] if f['ach'] >= ch
                           for a, b, m in chunks(f, r0, r1)])
        return vt, at

    def mic_tracks(r0, r1, shift):
        out = []
        for mc in mics:
            f = mc['file']
            a, b = max(r0, f['off0']), min(r1, f['off0'] + f['dur'])
            out.append([D.clip(f, a - r0 + shift, b - r0 + shift, a - f['off0'], 'audio', True, 1)])
        return out

    # 1. SYNCRO : tout aligné, son caméra désactivé
    vt, at_cam = cam_tracks(0, dur, 0, True)
    syncro = D.sequence('seq-syncro', plan['names']['syncro'], dur, vt, mic_tracks(0, dur, 0) + at_cam)
    # 2. MULTICAM source : une piste vidéo par angle (ordre = angles)
    vt, at_cam = cam_tracks(0, dur, 0, True)
    mcname = plan['names']['multicam']
    multicam = D.sequence('seq-mc', mcname, dur, vt, mic_tracks(0, dur, 0) + at_cam)
    # 3. MONTAGE
    vt, at_cam = cam_tracks(0, dur, 0, False)
    mc = [D.nested('seq-mc', mcname, dur, a, b, a) for a, b, ang in plan['shots']]
    atr = [[]]   # A1 vide : réservée au son traité
    for k, mcfg in enumerate(mics):
        f = mcfg['file']
        segs = [s for s in plan['mic_segments']]
        tr = []
        for a, b, who in segs:
            a2, b2 = max(a, f['off0']), min(b, f['off0'] + f['dur'])
            if b2 - a2 > 0.03:
                tr.append(D.clip(f, a2, b2, a2 - f['off0'], 'audio', True, 1))
        atr.append(tr)
    montage = D.sequence('seq-montage', plan['names']['montage'], dur, vt + [mc], atr + at_cam)
    return ('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE xmeml>\n<xmeml version="4"><project>'
            f'<name>{escape(name)}</name><children>{syncro}{multicam}{montage}</children></project></xmeml>')
