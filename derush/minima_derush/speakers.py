"""Qui parle quand : à partir des micros (un micro par personne)."""
import numpy as np
from .media import SR

HOP = SR // 10      # 10 images d'analyse par seconde


def envelope_db(x):
    n = len(x) // HOP
    r = np.sqrt((x[:n * HOP].reshape(n, HOP) ** 2).mean(1) + 1e-12)
    return 20 * np.log10(r + 1e-6)


def mic_stats(L):
    noise = float(np.percentile(L, 15)); peak = float(np.percentile(L, 95))
    return noise, peak


def labels(envs, switch_s=1.3, window_s=2.0, margin_db=3.0):
    """envs : liste d'enveloppes dB (10 Hz), alignées sur le même temps.
    Retourne (lab, overlap) : lab[i] = index du micro qui parle (avec hystérésis),
    overlap[i] = plusieurs personnes parlent fort en même temps."""
    n = min(len(e) for e in envs)
    L = np.array([np.convolve(e[:n], np.ones(5) / 5, 'same') for e in envs])
    st = [mic_stats(l) for l in L]
    noise = np.array([s[0] for s in st])[:, None]; peak = np.array([s[1] for s in st])[:, None]
    rel = (L - noise) / np.maximum(peak - noise, 6.0)          # 0 = bruit de fond, 1 = voix forte
    act = rel > 0.45
    score = np.where(act, L - noise, -99.0)
    dom = np.argmax(score, 0)
    srt = np.sort(score, 0)
    clear = act.any(0) & ((srt[-1] - srt[-2] > margin_db) if len(envs) > 1 else True)
    dom = np.where(clear, dom, -1)
    first = np.where(dom >= 0)[0]
    cur = int(dom[first[0]]) if len(first) else 0
    W, need = int(window_s * 10), int(switch_s * 10)
    lab = np.empty(n, int)
    for i in range(n):
        d = dom[i]
        if d >= 0 and d != cur and (dom[i:i + W] == d).sum() >= need:
            cur = int(d)
        lab[i] = cur
    act = act.copy()
    act_both = act.sum(0) >= 2
    overlap = act_both & ~clear
    return lab, overlap


def segments(lab, t0=0.0, t1=None):
    t1 = len(lab) / 10 if t1 is None else t1
    a, b = int(t0 * 10), int(min(t1 * 10, len(lab)))
    out = []; s = a
    for i in range(a + 1, b + 1):
        if i == b or lab[i] != lab[s]:
            out.append([s / 10, i / 10, int(lab[s])]); s = i
    return out


def merge_short(segs, min_len):
    out = []
    for s in segs:
        if out and (s[1] - s[0] < min_len or s[2] == out[-1][2]):
            out[-1][1] = s[1]
        else:
            out.append(list(s))
    # premier segment trop court : on le fond dans le suivant
    if len(out) > 1 and out[0][1] - out[0][0] < min_len:
        out[1][0] = out[0][0]; out.pop(0)
    return out


def shots(lab, overlap, cam_of_speaker, wide_cam=None, min_shot=2.0, anticipate=0.3,
          wide_overlap_s=1.5, wide_long_s=0.0, wide_len=4.0):
    """Plan de coupe : liste [start, end, cam_index]."""
    segs = merge_short(segments(lab), min_shot)
    for j in range(1, len(segs)):            # on coupe un peu avant la prise de parole
        t = max(segs[j - 1][0] + 1.0, segs[j][0] - anticipate)
        segs[j - 1][1] = t; segs[j][0] = t
    plan = [[a, b, cam_of_speaker.get(s, cam_of_speaker.get(0))] for a, b, s in segs]
    if wide_cam is not None:
        # plans larges quand plusieurs personnes parlent en même temps
        both = np.convolve(overlap.astype(float), np.ones(5) / 5, 'same') > 0.6
        ov = segments(both.astype(int))
        ins = [(a, b) for a, b, v in ov if v == 1 and b - a >= wide_overlap_s]
        if wide_long_s > 0:            # respiration dans les longues prises de parole
            for a, b, c in plan:
                k = 1
                while a + k * wide_long_s + wide_len < b - 2.0:
                    m = a + k * wide_long_s; ins.append((m, m + wide_len)); k += 1
        for a, b in sorted(ins):
            plan = _insert(plan, a, b, wide_cam)
        plan = merge_short([[a, b, c] for a, b, c in plan], 1.0)
    return [[round(a * 25) / 25, round(b * 25) / 25, c] for a, b, c in plan if round(b * 25) > round(a * 25)]


def _insert(plan, a, b, cam):
    out = []
    for s, e, c in plan:
        if e <= a or s >= b:
            out.append([s, e, c]); continue
        if s < a: out.append([s, a, c])
        if e > b: out.append([b, e, c])
    out.append([a, b, cam])
    return sorted(out)


def mic_segments(lab, min_len=1.0, preroll=0.6):
    """Segments [start, end, qui_parle] pour ouvrir/couper les micros."""
    segs = merge_short(segments(lab), min_len)
    for j in range(1, len(segs)):
        t = max(segs[j - 1][0] + 0.5, segs[j][0] - preroll)
        segs[j - 1][1] = t; segs[j][0] = t
    return [[round(a * 25) / 25, round(b * 25) / 25, c] for a, b, c in segs if round(b * 25) > round(a * 25)]
