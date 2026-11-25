"""Après l'ouverture du XML dans Premiere : active le multicam et coupe les micros de ceux qui écoutent."""
import gzip, json, re, shutil, os
from .prproj_lib import Proj


def _read(path):
    with open(path, 'rb') as f:
        raw = f.read()
    gz = raw[:2] == b'\x1f\x8b'
    return (gzip.decompress(raw) if gz else raw).decode('utf-8'), gz


def finalize(prproj, plan_path, backup=True):
    plan = json.load(open(plan_path, encoding='utf-8'))
    text, gz = _read(prproj)
    P = Proj(text)
    names = plan['names']
    try:
        mc_seq = P.seq_by_name(names['multicam'])
        mont = P.seq_by_name(names['montage'])
    except KeyError as e:
        raise RuntimeError(f"Séquence {e} introuvable dans ce projet : est-ce bien le projet ouvert depuis le XML de Minima ?")
    T = P.tracks(mont)
    ncam = len(plan['cams'])
    # --- multicam
    mc_track = T['Video'][ncam]
    items = sorted([x for x in P.items(mc_track) if x['name'] == names['multicam']], key=lambda x: x['start'])
    shots = plan['shots']
    if len(items) != len(shots):
        raise RuntimeError(f"{len(items)} plans trouvés au lieu de {len(shots)} : la séquence a été modifiée ?")
    done_mc = 0
    for it, (a, b, ang) in zip(items, shots):
        sc = re.search(r'<SubClip ObjectRef="(\d+)"/>', P.body(it['id'])).group(1)
        cl = re.search(r'<Clip ObjectRef="(\d+)"/>', P.body(sc)).group(1)
        bd = P.body(cl)
        bd = re.sub(r'\s*<IsMulticam>[^<]*</IsMulticam>', '', bd)
        bd = re.sub(r'\s*<SelectedTrackIndex>[^<]*</SelectedTrackIndex>', '', bd)
        bd, n = re.subn(r'(<OutPoint>-?\d+</OutPoint>)',
                        rf'\1\n\t\t\t<IsMulticam>true</IsMulticam>\n\t\t\t<SelectedTrackIndex>{int(ang)}</SelectedTrackIndex>', bd, count=1)
        if n:
            P.setbody(cl, bd); done_mc += 1
    # --- micros : on coupe (mute) celui qui écoute
    segs = plan['mic_segments']
    starts = {round(a * 25): w for a, b, w in segs}
    muted = 0
    for k in range(len(plan['mics'])):
        tr = T['Audio'][1 + k]
        for it in P.items(tr):
            w = starts.get(round(it['start'] * 25))
            if w is None:
                # segment tronqué au début du fichier : on prend le segment qui le contient
                w = next((s[2] for s in segs if s[0] - 0.05 <= it['start'] < s[1]), k)
            b = P.body(it['id'])
            b = b.replace('<IsMuted>true</IsMuted>', '').replace('<IsMuted>false</IsMuted>', '')
            if w != k:
                b = re.sub(r'(<SubClip ObjectRef="\d+"/>)', r'\1\n\t\t\t<IsMuted>true</IsMuted>', b, count=1); muted += 1
            P.setbody(it['id'], b)
    out = P.dump()
    if backup:
        shutil.copy2(prproj, prproj + '.avant-minima')
    data = out.encode('utf-8')
    with open(prproj, 'wb') as f:
        f.write(gzip.compress(data) if gz else data)
    return {'multicam': done_mc, 'muted': muted}
