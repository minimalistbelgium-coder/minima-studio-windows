"""Synchronisation par l'audio : décalage + dérive d'horloge, précision < 1 ms."""
import numpy as np
from .media import SR


def _fftcorr(a, b):
    """corrélation croisée complète (équivalent de fftconvolve(a, b[::-1]))."""
    n = len(a) + len(b) - 1
    N = 1 << (n - 1).bit_length()
    A = np.fft.rfft(a, N); B = np.fft.rfft(b[::-1], N)
    return np.fft.irfft(A * B, N)[:n]


def _env(x, dec=16):
    n = len(x) // dec
    return np.abs(x[:n * dec]).reshape(n, dec).mean(1)


def coarse_offset(ref, sig):
    """d tel que sig[t] == ref[t + d] (en échantillons 8 kHz), + score de confiance."""
    e1, e2 = _env(ref), _env(sig)
    a, b = e1 - e1.mean(), e2 - e2.mean()
    c = _fftcorr(a, b)
    i = int(np.argmax(c))
    score = float(c[i] / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-9))
    srt = np.sort(c)
    peak_ratio = float(c[i] / (srt[-50] + 1e-9)) if len(srt) > 50 else 1.0
    return (i - (len(b) - 1)) * 16, score, peak_ratio


def _local(ref, sig, d, st, L, search):
    """affine le décalage autour de d sur une fenêtre de sig commençant en st."""
    if st < 0 or st + L > len(sig) or st + d - search < 0 or st + d + L + search > len(ref):
        return None
    r = ref[st + d - search: st + d + L + search]
    s = sig[st: st + L]
    if np.abs(s).max() < 1e-4 or np.abs(r).max() < 1e-4:
        return None
    c = _fftcorr(r - r.mean(), s - s.mean())[len(s) - 1: len(s) - 1 + 2 * search + 1]
    k = int(np.argmax(c))
    q = float(c[k] / (np.linalg.norm(s - s.mean()) * np.linalg.norm(r[k:k + L] - r[k:k + L].mean()) + 1e-9))
    return d + k - search, q


def sync(ref, sig):
    """Retourne dict(off0, slope, score, resid_ms) : le média commence à off0 secondes dans la référence,
    et sa position t_média correspond à off0 + t_média*(1+slope) dans la référence."""
    d, score, pr = coarse_offset(ref, sig)
    # affinage au milieu
    mid = _local(ref, sig, d, max(0, len(sig) // 2 - SR * 30), SR * 60, SR // 4)
    if mid:
        d = mid[0]
    pts = []
    for f in np.linspace(0.08, 0.92, 15):
        st = int(f * len(sig))
        r = _local(ref, sig, d, st, SR * 20, SR // 2)
        if r and r[1] > 0.2:
            pts.append((st / SR, r[0] / SR))
    if len(pts) >= 3:
        t, y = np.array(pts).T
        m = np.ones(len(t), bool)
        for _ in range(4):
            A = np.polyfit(t[m], y[m], 1)
            res = y - np.polyval(A, t)
            m = np.abs(res) < max(0.004, 3 * np.median(np.abs(res[m])))
            if m.sum() < 3:
                m = np.ones(len(t), bool); A = np.polyfit(t, y, 1); break
        slope, off0 = float(A[0]), float(A[1])
        resid = float(np.abs(res[m]).max() * 1000)
        n_ok = int(m.sum())
    else:
        slope, off0, resid, n_ok = 0.0, d / SR, None, len(pts)
    return {'off0': off0, 'slope': slope, 'score': score, 'peak': pr, 'resid_ms': resid, 'points': n_ok}
