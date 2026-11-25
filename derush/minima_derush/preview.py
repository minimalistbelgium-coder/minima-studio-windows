"""Aperçus pour l'écran de configuration : un extrait audio par micro, une image par caméra.

Rangés dans le dossier interne du moteur (jamais à côté des rushes).
"""
import os, hashlib
import numpy as np
from . import media, speakers as SP

CLIP_S = 6.0


def _dir():
    base = os.environ.get('MINIMA_CACHE') or os.path.join(os.path.expanduser('~'), '.minima-derush', 'cache')
    d = os.path.join(os.path.dirname(base) if os.path.basename(base) == 'cache' else base, 'previews')
    os.makedirs(d, exist_ok=True)
    return d


def _key(path, extra=''):
    st = os.stat(path)
    return hashlib.sha1(f'{os.path.abspath(path)}|{st.st_size}|{int(st.st_mtime)}|{extra}'.encode()).hexdigest()[:20]


def best_window(env, others, win=int(CLIP_S * 10)):
    """Début (en s) de l'extrait où ce micro domine le plus les autres (ou est le plus fort s'il est seul)."""
    n = len(env)
    if n <= win:
        return 0.0
    score = env.copy()
    if others:
        o = np.full(n, -120.0)
        for e in others:
            m = min(n, len(e)); o[:m] = np.maximum(o[:m], e[:m])
        score = env - o
        # on ignore les silences : l'extrait doit contenir de la parole sur ce micro
        noise, peak = SP.mic_stats(env)
        score = np.where(env > noise + 0.45 * (peak - noise), score, -60.0)
    c = np.concatenate([[0.0], np.cumsum(score)])
    s = c[win:] - c[:-win]
    # on évite les toutes premières secondes (réglages, claps)
    lo = min(300, max(0, len(s) // 10))
    i = lo + int(np.argmax(s[lo:])) if len(s) > lo else int(np.argmax(s))
    return i / 10.0


def mic_clips(mics):
    """mics : [{'path':...}] -> ajoute 'preview' (m4a) à chacun."""
    envs = []
    for m in mics:
        try:
            envs.append(SP.envelope_db(media.load_audio(m['path'])))
        except Exception:
            envs.append(None)
    for i, m in enumerate(mics):
        if envs[i] is None:
            continue
        others = [e for j, e in enumerate(envs) if j != i and e is not None]
        t = best_window(envs[i], others)
        out = os.path.join(_dir(), _key(m['path'], f'clip{t}') + '.m4a')
        if not os.path.exists(out):
            r = media._run([media.ffmpeg_path(), '-v', 'error', '-nostdin', '-y', '-ss', f'{t:.1f}', '-t', str(CLIP_S),
                            '-i', m['path'], '-ac', '1', '-ar', '44100', '-af', 'loudnorm=I=-18:TP=-2',
                            '-c:a', 'aac', '-b:a', '128k', out])
            if r.returncode != 0:
                continue
        m['preview'] = out
        m['preview_at'] = t


def cam_thumbs(cams):
    """cams : [{'files':[...]}] -> ajoute 'thumb' (jpg) à chacune."""
    for c in cams:
        f = max(c['files'], key=lambda p: os.path.getsize(p)) if c.get('files') else None
        if not f:
            continue
        try:
            dur = media.probe(f)['duration'] or 0
        except Exception:
            continue
        t = max(0.0, dur * 0.3)
        out = os.path.join(_dir(), _key(f, f'thumb{t:.0f}') + '.jpg')
        if not os.path.exists(out):
            r = media._run([media.ffmpeg_path(), '-v', 'error', '-nostdin', '-y', '-ss', f'{t:.2f}', '-i', f,
                            '-frames:v', '1', '-vf', 'scale=480:-2', '-q:v', '4', out])
            if r.returncode != 0 or not os.path.exists(out):
                continue
        c['thumb'] = out


def plans_dir():
    base = os.environ.get('MINIMA_CACHE') or os.path.join(os.path.expanduser('~'), '.minima-derush', 'cache')
    d = os.path.join(os.path.dirname(base) if os.path.basename(base) == 'cache' else base, 'plans')
    os.makedirs(d, exist_ok=True)
    return d
