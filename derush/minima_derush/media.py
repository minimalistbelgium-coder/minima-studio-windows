"""Accès aux médias via ffmpeg (embarqué dans l'app, ou trouvé dans le PATH)."""
import os, re, sys, shutil, subprocess, hashlib, json
import numpy as np

SR = 8000           # fréquence d'analyse (suffit pour la syncro et la détection de parole)
VIDEO_EXT = {'.mp4', '.mov', '.mxf', '.mts', '.m2ts', '.avi', '.mkv', '.m4v'}
AUDIO_EXT = {'.wav', '.aif', '.aiff', '.bwf', '.mp3', '.m4a', '.flac'}

_NOWIN = 0x08000000 if os.name == 'nt' else 0   # CREATE_NO_WINDOW sous Windows


def ffmpeg_path():
    env = os.environ.get('MINIMA_FFMPEG')
    if env and os.path.exists(env):
        return env
    exe = 'ffmpeg.exe' if os.name == 'nt' else 'ffmpeg'
    here = os.path.dirname(sys.executable if getattr(sys, 'frozen', False) else os.path.abspath(__file__))
    for d in (here, os.path.join(here, 'bin'), os.path.join(here, '..', 'bin')):
        p = os.path.join(d, exe)
        if os.path.exists(p):
            return p
    p = shutil.which('ffmpeg')
    if p:
        return p
    for p in ('/opt/homebrew/bin/ffmpeg', '/usr/local/bin/ffmpeg'):
        if os.path.exists(p):
            return p
    raise RuntimeError("ffmpeg introuvable : il doit être livré avec Minima Studio.")


def _run(args, **kw):
    return subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, creationflags=_NOWIN, **kw)


def probe(path):
    """Infos utiles d'un fichier, lues dans la sortie de `ffmpeg -i` (pas besoin de ffprobe)."""
    r = _run([ffmpeg_path(), '-hide_banner', '-i', path])
    txt = r.stderr.decode('utf-8', 'replace')
    info = {'path': path, 'name': os.path.basename(path), 'video': None, 'audio': [], 'duration': None, 'timecode': None}
    m = re.search(r'Duration: (\d+):(\d+):(\d+(?:\.\d+)?)', txt)
    if m:
        info['duration'] = int(m.group(1)) * 3600 + int(m.group(2)) * 60 + float(m.group(3))
    m = re.search(r'timecode\s*:\s*(\d\d:\d\d:\d\d[:;]\d\d)', txt)
    if m:
        info['timecode'] = m.group(1)
    for line in txt.splitlines():
        if 'Stream #' not in line:
            continue
        if 'Video:' in line and info['video'] is None and 'attached pic' not in line:
            wh = re.search(r', (\d{2,5})x(\d{2,5})', line)
            fps = re.search(r'([\d.]+) fps', line) or re.search(r'([\d.]+) tbr', line)
            info['video'] = {'width': int(wh.group(1)) if wh else 1920, 'height': int(wh.group(2)) if wh else 1080,
                             'fps': float(fps.group(1)) if fps else 25.0}
        elif 'Audio:' in line:
            sr = re.search(r'(\d+) Hz', line)
            ch = 2
            if 'mono' in line: ch = 1
            elif 'stereo' in line: ch = 2
            else:
                mm = re.search(r'(\d+) channels', line)
                if mm: ch = int(mm.group(1))
            depth = 24 if re.search(r's24|pcm_s24|s32', line) else 16
            info['audio'].append({'rate': int(sr.group(1)) if sr else 48000, 'channels': ch, 'depth': depth})
    if info['duration'] is None:
        raise RuntimeError(f"Fichier illisible : {path}")
    return info


def _cache_dir():
    base = os.environ.get('MINIMA_CACHE') or os.path.join(os.path.expanduser('~'), '.minima-derush', 'cache')
    os.makedirs(base, exist_ok=True)
    return base


def load_audio(path, stream=0, channel=None):
    """Audio mono 8 kHz float32 (moyenne des canaux, ou un canal précis), mis en cache sur le disque."""
    st = os.stat(path)
    key = hashlib.sha1(f'{os.path.abspath(path)}|{st.st_size}|{int(st.st_mtime)}|{stream}|{channel}|{SR}'.encode()).hexdigest()
    cp = os.path.join(_cache_dir(), key + '.npy')
    if os.path.exists(cp):
        return np.load(cp)
    args = [ffmpeg_path(), '-v', 'error', '-nostdin', '-i', path, '-map', f'0:a:{stream}', '-vn']
    if channel is not None:
        args += ['-af', f'pan=mono|c0=c{channel}']
    else:
        args += ['-ac', '1']
    args += ['-ar', str(SR), '-f', 's16le', '-acodec', 'pcm_s16le', '-']
    r = _run(args)
    if r.returncode != 0 or not r.stdout:
        raise RuntimeError(f"Impossible de lire l'audio de {os.path.basename(path)} : {r.stderr.decode('utf-8','replace')[:300]}")
    x = np.frombuffer(r.stdout, dtype='<i2').astype(np.float32) / 32768.0
    np.save(cp, x)
    return x
