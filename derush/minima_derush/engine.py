"""Enchaîne : lecture des médias, syncro, qui parle, plan de coupe, XML."""
import os, json, unicodedata
import numpy as np
from . import media, sync as S, speakers as SP, xmlgen
from .progress import step, log, warn

DEFAULTS = {'min_shot': 2.0, 'anticipate': 0.3, 'wide': 'overlap', 'wide_every': 30.0, 'wide_len': 4.0,
            'mic_min': 1.0, 'mic_preroll': 0.6}


def mic_activity(x):
    L = SP.envelope_db(x)
    noise, peak = SP.mic_stats(L)
    return {'noise_db': round(noise, 1), 'peak_db': round(peak, 1), 'range_db': round(peak - noise, 1),
            'active': bool(peak > -45 and peak - noise > 12)}


def analyse(cfg):
    """cfg : {name, out_dir, cams:[{label, files, role}], mics:[{label, path, speaker}], options}
    role d'une caméra : nom d'un micro (la personne qu'elle filme), 'wide' (plan large) ou 'ignore'."""
    opt = dict(DEFAULTS, **cfg.get('options', {}))
    nfc = lambda v: unicodedata.normalize('NFC', v) if isinstance(v, str) else v
    for c in cfg['cams']:
        c['label'], c['role'] = nfc(c['label']), nfc(c.get('role'))
    for m in cfg['mics']:
        m['label'], m['speaker'] = nfc(m['label']), nfc(m.get('speaker'))
    mics_cfg = [m for m in cfg['mics'] if m.get('use', True)]
    cams_cfg = [c for c in cfg['cams'] if c.get('role') != 'ignore']
    if not mics_cfg:
        raise RuntimeError("Aucun micro sélectionné.")
    if not cams_cfg:
        raise RuntimeError("Aucune caméra sélectionnée.")

    # --- lecture audio
    total = len(mics_cfg) + sum(len(c['files']) for c in cams_cfg)
    done = 0
    mic_audio = []
    for m in mics_cfg:
        step('lecture', pct=round(100 * done / total), msg=f"Lecture du micro {m['label']}")
        info = media.probe(m['path'])
        x = media.load_audio(m['path'])
        mic_audio.append((m, info, x)); done += 1
    ref_i = int(np.argmax([len(x) for _, _, x in mic_audio]))
    ref = mic_audio[ref_i][2]

    # --- syncro des micros entre eux (enregistreur multipiste : décalage nul en général)
    mics = []
    for i, (m, info, x) in enumerate(mic_audio):
        if i == ref_i:
            r = {'off0': 0.0, 'slope': 0.0, 'score': 1.0, 'resid_ms': 0.0}
        else:
            r = S.sync(ref, x)
            if abs(r['off0']) < 0.05 and len(x) == len(ref):
                r = {'off0': 0.0, 'slope': 0.0, 'score': 1.0, 'resid_ms': 0.0}
        a = info['audio'][0] if info['audio'] else {'channels': 1, 'depth': 24, 'rate': 48000}
        mics.append({'label': m['label'], 'speaker': m.get('speaker') or m['label'], 'x': x,
                     'file': {'path': m['path'], 'name': info['name'], 'dur': info['duration'], 'video': False,
                              'ach': a['channels'], 'depth': a['depth'], 'rate': a['rate'],
                              'off0': r['off0'], 'slope': r['slope']}, 'sync': r})

    # --- syncro caméras
    cams, vinfo = [], None
    for c in cams_cfg:
        files = []
        for p in c['files']:
            step('syncro', pct=round(100 * done / total), msg=f"Syncro {c['label']} : {os.path.basename(p)}")
            info = media.probe(p)
            if info['video'] and vinfo is None:
                vinfo = info['video']
            if not info['audio']:
                warn(f"{os.path.basename(p)} n'a pas de son : impossible de le synchroniser, ignoré.")
                done += 1; continue
            x = media.load_audio(p)
            r = S.sync(ref, x)
            ok = r['points'] >= 3 and (r['resid_ms'] is None or r['resid_ms'] < 40)
            if not ok:
                warn(f"Syncro peu sûre pour {os.path.basename(p)} (à vérifier).")
            log(f"{c['label']} / {os.path.basename(p)} : début {r['off0']:+.3f} s, dérive {r['slope']*3600*1000:+.1f} ms/h")
            a = info['audio'][0]
            files.append({'path': p, 'name': info['name'], 'dur': info['duration'], 'video': True,
                          'width': info['video']['width'] if info['video'] else 1920,
                          'height': info['video']['height'] if info['video'] else 1080,
                          'ach': min(a['channels'], 2), 'depth': a['depth'], 'rate': a['rate'],
                          'off0': r['off0'], 'slope': r['slope'], 'sync': {k: v for k, v in r.items()}})
            done += 1
        if files:
            cams.append({'label': c['label'], 'role': c.get('role'), 'files': files})
    if vinfo is None:
        vinfo = {'fps': 25.0, 'width': 1920, 'height': 1080}

    # --- durée de référence : couverture des micros
    dur = max(m['file']['off0'] + m['file']['dur'] for m in mics)

    # --- qui parle
    step('analyse', pct=95, msg="Analyse de qui parle")
    envs = []
    for m in mics:
        e = SP.envelope_db(m['x'])
        sh = int(round(m['file']['off0'] * 10))
        e = np.concatenate([np.full(max(0, sh), e.min()), e[max(0, -sh):]])
        envs.append(e)
    n = min(len(e) for e in envs)
    envs = [e[:n] for e in envs]
    lab, overlap = SP.labels(envs)
    speakers = [m['speaker'] for m in mics]

    # angles : les caméras dans l'ordre (caméras des personnes d'abord, plan large ensuite)
    cams.sort(key=lambda c: (c['role'] == 'wide', speakers.index(c['role']) if c['role'] in speakers else 99))
    cam_of = {}
    for i, sp in enumerate(speakers):
        for j, c in enumerate(cams):
            if c['role'] == sp:
                cam_of[i] = j; break
    wide = next((j for j, c in enumerate(cams) if c['role'] == 'wide'), None)
    if not cam_of:
        raise RuntimeError("Aucune caméra n'est associée à une personne : indique qui chaque caméra filme.")
    for i in range(len(speakers)):            # personne sans caméra : plan large, sinon 1re caméra
        cam_of.setdefault(i, wide if wide is not None else 0)
    wide_mode = opt['wide'] if wide is not None else 'none'
    shots = SP.shots(lab, overlap, cam_of, wide_cam=wide if wide_mode != 'none' else None,
                     min_shot=opt['min_shot'], anticipate=opt['anticipate'],
                     wide_long_s=opt['wide_every'] if wide_mode == 'overlap+breath' else 0.0, wide_len=opt['wide_len'])
    shots = [[a, min(b, dur), c] for a, b, c in shots if a < dur]
    msegs = SP.mic_segments(lab, opt['mic_min'], opt['mic_preroll'])
    msegs = [[a, min(b, dur), w] for a, b, w in msegs if a < dur]

    name = cfg['name']
    plan = {'version': 1, 'name': name, 'duration': dur, 'video': vinfo,
            'names': {'syncro': f'SYNCRO - {name}', 'multicam': f'MULTICAM - {name}', 'montage': f'{name} - MONTAGE'},
            'speakers': speakers,
            'mics': [{'label': m['label'], 'speaker': m['speaker'], 'file': m['file']} for m in mics],
            'cams': [{'label': c['label'], 'role': c['role'], 'files': [{k: v for k, v in f.items()} for f in c['files']]} for c in cams],
            'shots': shots, 'mic_segments': msegs, 'options': opt}
    d = np.array([b - a for a, b, _ in shots]) if shots else np.array([0.0])
    plan['stats'] = {'shots': len(shots), 'avg_shot_s': round(float(d.mean()), 1),
                     'per_angle_pct': {cams[j]['label']: round(float(d[[c == j for *_, c in shots]].sum() / d.sum() * 100), 1) for j in range(len(cams))}}
    return plan


def write(plan, out_dir, plan_dir=None):
    """Le XML va à côté des rushes (il faut l'ouvrir dans Premiere) ; le plan, interne au moteur,
    va dans le dossier de l'app, jamais dans le projet."""
    import hashlib, time
    from .preview import plans_dir
    os.makedirs(out_dir, exist_ok=True)
    xml_path = os.path.join(out_dir, plan['name'] + '.xml')
    with open(xml_path, 'w', encoding='utf-8') as f:
        f.write(xmlgen.build(plan))
    pd = plan_dir or plans_dir()
    os.makedirs(pd, exist_ok=True)
    tag = hashlib.sha1(f'{os.path.abspath(xml_path)}|{time.time()}'.encode()).hexdigest()[:10]
    pj = os.path.join(pd, f"{plan['name']}-{tag}.minima.json")
    with open(pj, 'w', encoding='utf-8') as f:
        json.dump(plan, f, ensure_ascii=False, indent=1)
    return xml_path, pj
