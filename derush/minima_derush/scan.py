"""Repère les caméras et les micros d'un dossier de rushes."""
import os, re, unicodedata
from .media import VIDEO_EXT, AUDIO_EXT

SKIP_DIRS = re.compile(r'^(Adobe Premiere Pro|ORIGINAL$|_claude_tmp$|\.|__MACOSX|Motion Graphics Template Media|Premiere Composer)', re.I)
# pistes d'enregistreurs multipistes qui ne sont pas des micros (Rodecaster, Zoom…)
NOT_MIC = re.compile(r'(stereo ?mix|mixdown|bluetooth|sounds?\b|usb|chat|master|^tr?lr|_lr\b)', re.I)
WIDE = re.compile(r'(large|wide|plan ?g[eé]n[eé]ral|master|cam ?milieu|milieu|osmo)', re.I)


def scan(root):
    cams, mics = {}, []
    for d, dirs, files in os.walk(root):
        dirs[:] = sorted(x for x in dirs if not SKIP_DIRS.search(x))
        for f in sorted(files):
            if f.startswith('._') or f.startswith('.'):
                continue
            ext = os.path.splitext(f)[1].lower()
            p = os.path.join(d, f)
            if ext in VIDEO_EXT:
                key = os.path.relpath(d, root)
                cams.setdefault(key, []).append(p)
            elif ext in AUDIO_EXT:
                if NOT_MIC.search(f):
                    continue
                mics.append(p)
    out_cams = []
    for key, files in sorted(cams.items()):
        label = unicodedata.normalize('NFC', os.path.basename(key) if key != '.' else os.path.basename(root))
        out_cams.append({'id': f'cam{len(out_cams)+1}', 'label': label, 'files': files,
                         'role': 'wide' if WIDE.search(label) else None})
    out_mics = [{'id': f'mic{i+1}', 'label': unicodedata.normalize('NFC', os.path.splitext(os.path.basename(p))[0]), 'path': p} for i, p in enumerate(mics)]
    return {'root': root, 'cams': out_cams, 'mics': out_mics}
