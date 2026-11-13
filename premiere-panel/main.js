// Panneau Minima Studio pour Premiere Pro (UXP, Premiere 25.6+).
// Il démarre avec Premiere (loadEvent "startup") et compte le temps de montage même si l'app
// Minima Studio est fermée. Quand l'app suit déjà, le serveur lui donne la priorité : pas de double comptage.
const ENDPOINT = 'https://jkfighpoftczgszgoidp.supabase.co/functions/v1/premiere-panel';
const BEAT_MS = 30000;          // un battement toutes les 30 s
const POLL_MS = 5000;           // on regarde Premiere toutes les 5 s
const IDLE_MS = 5 * 60 * 1000;  // 5 min sans activité dans Premiere : pause

let ppro = null;
try { ppro = require('premierepro'); } catch (e) { ppro = null; }

const store = {
  get(k) { try { return localStorage.getItem(k); } catch (e) { return null; } },
  set(k, v) { try { if (v == null) localStorage.removeItem(k); else localStorage.setItem(k, v); } catch (e) { /* rien */ } },
};

const st = { token: store.get('ms-token'), key: '', lastActivity: 0, lastSig: '', last: null, busy: false };

// ---------- lecture de Premiere ----------
const keyFor = (name) => String(name || '').replace(/\.prproj$/i, '').trim().toLowerCase();
function touch() { st.lastActivity = Date.now(); }

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
          try { const sel = await seq.getSelection(); const items = sel && sel.getTrackItems ? await sel.getTrackItems() : null; sig += '|sel' + (items ? items.length : ''); } catch (e) { /* API absente */ }
        }
      } catch (e) { /* pas de séquence */ }
    }
  } catch (e) { /* pas de projet */ }
  return { key, sig };
}

// Les évènements Premiere (sélection, projet modifié, effet déposé…) comptent comme de l'activité.
function listenPremiere() {
  if (!ppro || !ppro.EventManager || !ppro.Constants) return;
  const add = (group, names) => {
    const g = ppro.Constants[group]; if (!g) return;
    names.forEach((n) => { if (g[n]) { try { ppro.EventManager.addGlobalEventListener(g[n], touch, false); } catch (e) { /* non global */ } } });
  };
  add('SequenceEvent', ['ACTIVATED', 'SELECTION_CHANGED', 'CLOSED']);
  add('ProjectEvent', ['OPENED', 'DIRTY', 'ACTIVATED', 'PROJECT_ITEM_SELECTION_CHANGED']);
  add('OperationCompleteEvent', ['EFFECT_DROP_COMPLETE', 'IMPORT_MEDIA_COMPLETE', 'EXPORT_MEDIA_COMPLETE', 'CLIP_EXTEND_REACHED', 'GENERATIVE_EXTEND_COMPLETE']);
}

async function poll() {
  const r = await readPremiere();
  if (r.key !== st.key) { st.key = r.key; touch(); }
  if (r.sig && r.sig !== st.lastSig) { st.lastSig = r.sig; touch(); }
}

// ---------- serveur ----------
async function call(body) {
  const res = await fetch(ENDPOINT, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  return res.json();
}

async function beat() {
  if (!st.token || st.busy) return render();
  st.busy = true;
  try {
    const active = !!st.key && Date.now() - st.lastActivity < IDLE_MS;
    st.last = await call({ action: 'beat', token: st.token, key: st.key, active });
    if (st.last && st.last.status === 'bad_token') { st.token = null; store.set('ms-token', null); }
  } catch (e) {
    st.last = { status: 'offline' };
  }
  st.busy = false; render();
}

// ---------- interface ----------
const $ = (id) => document.getElementById(id);
const hm = (s) => { s = Math.max(0, Math.round(s || 0)); const h = Math.floor(s / 3600); const m = Math.floor((s % 3600) / 60); return h ? h + 'h ' + String(m).padStart(2, '0') : m + ' min'; };

function render() {
  if (!$('main')) return;
  const logged = !!st.token;
  $('login').className = logged ? 'hidden' : '';
  $('main').className = logged ? '' : 'hidden';
  if (!logged) return;
  const r = st.last || {}; const dot = $('dot');
  $('linkBox').className = 'hidden';
  $('mission').textContent = r.mission || '';
  $('today').textContent = r.mission ? hm(r.today) + " aujourd'hui" : '';
  const who = r.who ? r.who + ' · ' : '';
  if (!ppro) { dot.className = 'dot warn'; $('state').textContent = 'Premiere 25.6 ou plus récent requis'; $('hint').textContent = ''; return; }
  switch (r.status) {
    case 'counting': dot.className = 'dot on'; $('state').textContent = who + 'Chrono en cours'; $('hint').textContent = 'Le temps est enregistré dans Minima Studio.'; break;
    case 'app': dot.className = 'dot app'; $('state').textContent = who + "Suivi par l'app"; $('hint').textContent = "L'app Minima Studio suit déjà ce montage. Le panneau prend le relais si tu la fermes."; break;
    case 'idle': dot.className = 'dot warn'; $('state').textContent = who + 'En pause'; $('hint').textContent = 'Aucune activité dans Premiere depuis 5 min.'; break;
    case 'no_project': dot.className = 'dot'; $('state').textContent = who + 'Aucun projet ouvert'; $('hint').textContent = 'Ouvre le projet Premiere de ta mission.'; break;
    case 'unlinked': {
      dot.className = 'dot warn'; $('state').textContent = who + 'Projet non lié'; $('hint').textContent = 'Choisis la mission de ce projet (« ' + st.key + ' »). Ce sera retenu.';
      const sel = $('missions'); const list = r.missions || [];
      if (sel.dataset.sig !== JSON.stringify(list.map((m) => m.id))) {
        sel.innerHTML = list.map((m) => '<option value="' + m.id + '">' + esc(m.title) + (m.client ? ' · ' + esc(m.client) : '') + '</option>').join('');
        sel.dataset.sig = JSON.stringify(list.map((m) => m.id));
      }
      $('linkBox').className = list.length ? '' : 'hidden';
      if (!list.length) $('hint').textContent = "Aucune mission en cours ne t'est assignée.";
      break;
    }
    case 'offline': dot.className = 'dot warn'; $('state').textContent = 'Hors ligne'; $('hint').textContent = 'Nouvel essai dans 30 s.'; break;
    default: dot.className = 'dot'; $('state').textContent = 'Connexion…'; $('hint').textContent = '';
  }
}
const esc = (s) => String(s || '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

function wire() {
  if (!$('save') || $('save').dataset.wired) return;
  $('save').dataset.wired = '1';
  $('save').addEventListener('click', async () => {
    const code = $('code').value.trim().toUpperCase();
    if (!/^[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}$/.test(code)) { $('loginErr').textContent = 'Le code ressemble à AB12-CD34-EF56.'; return; }
    st.token = code; store.set('ms-token', code); $('loginErr').textContent = ''; touch(); await beat();
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
setInterval(beat, BEAT_MS);
poll().then(beat);
