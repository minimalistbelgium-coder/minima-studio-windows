// Minima Studio pour Windows : chrono automatique dans Premiere Pro, mode mini,
// notifications, ouverture au démarrage et mises à jour. Ne fait rien dans un navigateur.
const T = window.__TAURI__;

function whenReady(fn) { if (window.MS) fn(); else window.addEventListener('ms-ready', fn, { once: true }); }

const REPO = 'minimalistbelgium-coder/minima-studio-windows';
const IDLE_LIMIT = 300;     // 5 min sans clavier ni souris : pause
const FOCUS_GRACE = 120;    // 2 min hors de Premiere encore comptées
const AWAY_TIMEOUT = 900;   // 15 min sans réponse : session close
const TICK = 5;             // secondes entre deux lectures
const BEAT = 30;            // secondes entre deux enregistrements

const invoke = (cmd, args) => T.core.invoke(cmd, args);
// Plugins appelés directement (ne dépend pas des API JS globales)
const notify = (title, body) => invoke('plugin:notification|notify', { options: { title, body } }).catch(() => {});
const openUrl = (url) => invoke('plugin:opener|open_url', { url }).catch((e) => console.warn(e));
const uuid = () => crypto.randomUUID();
const now = () => new Date();
const iso = (d) => d.toISOString();

const st = {
  status: 'waiting', // waiting | running | paused | askAway | disabled
  pauseReason: '', mission: null, manual: false, manualMission: null,
  premiereOpen: false, premiereFront: false, titles: [], projectName: null, projectPath: null,
  unlinked: null, dismissed: new Set(),
  sessionId: null, sessionStart: null, sessionSeconds: 0, baseSeconds: 0,
  countedIdle: 0, countedAway: 0, awayStart: null, lastTick: Date.now(), lastBeat: 0,
  budget: 0, myShare: null, showDiag: false, version: '',
};

function start() {
  const MS = window.MS;
  document.body.classList.add('desktop');
  // Liens externes : navigateur par défaut
  document.addEventListener('click', (e) => {
    const a = e.target.closest('a[href]');
    if (!a) return;
    const href = a.getAttribute('href');
    if (/^https?:\/\//i.test(href) && !href.startsWith(location.origin)) {
      e.preventDefault(); openUrl(href);
    } else if (href.startsWith('mailto:')) { e.preventDefault(); openUrl(href); }
  }, true);

  window.addEventListener('ms-refresh', () => { notifyNew(); renderCard(); injectMissionButton(); });
  new MutationObserver(injectMissionButton).observe(document.getElementById('sheet-root'), { childList: true });
  document.getElementById('tracker-root').addEventListener('click', onCardClick);
  document.getElementById('tracker-root').addEventListener('change', onCardChange);

  invoke('plugin:app|version').then((v) => { st.version = v; checkUpdate(); });
  setInterval(checkUpdate, 3 * 3600 * 1000);
  setInterval(() => tick().catch(console.error), TICK * 1000);
  setInterval(publishMini, 1000);
  tick().catch(console.error);
}

const me = () => window.MS.S.me;
const isTeam = () => me() && me().active && (me().role === 'admin' || me().role === 'editor');

// ---------- lecture de Premiere ----------
function parseTitle(t) {
  const i = t.toLowerCase().lastIndexOf('.prproj');
  if (i >= 0) {
    const head = t.slice(0, i + 7);
    const m = head.match(/([A-Za-z]:\\|\\\\|\/).*$/);
    if (m) { const path = m[0]; return { path, name: path.split(/[\\/]/).pop() }; }
    let name = head; const dash = name.lastIndexOf(' - '); if (dash >= 0) name = name.slice(dash + 3);
    return { path: null, name: name.trim() };
  }
  // Repli : « Adobe Premiere Pro 2025 - Mon projet * »
  const parts = t.split(' - ').map((x) => x.trim()).filter((x) => x && !/^adobe premiere|^premiere pro/i.test(x));
  if (!parts.length) return null;
  let name = parts[0].replace(/\s*\*$/, '');
  if (name.length < 2 || /^(accueil|home|projet|project|effets|effects|source|programme|program|timeline)$/i.test(name)) return null;
  return { path: null, name: name + '.prproj' };
}
const keyFor = (name) => name.replace(/\.prproj$/i, '').trim().toLowerCase();
const links = () => { try { return JSON.parse(localStorage.getItem('premiereLinks') || '{}'); } catch { return {}; } };

function matchMission(key) {
  const { S, memberIds } = window.MS;
  const id = links()[key];
  const m = id && S.missions.find((x) => x.id === id);
  if (m) return m;
  const mine = S.missions.filter((x) => me().role === 'admin' || memberIds(x.id).includes(me().id));
  return mine.find((x) => (x.premiere_key || '').toLowerCase() === key) || null;
}

async function linkProject(key, missionId) {
  const l = links(); l[key] = missionId; localStorage.setItem('premiereLinks', JSON.stringify(l));
  await window.MS.sb.rpc('link_premiere', { m: missionId, key });
  st.unlinked = null; await window.MS.refresh();
}

// ---------- boucle du chrono ----------
async function tick() {
  if (!isTeam()) { st.status = 'disabled'; renderCard(); return; }
  const t = Date.now();
  let dt = (t - st.lastTick) / 1000; st.lastTick = t;
  if (dt > 60) { if (st.sessionId) await endSession(0, 'Interruption'); dt = 0; }
  dt = Math.min(dt, 15);

  let p = { open: false, front: false, titles: [], idle_secs: 0 };
  try { p = await invoke('premiere_state'); } catch (e) { console.warn(e); }
  st.premiereOpen = p.open; st.premiereFront = p.front; st.titles = p.titles || [];
  st.projectName = null; st.projectPath = null;
  for (const title of st.titles) { const r = parseTitle(title); if (r) { st.projectName = r.name; st.projectPath = r.path; break; } }

  let target = null;
  if (st.manual && st.manualMission) {
    target = window.MS.S.missions.find((x) => x.id === st.manualMission.id) || st.manualMission;
  } else if (st.projectName) {
    const key = keyFor(st.projectName);
    target = matchMission(key);
    if (!target && !st.dismissed.has(key)) st.unlinked = key;
    if (target && st.unlinked === key) st.unlinked = null;
  } else st.unlinked = null;

  if (st.mission && st.sessionId && st.mission.id !== target?.id) await endSession(0, null);

  if (!target) {
    if (st.sessionId) await endSession(0, null);
    if (st.status !== 'paused') st.status = 'waiting';
    if (!st.premiereOpen && !st.manual) st.mission = null;
    return renderCard();
  }

  // Inactivité
  if (p.idle_secs >= IDLE_LIMIT) {
    if (st.sessionId) { await endSession(Math.max(st.countedIdle, st.countedAway), 'Inactif depuis 5 min'); if (st.manual) { st.manual = false; st.manualMission = null; } }
    st.status = 'paused'; st.pauseReason = 'Inactif'; st.mission = target;
    return renderCard();
  }

  // Hors de Premiere (mode auto)
  if (!st.manual && !st.premiereFront) {
    if (st.awayStart) {
      const away = (t - st.awayStart) / 1000;
      if (away >= AWAY_TIMEOUT) { await endSession(st.countedAway, 'Hors de Premiere'); st.awayStart = null; return renderCard(); }
      if (away >= FOCUS_GRACE && st.sessionId && st.status !== 'askAway') {
        st.status = 'askAway';
        notify('Minima Studio', "Premiere n'est plus au premier plan. Tu travailles toujours dessus ?");
      }
    } else if (st.sessionId) st.awayStart = t;
    if (st.status === 'askAway') return renderCard();
  } else if (st.premiereFront && st.awayStart) {
    const away = (t - st.awayStart) / 1000;
    if (away > FOCUS_GRACE && st.sessionId) st.sessionSeconds = Math.max(0, st.sessionSeconds - (away - FOCUS_GRACE));
    st.awayStart = null; if (st.status === 'askAway') st.status = 'running';
  }

  if (!st.sessionId) {
    if (!(st.manual || st.premiereFront)) { st.status = st.status === 'paused' ? 'paused' : 'waiting'; st.mission = target; return renderCard(); }
    await startSession(target);
  }
  st.mission = target;
  st.status = 'running';
  st.sessionSeconds += dt;
  st.countedIdle = p.idle_secs > 60 ? st.countedIdle + dt : 0;
  st.countedAway = (!st.manual && !st.premiereFront) ? st.countedAway + dt : 0;
  if (t - st.lastBeat >= BEAT * 1000) await heartbeat(true);
  renderCard();
}

async function startSession(m) {
  const { sb, S, split } = window.MS;
  st.mission = m; st.sessionSeconds = 0; st.countedIdle = 0; st.countedAway = 0;
  const id = uuid(); const startAt = now();
  st.sessionId = id; st.sessionStart = startAt; st.lastBeat = Date.now();
  st.budget = m.editor_budget || 0;
  const rows = split(m); const mine = rows.find((r) => r.u === S.me.id);
  st.baseSeconds = mine ? mine.secs : 0;
  st.othersWeighted = rows.filter((r) => r.u !== S.me.id).reduce((a, r) => a + r.w, 0);
  st.myWeight = (S.me.role === 'admin' && rows.length > 0 && rows.some((r) => r.u !== S.me.id)) ? (m.admin_weight || 1.5) : 1;
  const { error } = await sb.from('sessions').insert({
    id, mission_id: m.id, user_id: S.me.id, started_at: iso(startAt), ended_at: iso(startAt),
    duration_sec: 0, source: st.manual ? 'manual' : 'auto', live: true, project_path: st.manual ? null : st.projectPath,
  });
  if (error) { console.warn(error); st.sessionId = null; }
}

async function heartbeat(live) {
  if (!st.sessionId) return;
  st.lastBeat = Date.now();
  const end = new Date(st.sessionStart.getTime() + st.sessionSeconds * 1000);
  await window.MS.sb.from('sessions').update({ ended_at: iso(live ? now() : end), duration_sec: Math.round(st.sessionSeconds), live }).eq('id', st.sessionId);
}

async function endSession(deduct, reason) {
  if (!st.sessionId) { if (reason) { st.status = 'paused'; st.pauseReason = reason; } return; }
  st.sessionSeconds = Math.max(0, st.sessionSeconds - deduct);
  const id = st.sessionId; st.sessionId = null;
  const end = new Date(st.sessionStart.getTime() + st.sessionSeconds * 1000);
  await window.MS.sb.from('sessions').update({ ended_at: iso(end), duration_sec: Math.round(st.sessionSeconds), live: false }).eq('id', id);
  st.baseSeconds += st.sessionSeconds; st.sessionSeconds = 0;
  st.countedIdle = 0; st.countedAway = 0; st.awayStart = null;
  if (reason) { st.status = 'paused'; st.pauseReason = reason; } else st.status = 'waiting';
}

async function answerAway(still) {
  if (still) { st.awayStart = null; st.countedAway = 0; st.status = 'running'; }
  else { await endSession(st.countedAway, 'Hors de Premiere'); st.awayStart = null; }
  renderCard();
}

async function startManual(m) {
  if (st.sessionId) await endSession(0, null);
  st.manual = true; st.manualMission = m; st.status = 'running';
  await startSession(m); renderCard();
}
async function stopManual() {
  await endSession(0, null); st.manual = false; st.manualMission = null; renderCard();
}

// ---------- montants ----------
function totalSeconds() { return st.baseSeconds + st.sessionSeconds; }
function estimate() {
  if (!st.mission || !st.budget) return null;
  const mine = totalSeconds() * (st.myWeight || 1);
  const tot = mine + (st.othersWeighted || 0);
  return tot > 0 ? (st.budget * mine) / tot : st.budget;
}
function rate() {
  const s = totalSeconds(); const a = estimate() ?? st.budget;
  return s >= 300 && a ? a / (s / 3600) : null;
}
const clock = (sec) => { sec = Math.floor(sec); const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60; return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`; };

// ---------- carte du chrono ----------
function statusLine() {
  switch (st.status) {
    case 'running': return st.manual ? 'Chrono manuel' : `Premiere · ${st.projectName || ''}`;
    case 'paused': return `En pause · ${st.pauseReason}`;
    case 'askAway': return 'Tu travailles toujours dessus ?';
    default:
      if (!st.premiereOpen) return 'Ouvre un projet dans Premiere Pro';
      if (!st.projectName) return 'Aucun projet détecté dans Premiere';
      return 'En attente de Premiere au premier plan';
  }
}

function renderCard() {
  const root = document.getElementById('tracker-root');
  if (!root) return;
  if (!isTeam() || !window.MS.S.session) { root.innerHTML = ''; return; }
  const { esc, eur, S, client } = window.MS;
  const col = st.status === 'running' ? 'var(--green)' : st.status === 'askAway' || st.status === 'paused' ? 'var(--amber)' : 'var(--muted)';
  const r = rate();
  const mine = S.missions.filter((m) => !['validated', 'paid', 'requested'].includes(m.status) && (S.me.role === 'admin' || window.MS.memberIds(m.id).includes(S.me.id)));
  const c = st.mission ? client(st.mission.client_id) : null;
  root.innerHTML = `<div class="tracker ${st.status}">
    <div class="tr-head"><span class="dot" style="background:${col}"></span><span class="tr-title">${esc(st.mission ? `${c ? c.name + ' · ' : ''}${st.mission.title}` : 'Chrono')}</span>
      <button class="tr-icon" data-tr="mini" title="Mode mini" aria-label="Mode mini">⤢</button></div>
    <div class="tr-clock mono" style="color:${st.status === 'running' ? 'var(--green)' : 'var(--text)'}">${clock(totalSeconds())}</div>
    ${st.mission && st.budget ? `<div class="tr-stats"><div><span>À LA CLÉ</span><b style="color:var(--green)">${eur(st.budget)}</b></div><div><span>RATIO</span><b>${r ? eur(Math.round(r)) + ' / h' : '–'}</b></div></div>` : ''}
    <div class="tr-line">${esc(statusLine())}</div>
    ${st.status === 'askAway' ? '<div class="tr-row"><button class="btn pri" data-tr="still">Oui, compter</button><button class="btn" data-tr="away">Non</button></div>' : ''}
    ${st.unlinked && st.status !== 'askAway' ? `<div class="tr-link"><div class="tr-line" style="color:var(--amber)">Projet « ${esc(st.unlinked)} » non lié</div>
      <select class="in" data-tr="link"><option value="">Associer à une mission…</option>${mine.map((m) => `<option value="${m.id}">${esc((client(m.client_id)?.name || '') + ' · ' + m.title)}</option>`).join('')}</select>
      <button class="tr-text" data-tr="dismiss">Ignorer ce projet</button></div>` : ''}
    ${st.manual ? '<button class="btn" data-tr="stop" style="width:100%;margin-top:8px">Arrêter le chrono</button>' : ''}
    <button class="tr-text" data-tr="diag">${st.showDiag ? 'Masquer le diagnostic' : 'Diagnostic'}</button>
    ${st.showDiag ? `<div class="tr-diag">Premiere ouvert : ${st.premiereOpen ? 'oui' : 'non'}<br>Au premier plan : ${st.premiereFront ? 'oui' : 'non'}<br>Projet : ${esc(st.projectName || 'aucun')}<br>Titres lus :<br>${st.titles.map((t) => '· ' + esc(t)).join('<br>') || 'aucun'}<br>Version : ${esc(st.version)}</div>` : ''}
    ${updateBanner()}
  </div>`;
}

async function onCardClick(e) {
  const b = e.target.closest('[data-tr]'); if (!b) return;
  const a = b.dataset.tr;
  if (a === 'mini') await invoke('show_mini');
  else if (a === 'still') await answerAway(true);
  else if (a === 'away') await answerAway(false);
  else if (a === 'stop') await stopManual();
  else if (a === 'dismiss') { st.dismissed.add(st.unlinked); st.unlinked = null; renderCard(); }
  else if (a === 'diag') { st.showDiag = !st.showDiag; renderCard(); }
  else if (a === 'update' && st.update) { await openUrl(st.update.url); window.MS.toast("Lance l'installeur téléchargé, l'app se mettra à jour"); }
}
async function onCardChange(e) {
  if (e.target.dataset.tr === 'link' && e.target.value && st.unlinked) await linkProject(st.unlinked, e.target.value);
}

// Bouton « Démarrer le chrono » dans une mission (temps hors de Premiere)
function injectMissionButton() {
  const head = document.querySelector('#sheet-root .sheet-head');
  const { S } = window.MS;
  if (!head || !isTeam() || !S.openId || head.querySelector('[data-start-chrono]')) return;
  const m = S.missions.find((x) => x.id === S.openId);
  if (!m || ['validated', 'paid', 'requested'].includes(m.status)) return;
  const btn = document.createElement('button');
  btn.className = 'btn'; btn.dataset.startChrono = '1'; btn.style.minHeight = '36px';
  const running = st.manual && st.manualMission?.id === m.id;
  btn.textContent = running ? 'Arrêter le chrono' : 'Démarrer le chrono';
  btn.addEventListener('click', async (e) => {
    e.stopPropagation();
    if (st.manual && st.manualMission?.id === m.id) await stopManual(); else await startManual(m);
    btn.textContent = st.manual ? 'Arrêter le chrono' : 'Démarrer le chrono';
  });
  head.insertBefore(btn, head.querySelector('.x'));
}

// ---------- mode mini ----------
function publishMini() {
  const { S, client } = window.MS || {};
  if (!S) return;
  const r = rate();
  const data = {
    status: st.status, line: statusLine(), seconds: totalSeconds(),
    title: st.mission ? `${client(st.mission.client_id)?.name ? client(st.mission.client_id).name + ' · ' : ''}${st.mission.title}` : 'Chrono',
    budget: st.mission ? st.budget : null, rate: r, t: Date.now(),
  };
  try { localStorage.setItem('minimaTracker', JSON.stringify(data)); } catch {}
  if (st.status === 'running' || st.status === 'askAway') renderClockOnly();
}
function renderClockOnly() {
  const el = document.querySelector('#tracker-root .tr-clock'); if (el) el.textContent = clock(totalSeconds());
}

// ---------- notifications Windows ----------
let notifReady = false;
async function notifyNew() {
  const { S } = window.MS;
  if (!S.me) return;
  if (!notifReady) {
    notifReady = true;
    try { if (!(await invoke('plugin:notification|is_permission_granted'))) await invoke('plugin:notification|request_permission'); } catch {}
  }
  let posted; try { posted = new Set(JSON.parse(localStorage.getItem('postedNotifs') || 'null') || []); } catch { posted = new Set(); }
  const first = localStorage.getItem('postedNotifs') === null;
  for (const n of S.notifs.filter((x) => !x.read_at)) {
    if (posted.has(n.id)) continue;
    posted.add(n.id);
    if (first || Date.now() - new Date(n.created_at).getTime() > 86400000) continue;
    notify(n.title, n.body || '');
  }
  localStorage.setItem('postedNotifs', JSON.stringify([...posted].slice(-300)));
}

// ---------- mises à jour ----------
function newer(a, b) {
  const pa = a.split('.').map(Number), pb = b.split('.').map(Number);
  for (let i = 0; i < 3; i++) { if ((pa[i] || 0) > (pb[i] || 0)) return true; if ((pa[i] || 0) < (pb[i] || 0)) return false; }
  return false;
}
async function checkUpdate() {
  if (!st.version) return;
  try {
    const r = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`, { headers: { Accept: 'application/vnd.github+json' } });
    if (!r.ok) return;
    const j = await r.json();
    const v = (j.tag_name || '').replace(/^v/, '');
    if (v && newer(v, st.version)) {
      const asset = (j.assets || []).find((x) => /setup\.exe$/i.test(x.name));
      st.update = { version: v, url: asset ? asset.browser_download_url : j.html_url };
      renderCard();
    }
  } catch {}
}
function updateBanner() {
  return st.update ? `<button class="tr-update" data-tr="update">Nouvelle version ${window.MS.esc(st.update.version)} : télécharger</button>` : '';
}

// Ouverture au démarrage de Windows (activée par défaut une fois)
(async () => {
  if (!T) return;
  try {
    if (localStorage.getItem('autostartSet') === null) {
      await invoke('plugin:autostart|enable'); localStorage.setItem('autostartSet', '1');
    }
  } catch {}
})();

// Démarrage (en fin de fichier : toutes les constantes sont prêtes)
if (T) whenReady(start);
