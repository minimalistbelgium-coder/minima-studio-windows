// Panneau Minima Studio pour Premiere Pro (UXP, Premiere 25.6+).
// Il démarre avec Premiere (loadEvent "startup") et compte le temps de montage même si l'app
// Minima Studio est fermée. Quand l'app suit déjà, le serveur lui donne la priorité : pas de double comptage.
//
// Comptage précis : seul le temps entre deux actions dans Premiere (lecture, déplacement de la tête,
// sélection, montage, effet…) espacées de moins d'une minute est compté. Dès qu'il ne se passe plus rien
// (autre app, autre onglet, pause café), le compteur s'arrête et ce temps mort n'est jamais enregistré.
const ENDPOINT = 'https://jkfighpoftczgszgoidp.supabase.co/functions/v1/premiere-panel';
const BEAT_MS = 15000;   // envoi au serveur toutes les 15 s
const POLL_MS = 2000;    // lecture de Premiere toutes les 2 s
const GAP_S = 60;        // au-delà d'une minute sans action, le temps n'est pas compté

let ppro = null;
try { ppro = require('premierepro'); } catch (e) { ppro = null; }

const store = {
  get(k) { try { return localStorage.getItem(k); } catch (e) { return null; } },
  set(k, v) { try { if (v == null) localStorage.removeItem(k); else localStorage.setItem(k, v); } catch (e) { /* rien */ } },
};

const st = {
  token: store.get('ms-token'), key: '', lastSig: '',
  lastActivity: 0,          // dernière action constatée (ms)
  credit: 0,                // secondes de travail constatées, pas encore envoyées
  creditKey: '',            // projet auquel appartient ce crédit
  last: null, lastAt: 0,    // dernière réponse du serveur
  busy: false,
};

// ---------- activité ----------
const nowMs = () => Date.now();
const isActive = () => !!st.key && st.lastActivity > 0 && (nowMs() - st.lastActivity) / 1000 <= GAP_S;

function touch() {
  const t = nowMs();
  if (st.key && st.lastActivity) {
    const gap = (t - st.lastActivity) / 1000;
    if (gap > 0 && gap <= GAP_S) { st.credit += gap; st.creditKey = st.key; }
  }
  st.lastActivity = t;
}

// ---------- lecture de Premiere ----------
const keyFor = (name) => String(name || '').replace(/\.prproj$/i, '').trim().toLowerCase();

async function readPremiere() {
  if (!ppro) return { key: '', sig: '' };
  let key = ''; let sig = '';
  try {
    const project = await ppro.Project.getActiveProject();
    if (project) {
      const name = project.name || (project.path || '').split(/[\\/]/).pop();
      key = keyFor(name);
      sig += project.path || name;
      try {
        const seq = await project.getActiveSequence();
        if (seq) {
          sig += '|' + (seq.name || '');
          try { const pos = await seq.getPlayerPosition(); sig += '|' + (pos && (pos.seconds != null ? pos.seconds : pos.ticks)); } catch (e) { /* API absente */ }
          try { const end = await seq.getEndTime(); sig += '|e' + (end && (end.seconds != null ? end.seconds : end.ticks)); } catch (e) { /* API absente */ }
          try { const sel = await seq.getSelection(); const items = sel && sel.getTrackItems ? await sel.getTrackItems() : null; sig += '|s' + (items ? items.length : ''); } catch (e) { /* API absente */ }
        }
      } catch (e) { /* pas de séquence */ }
    }
  } catch (e) { /* pas de projet */ }
  return { key, sig };
}

// Les évènements Premiere (sélection, projet modifié, effet déposé…) comptent comme des actions.
function listenPremiere() {
  if (!ppro || !ppro.EventManager || !ppro.Constants) return;
  const add = (group, names) => {
    const g = ppro.Constants[group]; if (!g) return;
    names.forEach((n) => { if (g[n]) { try { ppro.EventManager.addGlobalEventListener(g[n], touch, false); } catch (e) { /* non global */ } } });
  };
  add('SequenceEvent', ['ACTIVATED', 'SELECTION_CHANGED']);
  add('ProjectEvent', ['DIRTY', 'PROJECT_ITEM_SELECTION_CHANGED']);
  add('OperationCompleteEvent', ['EFFECT_DROP_COMPLETE', 'IMPORT_MEDIA_COMPLETE', 'CLIP_EXTEND_REACHED', 'GENERATIVE_EXTEND_COMPLETE']);
}

async function poll() {
  const r = await readPremiere();
  if (r.key !== st.key) {
    // Changement de projet : le temps déjà constaté part sur l'ancien projet, on repart de zéro.
    if (st.credit >= 1 && st.creditKey) await beat(st.creditKey);
    st.credit = 0; st.creditKey = '';
    st.key = r.key; st.lastSig = r.sig; st.lastActivity = r.key ? nowMs() : 0;
    st.last = null; render(); beat();
    return;
  }
  if (r.sig && r.sig !== st.lastSig) { st.lastSig = r.sig; touch(); }
}

// ---------- serveur ----------
async function call(body) {
  const res = await fetch(ENDPOINT, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  return res.json();
}

async function beat(forKey) {
  if (!st.token || st.busy) return render();
  st.busy = true;
  const key = forKey != null ? forKey : st.key;
  const sameKey = !st.creditKey || st.creditKey === key;
  const secs = sameKey ? Math.floor(st.credit) : 0;
  try {
    const r = await call({ action: 'beat', token: st.token, key, active: forKey == null && isActive(), secs });
    if (r && r.status && r.status !== 'error') st.credit = Math.max(0, st.credit - secs);
    if (forKey == null) { st.last = r; st.lastAt = nowMs(); }
    if (r && r.status === 'bad_token') { st.token = null; store.set('ms-token', null); }
  } catch (e) {
    if (forKey == null) { st.last = { status: 'offline' }; st.lastAt = nowMs(); }
    st.credit = Math.min(st.credit, 3600);
  }
  st.busy = false; render();
}

// ---------- interface ----------
const $ = (id) => document.getElementById(id);
const clock = (s) => { s = Math.max(0, Math.floor(s || 0)); const h = Math.floor(s / 3600); const m = Math.floor((s % 3600) / 60); const x = s % 60; return h + ':' + String(m).padStart(2, '0') + ':' + String(x).padStart(2, '0'); };
const esc = (s) => String(s || '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const show = (id, on) => { const el = $(id); if (el) el.className = el.className.replace(/\s*hidden/g, '') + (on ? '' : ' hidden'); };

function setPill(cls, text) { $('dot').className = 'dot ' + cls; $('state').textContent = text; }

// Temps affiché : dernier total du serveur + travail constaté depuis, et la minute en cours tant qu'on bosse.
function liveSeconds() {
  const r = st.last || {};
  let s = r.today || 0;
  if (r.status === 'counting' || r.status === 'idle') {
    if (st.creditKey === st.key || !st.creditKey) s += st.credit;
    if (isActive()) s += (nowMs() - st.lastActivity) / 1000;
  }
  return s;
}

function render() {
  if (!$('main')) return;
  const logged = !!st.token;
  show('login', !logged); show('main', logged); show('pill', logged);
  if (!logged) return;
  const r = st.last || {};
  show('linkBox', false);
  $('mission').textContent = r.mission || '';
  $('client').textContent = r.client || '';
  const hasMission = !!r.mission;
  show('card', hasMission);
  const clk = $('clock'); const card = $('card');
  clk.textContent = clock(liveSeconds());
  if (!ppro) { setPill('warn', 'Premiere trop ancien'); $('hint').textContent = 'Il faut Premiere 25.6 ou plus récent.'; return; }
  const who = r.who ? r.who : '';
  switch (r.status) {
    case 'counting':
    case 'idle': {
      const on = isActive();
      setPill(on ? 'on' : 'warn', on ? 'En cours' : 'En pause');
      clk.className = 'clock ' + (on ? 'on' : 'idle'); card.className = 'card' + (on ? ' on' : '');
      $('sub').textContent = on ? 'Le temps est enregistré dans Minima Studio.' : 'Reprend dès que tu travailles dans Premiere.';
      $('hint').textContent = on ? '' : "Seul le temps passé à monter est compté : une minute sans action dans Premiere et le chrono s'arrête.";
      break;
    }
    case 'app':
      setPill('app', "Suivi par l'app"); clk.className = 'clock app'; card.className = 'card';
      $('sub').textContent = "L'app Minima Studio chronomètre ce montage.";
      $('hint').textContent = 'Le panneau prend le relais si tu fermes l’app.';
      break;
    case 'no_project':
      setPill('', 'Aucun projet'); $('hint').textContent = 'Ouvre le projet Premiere de ta mission.'; break;
    case 'unlinked': {
      setPill('warn', 'Projet non lié');
      $('hint').textContent = 'Choisis la mission de ce projet (« ' + st.key + ' »). Ce sera retenu.';
      const sel = $('missions'); const list = r.missions || [];
      const sig = JSON.stringify(list.map((m) => m.id));
      if (sel.dataset.sig !== sig) {
        sel.innerHTML = list.map((m) => '<option value="' + m.id + '">' + esc(m.title) + (m.client ? ' · ' + esc(m.client) : '') + '</option>').join('');
        sel.dataset.sig = sig;
      }
      show('linkBox', list.length > 0);
      if (!list.length) $('hint').textContent = "Aucune mission en cours ne t'est assignée.";
      break;
    }
    case 'offline': setPill('off', 'Hors ligne'); $('hint').textContent = 'Le temps constaté est gardé et sera envoyé au retour du réseau.'; break;
    default: setPill('', 'Connexion…'); $('hint').textContent = '';
  }
  if (who && r.status !== 'offline') $('logout').textContent = 'Connecté : ' + who + ' · changer de compte';
}

function wire() {
  if (!$('save') || $('save').dataset.wired) return;
  $('save').dataset.wired = '1';
  $('save').addEventListener('click', async () => {
    const code = $('code').value.trim().toUpperCase();
    if (!/^[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}$/.test(code)) { $('loginErr').textContent = 'Le code ressemble à AB12-CD34-EF56.'; return; }
    st.token = code; store.set('ms-token', code); $('loginErr').textContent = ''; await beat();
    if (!st.token) { $('loginErr').textContent = 'Code inconnu. Génère-en un nouveau dans Minima Studio.'; render(); }
  });
  $('link').addEventListener('click', async () => {
    const mid = $('missions').value; if (!mid || !st.key) return;
    try { await call({ action: 'link', token: st.token, mission: mid, key: st.key }); } catch (e) { /* réessai au prochain battement */ }
    touch(); beat();
  });
  $('logout').addEventListener('click', () => { st.token = null; store.set('ms-token', null); st.last = null; render(); });
}

// Le panneau peut être affiché ou non : la logique tourne dans tous les cas.
try {
  const { entrypoints } = require('uxp');
  entrypoints.setup({ panels: { minimaPanel: { show() { wire(); render(); } } } });
} catch (e) { /* hors UXP */ }
document.addEventListener('DOMContentLoaded', () => { wire(); render(); });
wire();

listenPremiere();
setInterval(poll, POLL_MS);
setInterval(() => beat(), BEAT_MS);
setInterval(render, 1000);
poll();
