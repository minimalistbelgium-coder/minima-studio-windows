// Minima Studio 1.1 : site web, iPhone et app Windows
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/+esm';

const SUPABASE_URL = 'https://jkfighpoftczgszgoidp.supabase.co';
const SUPABASE_KEY = 'sb_publishable_-DmB0APAPx5v6SnUdD8LMQ_jhyKFJUF';
const VAPID_PUBLIC = 'BE4XpKacAUXegzud16JVWqGHPUF8Kh4tolfppRy76697dUafBLkg4V-RC5M6OnRP86fklC4WlumRei9QW7ouUIc';
const LOGO = '<img class="logo-img" src="/logo.png" alt="Minimalist Belgium">';
const TAURI = !!window.__TAURI__;
const sb = createClient(SUPABASE_URL, SUPABASE_KEY, {
  auth: { flowType: 'pkce', persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
});

// ---------- état ----------
const store = { get(k) { try { return localStorage.getItem(k); } catch { return null; } }, set(k, v) { try { localStorage.setItem(k, v); } catch { /* stockage indisponible */ } } };
const S = {
  session: null, me: null, route: null, loading: true,
  clients: [], missions: [], profiles: [], members: [], finances: {}, sessions: [], notifs: [], invites: [],
  versions: {}, settings: {}, comments: {}, ai: [],
  filter: 'open', clientFilter: '', search: '', hoursWeek: 0, month: startOfMonth(new Date()), teamTab: 'members', finRange: 'month', earnMode: 'day',
  view: store.get('msAgendaView'), agDate: new Date(), agDay: ymd(new Date()), agEditor: '', agClient: '',
  sheet: null, openId: null, hash: '', pending: false,
  deepLink: new URLSearchParams(location.search).get('m'),
};
const app = document.getElementById('app');
const sheetRoot = document.getElementById('sheet-root');
const dialogRoot = document.body.appendChild(Object.assign(document.createElement('div'), { id: 'dialog-root' }));

// ---------- outils ----------
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const eur = (n) => new Intl.NumberFormat('fr-BE', { style: 'currency', currency: 'EUR', maximumFractionDigits: Math.abs(n) % 1 ? 2 : 0 }).format(n || 0);
const hm = (sec) => { sec = Math.round(sec || 0); const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60); return `${h}h ${String(m).padStart(2, '0')}`; };
const d = (s) => (s ? new Date(s) : null);
function startOfMonth(x) { return new Date(x.getFullYear(), x.getMonth(), 1); }
function ymd(x) { return `${x.getFullYear()}-${String(x.getMonth() + 1).padStart(2, '0')}-${String(x.getDate()).padStart(2, '0')}`; }
const fromYmd = (s) => { const [y, m, dd] = s.split('-').map(Number); return new Date(y, m - 1, dd); };
const addDays = (x, n) => new Date(x.getFullYear(), x.getMonth(), x.getDate() + n);
const startOfWeek = (x) => addDays(x, -((x.getDay() + 6) % 7));
const toLocalInput = (x) => new Date(x.getTime() - x.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
const sameMonth = (a, b) => a && a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth();
const isToday = (x) => x && x.toDateString() === new Date().toDateString();
const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1);
const fmtTime = (x) => x.toLocaleTimeString('fr-BE', { hour: '2-digit', minute: '2-digit' });
const fmtDay = (x) => x.toLocaleDateString('fr-BE', { weekday: 'short', day: 'numeric', month: 'short' });
const fmtLong = (x) => cap(x.toLocaleDateString('fr-BE', { weekday: 'long', day: 'numeric', month: 'long' }));
const isMobile = () => matchMedia('(max-width:820px)').matches;
function deadlineLabel(m) {
  const x = d(m.deadline); if (!x) return 'Sans deadline';
  if (isToday(x)) return `Auj. ${fmtTime(x)}`;
  if (x.toDateString() === addDays(new Date(), 1).toDateString()) return `Demain ${fmtTime(x)}`;
  return `${fmtDay(x)} ${fmtTime(x)}`;
}
function relative(x) {
  const s = (Date.now() - x.getTime()) / 1000;
  if (s < 60) return "à l'instant"; if (s < 3600) return `il y a ${Math.floor(s / 60)} min`;
  if (s < 86400) return `il y a ${Math.floor(s / 3600)} h`; return `il y a ${Math.floor(s / 86400)} j`;
}
function toast(t) { const el = document.getElementById('toast'); el.textContent = t; el.classList.add('on'); clearTimeout(toast.t); toast.t = setTimeout(() => el.classList.remove('on'), 2800); }
function debounce(fn, ms) { let t; return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); }; }

// Fenêtre de confirmation au style de l'app. Renvoie null si on annule, sinon true (ou le texte saisi).
function dialog({ title, body = '', ok = 'Confirmer', cancel = 'Annuler', danger = false, input = null }) {
  return new Promise((resolve) => {
    const field = !input ? '' : input.type === 'textarea'
      ? `<textarea class="in" name="v" placeholder="${esc(input.placeholder || '')}" ${input.required ? 'required' : ''} style="min-height:96px;margin-top:14px">${esc(input.value || '')}</textarea>`
      : `<input class="in" name="v" type="${input.type || 'text'}" placeholder="${esc(input.placeholder || '')}" value="${esc(input.value || '')}" ${input.required ? 'required' : ''} style="margin-top:14px">`;
    dialogRoot.innerHTML = `<div class="scrim dlg-scrim"><form class="dlg" role="alertdialog" aria-modal="true" aria-label="${esc(title)}">
      <h2>${esc(title)}</h2>${body ? `<p>${esc(body)}</p>` : ''}${field}
      <div class="dlg-btns"><button class="btn" type="button" data-dlg="0">${esc(cancel)}</button><button class="btn ${danger ? 'red' : 'pri'}" type="submit">${esc(ok)}</button></div></form></div>`;
    const form = dialogRoot.querySelector('form');
    const done = (v) => { dialogRoot.innerHTML = ''; dialog.close = null; resolve(v); };
    dialog.close = () => done(null);
    form.addEventListener('submit', (e) => { e.preventDefault(); e.stopPropagation(); done(input ? form.v.value.trim() : true); });
    form.querySelector('[data-dlg]').addEventListener('click', () => done(null));
    dialogRoot.firstChild.addEventListener('click', (e) => { e.stopPropagation(); if (e.target === dialogRoot.firstChild) done(null); });
    (form.v || form.querySelector('[type=submit]')).focus();
  });
}

const STATUS = {
  requested: ['Demande', '#F472B6'], assigned: ['Assignée', '#8B8D94'], editing: ['En montage', '#4C8DFF'],
  v1_delivered: ['V1 livrée', '#3DD68C'], revisions: ['Retouches', '#F5A524'], fix_delivered: ['Corrections livrées', '#C084FC'],
  validated: ['Validée', '#3DD68C'], paid: ['Payée', '#8B8D94'],
};
const CLIENT_STATUS = {
  requested: 'Demande envoyée', assigned: 'Projet lancé', editing: 'En montage', v1_delivered: 'À valider',
  revisions: 'Retours en cours', fix_delivered: 'À valider', validated: 'Terminé', paid: 'Terminé',
};
const CLIENT_LINE = {
  requested: 'Gaston regarde ta demande et te confirme le lancement.', assigned: 'Projet lancé, le montage va commencer.',
  editing: 'Montage en cours.', v1_delivered: 'Ta vidéo est prête : à toi de la valider.', revisions: 'On travaille sur tes retours.',
  fix_delivered: 'Les corrections sont prêtes : à toi de les valider.', validated: 'Projet terminé.', paid: 'Projet terminé.',
};
const PROGRESS = { requested: 6, assigned: 18, editing: 42, v1_delivered: 72, revisions: 82, fix_delivered: 92, validated: 100, paid: 100 };
const STEPS = ['assigned', 'editing', 'v1_delivered', 'revisions', 'validated', 'paid'];
const stepIndex = (s) => (s === 'fix_delivered' ? 3 : Math.max(0, STEPS.indexOf(s)));
const isOpen = (m) => !['validated', 'paid'].includes(m.status);
const isDelivered = (m) => ['v1_delivered', 'fix_delivered', 'validated', 'paid'].includes(m.status);
const awaitsClient = (m) => ['v1_delivered', 'fix_delivered'].includes(m.status);
const isLate = (m) => d(m.deadline) && d(m.deadline) < new Date() && ['assigned', 'editing'].includes(m.status);
function pill(text, color) { return `<span class="pill" style="--c:${color}">${esc(text)}</span>`; }
// Couleur de texte lisible sur fond teinté : éclaircie en thème sombre, assombrie en thème clair (variables CSS).
function tint(color) { return `color-mix(in srgb,${color} var(--tint-p),var(--tint-to))`; }
const statusColor = (s) => (STATUS[s] || [0, '#8B8D94'])[1];
const statusPill = (s) => pill((STATUS[s] || [s])[0], statusColor(s));
const pillFor = (m) => (isClient() ? pill(CLIENT_STATUS[m.status] || m.status, statusColor(m.status)) : statusPill(m.status));

const client = (id) => S.clients.find((c) => c.id === id);
const profile = (id) => S.profiles.find((p) => p.id === id);
const mission = (id) => S.missions.find((m) => m.id === id);
const firstName = (p) => (p?.full_name || p?.email || '?').split(/[\s@]/)[0];
const memberIds = (mid) => S.members.filter((x) => x.mission_id === mid).map((x) => x.user_id);
const missionSessions = (mid) => S.sessions.filter((s) => s.mission_id === mid);
const liveSessions = () => S.sessions.filter((s) => s.live && d(s.ended_at) && Date.now() - d(s.ended_at).getTime() < 120000);
const isAdmin = () => S.me?.role === 'admin' && S.me.active;
const isClient = () => S.me?.role === 'client' && S.me.active;
const isEditor = () => S.me?.role === 'editor' && S.me.active;
const team = () => S.profiles.filter((p) => p.active && (p.role === 'editor' || p.role === 'admin'));
const isMine = (m) => memberIds(m.id).includes(S.me.id);
const AV = ['#A78BFA', '#34D399', '#F5A524', '#F472B6', '#2DD4BF', '#4C8DFF'];
const COLORS = ['#F472B6', '#2DD4BF', '#F5A524', '#A78BFA', '#34D399', '#4C8DFF', '#FB7185', '#FACC15'];
function avatar(p, size = 26) {
  if (!p) return '';
  const ini = (p.full_name || p.email || '?').split(/\s+/).map((x) => x[0]).join('').slice(0, 2).toUpperCase();
  const col = p.color ? `#${p.color.replace('#', '')}` : AV[(p.email || '').length % AV.length];
  const img = p.avatar_url ? `<img src="${esc(p.avatar_url)}" alt="" referrerpolicy="no-referrer">` : esc(ini);
  return `<span class="av" style="width:${size}px;height:${size}px;background:${col};font-size:${Math.round(size * 0.4)}px">${img}</span>`;
}
const avatars = (ids, size = 20) => `<span class="avs">${ids.map(profile).filter(Boolean).map((p) => avatar(p, size)).join('')}</span>`;
const clientColor = (c) => (c?.color ? `#${c.color.replace('#', '')}` : '#8B8D94');

// Même règle que l'app Mac : l'admin compte ×1,5 seulement s'il partage la mission.
function split(m) {
  const by = {};
  missionSessions(m.id).forEach((s) => { by[s.user_id] = (by[s.user_id] || 0) + (s.duration_sec || 0); });
  const ids = Object.keys(by); const shared = ids.length > 1;
  const rows = ids.map((u) => { const w = shared && profile(u)?.role === 'admin' ? (m.admin_weight || 1.5) : 1; return { u, secs: by[u], w: by[u] * w }; });
  const tot = rows.reduce((a, r) => a + r.w, 0); if (!tot) return [];
  return rows.map((r) => ({ ...r, pct: (100 * r.w) / tot, amount: ((m.editor_budget || 0) * r.w) / tot })).sort((a, b) => b.amount - a.amount);
}
function editorPayout(m) {
  const s = split(m);
  if (s.length) return s.filter((r) => profile(r.u)?.role !== 'admin').reduce((a, r) => a + r.amount, 0);
  return memberIds(m.id).some((u) => profile(u)?.role !== 'admin') ? m.editor_budget || 0 : 0;
}
// Part d'un monteur sur une mission (estimée à parts égales tant qu'aucun temps n'est enregistré).
function myShare(m) {
  const rows = split(m); const me = rows.find((r) => r.u === S.me.id);
  if (rows.length) return { amount: me?.amount || 0, secs: me?.secs || 0, estimated: false };
  const n = memberIds(m.id).length || 1;
  return { amount: isMine(m) ? (m.editor_budget || 0) / n : 0, secs: 0, estimated: true };
}
const monthOf = (m) => d(m.deadline) || d(m.created_at);

// ---------- données ----------
async function loadAll() {
  if (isClient()) {
    const [c, m, n, v, dep] = await Promise.all([
      sb.from('clients').select('*'),
      sb.rpc('client_projects'),
      sb.from('notifications').select('*').order('created_at', { ascending: false }).limit(40),
      sb.from('mission_versions').select('*').order('created_at'),
      sb.rpc('rushes_deposit_link'),
    ]);
    S.clients = c.data || []; S.missions = m.data || []; S.notifs = n.data || [];
    groupVersions(v.data); S.settings = { rushes_deposit_link: dep.data || null };
    return;
  }
  const q = [
    sb.from('clients').select('*').order('name'),
    sb.from('missions').select('*').order('deadline', { ascending: true, nullsFirst: false }),
    sb.from('profiles').select('*'),
    sb.from('mission_members').select('*'),
    sb.from('sessions').select('*').order('started_at', { ascending: false }).limit(3000),
    sb.from('notifications').select('*').order('created_at', { ascending: false }).limit(60),
    sb.from('mission_versions').select('*').order('created_at'),
    sb.from('app_settings').select('*'),
  ];
  if (isAdmin()) q.push(sb.from('mission_finance').select('*'), sb.from('team_invites').select('*').order('invited_at', { ascending: false }));
  const r = await Promise.all(q);
  const err = r.find((x) => x.error); if (err) console.warn(err.error);
  [S.clients, S.missions, S.profiles, S.members, S.sessions, S.notifs] = r.slice(0, 6).map((x) => x.data || []);
  groupVersions(r[6].data);
  S.settings = {}; (r[7].data || []).forEach((x) => { S.settings[x.key] = x.value; });
  S.finances = {}; (r[8]?.data || []).forEach((f) => { S.finances[f.mission_id] = f; });
  S.invites = r[9]?.data || [];
  // Montages faits par Claude (table absente ou vide : on ignore sans erreur)
  const ai = await sb.from('ai_work').select('*').order('ended_at', { ascending: false });
  S.ai = ai.error ? [] : ai.data || [];
}
function groupVersions(rows) { S.versions = {}; (rows || []).forEach((v) => { (S.versions[v.mission_id] ||= []).push(v); }); }
function digest() {
  const ses = S.sessions.reduce((a, s) => a + (s.duration_sec || 0) + (s.live ? 1 : 0), S.sessions.length);
  return JSON.stringify([S.me, S.missions, S.members, S.notifs, S.finances, S.profiles, S.clients, S.invites, S.versions, S.settings, S.ai, ses, liveSessions().length]);
}

async function loadMe() {
  const { data: { session } } = await sb.auth.getSession();
  S.session = session;
  if (!session) { S.me = null; return; }
  const { data } = await sb.from('profiles').select('*').eq('id', session.user.id).maybeSingle();
  S.me = data;
}

// ---------- icônes ----------
const svg = (p) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${p}</svg>`;
const I = {
  home: svg('<path d="M3 11l9-7 9 7v9a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/>'),
  film: svg('<rect x="3" y="5" width="18" height="15" rx="2"/><path d="M3 10h18M8 5v5M16 5v5"/>'),
  cal: svg('<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/>'),
  euro: svg('<path d="M4 19V9M10 19V5M16 19v-7M22 19H2"/>'),
  plus: svg('<path d="M12 5v14M5 12h14"/>'),
  bell: svg('<path d="M6 8a6 6 0 0 1 12 0c0 7 3 8 3 8H3s3-1 3-8M10 20a2 2 0 0 0 4 0"/>'),
  team: svg('<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c.8-3.5 3.4-5.5 6.5-5.5s5.7 2 6.5 5.5M16 4.5a3.5 3.5 0 0 1 0 7M18 14.6c2 .7 3.2 2.6 3.5 5.4"/>'),
  out: svg('<path d="M15 4h4v16h-4M10 8l-4 4 4 4M6 12h11"/>'),
  search: svg('<circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/>'),
  edit: svg('<path d="M4 20h4L19 9l-4-4L4 16zM13.5 6.5l4 4"/>'),
  copy: svg('<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"/>'),
  trash: svg('<path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13"/>'),
  check: svg('<path d="M5 12.5l4.5 4.5L19 7.5"/>'),
  left: svg('<path d="M15 5l-7 7 7 7"/>'),
  right: svg('<path d="M9 5l7 7-7 7"/>'),
};
const small = (ic) => ic.replace('<svg', '<svg width="16" height="16"');
const NEW_BTN = `<button class="btn pri" data-act="newmission">${small(I.plus)}Nouvelle mission</button>`;

const unread = () => S.notifs.filter((n) => !n.read_at).length;
// [clé, titre, icône, compteur, pastille, visible dans la barre du téléphone]
function routesFor() {
  if (isAdmin()) {
    const req = S.missions.filter((m) => m.status === 'requested').length;
    return [['home', 'Accueil', I.home, 0, 0, 1], ['projects', 'Projets', I.film, S.missions.filter((m) => isOpen(m) && m.status !== 'requested').length, req, 1], ['agenda', 'Agenda', I.cal, 0, 0, 1],
      ['finance', 'Finances', I.euro, 0, 0, 1], ['team', 'Équipe', I.team, 0, 0, 1], ['notifs', 'Activité', I.bell, 0, unread(), 0]];
  }
  if (isClient()) return [['projects', 'Mes projets', I.home, 0, S.missions.filter((m) => awaitsClient(m) && m.delivery_url).length, 1], ['agenda', 'Calendrier', I.cal, 0, 0, 1], ['new', 'Nouveau', I.plus, 0, 0, 1], ['notifs', 'Activité', I.bell, 0, unread(), 0]];
  return [['home', 'Accueil', I.home, 0, 0, 1], ['projects', 'Missions', I.film, S.missions.filter(isOpen).length, 0, 1], ['agenda', 'Agenda', I.cal, 0, 0, 1], ['earnings', 'Revenus', I.euro, 0, 0, 1], ['notifs', 'Activité', I.bell, 0, unread(), 0]];
}

// ---------- thème clair / sombre ----------
const THEME_BG = { dark: '#0A0B0E', light: '#ECEEF3' };
const sysTheme = () => (window.matchMedia && matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark');
// Choix mémorisé sur l'appareil, sinon celui du système.
const theme = () => { const t = store.get('msTheme'); return t === 'light' || t === 'dark' ? t : sysTheme(); };
function applyTheme() {
  const t = theme();
  document.documentElement.dataset.theme = t;
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', THEME_BG[t]);
  document.querySelectorAll('.tgl').forEach((b) => b.setAttribute('aria-checked', String(t === 'dark')));
}
function toggleTheme() {
  const root = document.documentElement;
  store.set('msTheme', theme() === 'dark' ? 'light' : 'dark');
  root.classList.add('theming'); clearTimeout(toggleTheme.t); toggleTheme.t = setTimeout(() => root.classList.remove('theming'), 420);
  applyTheme();
}
const themeToggle = (id) => `<button class="tgl" type="button" data-act="theme" role="switch" aria-checked="${theme() === 'dark'}" aria-label="Thème sombre" title="Thème clair ou sombre"><span class="tgl-knob"><svg viewBox="0 0 24 24" aria-hidden="true"><mask id="tgm-${id}"><rect x="-8" y="-8" width="40" height="40" fill="#fff"/><circle class="tgl-bite" cx="27" cy="3" r="6.5" fill="#000"/></mask><circle class="tgl-core" cx="12" cy="12" r="4.6" fill="currentColor" mask="url(#tgm-${id})"/><path class="tgl-rays" stroke="currentColor" stroke-width="2" stroke-linecap="round" d="M12 2.2v2.2M12 19.6v2.2M2.2 12h2.2M19.6 12h2.2M5.1 5.1l1.5 1.5M17.4 17.4l1.5 1.5M5.1 18.9l1.5-1.5M17.4 6.6l1.5-1.5"/></svg></span></button>`;
applyTheme();
if (window.matchMedia) matchMedia('(prefers-color-scheme: light)').addEventListener?.('change', applyTheme);
window.addEventListener('storage', (e) => { if (e.key === 'msTheme') applyTheme(); });

// ---------- pastille glissante (segments, navigation, onglets) ----------
// Le rendu reconstruit la page : on retient la dernière position de chaque pastille pour la faire glisser vers la nouvelle.
const thumbMem = {};
function placeThumbs(animate = true) {
  const count = {};
  document.querySelectorAll('.seg,.navs,.tabbar').forEach((box) => {
    const kind = box.classList[0];
    const scope = box.closest('#sheet-root') ? 'sheet' : S.route;
    count[kind + scope] = (count[kind + scope] || 0) + 1;
    const key = kind === 'seg' ? `seg:${scope}:${count[kind + scope]}` : kind;
    box.querySelector(':scope > .thumb')?.remove();
    const on = box.querySelector(':scope > .on');
    if (!on || !box.offsetWidth) { box.classList.remove('has-thumb'); return; }
    const g = { x: on.offsetLeft, y: on.offsetTop, w: on.offsetWidth, h: on.offsetHeight };
    const prev = thumbMem[key]; thumbMem[key] = g;
    const th = document.createElement('i'); th.className = 'thumb still'; th.setAttribute('aria-hidden', 'true');
    const set = (q) => { th.style.width = `${q.w}px`; th.style.height = `${q.h}px`; th.style.transform = `translate(${q.x}px,${q.y}px)`; };
    const move = animate && prev && (prev.x !== g.x || prev.y !== g.y || prev.w !== g.w);
    set(move ? prev : g); box.prepend(th); box.classList.add('has-thumb');
    if (kind === 'seg' && g.x + g.w > box.scrollLeft + box.clientWidth) box.scrollLeft = g.x - 8;
    if (move) { th.getBoundingClientRect(); th.classList.remove('still'); set(g); }
  });
}

// ---------- infobulle des graphiques (survol, toucher, clavier) ----------
const tipEl = document.body.appendChild(Object.assign(document.createElement('div'), { id: 'tip' }));
tipEl.setAttribute('role', 'tooltip');
let tipFor = null;
function hideTip() { if (tipFor) tipFor.classList.remove('tip-on'); tipFor = null; tipEl.classList.remove('on'); }
function showTip(t, x) {
  if (tipFor !== t) { hideTip(); tipFor = t; t.classList.add('tip-on'); tipEl.innerHTML = t.dataset.tip; }
  const b = t.getBoundingClientRect(); const w = tipEl.offsetWidth, h = tipEl.offsetHeight;
  const cx = x ?? b.left + b.width / 2;
  const left = Math.max(8, Math.min(window.innerWidth - w - 8, cx - w / 2));
  const top = b.top - h - 10 >= 8 ? b.top - h - 10 : Math.min(window.innerHeight - h - 8, b.bottom + 10);
  tipEl.style.left = `${Math.round(left)}px`; tipEl.style.top = `${Math.round(top)}px`; tipEl.classList.add('on');
}
const tipTarget = (e) => (e.target instanceof Element ? e.target.closest('[data-tip]') : null);
document.addEventListener('pointermove', (e) => { if (e.pointerType === 'touch') return; const t = tipTarget(e); if (t) showTip(t, e.clientX); else if (tipFor) hideTip(); });
document.addEventListener('pointerdown', (e) => { const t = tipTarget(e); if (t && e.pointerType === 'touch') showTip(t, e.clientX); else if (!t) hideTip(); });
document.addEventListener('focusin', (e) => { const t = tipTarget(e); if (t && t.matches(':focus-visible')) showTip(t); });
document.addEventListener('focusout', (e) => { if (tipFor && e.target === tipFor) hideTip(); });
document.documentElement.addEventListener('mouseleave', hideTip);
window.addEventListener('scroll', hideTip, { passive: true, capture: true });
// Contenu d'une infobulle : un titre et des lignes [libellé, valeur, couleur]. Le tout est échappé pour tenir dans un attribut.
const tipHtml = (title, rows) => esc(`<b>${esc(title)}</b>${rows.map(([l, v, c]) => `<span class="tip-r">${c ? `<i style="background:${c}"></i>` : ''}<span>${esc(l)}</span><b>${esc(v)}</b></span>`).join('')}`);

// ---------- graphiques (SVG inline, sans dépendance) ----------
const kEur = (n) => (Math.abs(n) >= 1000 ? `${(n / 1000).toLocaleString('fr-BE', { maximumFractionDigits: 1 })} k€` : `${Math.round(n)} €`);
const profColor = (p) => (p?.color ? `#${p.color.replace('#', '')}` : AV[(p?.email || '').length % AV.length]);
const monthShort = (x) => x.toLocaleDateString('fr-BE', { month: 'short' }).replace('.', '');
const monthLong = (x) => cap(x.toLocaleDateString('fr-BE', { month: 'long', year: 'numeric' }));
const emptyArt = (text) => `<div class="empty art">${I.euro}<span>${text}</span></div>`;
// Échelle verticale lisible : graduations rondes, zéro toujours inclus.
function chartScale(minV, maxV) {
  const lo0 = Math.min(0, minV); const raw = Math.max(1, maxV - lo0) / 4;
  const p = 10 ** Math.floor(Math.log10(raw));
  const step = [1, 2, 2.5, 5, 10].map((k) => k * p).find((x) => x >= raw);
  const lo = Math.floor(lo0 / step) * step; const hi = Math.max(step, Math.ceil(maxV / step) * step);
  const ticks = []; for (let t = lo; t <= hi + step / 1000; t += step) ticks.push(t);
  return { lo, hi, ticks };
}
let chartSeq = 0;
// Courbes : le tracé est en SVG étiré sur la largeur, les libellés et zones de survol sont en HTML pour rester nets à toute taille.
// series : [{ color, values, area }], une valeur par colonne (une série peut s'arrêter avant la fin).
function lineChart({ labels, series, tips = [], sel = -1, attrs = () => '', cls = '', label = '' }) {
  const n = labels.length; const all = series.flatMap((s) => s.values); const id = ++chartSeq;
  const { lo, hi, ticks } = chartScale(Math.min(0, ...all), Math.max(0, ...all));
  const X = (i) => ((i + 0.5) / n) * 100; const Y = (v) => 100 - ((v - lo) / (hi - lo)) * 100;
  const f = (v) => v.toFixed(2);
  const path = (vals) => vals.map((v, i) => `${i ? 'L' : 'M'}${f(X(i))} ${f(Y(v))}`).join('');
  const grid = ticks.map((t) => `<line x1="0" x2="100" y1="${f(Y(t))}" y2="${f(Y(t))}" class="${t === 0 ? 'zero' : ''}"/>`).join('');
  const defs = series.map((s, k) => (s.area ? `<linearGradient id="cg${id}-${k}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" style="stop-color:${s.color};stop-opacity:.3"/><stop offset="1" style="stop-color:${s.color};stop-opacity:0"/></linearGradient>` : '')).join('');
  const lines = series.map((s, k) => {
    if (!s.values.length) return '';
    const dPath = s.values.length === 1 ? `M${f(X(0) - 0.6)} ${f(Y(s.values[0]))}L${f(X(0) + 0.6)} ${f(Y(s.values[0]))}` : path(s.values);
    return `${s.area && s.values.length > 1 ? `<path d="${dPath}L${f(X(s.values.length - 1))} ${f(Y(0))}L${f(X(0))} ${f(Y(0))}Z" fill="url(#cg${id}-${k})"/>` : ''}<path class="ch-line" d="${dPath}" style="stroke:${s.color}"/>`;
  }).join('');
  const cols = labels.map((_, i) => `<div class="ch-col ${i === sel ? 'sel' : ''}" ${attrs(i)} ${tips[i] ? `data-tip="${tips[i]}"` : ''}>${series.map((s) => (s.values[i] == null ? '' : `<i class="ch-dot" style="top:${f(Y(s.values[i]))}%;--c:${s.color}"></i>`)).join('')}</div>`).join('');
  return `<div class="chart ${cls}" role="group" aria-label="${esc(label)}"><div class="ch-plot">${ticks.map((t) => `<span class="ch-y" style="top:${f(Y(t))}%">${kEur(t)}</span>`).join('')}
    <svg class="ch-svg" viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true"><defs>${defs}</defs><g class="ch-grid">${grid}</g><g class="ch-draw">${lines}</g></svg>
    <div class="ch-cols">${cols}</div></div>
    <div class="ch-x ${n > 14 ? 'dense' : ''}" aria-hidden="true">${labels.map((l, i) => `<span class="${i === sel ? 'sel' : ''}">${esc(l)}</span>`).join('')}</div></div>`;
}
// Barre horizontale : libellé, valeur et jauge. Le texte reste en encre neutre, seule la jauge porte la couleur.
function barRow({ lead = '', name, sub = '', value, small: sm = '', pct, color, tip, attrs = 'tabindex="0"', i = 0 }) {
  return `<div class="bar-row" ${attrs} data-tip="${tip}" style="--c:${color};--i:${i}"><span class="bl">${lead}<span>${esc(name)}</span>${sub ? `<span class="lbl">${esc(sub)}</span>` : ''}</span>
    <span class="bv mono">${esc(value)}${sm ? `<small>${esc(sm)}</small>` : ''}</span><span class="bt"><i style="width:${Math.max(0, Math.min(100, pct || 0)).toFixed(1)}%"></i></span></div>`;
}

// --- Finances : séries mensuelles et répartitions
function financeMonths(end, n = 12) {
  const out = Array.from({ length: n }, (_, i) => ({ mo: new Date(end.getFullYear(), end.getMonth() - (n - 1 - i), 1), billed: 0, payout: 0, margin: 0, n: 0 }));
  const idx = {}; out.forEach((o) => { idx[`${o.mo.getFullYear()}-${o.mo.getMonth()}`] = o; });
  S.missions.forEach((m) => {
    if (m.status === 'requested') return;
    const x = monthOf(m); const o = x && idx[`${x.getFullYear()}-${x.getMonth()}`]; if (!o) return;
    o.billed += S.finances[m.id]?.client_price || 0; o.payout += editorPayout(m); o.n += 1;
  });
  out.forEach((o) => { o.margin = o.billed - o.payout; });
  return out;
}
function financeBreakdown(list) {
  const byClient = {}; const byEditor = {};
  list.forEach((m) => {
    const c = (byClient[m.client_id || ''] ||= { billed: 0, payout: 0, n: 0 });
    c.billed += S.finances[m.id]?.client_price || 0; c.payout += editorPayout(m); c.n += 1;
    split(m).filter((r) => profile(r.u)?.role !== 'admin').forEach((r) => { const e = (byEditor[r.u] ||= { amount: 0, secs: 0, n: 0 }); e.amount += r.amount; e.secs += r.secs; e.n += 1; });
  });
  return { byClient, byEditor };
}
function financeCharts(mo, list) {
  const nowM = startOfMonth(new Date());
  const diff = (mo.getFullYear() - nowM.getFullYear()) * 12 + mo.getMonth() - nowM.getMonth();
  const end = diff > 0 || diff < -11 ? mo : nowM;
  const months = financeMonths(end); const selI = months.findIndex((o) => sameMonth(o.mo, mo));
  const sum = (k) => months.reduce((a, o) => a + o[k], 0);
  const SER = [['Facturé', 'var(--s1)', 'billed'], ['Reversé', 'var(--s2)', 'payout'], ['Marge', 'var(--s3)', 'margin']];
  const evo = months.some((o) => o.n) ? lineChart({
    labels: months.map((o) => monthShort(o.mo)), sel: selI, cls: 'months', label: 'Facturé, reversé aux monteurs et marge sur 12 mois',
    series: SER.map(([, color, k], i) => ({ color, values: months.map((o) => Math.round(o[k])), area: i === 0 })),
    tips: months.map((o) => tipHtml(monthLong(o.mo), [...SER.map(([t, c, k]) => [t, eur(Math.round(o[k])), c]), ['Missions', String(o.n)]])),
    attrs: (i) => `role="button" tabindex="0" data-month="${i - selI}" aria-label="${esc(`${monthLong(months[i].mo)} : facturé ${eur(Math.round(months[i].billed))}, reversé ${eur(Math.round(months[i].payout))}, marge ${eur(Math.round(months[i].margin))}`)}"`,
  }) : emptyArt('Pas encore de mission sur cette période.');
  const year = S.finRange === 'year';
  const from = months[0].mo; const to = new Date(end.getFullYear(), end.getMonth() + 1, 1);
  const scope = year ? S.missions.filter((m) => m.status !== 'requested' && monthOf(m) && monthOf(m) >= from && monthOf(m) < to) : list;
  const { byClient, byEditor } = financeBreakdown(scope);
  const cl = Object.entries(byClient).map(([id, v]) => ({ c: client(id), ...v })).sort((a, b) => b.billed - a.billed || b.n - a.n);
  const clTot = cl.reduce((a, r) => a + r.billed, 0); const clMax = Math.max(1, ...cl.map((r) => r.billed));
  const pc = (v, t) => (t ? `${Math.round((v / t) * 100)} %` : '');
  const clRows = cl.map((r, i) => barRow({ i, lead: `<span class="dot" style="background:${clientColor(r.c)}"></span>`, name: r.c?.name || 'Sans client', sub: `${r.n} mission${r.n > 1 ? 's' : ''}`,
    value: eur(Math.round(r.billed)), small: pc(r.billed, clTot), pct: (r.billed / clMax) * 100, color: clientColor(r.c),
    tip: tipHtml(r.c?.name || 'Sans client', [['Facturé', eur(Math.round(r.billed)), 'var(--s1)'], ['Reversé', eur(Math.round(r.payout)), 'var(--s2)'], ['Marge', eur(Math.round(r.billed - r.payout)), 'var(--s3)'], ['Part du facturé', pc(r.billed, clTot) || '–']]) })).join('');
  const share = clTot ? `<div class="share" aria-hidden="true">${cl.filter((r) => r.billed > 0).map((r) => `<i style="flex:${r.billed};--c:${clientColor(r.c)}"></i>`).join('')}</div>` : '';
  const ed = Object.entries(byEditor).map(([u, v]) => ({ p: profile(u), ...v })).sort((a, b) => b.amount - a.amount);
  const edTot = ed.reduce((a, r) => a + r.amount, 0); const edMax = Math.max(1, ...ed.map((r) => r.amount));
  const rate = (r) => (r.secs >= 600 ? `${eur(Math.round(r.amount / (r.secs / 3600)))}/h` : '');
  const edRows = ed.map((r, i) => barRow({ i, lead: avatar(r.p, 22), name: firstName(r.p), sub: [hm(r.secs), rate(r)].filter(Boolean).join(' · '),
    value: eur(Math.round(r.amount)), small: pc(r.amount, edTot), pct: (r.amount / edMax) * 100, color: profColor(r.p),
    tip: tipHtml(r.p?.full_name || firstName(r.p), [['Reversé', eur(Math.round(r.amount))], ['Temps de montage', hm(r.secs)], ['Taux horaire', rate(r) || '–'], ['Missions', String(r.n)]]) })).join('');
  const period = year ? `${monthShort(from)} ${from.getFullYear()} à ${monthShort(end)} ${end.getFullYear()}` : monthLong(mo);
  const seg = `<div class="seg mini"><button class="${year ? '' : 'on'}" data-set="finRange:month">Ce mois</button><button class="${year ? 'on' : ''}" data-set="finRange:year">12 mois</button></div>`;
  return `<div class="card" style="margin-bottom:16px"><div class="ch-head"><div><h2>Évolution sur 12 mois</h2><div class="lbl">Montants HTVA par mois. Choisis un mois sur la courbe pour voir son détail.</div></div>
      <div class="ch-legend"><span class="lbl">Total</span>${SER.map(([t, c, k]) => `<span><i style="--c:${c}"></i>${t}<b>${eur(Math.round(sum(k)))}</b></span>`).join('')}</div></div>${evo}</div>
  <div class="cols even">
    <div class="card"><div class="ch-head"><div><h2>Par client</h2><div class="lbl">Facturé · ${esc(period)}</div></div>${seg}</div>${share}<div class="bars">${clRows || emptyArt('Aucune mission sur cette période.')}</div></div>
    <div class="card"><div class="ch-head"><div><h2>Par monteur</h2><div class="lbl">Reversé · ${esc(period)}</div></div>${seg}</div><div class="bars">${edRows || emptyArt('Pas encore de temps enregistré.')}</div></div>
  </div>`;
}

// --- Revenus du monteur : gains par jour et par projet
// La part de chaque mission (myShare) est répartie sur les jours où le monteur y a travaillé, au prorata du temps passé chaque jour.
function myDailyGains() {
  const out = {};
  S.missions.forEach((m) => {
    const mine = missionSessions(m.id).filter((s) => s.user_id === S.me.id && s.duration_sec > 0 && s.started_at);
    const tot = mine.reduce((a, s) => a + s.duration_sec, 0); if (!tot) return;
    const amount = myShare(m).amount;
    mine.forEach((s) => { const e = (out[dayKey(s)] ||= { amount: 0, secs: 0 }); e.amount += (amount * s.duration_sec) / tot; e.secs += s.duration_sec; });
  });
  return out;
}
function gainsChart(days, { cum = false, cls = '', every = null, upTo = days.length } = {}) {
  const daily = myDailyGains(); let run = 0;
  const rows = days.map((x) => { const e = daily[ymd(x)] || { amount: 0, secs: 0 }; run += e.amount; return { x, ...e, run }; });
  const shown = rows.slice(0, upTo);
  const total = shown.reduce((a, r) => a + r.amount, 0); const active = shown.filter((r) => r.secs > 0).length;
  const html = total > 0 ? lineChart({
    cls, label: cum ? 'Gains cumulés par jour' : 'Gains par jour',
    labels: rows.map((r, i) => (every ? every(r.x, i) : String(r.x.getDate()))),
    series: [{ color: 'var(--s3)', area: true, values: shown.map((r) => Math.round((cum ? r.run : r.amount) * 100) / 100) }],
    tips: rows.map((r, i) => (i < upTo ? tipHtml(fmtLong(r.x), [['Gain du jour', eur(Math.round(r.amount)), 'var(--s3)'], ['Temps de montage', hm(r.secs)], ['Cumul', eur(Math.round(r.run))]]) : '')),
  }) : '';
  return { html, total, active };
}
function projectBars(list, limit = 0) {
  const sorted = [...list].sort((a, b) => b.amount - a.amount); const max = Math.max(1, ...sorted.map((r) => r.amount));
  const rows = limit ? sorted.slice(0, limit) : sorted;
  return rows.map((r, i) => { const c = client(r.m.client_id); const rate = r.secs >= 300 ? `${eur(Math.round(r.amount / (r.secs / 3600)))}/h` : '–';
    return barRow({ i, attrs: `role="button" tabindex="0" data-open="${r.m.id}"`, lead: `<span class="dot" style="background:${clientColor(c)}"></span>`, name: r.m.title, value: eur(Math.round(r.amount)), small: r.secs ? hm(r.secs) : 'estimation',
      pct: (r.amount / max) * 100, color: clientColor(c),
      tip: tipHtml(r.m.title, [['Client', c?.name || '–'], [r.estimated ? 'Ta part (estimation)' : 'Ta part', eur(Math.round(r.amount))], ['Temps de montage', hm(r.secs)], ['Taux horaire', rate], ['Statut', (STATUS[r.m.status] || [r.m.status])[0]]]) }); }).join('');
}
const myMonthShares = (mo) => S.missions.filter((m) => sameMonth(monthOf(m), mo)).map((m) => ({ m, ...myShare(m) })).filter((r) => r.amount > 0 || r.secs > 0);
// Aperçu sur l'accueil du monteur : 30 derniers jours et meilleurs projets du mois.
function gainsPreview() {
  const t0 = new Date(); t0.setHours(0, 0, 0, 0);
  const days = Array.from({ length: 30 }, (_, i) => addDays(t0, i - 29));
  const g = gainsChart(days, { cls: 'mini', every: (x, i) => ((29 - i) % 7 === 0 ? x.toLocaleDateString('fr-BE', { day: 'numeric', month: 'short' }).replace('.', '') : '') });
  const bars = projectBars(myMonthShares(startOfMonth(t0)), 3);
  return `<div class="card"><div class="card-head"><div><h2>Mes gains</h2><div class="lbl" style="margin-top:3px">30 derniers jours · ${eur(Math.round(g.total))} sur ${g.active} jour${g.active > 1 ? 's' : ''} de montage</div></div><button class="btn sm" data-go="earnings">Détail</button></div>
    ${g.html || emptyArt('Ta courbe de gains apparaît dès ta première session de montage.')}
    ${bars ? `<div class="day-h" style="margin:16px 0 6px">Projets du mois</div><div class="bars">${bars}</div>` : ''}</div>`;
}

// ---------- rendu ----------
function render(anim = false) {
  if (S.loading) return;
  hideTip();
  if (!S.session) return renderLogin();
  if (!S.me || S.me.role === 'none' || !S.me.active) return renderPending();
  S.hash = digest();
  const routes = routesFor();
  if (!S.route || !routes.some((r) => r[0] === S.route)) S.route = routes[0][0];
  const nav = routes.map(([k, t, ic, count, badge]) => `<button class="nav ${S.route === k ? 'on' : ''}" data-go="${k}">${ic}${t}${badge ? `<span class="badge">${badge}</span>` : count ? `<span class="count">${count}</span>` : ''}</button>`).join('');
  const tabs = routes.filter((r) => r[5]).map(([k, t, ic, , badge]) => `<button class="${S.route === k ? 'on' : ''}" data-go="${k}" aria-label="${t}">${ic}<span>${t}</span>${badge ? `<span class="badge">${badge}</span>` : ''}</button>`).join('');
  const role = isAdmin() ? 'Admin' : isClient() ? esc(client(S.me.client_id)?.name || 'Client') : 'Monteur';
  const y = window.scrollY;
  app.innerHTML = `
  <div class="shell">
    <nav class="side" aria-label="Navigation">
      <div class="brand"><div class="logo">${LOGO}</div><div><b>Minima Studio</b><span class="lbl">${role}</span></div></div>
      <div class="navs">${nav}</div>
      <div class="side-foot"><button class="foot" data-act="account" aria-label="Mon compte">${avatar(S.me, 30)}<span style="flex:1;min-width:0;text-align:left"><span class="foot-name">${esc(firstName(S.me))}</span><span class="lbl foot-mail">${esc(S.me.email)}</span></span></button>${themeToggle('s')}</div>
    </nav>
    <main class="${anim ? 'enter' : ''}">
      <div class="mobile-head"><div class="row"><div class="logo">${LOGO}</div><div><b style="font-size:14.5px">Minima Studio</b><div class="lbl" style="font-size:11.5px">${role}</div></div></div>
        <div class="row">${themeToggle('m')}<button class="bell ${S.route === 'notifs' ? 'on' : ''}" data-go="notifs" aria-label="Activité">${I.bell}${unread() ? `<span class="badge">${unread()}</span>` : ''}</button>
        <button class="bell plain" data-act="account" aria-label="Mon compte">${avatar(S.me, 36)}</button></div></div>
      ${page()}
    </main>
    <nav class="tabbar" aria-label="Onglets">${tabs}</nav>
  </div>`;
  if (!anim) window.scrollTo(0, y);
  hideTip(); placeThumbs();
}

function page() {
  switch (S.route) {
    case 'home': return isAdmin() ? homeAdmin() : homeEditor();
    case 'projects': return isClient() ? clientHome() : projectsPage();
    case 'agenda': return agendaPage();
    case 'finance': return financePage();
    case 'earnings': return earningsPage();
    case 'new': return newProjectPage();
    case 'notifs': return notifsPage();
    case 'team': return teamPage();
    default: return '';
  }
}
function header(kicker, title, right = '') {
  return `<div class="top"><div><div class="lbl">${esc(kicker)}</div><h1>${esc(title)}</h1></div>${right}</div>`;
}
// Toutes les cartes ont la même structure (libellé, valeur, pied), même quand le pied est vide : hauteurs et lignes alignées.
function stat(label, value, foot = '', color = 'var(--muted)') {
  const size = value.length > 13 ? ' xlong' : value.length > 8 ? ' long' : '';
  return `<div class="card stat"><div class="lbl" title="${esc(label)}">${esc(label)}</div><div class="big${size}">${esc(value)}</div><div class="foot-note" style="color:${color}">${foot ? esc(foot) : '&nbsp;'}</div></div>`;
}
function missionRow(m, right) {
  const c = client(m.client_id);
  const people = memberIds(m.id).map(profile).filter(Boolean);
  const live = liveSessions().some((s) => s.mission_id === m.id);
  const names = [...people.map(firstName), ...(aiFor(m.id).length ? ['Claude'] : [])];
  const sub = [c?.name, isClient() ? null : names.join(' + ') || (m.status === 'requested' ? null : 'Personne'), deadlineLabel(m)].filter(Boolean).join(' · ');
  return `<div class="item" role="button" tabindex="0" data-open="${m.id}"><span class="dot" style="background:${clientColor(c)}"></span>
    <div class="grow"><div class="t">${esc(m.title)}${live ? ' <span class="dot pulse" style="background:var(--green);width:6px;height:6px;vertical-align:middle"></span>' : ''}</div><div class="s" style="${isLate(m) ? 'color:var(--red)' : ''}">${esc(sub)}</div></div>
    ${right ?? pillFor(m)}</div>`;
}
const listCard = (rows, empty) => `<div class="card flush"><div class="list">${rows || `<div class="empty">${empty}</div>`}</div></div>`;

// --- Accueil admin
function adminTodo() {
  const out = [];
  const add = (rank, color, label, m) => out.push({ rank, color, label, m });
  S.missions.forEach((m) => {
    const f = S.finances[m.id]; const dl = d(m.deadline);
    if (m.status === 'requested') add(0, '#F472B6', 'Demande à valider', m);
    else if (isLate(m)) add(1, '#FF6B6B', 'En retard', m);
    else if (awaitsClient(m)) add(2, '#3DD68C', m.status === 'v1_delivered' ? 'V1 livrée : à vérifier et envoyer au client' : 'Corrections livrées : à vérifier et envoyer', m);
    else if (isOpen(m) && !memberIds(m.id).length) add(3, '#F5A524', 'Aucun monteur assigné', m);
    else if (isOpen(m) && isToday(dl)) add(4, '#F5A524', "Deadline aujourd'hui", m);
    else if (m.status === 'assigned' && !m.rushes_url) add(5, '#4C8DFF', 'Rushes manquants', m);
    if (m.status === 'validated' && f?.client_price && !f.invoiced) add(6, '#A78BFA', `À facturer · ${eur(f.client_price)}`, m);
  });
  return out.sort((a, b) => a.rank - b.rank);
}
const todoRow = (t, extra = '') => `<div class="item" role="button" tabindex="0" data-open="${t.m.id}"><span class="tbar" style="background:${t.color}"></span>
  <div class="grow"><div class="todo-l" style="color:${tint(t.color)}">${esc(t.label)}</div><div class="t">${esc(t.m.title)}</div><div class="s">${esc([client(t.m.client_id)?.name, deadlineLabel(t.m)].filter(Boolean).join(' · '))}</div></div>${extra}</div>`;

function homeAdmin() {
  const now = new Date();
  const month = S.missions.filter((m) => sameMonth(monthOf(m), now) && m.status !== 'requested');
  const billed = month.reduce((a, m) => a + (S.finances[m.id]?.client_price || 0), 0);
  const payout = month.reduce((a, m) => a + editorPayout(m), 0);
  const margin = billed - payout;
  const open = S.missions.filter((m) => isOpen(m) && m.status !== 'requested');
  const late = open.filter(isLate).length;
  const todo = adminTodo();
  return `${header(fmtLong(now), `Bonjour ${firstName(S.me)}`, NEW_BTN)}
  <div class="grid">
    ${stat(`Facturé · ${now.toLocaleDateString('fr-BE', { month: 'long' })}`, eur(billed), `${month.length} mission${month.length > 1 ? 's' : ''}`)}
    ${stat('À payer aux monteurs', eur(Math.round(payout)))}
    ${stat('Ta marge', eur(Math.round(margin)), billed ? `${Math.round((margin / billed) * 100)} % du facturé` : '', margin >= 0 ? 'var(--green)' : 'var(--red)')}
    ${stat('En cours', String(open.length), late ? `${late} en retard` : 'Tout est à l’heure', late ? 'var(--red)' : 'var(--green)')}
  </div>
  <div class="cols">
    <div class="wide stack">
      <div class="card flush"><div class="card-head"><h2>À faire</h2>${pill(todo.length ? `${todo.length} action${todo.length > 1 ? 's' : ''}` : 'Rien en attente', todo.length ? '#F5A524' : '#3DD68C')}</div>
        <div class="list">${todo.slice(0, 8).map((t) => todoRow(t)).join('') || '<div class="empty">Tout est à jour. Rien ne demande ton attention.</div>'}</div></div>
      <div class="card flush"><div class="card-head"><h2>En cours</h2><button class="btn sm" data-go="projects">Tout voir</button></div><div class="list">${open.filter((m) => !isDelivered(m)).slice(0, 6).map((m) => missionRow(m)).join('') || '<div class="empty">Aucune mission en cours.</div>'}</div></div>
    </div>
    <div class="narrow stack">${upcomingCard()}${claudeCard()}${liveCard()}</div>
  </div>
  ${hoursCard(team(), 'Heures par jour')}`;
}
function upcomingCard() {
  const from = new Date(); from.setHours(0, 0, 0, 0); const to = addDays(from, 7);
  const list = S.missions.filter((m) => { const x = d(m.deadline); return x && x >= from && x < to && isOpen(m) && m.status !== 'requested'; });
  const byDay = {}; list.forEach((m) => { (byDay[ymd(d(m.deadline))] ||= []).push(m); });
  const rows = Object.keys(byDay).sort().map((k) => `<div class="day-h">${esc(dayName(fromYmd(k)))}</div>${byDay[k].sort((a, b) => d(a.deadline) - d(b.deadline)).map((m) => evRow(m, true)).join('')}`).join('');
  return `<div class="card"><div class="card-head"><h2>7 prochains jours</h2><button class="btn sm" data-go="agenda">Agenda</button></div>${rows || '<div class="empty" style="padding:6px 0">Aucune deadline cette semaine.</div>'}</div>`;
}
function dayName(x) {
  if (isToday(x)) return "Aujourd'hui";
  if (x.toDateString() === addDays(new Date(), 1).toDateString()) return 'Demain';
  return fmtLong(x);
}
function liveCard() {
  const live = liveSessions();
  const rows = team().map((p) => {
    const s = live.find((x) => x.user_id === p.id);
    const m = s && mission(s.mission_id);
    const last = S.sessions.find((x) => x.user_id === p.id);
    const sub = m ? `${esc(m.title)} · en ce moment` : last ? `Dernière session ${relative(d(last.ended_at || last.started_at))}` : 'Pas encore actif';
    return `<div class="item" ${m ? `role="button" tabindex="0" data-open="${m.id}"` : ''}>${avatar(p, 28)}<div class="grow"><div class="t">${esc(firstName(p))}</div><div class="s">${sub}</div></div>
      <span class="mono" style="font-size:13px;color:${s ? 'var(--green)' : 'var(--muted)'}">${s ? hm(s.duration_sec) : ''}</span></div>`;
  }).join('');
  return `<div class="card flush"><div class="card-head"><h2>En direct</h2>${pill(live.length ? `${live.length} actif${live.length > 1 ? 's' : ''}` : 'Personne', live.length ? '#3DD68C' : '#8B8D94')}</div><div class="list">${rows || '<div class="empty">Aucun membre.</div>'}</div></div>`;
}

// --- Heures effectives par jour (temps mesuré dans Premiere)
function dayKey(s) { return ymd(d(s.started_at)); }
function hoursCard(people, title) {
  const ws = addDays(startOfWeek(new Date()), 7 * S.hoursWeek);
  const days = Array.from({ length: 7 }, (_, i) => addDays(ws, i));
  const ids = people.map((p) => p.id);
  const by = {};
  S.sessions.forEach((s) => { if (!ids.includes(s.user_id)) return; const k = `${s.user_id}|${dayKey(s)}`; by[k] = (by[k] || 0) + (s.duration_sec || 0); });
  const cell = (u, x) => by[`${u}|${ymd(x)}`] || 0;
  const dayTotal = (x) => ids.reduce((a, u) => a + cell(u, x), 0);
  const weekTotal = days.reduce((a, x) => a + dayTotal(x), 0);
  const max = Math.max(3600, ...days.map(dayTotal));
  const lbl = `${ws.getDate()} ${ws.toLocaleDateString('fr-BE', { month: 'short' })} au ${addDays(ws, 6).toLocaleDateString('fr-BE', { day: 'numeric', month: 'short' })}`;
  const nav = `<div class="row" style="gap:6px"><button class="ic sm" data-hweek="-1" aria-label="Semaine précédente">${I.left}</button><span class="lbl" style="min-width:118px;text-align:center">${S.hoursWeek === 0 ? 'Cette semaine' : esc(lbl)}</span><button class="ic sm" data-hweek="1" aria-label="Semaine suivante" ${S.hoursWeek >= 0 ? 'disabled' : ''}>${I.right}</button></div>`;
  const head = `<div class="card-head"><div><h2>${esc(title)}</h2><div class="lbl" style="margin-top:3px">Temps actif dans Premiere · ${hm(weekTotal)} sur la semaine</div></div>${nav}</div>`;
  const bars = `<div class="hbars">${days.map((x) => { const t = dayTotal(x); return `<div class="hb ${isToday(x) ? 'today' : ''}"><span class="hv mono">${t ? hm(t) : ''}</span><div class="hcol"><div style="height:${Math.round((t / max) * 100)}%"></div></div><span class="hd">${x.toLocaleDateString('fr-BE', { weekday: 'short' }).replace('.', '')} ${x.getDate()}</span></div>`; }).join('')}</div>`;
  if (people.length === 1) return `<div class="card">${head}${bars}</div>`;
  const active = people.filter((p) => days.some((x) => cell(p.id, x)));
  const table = `<div class="htab-wrap"><table class="htab"><thead><tr><th></th>${days.map((x) => `<th class="${isToday(x) ? 'today' : ''}">${x.toLocaleDateString('fr-BE', { weekday: 'short' }).replace('.', '')}<b>${x.getDate()}</b></th>`).join('')}<th>Semaine</th></tr></thead><tbody>
    ${active.map((p) => `<tr><td><span class="row" style="gap:8px">${avatar(p, 22)}${esc(p.id === S.me.id ? 'Moi' : firstName(p))}</span></td>${days.map((x) => { const v = cell(p.id, x); return `<td class="mono ${isToday(x) ? 'today' : ''}" style="${v ? `background:rgba(76,141,255,${(0.08 + 0.4 * Math.min(1, v / 28800)).toFixed(2)})` : ''}">${v ? hm(v) : '<span class="muted">·</span>'}</td>`; }).join('')}<td class="mono" style="font-weight:600">${hm(days.reduce((a, x) => a + cell(p.id, x), 0))}</td></tr>`).join('') || `<tr><td colspan="9" class="empty">Aucun temps enregistré cette semaine.</td></tr>`}
    ${active.length > 1 ? `<tr class="tot"><td>Total</td>${days.map((x) => `<td class="mono">${dayTotal(x) ? hm(dayTotal(x)) : ''}</td>`).join('')}<td class="mono">${hm(weekTotal)}</td></tr>` : ''}</tbody></table></div>`;
  return `<div class="card">${head}${table}</div>`;
}

// --- Accueil monteur
function editorTodo() {
  const rank = (m) => (m.status === 'revisions' ? 0 : isLate(m) ? 1 : isToday(d(m.deadline)) ? 2 : m.status === 'editing' ? 3 : m.status === 'assigned' ? 4 : 9);
  const label = (m) => (m.status === 'revisions' ? ['Retours à traiter', '#F5A524'] : isLate(m) ? ['En retard', '#FF6B6B'] : isToday(d(m.deadline)) ? ["À livrer aujourd'hui", '#F5A524'] : m.status === 'editing' ? ['En montage', '#4C8DFF'] : ['À commencer', '#8B8D94']);
  return S.missions.filter((m) => isOpen(m) && !awaitsClient(m) && isMine(m)).sort((a, b) => rank(a) - rank(b) || (d(a.deadline) || 9e15) - (d(b.deadline) || 9e15))
    .map((m) => ({ m, label: label(m)[0], color: label(m)[1] }));
}
function homeEditor() {
  const now = new Date(); const wk = startOfWeek(now);
  const mine = S.sessions.filter((s) => s.user_id === S.me.id);
  const weekSecs = mine.filter((s) => d(s.started_at) >= wk).reduce((a, s) => a + (s.duration_sec || 0), 0);
  const todaySecs = mine.filter((s) => isToday(d(s.started_at))).reduce((a, s) => a + (s.duration_sec || 0), 0);
  const month = S.missions.filter((m) => sameMonth(monthOf(m), now));
  const gains = month.reduce((a, m) => a + myShare(m).amount, 0);
  const todo = editorTodo();
  const waiting = S.missions.filter((m) => awaitsClient(m) && isMine(m));
  const next = todo.filter((t) => t.m.deadline).sort((a, b) => d(a.m.deadline) - d(b.m.deadline))[0];
  const act = (m) => (m.status === 'assigned' ? `<button class="btn sm" data-act="start" data-id="${m.id}">Commencer</button>` : `<button class="btn sm pri" data-act="deliver" data-id="${m.id}">${m.status === 'revisions' ? 'Livrer les corrections' : 'Livrer la V1'}</button>`);
  return `${header(fmtLong(now), `Bonjour ${firstName(S.me)}`)}
  <div class="grid">
    ${stat('Cette semaine', hm(weekSecs), `${hm(todaySecs)} aujourd'hui`)}
    ${stat(`Gains · ${now.toLocaleDateString('fr-BE', { month: 'long' })}`, eur(Math.round(gains)), 'Estimation au temps passé')}
    ${stat('Missions en cours', String(todo.length), waiting.length ? `${waiting.length} en attente du client` : '')}
    ${stat('Prochaine deadline', next ? deadlineLabel(next.m) : '–', next ? next.m.title : 'Rien de prévu', next && isLate(next.m) ? 'var(--red)' : 'var(--muted)')}
  </div>
  <div class="cols">
    <div class="wide stack">
      <div class="card flush"><div class="card-head"><h2>À faire maintenant</h2><span class="lbl">${todo.length}</span></div>
        <div class="list">${todo.map((t) => todoRow(t, act(t.m))).join('') || '<div class="empty">Rien à monter pour le moment.</div>'}</div></div>
      ${waiting.length ? `<div class="card flush"><div class="card-head"><h2>Livrées, en attente du client</h2></div><div class="list">${waiting.map((m) => missionRow(m)).join('')}</div></div>` : ''}
      ${gainsPreview()}
      ${hoursCard([S.me], 'Mes heures par jour')}
    </div>
    <div class="narrow stack">${upcomingCard()}</div>
  </div>`;
}

// --- Projets (admin et monteur)
function projectGroups() {
  const base = S.missions.filter((m) => m.status !== 'requested');
  const g = { open: base.filter((m) => isOpen(m) && !isDelivered(m)), delivered: base.filter((m) => isOpen(m) && isDelivered(m)), done: base.filter((m) => !isOpen(m)), all: base };
  if (isAdmin()) g.requests = S.missions.filter((m) => m.status === 'requested');
  return g;
}
function projectRows() {
  const g = projectGroups();
  let list = g[S.filter] || g.open;
  if (S.clientFilter) list = list.filter((m) => m.client_id === S.clientFilter);
  const q = S.search.trim().toLowerCase();
  if (q) list = (S.filter === 'requests' ? list : g.all).filter((m) => `${m.title} ${client(m.client_id)?.name || ''} ${memberIds(m.id).map((u) => firstName(profile(u))).join(' ')}`.toLowerCase().includes(q));
  if (S.filter === 'done' && !q) list = [...list].reverse();
  return list.map((m) => missionRow(m)).join('') || `<div class="empty">${q ? 'Aucun résultat.' : S.filter === 'requests' ? 'Aucune demande en attente.' : 'Rien ici.'}</div>`;
}
function projectsPage() {
  const g = projectGroups();
  if (!g[S.filter]) S.filter = 'open';
  const clientsIn = S.clients.filter((c) => g[S.filter].some((m) => m.client_id === c.id));
  const segs = [['open', 'En cours'], ['delivered', 'Livrées'], ['done', 'Terminées'], ['all', 'Toutes']];
  if (isAdmin()) segs.push(['requests', 'Demandes']);
  const seg = segs.map(([k, t]) => `<button class="${S.filter === k ? 'on' : ''}" data-filter="${k}">${t}<span class="n ${k === 'requests' && g[k].length ? 'hot' : ''}">${g[k].length}</span></button>`).join('');
  const chips = clientsIn.length > 1 ? `<div class="chips"><button class="chip ${!S.clientFilter ? 'on' : ''}" data-client="">Tous les clients</button>${clientsIn.map((c) => clientChip(c, S.clientFilter === c.id, 'data-client')).join('')}</div>` : '';
  return `${header(`${g.open.length} en cours · ${g.delivered.length} livrées`, isEditor() ? 'Mes missions' : 'Projets', isAdmin() ? NEW_BTN : '')}
  <div class="toolbar"><div class="seg">${seg}</div><label class="search">${I.search}<input id="proj-search" type="search" placeholder="Rechercher une mission, un client…" value="${esc(S.search)}" aria-label="Rechercher"></label></div>${chips}
  <div class="card flush"><div class="list" id="proj-list">${projectRows()}</div></div>
  ${S.filter === 'requests' ? '<p class="lbl" style="margin-top:14px">Ouvre une demande pour fixer le budget, le prix et le monteur, puis accepte-la. Le client est prévenu automatiquement.</p>' : ''}`;
}
const clientChip = (c, on, attr) => `<button class="chip ${on ? 'on' : ''}" ${attr}="${c.id}" style="${on ? `background:${clientColor(c)}2e;border-color:${clientColor(c)}99` : ''}"><span class="dot" style="background:${clientColor(c)}"></span>${esc(c.name)}</button>`;

// --- Agenda
function agendaBase() {
  let list = S.missions.filter((m) => isAdmin() || isClient() || isMine(m));
  if (S.agEditor) list = list.filter((m) => memberIds(m.id).includes(S.agEditor));
  if (S.agClient) list = list.filter((m) => m.client_id === S.agClient);
  return list;
}
const evState = (m) => (m.status === 'requested' ? 'req' : !isOpen(m) ? 'done' : isLate(m) ? 'late' : '');
function evRow(m, compact) {
  const c = client(m.client_id); const st = evState(m);
  return `<div class="ev-row ${st} ${compact === true ? 'compact' : ''}" role="button" tabindex="0" data-open="${m.id}" style="--c:${st === 'late' ? '#FF6B6B' : clientColor(c)}">
    <span class="tm mono">${d(m.deadline) ? fmtTime(d(m.deadline)) : '–'}</span>
    <div class="grow"><div class="t">${esc(m.title)}</div><div class="s">${esc(isClient() ? CLIENT_LINE[m.status] || '' : [c?.name, memberIds(m.id).map((u) => firstName(profile(u))).join(' + ')].filter(Boolean).join(' · '))}</div></div>
    ${isClient() ? '' : avatars(memberIds(m.id))}${pillFor(m)}</div>`;
}
function agendaPage() {
  const mobile = isMobile();
  let view = S.view || (mobile ? 'list' : 'month'); if (mobile && view === 'week') view = 'month';
  const all = agendaBase(); const dated = all.filter((m) => m.deadline);
  const byDay = {}; dated.forEach((m) => { (byDay[ymd(d(m.deadline))] ||= []).push(m); });
  Object.values(byDay).forEach((l) => l.sort((a, b) => d(a.deadline) - d(b.deadline)));
  const today = ymd(new Date());
  let from, to, label, body;
  if (view === 'week') { from = startOfWeek(S.agDate); to = addDays(from, 7); label = `${from.getDate()} ${from.getMonth() !== addDays(to, -1).getMonth() ? from.toLocaleDateString('fr-BE', { month: 'short' }) + ' ' : ''}au ${addDays(to, -1).toLocaleDateString('fr-BE', { day: 'numeric', month: 'long' })}`; }
  else { from = startOfMonth(S.agDate); to = new Date(from.getFullYear(), from.getMonth() + 1, 1); label = cap(from.toLocaleDateString('fr-BE', { month: 'long', year: 'numeric' })); }
  const inRange = dated.filter((m) => d(m.deadline) >= from && d(m.deadline) < to);

  if (view === 'month') {
    const start = startOfWeek(from); const weeks = Math.ceil(((from.getDay() + 6) % 7 + new Date(from.getFullYear(), from.getMonth() + 1, 0).getDate()) / 7);
    const cells = Array.from({ length: weeks * 7 }, (_, i) => addDays(start, i)).map((x) => {
      const k = ymd(x); const evs = byDay[k] || []; const out = x.getMonth() !== from.getMonth();
      const chips = evs.slice(0, 3).map((m) => { const st = evState(m); return `<div class="ev ${st}" role="button" tabindex="0" data-open="${m.id}" style="--c:${st === 'late' ? '#FF6B6B' : clientColor(client(m.client_id))}" title="${esc(m.title)}"><span class="tm mono">${fmtTime(d(m.deadline))}</span><span class="tt">${st === 'done' ? '✓ ' : ''}${esc(m.title)}</span></div>`; }).join('');
      const dots = evs.slice(0, 4).map((m) => `<i style="background:${evState(m) === 'late' ? '#FF6B6B' : clientColor(client(m.client_id))}"></i>`).join('');
      return `<div class="cal-d ${out ? 'out' : ''} ${k === today ? 'today' : ''} ${k === S.agDay ? 'sel' : ''} ${x.getDay() % 6 === 0 ? 'we' : ''}" data-day="${k}" role="button" tabindex="0" aria-label="${esc(fmtLong(x))}, ${evs.length} mission${evs.length > 1 ? 's' : ''}">
        <span class="num">${x.getDate()}</span><div class="evs">${chips}${evs.length > 3 ? `<span class="more">+ ${evs.length - 3} autre${evs.length > 4 ? 's' : ''}</span>` : ''}</div><div class="dots">${dots}</div></div>`;
    }).join('');
    const sel = fromYmd(S.agDay); const selEvs = byDay[S.agDay] || [];
    body = `<div class="cal">${['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'].map((x) => `<div class="cal-h">${x}</div>`).join('')}${cells}</div>
      <div class="card" style="margin-top:14px"><div class="card-head"><h2>${esc(dayName(sel))}</h2>${isAdmin() ? `<button class="btn sm" data-act="newmission" data-day="${S.agDay}">${small(I.plus)}Mission ce jour</button>` : `<span class="lbl">${selEvs.length} mission${selEvs.length > 1 ? 's' : ''}</span>`}</div>
        ${selEvs.map(evRow).join('') || '<div class="empty" style="padding:6px 0">Rien de prévu ce jour-là.</div>'}</div>`;
  } else if (view === 'week') {
    body = `<div class="wk">${Array.from({ length: 7 }, (_, i) => addDays(from, i)).map((x) => {
      const k = ymd(x); const evs = byDay[k] || [];
      return `<div class="wk-col ${k === today ? 'today' : ''}"><div class="wk-h"><span>${x.toLocaleDateString('fr-BE', { weekday: 'short' })}</span><b>${x.getDate()}</b>${isAdmin() ? `<button class="wk-add" data-act="newmission" data-day="${k}" aria-label="Nouvelle mission le ${esc(fmtLong(x))}">+</button>` : ''}</div>
        ${evs.map((m) => { const st = evState(m); const c = client(m.client_id); const col = st === 'late' ? '#FF6B6B' : clientColor(c);
          return `<div class="wk-card ${st}" role="button" tabindex="0" data-open="${m.id}" style="--c:${col}"><div class="wk-c">${esc(c?.name || '')}</div><div class="wk-t">${esc(m.title)}</div>
            <div class="wk-f"><span class="mono">${fmtTime(d(m.deadline))}</span>${isClient() ? '' : avatars(memberIds(m.id), 18)}</div>${pillFor(m)}</div>`; }).join('') || '<div class="wk-empty">Libre</div>'}</div>`;
    }).join('')}</div>`;
  } else {
    const t0 = new Date(); t0.setHours(0, 0, 0, 0); const wkEnd = addDays(startOfWeek(t0), 7);
    const groups = [['En retard', (m) => isLate(m)], ["Aujourd'hui", (m) => isToday(d(m.deadline))], ['Demain', (m) => ymd(d(m.deadline)) === ymd(addDays(t0, 1))],
      ['Cette semaine', (m) => d(m.deadline) >= t0 && d(m.deadline) < wkEnd], ['Semaine prochaine', (m) => d(m.deadline) >= wkEnd && d(m.deadline) < addDays(wkEnd, 7)], ['Plus tard', (m) => d(m.deadline) >= addDays(wkEnd, 7)]];
    const pool = dated.filter((m) => isOpen(m) || d(m.deadline) >= t0); const used = new Set();
    body = groups.map(([t, fn], gi) => {
      const l = pool.filter((m) => !used.has(m.id) && fn(m)); l.forEach((m) => used.add(m.id));
      if (!l.length) return '';
      const days = {}; l.forEach((m) => { (days[ymd(d(m.deadline))] ||= []).push(m); });
      const single = Object.keys(days).length === 1 && gi > 0 && gi < 3;
      return `<div class="card" style="margin-bottom:12px"><div class="card-head"><h2 style="${gi === 0 ? 'color:var(--red)' : ''}">${t}</h2><span class="lbl">${l.length}</span></div>${Object.keys(days).sort().map((k) => `${single ? '' : `<div class="day-h">${esc(fmtLong(fromYmd(k)))}</div>`}${days[k].map(evRow).join('')}`).join('')}</div>`;
    }).join('');
    const nodate = all.filter((m) => !m.deadline && isOpen(m));
    if (nodate.length) body += `<div class="card"><div class="card-head"><h2>Sans deadline</h2><span class="lbl">${nodate.length}</span></div>${nodate.map(evRow).join('')}</div>`;
    body = body || '<div class="card"><div class="empty">Aucune deadline à venir.</div></div>';
  }

  const views = (mobile ? [['month', 'Mois'], ['list', 'Liste']] : [['month', 'Mois'], ['week', 'Semaine'], ['list', 'Liste']]).map(([k, t]) => `<button class="${view === k ? 'on' : ''}" data-view="${k}">${t}</button>`).join('');
  const nav = view === 'list' ? '' : `<div class="cal-nav"><button class="ic" data-ag="-1" aria-label="Précédent">${I.left}</button><b>${esc(label)}</b><button class="ic" data-ag="1" aria-label="Suivant">${I.right}</button><button class="btn sm" data-ag="0">Aujourd'hui</button></div>`;
  const openIn = inRange.filter((m) => isOpen(m) && m.status !== 'requested');
  const count = (u) => openIn.filter((m) => memberIds(m.id).includes(u)).length;
  const people = isAdmin() && team().length > 1 ? `<button class="chip ${!S.agEditor ? 'on' : ''}" data-ag-editor="">Toute l'équipe</button>${team().map((p) => `<button class="chip ${S.agEditor === p.id ? 'on' : ''}" data-ag-editor="${p.id}">${avatar(p, 18)}${esc(firstName(p))}${view !== 'list' && count(p.id) ? `<span class="n">${count(p.id)}</span>` : ''}</button>`).join('')}` : '';
  const cl = S.clients.filter((c) => all.some((m) => m.client_id === c.id) || S.agClient === c.id);
  const clients = !isClient() && cl.length > 1 ? `${people ? '<span class="chip-sep"></span>' : ''}<button class="chip ${!S.agClient ? 'on' : ''}" data-ag-client="">Tous les clients</button>${cl.map((c) => clientChip(c, S.agClient === c.id, 'data-ag-client')).join('')}` : '';
  const late = inRange.filter(isLate).length;
  const kicker = view === 'list' ? `${dated.filter(isOpen).length} deadline${dated.filter(isOpen).length > 1 ? 's' : ''} à venir` : `${inRange.length} deadline${inRange.length > 1 ? 's' : ''}${late ? ` · ${late} en retard` : ''} · ${inRange.filter((m) => !isOpen(m)).length} terminée${inRange.filter((m) => !isOpen(m)).length > 1 ? 's' : ''}`;
  return `${header(kicker, isClient() ? 'Calendrier' : 'Agenda', `<div class="seg">${views}</div>`)}
  ${nav}${people || clients ? `<div class="chips">${people}${clients}</div>` : ''}${body}
  <div class="legend"><span><i class="lg" style="background:var(--red)"></i>En retard</span><span><i class="lg" style="background:var(--muted);opacity:.5"></i>Terminée</span>${isAdmin() ? '<span><i class="lg dash"></i>Demande client</span>' : ''}<span>La couleur est celle du client.</span></div>`;
}

// --- Finances (admin)
function financePage() {
  const mo = S.month;
  const list = S.missions.filter((m) => m.status !== 'requested' && sameMonth(monthOf(m), mo));
  const billed = list.reduce((a, m) => a + (S.finances[m.id]?.client_price || 0), 0);
  const payout = list.reduce((a, m) => a + editorPayout(m), 0);
  const toBill = list.filter((m) => S.finances[m.id]?.client_price && !S.finances[m.id]?.invoiced);
  const rows = list.map((m) => {
    const f = S.finances[m.id]; const p = f?.client_price; const pay = editorPayout(m);
    return `<div class="item" role="button" tabindex="0" data-open="${m.id}"><span class="dot" style="background:${clientColor(client(m.client_id))}"></span>
      <div class="grow"><div class="t">${esc(m.title)}</div><div class="s">${esc(client(m.client_id)?.name || 'Sans client')} · ${p ? eur(p) : 'prix à renseigner'} → ${eur(Math.round(pay))}</div></div>
      <div class="mono" style="flex-shrink:0;font-weight:600;color:${p == null ? 'var(--muted)' : p - pay >= 0 ? 'var(--green)' : 'var(--red)'}">${p == null ? '–' : eur(Math.round(p - pay))}</div>
      ${p ? `<button class="btn sm ${f.invoiced ? 'ok' : ''}" data-act="invoice" data-id="${m.id}" aria-pressed="${!!f.invoiced}">${f.invoiced ? `${small(I.check)}Facturée` : 'Facturer'}</button>` : ''}</div>`;
  }).join('');
  return `${header('Visible uniquement par toi', 'Finances', monthSeg(mo))}
  <div class="grid">
    ${stat('Facturé aux clients', eur(billed), `${list.length} mission${list.length > 1 ? 's' : ''} · HTVA`)}
    ${stat('Reversé aux monteurs', eur(Math.round(payout)), billed ? `${Math.round((payout / billed) * 100)} % du facturé` : '')}
    ${stat('Ta marge', eur(Math.round(billed - payout)), billed ? `${Math.round(((billed - payout) / billed) * 100)} % du facturé` : '', 'var(--green)')}
    ${stat('À facturer', String(toBill.length), toBill.length ? eur(toBill.reduce((a, m) => a + S.finances[m.id].client_price, 0)) : 'Tout est facturé')}
  </div>
  ${financeCharts(mo, list)}
  <div class="card flush"><div class="card-head"><h2>Missions de ${esc(mo.toLocaleDateString('fr-BE', { month: 'long' }))}</h2><span class="lbl">Marge</span></div><div class="list">${rows || '<div class="empty">Aucune mission ce mois-ci.</div>'}</div></div>`;
}
function monthSeg(mo) {
  const label = cap(mo.toLocaleDateString('fr-BE', { month: 'long', year: 'numeric' }));
  return `<div class="seg"><button data-month="-1" aria-label="Mois précédent">‹</button><button class="on" style="min-width:140px">${esc(label)}</button><button data-month="1" aria-label="Mois suivant">›</button></div>`;
}

// --- Revenus (monteur)
function earningsPage() {
  const mo = S.month;
  const list = myMonthShares(mo);
  const today = new Date(); const nDays = new Date(mo.getFullYear(), mo.getMonth() + 1, 0).getDate();
  const days = Array.from({ length: nDays }, (_, i) => new Date(mo.getFullYear(), mo.getMonth(), i + 1));
  const cum = S.earnMode === 'cum';
  const g = gainsChart(days, { cum, upTo: sameMonth(today, mo) ? today.getDate() : mo > today ? 0 : nDays, every: (x) => (x.getDate() === 1 || x.getDate() % 5 === 0 ? String(x.getDate()) : '') });
  const bars = projectBars(list);
  const total = list.reduce((a, r) => a + r.amount, 0); const secs = list.reduce((a, r) => a + r.secs, 0);
  const sure = list.filter((r) => !isOpen(r.m)).reduce((a, r) => a + r.amount, 0);
  const rows = list.map((r) => `<div class="item" role="button" tabindex="0" data-open="${r.m.id}"><span class="dot" style="background:${clientColor(client(r.m.client_id))}"></span>
    <div class="grow"><div class="t">${esc(r.m.title)}</div><div class="s">${esc(client(r.m.client_id)?.name || '')} · ${hm(r.secs)}${r.secs >= 300 ? ` · ${eur(Math.round(r.amount / (r.secs / 3600)))}/h` : ''}${r.estimated ? ' · estimation' : ''}</div></div>
    <div class="mono" style="flex-shrink:0;font-weight:600;color:var(--green)">${eur(Math.round(r.amount))}</div><span class="hide-m">${statusPill(r.m.status)}</span></div>`).join('');
  return `${header('Ta part sur chaque mission', 'Mes revenus', monthSeg(mo))}
  <div class="grid">
    ${stat('Gains du mois', eur(Math.round(total)), `${list.length} mission${list.length > 1 ? 's' : ''}`)}
    ${stat('Déjà validé', eur(Math.round(sure)), total ? `${Math.round((sure / total) * 100)} % du mois` : '', 'var(--green)')}
    ${stat('Temps de montage', hm(secs))}
    ${stat('Taux horaire moyen', secs >= 600 ? `${eur(Math.round(total / (secs / 3600)))}/h` : '–')}
  </div>
  <div class="card" style="margin-bottom:16px"><div class="ch-head"><div><h2>${cum ? 'Gains cumulés' : 'Gains par jour'}</h2><div class="lbl">${g.total > 0 ? `${eur(Math.round(g.total))} gagnés sur ${g.active} jour${g.active > 1 ? 's' : ''} de montage` : 'Selon tes sessions de montage'}</div></div>
      <div class="seg mini"><button class="${cum ? '' : 'on'}" data-set="earnMode:day">Par jour</button><button class="${cum ? 'on' : ''}" data-set="earnMode:cum">Cumulé</button></div></div>
    ${g.html || emptyArt('Aucun temps de montage enregistré ce mois-ci.')}
    <p class="hint">La part de chaque mission est répartie sur tes jours de montage, au prorata du temps passé chaque jour. Une mission sans temps enregistré n'apparaît pas encore sur la courbe.</p></div>
  <div class="card" style="margin-bottom:16px"><div class="ch-head"><div><h2>Gains par projet</h2><div class="lbl">Ta part sur les missions de ${esc(mo.toLocaleDateString('fr-BE', { month: 'long' }))}</div></div></div><div class="bars">${bars || emptyArt('Aucune mission ce mois-ci.')}</div></div>
  <div class="card flush"><div class="card-head"><h2>Missions du mois</h2><span class="lbl">Ta part</span></div><div class="list">${rows || '<div class="empty">Aucune mission ce mois-ci.</div>'}</div></div>
  <p class="lbl" style="margin-top:14px">Le budget d'une mission est réparti selon le temps de montage de chacun. Tant que la mission n'est pas terminée, le montant peut encore bouger.</p>`;
}

// --- Client : accueil
function clientCard(m) {
  const col = statusColor(m.status); const ask = awaitsClient(m) && m.delivery_url;
  return `<div class="pcard ${ask ? 'ask' : ''}" role="button" tabindex="0" data-open="${m.id}">
    <div class="row" style="justify-content:space-between;gap:10px"><b class="t">${esc(m.title)}</b>${pillFor(m)}</div>
    <div class="s">${esc(CLIENT_LINE[m.status] || '')}</div>
    <div class="thin" style="margin:12px 0 8px"><div style="width:${PROGRESS[m.status] || 0}%;background:${col}"></div></div>
    <div class="row" style="justify-content:space-between;flex-wrap:wrap"><span class="lbl">${m.deadline ? `Livraison prévue · ${esc(deadlineLabel(m))}` : 'Date à définir'}</span>${ask ? '<span class="cta">Regarder et valider →</span>' : ''}</div></div>`;
}
function clientHome() {
  const c = client(S.me.client_id);
  const ask = S.missions.filter((m) => awaitsClient(m) && m.delivery_url);
  const open = S.missions.filter((m) => isOpen(m) && !ask.includes(m)); const done = S.missions.filter((m) => !isOpen(m));
  return `${header(c?.name || 'Espace client', `Bonjour ${firstName(S.me)}`, `<button class="btn pri" data-go="new">${small(I.plus)}Nouveau projet</button>`)}
  ${ask.length ? `<h2 class="sec">À toi de jouer</h2><div class="pgrid">${ask.map(clientCard).join('')}</div>` : ''}
  <h2 class="sec">En cours</h2>${open.length ? `<div class="pgrid">${open.map(clientCard).join('')}</div>` : `<div class="card"><div class="empty" style="padding:4px 0">${ask.length ? 'Aucun autre projet en cours.' : 'Aucun projet en cours. Propose-en un avec « Nouveau projet ».'}</div></div>`}
  ${done.length ? `<h2 class="sec">Terminés</h2>${listCard(done.map((m) => missionRow(m)).join(''))}` : ''}`;
}

// --- Client : nouveau projet / modification d'une demande
function requestFields(m) {
  const min = new Date(Date.now() + 86400000); min.setMinutes(0, 0, 0);
  const dep = S.settings.rushes_deposit_link;
  return `<label class="f" for="np-title" style="margin-top:0">Nom du projet</label>
    <input class="in" id="np-title" name="title" required placeholder="Ex. Podcast épisode 12" maxlength="120" value="${esc(m?.title || '')}">
    <label class="f" for="np-date">Pour quand ?</label>
    <input class="in" id="np-date" name="deadline" type="datetime-local" value="${m ? (m.deadline ? toLocalInput(d(m.deadline)) : '') : toLocalInput(min)}">
    <label class="f" for="np-brief">Ce que tu veux</label>
    <textarea class="in" id="np-brief" name="brief" placeholder="Format, durée, ton, références, ce qu'il faut couper…">${esc(m?.brief || '')}</textarea>
    <label class="f" for="np-rushes">Lien des rushes (WeTransfer, Drive…)</label>
    <input class="in" id="np-rushes" name="rushes" type="url" inputmode="url" placeholder="https://" value="${esc(m?.rushes_url || '')}">
    ${dep ? `<a class="btn full" href="${esc(dep)}" target="_blank" rel="noopener" style="margin-top:10px">Déposer mes rushes ici ↗</a>` : ''}`;
}
function newProjectPage() {
  return `${header(client(S.me.client_id)?.name || '', 'Nouveau projet')}
  <form class="card" id="new-form" style="max-width:640px">${requestFields(null)}
    <p class="lbl" style="margin:14px 0 18px">Tu peux ajouter le lien des rushes plus tard. Gaston reçoit ta demande et te confirme le lancement.</p>
    <button class="btn pri full" type="submit">Envoyer la demande</button>
  </form>`;
}

// --- Activité
function pushCard() {
  if (TAURI) return '';
  if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
    const ios = /iphone|ipad/i.test(navigator.userAgent);
    return ios ? '<div class="card" style="margin-bottom:16px"><b>Notifications sur iPhone</b><div class="lbl" style="margin-top:6px">Ajoute d\'abord cette page à ton écran d\'accueil (Partager › Sur l\'écran d\'accueil), ouvre-la depuis l\'icône, puis reviens ici.</div></div>' : '';
  }
  if (Notification.permission === 'granted' && S.pushOn) return '';
  if (Notification.permission === 'denied') return '<div class="card" style="margin-bottom:16px"><b>Notifications bloquées</b><div class="lbl" style="margin-top:6px">Autorise-les dans les réglages de ton navigateur ou de ton iPhone pour Minima Studio.</div></div>';
  return '<div class="card" style="margin-bottom:16px;display:flex;align-items:center;gap:14px;flex-wrap:wrap"><div style="flex:1;min-width:200px"><b>Recevoir les notifications</b><div class="lbl" style="margin-top:4px">Nouvelle demande, V1 livrée, retours… directement sur ton téléphone.</div></div><button class="btn pri" data-act="push">Activer</button></div>';
}
const KIND_COLOR = { request: '#F472B6', comment: '#4C8DFF', client: '#3DD68C', deadline: '#F5A524', rushes: '#2DD4BF', brief: '#A78BFA', status: '#8B8D94', member: '#A78BFA' };
function notifsPage() {
  const groups = {}; const t0 = new Date(); t0.setHours(0, 0, 0, 0);
  S.notifs.forEach((n) => { const x = d(n.created_at); const k = x >= t0 ? "Aujourd'hui" : x >= addDays(t0, -1) ? 'Hier' : x >= addDays(t0, -7) ? 'Cette semaine' : 'Plus tôt'; (groups[k] ||= []).push(n); });
  const body = Object.entries(groups).map(([k, l]) => `<div class="day-h">${k}</div>${l.map((n) => `
    <div class="item ${n.read_at ? '' : 'unread'}" role="button" tabindex="0" data-notif="${n.id}" ${n.mission_id && mission(n.mission_id) ? `data-open="${n.mission_id}"` : ''}><span class="dot" style="background:${KIND_COLOR[n.kind] || '#8B8D94'};opacity:${n.read_at ? 0.35 : 1}"></span>
      <div class="grow"><div class="t" style="white-space:normal">${esc(n.title)}</div><div class="s" style="white-space:normal">${esc(n.body || '')}${n.body ? ' · ' : ''}${relative(d(n.created_at))}</div></div></div>`).join('')}`).join('');
  return `${header(unread() ? `${unread()} non lue${unread() > 1 ? 's' : ''}` : 'Tout est lu', 'Activité', unread() ? '<button class="btn" data-act="readall">Tout marquer lu</button>' : '')}${pushCard()}
  <div class="card flush"><div class="list">${body || '<div class="empty">Rien de neuf.</div>'}</div></div>`;
}

// --- Équipe (admin)
const ROLE_LABEL = { admin: 'Admin', editor: 'Monteur', client: 'Client', none: 'Sans accès' };
const ROLE_COLOR = { admin: '#4C8DFF', editor: '#3DD68C', client: '#F472B6', none: '#8B8D94' };
function teamPage() {
  const tabs = [['members', 'Membres'], ['clients', 'Clients'], ['settings', 'Réglages']].map(([k, t]) => `<button class="${S.teamTab === k ? 'on' : ''}" data-teamtab="${k}">${t}</button>`).join('');
  let body = '';
  if (S.teamTab === 'clients') {
    body = `<div class="card flush"><div class="card-head"><h2>Clients</h2><button class="btn sm" data-act="newclient">${small(I.plus)}Ajouter</button></div><div class="list">
      ${S.clients.map((c) => { const ms = S.missions.filter((m) => m.client_id === c.id); const acc = S.profiles.filter((p) => p.role === 'client' && p.active && p.client_id === c.id).length;
        return `<div class="item" role="button" tabindex="0" data-client-open="${c.id}"><span class="dot" style="background:${clientColor(c)};width:12px;height:12px"></span><div class="grow"><div class="t">${esc(c.name)}</div><div class="s">${ms.filter((m) => isOpen(m)).length} en cours · ${ms.length} au total · ${acc ? `${acc} accès à l'espace client` : "pas encore d'accès client"}</div></div><span class="lbl">Modifier</span></div>`; }).join('') || '<div class="empty">Aucun client.</div>'}</div></div>`;
  } else if (S.teamTab === 'settings') {
    body = `<form class="card" id="settings-form" style="max-width:640px"><h2>Liens de dépôt</h2>
      <label class="f" for="st-del">Dépôt du montage (pour les monteurs)</label><input class="in" id="st-del" name="delivery_link" type="url" placeholder="https://" value="${esc(S.settings.delivery_link || '')}">
      <label class="f" for="st-rush">Dépôt des rushes (pour les clients)</label><input class="in" id="st-rush" name="rushes_deposit_link" type="url" placeholder="https://" value="${esc(S.settings.rushes_deposit_link || '')}">
      <p class="lbl" style="margin:12px 0 16px">Le premier lien apparaît dans chaque mission côté monteur. Le second est proposé au client quand il crée ou suit un projet.</p>
      <button class="btn pri" type="submit">Enregistrer</button></form>`;
  } else {
    const members = S.profiles.filter((p) => p.role !== 'none' || !p.active).sort((a, b) => Number(b.active) - Number(a.active) || a.role.localeCompare(b.role));
    const pending = S.invites.filter((i) => !i.accepted_at);
    body = `<form class="card" id="invite-form" style="margin-bottom:16px">
      <h2>Ajouter quelqu'un</h2>
      <div class="cols" style="margin:0;gap:12px"><div style="flex:2 1 220px"><label class="f" for="iv-mail">Adresse e-mail</label><input class="in" id="iv-mail" name="email" type="email" required placeholder="prenom@entreprise.be" autocomplete="off"></div>
      <div style="flex:1 1 150px"><label class="f" for="iv-role">Rôle</label><select class="in" id="iv-role" name="role"><option value="client">Client</option><option value="editor">Monteur</option><option value="admin">Admin</option></select></div>
      <div style="flex:1 1 150px" id="iv-client-wrap"><label class="f" for="iv-client">Client concerné</label><select class="in" id="iv-client" name="client"><option value="">Choisir…</option>${S.clients.map((c) => `<option value="${c.id}">${esc(c.name)}</option>`).join('')}</select></div></div>
      <button class="btn pri" type="submit" style="margin-top:16px">Ajouter</button>
      <p class="lbl" style="margin:10px 0 0">La personne se connecte ensuite avec cette adresse : sur studio.minimalistbelgium.com, ou dans l'app Mac ou PC pour un monteur.</p>
    </form>
    <div class="card flush" style="margin-bottom:16px"><div class="card-head"><h2>Membres</h2><span class="lbl">${members.filter((p) => p.active).length} actifs</span></div><div class="list">
      ${members.map((p) => `<div class="item" role="button" tabindex="0" data-member="${p.id}" style="${p.active ? '' : 'opacity:.5'}">${avatar(p, 30)}<div class="grow"><div class="t">${esc(p.full_name || p.email)}${p.id === S.me.id ? ' (toi)' : ''}</div><div class="s">${esc(p.email)}${p.role === 'client' ? ` · ${esc(client(p.client_id)?.name || 'client non relié')}` : ''}</div></div>${pill(p.active ? ROLE_LABEL[p.role] || p.role : 'Désactivé', p.active ? ROLE_COLOR[p.role] : '#8B8D94')}</div>`).join('')}
    </div></div>
    ${pending.length ? `<div class="card flush"><div class="card-head"><h2>Invitations en attente</h2></div><div class="list">${pending.map((i) => `<div class="item"><div class="grow"><div class="t">${esc(i.email)}</div><div class="s">${ROLE_LABEL[i.role] || ''}${i.client_id ? ` · ${esc(client(i.client_id)?.name || '')}` : ''}</div></div><button class="btn sm" data-uninvite="${esc(i.email)}">Annuler</button></div>`).join('')}</div></div>` : ''}`;
  }
  return `${header(`${S.profiles.filter((p) => p.active && p.role !== 'none').length} personnes · ${S.clients.length} clients`, 'Équipe', `<div class="seg">${tabs}</div>`)}${body}`;
}

// ---------- feuilles ----------
function setSheet(sheet) { S.sheet = sheet; S.openId = sheet?.type === 'mission' && sheet.mode === 'view' ? sheet.id : null; }
function openSheet(sheet) { setSheet(sheet); renderSheet(); }
function openMission(id, mode = 'view') {
  if (!mission(id)) return;
  if (!S.comments[id]) loadComments(id);
  openSheet({ type: 'mission', id, mode });
}
function closeSheet() { sheetRoot.innerHTML = ''; setSheet(null); lockScroll(false); }
// Bloque le défilement de la page sous une feuille, sans décalage quand la barre de défilement disparaît.
function lockScroll(on) {
  const b = document.body;
  if (!on) { b.style.overflow = ''; b.style.paddingRight = ''; return; }
  if (b.style.overflow === 'hidden') return;
  const gap = window.innerWidth - document.documentElement.clientWidth;
  b.style.overflow = 'hidden'; if (gap > 0) b.style.paddingRight = `${gap}px`;
}
function sheetWrap(kicker, title, sub, body, keep, narrow) {
  const y = sheetRoot.querySelector('.sheet')?.scrollTop || 0;
  sheetRoot.innerHTML = `<div class="scrim ${keep ? 'noanim' : ''}" data-close><div class="sheet-box ${keep ? 'noanim' : ''}" role="dialog" aria-modal="true" aria-label="${esc(title)}" ${narrow ? 'style="max-width:640px"' : ''}>
    <div class="grab"></div>
    <div class="sheet"><div class="sheet-head"><div style="flex:1;min-width:0"><div class="lbl">${esc(kicker)}</div><h2>${esc(title)}</h2>${sub}</div><button class="x" data-close aria-label="Fermer">×</button></div>
    ${body}</div></div></div>`;
  lockScroll(true);
  if (keep) sheetRoot.querySelector('.sheet').scrollTop = y;
  placeThumbs(false);
}
function renderSheet(keep = false) {
  const s = S.sheet; if (!s) return;
  if (s.type === 'mission') {
    const m = mission(s.id); if (!m) return closeSheet();
    const c = client(m.client_id);
    if (s.mode === 'edit') return sheetWrap(c?.name || '', isClient() ? 'Modifier ma demande' : 'Modifier la mission', '', isClient() ? requestEditForm(m) : missionForm(m, 'edit'), keep, true);
    const sub = `<div class="row" style="flex-wrap:wrap">${pillFor(m)}<span class="lbl" style="${isLate(m) ? 'color:var(--red)' : ''}">${esc(deadlineLabel(m))}</span></div>`;
    const body = isClient() ? clientDetail(m) : m.status === 'requested' && isAdmin() ? missionForm(m, 'accept') : teamDetail(m);
    return sheetWrap(c?.name || 'Sans client', m.title, sub, body, keep);
  }
  if (s.type === 'new') return sheetWrap('Minima Studio', 'Nouvelle mission', '', missionForm(s.preset || null, 'new'), keep, true);
  if (s.type === 'member') return sheetWrap('Équipe', profile(s.id)?.full_name || profile(s.id)?.email || '', '', memberForm(profile(s.id)), keep, true);
  if (s.type === 'client') return sheetWrap('Clients', s.id ? client(s.id)?.name || '' : 'Nouveau client', '', clientForm(s.id ? client(s.id) : null), keep, true);
  if (s.type === 'account') return sheetWrap(isAdmin() ? 'Admin' : isClient() ? client(S.me.client_id)?.name || 'Client' : 'Monteur', 'Mon compte', '', accountBody(), keep, true);
}
async function loadComments(id) {
  const { data } = await sb.from('mission_comments').select('*').eq('mission_id', id).order('created_at');
  S.comments[id] = data || [];
  if (S.sheet?.type === 'mission' && S.sheet.id === id && S.sheet.mode === 'view' && !typing(sheetRoot)) keepFields(sheetRoot, () => renderSheet(true));
}
function commentsCard(m) {
  const list = S.comments[m.id];
  const who = (c) => (c.author === S.me.id ? 'Toi' : profile(c.author) ? firstName(profile(c.author)) : (isClient() ? 'Minimalist Belgium' : client(m.client_id)?.name || 'Client'));
  const tag = (c) => (c.kind === 'approve' ? pill('Validé', '#3DD68C') : c.kind === 'changes' ? pill('Retours', '#F5A524') : '');
  return `<div class="card"><h2 style="margin-bottom:6px">Échanges</h2>
    ${list == null ? '<div class="empty">Chargement…</div>' : list.map((c) => `<div class="msg ${c.author === S.me.id ? 'me' : ''}"><div class="row" style="gap:8px"><b style="font-size:13px">${esc(who(c))}</b>${tag(c)}<span class="lbl" style="font-size:11.5px">${relative(d(c.created_at))}</span></div><div class="msg-b">${esc(c.body)}</div></div>`).join('') || '<div class="empty">Aucun message pour l\'instant.</div>'}
    <form data-comment="${m.id}" style="display:flex;gap:8px;margin-top:12px"><input class="in" name="body" placeholder="Écrire un message…" aria-label="Message" style="min-height:42px" autocomplete="off"><button class="btn" type="submit" style="min-height:42px">Envoyer</button></form></div>`;
}
function versionsList(m, skipLast) {
  const all = S.versions[m.id] || []; const list = (skipLast ? all.slice(0, -1) : all).slice().reverse();
  return list.map((v, i) => `<div class="kv"><span class="row">${pill(v.label, !skipLast && i === 0 ? '#3DD68C' : '#8B8D94')}<span class="lbl">${fmtDay(d(v.created_at))} ${fmtTime(d(v.created_at))}${!isClient() && profile(v.created_by) ? ` · ${esc(firstName(profile(v.created_by)))}` : ''}</span></span><a href="${esc(v.url)}" target="_blank" rel="noopener">Ouvrir ↗</a></div>`).join('');
}
function stepsHtml(m, labels) {
  const cur = stepIndex(m.status);
  return `<div class="card"><div class="steps">${STEPS.map((s, i) => {
    const done = i < cur && m.status !== 'requested', now = i === cur && m.status !== 'requested';
    const col = now ? statusColor(m.status) : done ? 'var(--green)' : 'var(--track)';
    return `<div class="step"><div class="bar" style="background:${col}"></div><div class="n" style="color:${now ? tint(col) : done ? 'var(--text)' : 'var(--muted)'}">${esc(labels(s, now))}</div></div>`;
  }).join('')}</div></div>`;
}
function linkBlock(title, url, action, color, editable, field, extra = '') {
  return `<div class="card" style="flex:1 1 240px"><div class="card-head" style="margin-bottom:10px"><h2>${title}</h2></div>
    ${url ? `<a class="btn full tinted" href="${esc(url)}" target="_blank" rel="noopener" style="--c:${color}">${action}<span>↗</span></a>` : '<div class="lbl" style="min-height:44px;display:flex;align-items:center">Pas encore de lien.</div>'}
    ${editable ? `<form data-link="${field}" style="display:flex;gap:8px;margin-top:10px"><input class="in" name="url" type="url" placeholder="${url ? 'Remplacer le lien' : 'Coller le lien'}" aria-label="${title} : lien" style="min-height:40px"><button class="btn" type="submit" style="min-height:40px">OK</button></form>` : ''}${extra}</div>`;
}

function clientDetail(m) {
  const labels = (s, now) => (now ? CLIENT_STATUS[m.status] : { assigned: 'Lancé', editing: 'Montage', v1_delivered: 'V1', revisions: 'Retours', validated: 'Terminé', paid: 'Facturé' }[s]);
  const vs = S.versions[m.id] || []; const last = vs[vs.length - 1]; const dep = S.settings.rushes_deposit_link;
  const top = m.status === 'requested'
    ? `<div class="card next" style="--c:#F472B6"><b>Demande envoyée</b><div class="lbl" style="margin-top:6px">Gaston regarde ta demande et te confirme le lancement. Tu peux encore la modifier.</div>
        <div class="row" style="margin-top:14px;flex-wrap:wrap"><button class="btn" data-act="edit" data-id="${m.id}">${small(I.edit)}Modifier ma demande</button><button class="btn danger" data-act="cancelrequest" data-id="${m.id}">Annuler la demande</button></div></div>`
    : stepsHtml(m, labels);
  const video = m.delivery_url ? `<div class="card next" style="--c:#3DD68C"><div class="card-head" style="margin-bottom:4px"><h2>Ta vidéo${last ? ` · ${esc(last.label)}` : ''}</h2>${awaitsClient(m) ? pill('À toi de jouer', '#3DD68C') : ''}</div>
    <a class="btn green full" href="${esc(m.delivery_url)}" target="_blank" rel="noopener" style="margin-top:10px">Regarder la version ↗</a>
    ${awaitsClient(m) ? `<form id="feedback-form" data-id="${m.id}" style="margin-top:14px"><label class="f" for="fb" style="margin-top:0">Tes retours (si tu en as)</label><textarea class="in" id="fb" name="msg" placeholder="Ex. à 2:14, couper la phrase… / changer la musique…" style="min-height:90px"></textarea>
      <div style="display:flex;gap:10px;margin-top:12px;flex-wrap:wrap"><button class="btn green" type="submit" name="approve" value="1" style="flex:1">Valider la vidéo</button><button class="btn" type="submit" name="approve" value="0" style="flex:1">Envoyer mes retours</button></div></form>` : ''}
    ${vs.length > 1 ? `<div class="lbl" style="margin-top:16px">Versions précédentes</div>${versionsList(m, true)}` : ''}</div>` : '';
  return `<div class="stack">${top}${video}
  <div class="cols" style="margin:0">${linkBlock('Tes rushes', m.rushes_url, 'Voir le lien', '#4C8DFF', true, 'client_rushes', dep ? `<a class="lnk" href="${esc(dep)}" target="_blank" rel="noopener">Ou déposer mes fichiers ici ↗</a>` : '')}</div>
  ${m.brief ? `<div class="card"><h2 style="margin-bottom:10px">Brief</h2><div class="brief">${esc(m.brief)}</div></div>` : ''}
  ${m.status !== 'requested' ? commentsCard(m) : ''}</div>`;
}
function requestEditForm(m) {
  return `<form class="card" id="request-edit-form" data-id="${m.id}">${requestFields(m)}
    <div class="row" style="margin-top:18px"><button class="btn pri" type="submit" style="flex:2">Enregistrer</button><button class="btn" type="button" data-act="view" data-id="${m.id}" style="flex:1">Annuler</button></div></form>`;
}

function nextStep(m) {
  const f = S.finances[m.id]; const can = isAdmin() || isMine(m);
  const b = (act, label, cls = 'pri') => `<button class="btn ${cls}" data-act="${act}" data-id="${m.id}">${label}</button>`;
  switch (m.status) {
    case 'assigned': return can ? [m.rushes_url ? 'Les rushes sont là : le montage peut commencer.' : 'Les rushes ne sont pas encore arrivés.', b('start', 'Commencer le montage')] : null;
    case 'editing': return can ? ['Quand la V1 est prête, colle son lien. Le statut passe tout seul à « V1 livrée ».', b('deliver', 'Livrer la V1')] : null;
    case 'revisions': return can ? ['Le client a envoyé ses retours (voir Échanges).', b('deliver', 'Livrer les corrections')] : null;
    case 'v1_delivered': case 'fix_delivered':
      return isAdmin() ? ['Vérifie la version, puis préviens le client pour qu\'il la valide.', b('notifyclient', 'Prévenir le client') + b('validate', 'Marquer validée', '')] : ['Livré. En attente de la validation du client.', ''];
    case 'validated':
      if (!isAdmin()) return ['Validée par le client. Bravo !', ''];
      return f?.client_price && !f.invoiced ? ['Validée. Il reste à facturer le client.', b('invoice', 'Marquer facturée')] : ['Validée et facturée. Passe-la en « Payée » quand le paiement arrive.', b('paid', 'Marquer payée')];
    default: return null;
  }
}
// ---------- Claude monteur ----------
const CLAUDE = '#D97757';
const aiFor = (mid) => S.ai.filter((a) => a.mission_id === mid);
const claudeAvatar = (size = 26) => `<span class="av claude" style="width:${size}px;height:${size}px;font-size:${Math.round(size * 0.55)}px" aria-label="Claude">✳</span>`;
// Temps humain de référence : moyenne des 5 dernières missions livrées du même podcast (même client), montées sans Claude.
function humanReference(m) {
  const done = ['v1_delivered', 'revisions', 'fix_delivered', 'validated', 'paid'];
  const refs = S.missions.filter((x) => x.id !== m.id && x.client_id === m.client_id && done.includes(x.status) && !aiFor(x.id).length)
    .map((x) => ({ x, secs: missionSessions(x.id).reduce((a, s) => a + (s.duration_sec || 0), 0) }))
    .filter((r) => r.secs >= 600)
    .sort((a, b) => d(b.x.v1_delivered_at || b.x.created_at) - d(a.x.v1_delivered_at || a.x.created_at)).slice(0, 5);
  return refs.length ? { secs: refs.reduce((a, r) => a + r.secs, 0) / refs.length, n: refs.length } : null;
}
function claudeSaved(m) {
  const ai = aiFor(m.id).reduce((a, w) => a + (w.duration_sec || 0), 0); const ref = humanReference(m);
  return ref ? { saved: Math.max(0, ref.secs - ai), ref } : null;
}
function claudeCard() {
  if (!isAdmin() || !S.ai.length) return '';
  const now = new Date(); const month = S.ai.filter((w) => sameMonth(d(w.ended_at), now));
  const ids = [...new Set(month.map((w) => w.mission_id))].filter(mission);
  const time = month.reduce((a, w) => a + (w.duration_sec || 0), 0);
  const saved = ids.reduce((a, id) => a + (claudeSaved(mission(id))?.saved || 0), 0);
  const last = S.ai.find((w) => mission(w.mission_id));
  return `<div class="card claude-card"><div class="card-head"><h2 class="row" style="gap:8px">${claudeAvatar(22)}Claude</h2><span class="lbl">ce mois</span></div>
    <div class="claude-nums"><div><div class="big">${ids.length}</div><div class="lbl">montage${ids.length > 1 ? 's' : ''}</div></div><div><div class="big">${hm(time)}</div><div class="lbl">de travail</div></div><div><div class="big" style="color:var(--green)">${saved ? hm(saved) : '–'}</div><div class="lbl">gagnées</div></div></div>
    ${last ? `<div class="item" role="button" tabindex="0" data-open="${last.mission_id}" style="border-top:1px solid var(--line);margin-top:12px"><div class="grow"><div class="t">${esc(mission(last.mission_id).title)}</div><div class="s">Dernier montage ${relative(d(last.ended_at))}</div></div></div>` : ''}</div>`;
}

// Qui a monté cette mission, et combien de temps (bandeau en haut de la fiche).
function timeStrip(m) {
  if (m.status === 'requested') return '';
  const by = {};
  missionSessions(m.id).forEach((s) => {
    const r = (by[s.user_id] ||= { u: s.user_id, secs: 0, last: null, live: false });
    r.secs += s.duration_sec || 0;
    const e = d(s.ended_at || s.started_at); if (!r.last || e > r.last) r.last = e;
    if (s.live && d(s.ended_at) && Date.now() - d(s.ended_at).getTime() < 120000) r.live = true;
  });
  aiFor(m.id).forEach((w) => {
    const r = (by.__claude ||= { u: '__claude', secs: 0, last: null, live: false });
    r.secs += w.duration_sec || 0; const e = d(w.ended_at); if (!r.last || e > r.last) r.last = e;
  });
  const rows = Object.values(by).sort((a, b) => b.secs - a.secs);
  const total = rows.reduce((a, r) => a + r.secs, 0);
  const cs = by.__claude ? claudeSaved(m) : null;
  const pal = ['#A78BFA', '#34D399', '#F5A524', '#F472B6', '#2DD4BF', '#FB7185'];
  const eds = rows.filter((r) => profile(r.u)?.role !== 'admin').map((r) => r.u);
  const col = (u) => (u === '__claude' ? CLAUDE : profile(u)?.role === 'admin' ? '#4C8DFF' : pal[eds.filter((x) => x !== '__claude').indexOf(u) % pal.length]);
  const who = (u) => (u === '__claude' ? 'Claude' : u === S.me.id ? 'Toi' : profile(u) ? firstName(profile(u)) : 'Ancien membre');
  const last = (r) => (r.live ? 'en train de monter' : r.last ? (isToday(r.last) ? `dernière session aujourd'hui à ${fmtTime(r.last)}` : `dernière session ${relative(r.last)}`) : '');
  if (!total) return `<div class="card tstrip"><div class="card-head" style="margin:0"><h2>Temps passé</h2><span class="lbl">Personne n'a encore travaillé dessus</span></div></div>`;
  return `<div class="card tstrip"><div class="card-head" style="margin-bottom:10px"><h2>Temps passé</h2><span class="lbl mono">${hm(total)} au total</span></div>
    <div class="tbarline">${rows.map((r) => `<i style="flex:${r.secs};background:${col(r.u)}" title="${esc(who(r.u))} · ${hm(r.secs)}"></i>`).join('')}</div>
    <div class="tpeople">${rows.map((r) => `<div class="tperson ${r.u === '__claude' ? 'ai' : ''}">${r.u === '__claude' ? claudeAvatar(26) : profile(r.u) ? avatar(profile(r.u), 26) : ''}<div><div class="row" style="gap:6px"><span class="dot" style="background:${col(r.u)}"></span><b>${esc(who(r.u))}</b><span class="mono" style="font-weight:600">${hm(r.secs)}</span><span class="lbl">${Math.round((100 * r.secs) / total)} %</span></div><div class="lbl" style="${r.live ? 'color:var(--green)' : ''}">${esc(r.u === '__claude' ? `montage IA ${last(r).replace('dernière session ', '')}` : last(r))}</div></div></div>`).join('')}</div>
    ${cs ? `<div class="claude-saved">${claudeAvatar(18)}<span>Claude t'a fait gagner environ <b>${hm(cs.saved)}</b> sur ce montage</span><span class="lbl">par rapport à la moyenne des ${cs.ref.n} dernier${cs.ref.n > 1 ? 's' : ''} épisode${cs.ref.n > 1 ? 's' : ''} monté${cs.ref.n > 1 ? 's' : ''} à la main (${hm(cs.ref.secs)})</span></div>` : by.__claude ? '<div class="claude-saved"><span class="lbl">Pas encore assez d\'épisodes montés à la main pour estimer le temps gagné.</span></div>' : ''}</div>`;
}

function teamDetail(m) {
  const rows = split(m);
  const ses = missionSessions(m.id).filter((s) => isAdmin() || s.user_id === S.me.id);
  const f = S.finances[m.id];
  const labels = (s, now) => (now ? STATUS[m.status][0] : STATUS[s][0]);
  const step = nextStep(m);
  const statusMenu = isAdmin()
    ? `<label class="f" for="st" style="margin-top:0">Changer le statut</label><select class="in" id="st" data-status="${m.id}">${Object.keys(STATUS).filter((k) => k !== 'requested').map((k) => `<option value="${k}" ${k === m.status ? 'selected' : ''}>${STATUS[k][0]}</option>`).join('')}</select>`
    : `<div class="lbl">Statut</div><div style="margin-top:8px">${statusPill(m.status)}</div>`;
  const me = rows.find((r) => r.u === S.me.id); const share = myShare(m);
  const right = isAdmin()
    ? `<div class="card" style="border-color:rgba(76,141,255,.35)"><div class="card-head"><h2>Répartition</h2>${pill('Calcul auto', '#4C8DFF')}</div>
        <div class="lbl">Budget montage</div><div class="big" style="margin:6px 0 14px">${eur(m.editor_budget)}</div>
        ${rows.length ? `<div style="display:flex;height:10px;border-radius:5px;overflow:hidden;margin-bottom:8px">${rows.map((r, i) => `<div style="width:${r.pct}%;background:${profile(r.u)?.role === 'admin' ? '#4C8DFF' : AV[i % AV.length]}"></div>`).join('')}</div>` : '<div class="lbl">Pas encore de temps enregistré.</div>'}
        ${rows.map((r) => `<div class="kv"><span>${esc(r.u === S.me.id ? 'Toi' : firstName(profile(r.u)))} · ${Math.round(r.pct)} % <span class="lbl">${hm(r.secs)}</span></span><span class="mono" style="font-weight:600">${eur(Math.round(r.amount * 100) / 100)}</span></div>`).join('')}
        ${f?.client_price != null ? `<div class="kv"><span>Prix client</span><span class="mono">${eur(f.client_price)}</span></div><div class="kv"><span>Ta marge</span><span class="mono" style="font-weight:600;color:var(--green)">${eur(Math.round(f.client_price - editorPayout(m)))}</span></div>
          <div class="kv"><span>Facturation</span><button class="btn sm ${f.invoiced ? 'ok' : ''}" data-act="invoice" data-id="${m.id}" aria-pressed="${!!f.invoiced}">${f.invoiced ? `${small(I.check)}Facturée` : 'Marquer facturée'}</button></div>` : '<div class="kv"><span class="lbl">Prix client non renseigné</span><button class="btn sm" data-act="edit" data-id="' + m.id + '">Ajouter</button></div>'}
      </div>`
    : `<div class="card"><div class="lbl">Budget de la mission</div><div class="big" style="margin:6px 0 14px">${eur(m.editor_budget)}</div>
        <div class="kv"><span>Ta part${share.estimated ? ' (estimation)' : ''}</span><span class="mono" style="font-weight:600;color:var(--green)">${eur(Math.round(share.amount * 100) / 100)}</span></div>
        <div class="kv"><span>Ton temps</span><span class="mono">${hm(me?.secs)}</span></div>
        <div class="kv"><span>Ton taux horaire</span><span class="mono">${me && me.secs >= 300 ? `${eur(Math.round(me.amount / (me.secs / 3600)))}/h` : '–'}</span></div></div>`;
  const vs = S.versions[m.id] || [];
  const dep = S.settings.delivery_link;
  return `${isAdmin() ? `<div class="acts"><button class="btn sm" data-act="edit" data-id="${m.id}">${small(I.edit)}Modifier</button><button class="btn sm" data-act="duplicate" data-id="${m.id}">${small(I.copy)}Dupliquer</button><button class="btn sm danger" data-act="delete" data-id="${m.id}">${small(I.trash)}Supprimer</button></div>` : ''}
  <div class="stack">
  ${step ? `<div class="card next" style="--c:${statusColor(m.status)}"><div class="next-in"><div><div class="lbl">Prochaine étape</div><div style="margin-top:4px">${esc(step[0])}</div></div><div class="row" style="flex-wrap:wrap">${step[1]}</div></div></div>` : ''}
  ${timeStrip(m)}
  ${stepsHtml(m, labels)}
  <div class="cols" style="margin:0"><div class="wide stack">
    <div class="cols" style="margin:0">${linkBlock('Rushes', m.rushes_url, 'Télécharger les rushes', '#4C8DFF', isAdmin(), 'rushes')}
      <div class="card" style="flex:1 1 240px"><div class="card-head" style="margin-bottom:10px"><h2>Versions</h2><span class="lbl">${vs.length || ''}</span></div>
        ${versionsList(m) || '<div class="lbl" style="min-height:44px;display:flex;align-items:center">Aucune version livrée.</div>'}
        <form data-link="delivery" style="display:flex;gap:8px;margin-top:10px"><input class="in" name="url" type="url" placeholder="Lien d'une nouvelle version" aria-label="Lien d'une nouvelle version" style="min-height:40px"><button class="btn" type="submit" style="min-height:40px">OK</button></form>
        ${dep ? `<a class="lnk" href="${esc(dep)}" target="_blank" rel="noopener">Déposer mon montage ↗</a>` : ''}</div></div>
    ${m.brief ? `<div class="card"><h2 style="margin-bottom:10px">Brief</h2><div class="brief">${esc(m.brief)}</div></div>` : ''}
    <div class="card"><div class="card-head"><h2>${isAdmin() ? 'Sessions' : 'Mes sessions'}</h2><span class="lbl mono">${hm(ses.reduce((a, s) => a + (s.duration_sec || 0), 0))}</span></div>
      ${ses.slice(0, 10).map((s) => `<div class="kv"><span class="row">${avatar(profile(s.user_id), 22)}${esc(s.user_id === S.me.id ? 'Toi' : firstName(profile(s.user_id)))}</span><span class="lbl">${fmtDay(d(s.started_at))} ${fmtTime(d(s.started_at))}</span><span class="mono">${hm(s.duration_sec)}</span></div>`).join('') || '<div class="empty">Aucune session.</div>'}
      ${ses.length > 10 ? `<div class="lbl" style="margin-top:8px">et ${ses.length - 10} autres sessions</div>` : ''}</div>
    ${commentsCard(m)}
  </div><div class="narrow stack">
    <div class="card">${statusMenu}<div class="lbl" style="margin-top:14px">Équipe</div><div class="row" style="margin-top:8px;flex-wrap:wrap">${memberIds(m.id).map(profile).filter(Boolean).map((p) => `<span class="row" style="gap:6px">${avatar(p, 22)}${esc(firstName(p))}</span>`).join('') || '<span class="lbl">Personne pour l\'instant</span>'}</div></div>
    ${right}
  </div></div></div>`;
}

// Formulaire commun : nouvelle mission, modification, acceptation d'une demande.
function missionForm(m, mode) {
  const f = m?.id ? S.finances[m.id] : null; const picked = m?.id ? memberIds(m.id) : (m?.members || []);
  let dl = m?.deadline ? d(m.deadline) : null;
  if (!dl && mode === 'new') { dl = new Date(Date.now() + 3 * 86400000); dl.setHours(18, 0, 0, 0); }
  const intro = mode === 'accept' ? `<div class="card next" style="--c:#F472B6;margin-bottom:14px"><b>Demande du client</b>
    <div class="lbl" style="margin-top:6px">Envoyée ${relative(d(m.created_at))}${m.rushes_url ? ' · rushes fournis' : ' · pas encore de rushes'}</div>
    ${m.brief ? `<div class="brief" style="margin-top:12px">${esc(m.brief)}</div>` : ''}
    ${m.rushes_url ? `<a class="btn" style="margin-top:12px" href="${esc(m.rushes_url)}" target="_blank" rel="noopener">Voir les rushes ↗</a>` : ''}</div>` : '';
  return `${intro}<form class="card" id="mission-form" data-mode="${mode}" data-id="${m?.id || ''}">
    ${mode === 'accept' ? '<h2 style="margin-bottom:4px">Lancer le projet</h2>' : ''}
    <label class="f" for="nm-client" style="margin-top:0">Client</label>
    <select class="in" id="nm-client" name="client" required ${mode === 'accept' ? 'disabled' : ''}><option value="" disabled ${m?.client_id ? '' : 'selected'}>Choisir le client…</option>${S.clients.map((c) => `<option value="${c.id}" ${m?.client_id === c.id ? 'selected' : ''}>${esc(c.name)}</option>`).join('')}<option value="__new">+ Nouveau client…</option></select>
    <input class="in" id="nm-newclient" name="newclient" placeholder="Nom du nouveau client" aria-label="Nom du nouveau client" style="margin-top:8px;display:none">
    <label class="f" for="nm-title">Titre</label><input class="in" id="nm-title" name="title" required placeholder="Ex. Cover épisode 50" maxlength="120" value="${esc(m?.title || '')}">
    <label class="f" for="nm-dl">Deadline</label><input class="in" id="nm-dl" name="deadline" type="datetime-local" value="${dl ? toLocalInput(dl) : ''}">
    <div class="cols" style="margin:0;gap:12px">
      <div style="flex:1 1 150px"><label class="f" for="nm-price">Prix client HTVA (€)</label><input class="in" id="nm-price" name="price" type="number" inputmode="decimal" min="0" step="1" value="${f?.client_price ?? m?.price ?? ''}"></div>
      <div style="flex:1 1 150px"><label class="f" for="nm-budget">Budget montage (€)</label><input class="in" id="nm-budget" name="budget" type="number" inputmode="decimal" min="0" step="1" required value="${m?.id && mode !== 'accept' ? m.editor_budget ?? '' : m?.editor_budget || ''}"></div>
    </div>
    <label class="f">Qui monte ?</label>
    <div class="pick">${team().map((p) => `<button type="button" data-pick="${p.id}" class="${picked.includes(p.id) ? 'on' : ''}" aria-pressed="${picked.includes(p.id)}">${avatar(p, 22)}${esc(p.id === S.me.id ? 'Moi' : firstName(p))}</button>`).join('')}</div>
    ${mode === 'accept' ? '' : `<label class="f" for="nm-rushes">Lien des rushes</label><input class="in" id="nm-rushes" name="rushes" type="url" inputmode="url" placeholder="https:// (facultatif)" value="${esc(m?.rushes_url || '')}">
    <label class="f" for="nm-brief">Brief</label><textarea class="in" id="nm-brief" name="brief" placeholder="Format, durée, consignes… (facultatif)">${esc(m?.brief || '')}</textarea>`}
    <div class="row" style="margin-top:20px;flex-wrap:wrap">
      <button class="btn pri" type="submit" style="flex:2">${mode === 'new' ? 'Créer la mission' : mode === 'accept' ? 'Accepter et lancer' : 'Enregistrer'}</button>
      ${mode === 'accept' ? `<button class="btn danger" type="button" data-act="refuse" data-id="${m.id}" style="flex:1">Refuser</button>` : mode === 'edit' ? `<button class="btn" type="button" data-act="view" data-id="${m.id}" style="flex:1">Annuler</button>` : ''}</div>
    ${mode === 'new' ? '<p class="lbl" style="margin:10px 0 0">Les monteurs choisis reçoivent une notification.</p>' : ''}
  </form>`;
}
function memberForm(p) {
  if (!p) return '';
  const self = p.id === S.me.id;
  return `<form class="card" id="member-form" data-id="${p.id}">
    <div class="row" style="gap:12px">${avatar(p, 44)}<div><b>${esc(p.full_name || p.email)}</b><div class="lbl">${esc(p.email)}</div></div></div>
    <label class="f" for="mb-role">Rôle</label><select class="in" id="mb-role" name="role" ${self ? 'disabled' : ''}>${['admin', 'editor', 'client'].map((r) => `<option value="${r}" ${p.role === r ? 'selected' : ''}>${ROLE_LABEL[r]}</option>`).join('')}${p.role === 'none' ? '<option value="none" selected>Sans accès</option>' : ''}</select>
    <div id="mb-client-wrap" style="${p.role === 'client' ? '' : 'display:none'}"><label class="f" for="mb-client">Client concerné</label><select class="in" id="mb-client" name="client"><option value="">Choisir…</option>${S.clients.map((c) => `<option value="${c.id}" ${p.client_id === c.id ? 'selected' : ''}>${esc(c.name)}</option>`).join('')}</select></div>
    ${self ? '<p class="lbl" style="margin-top:12px">Tu ne peux pas modifier ton propre rôle.</p>' : ''}
    <div class="row" style="margin-top:20px;flex-wrap:wrap"><button class="btn pri" type="submit" style="flex:2" ${self ? 'disabled' : ''}>Enregistrer</button>
      ${self ? '' : `<button class="btn ${p.active ? 'danger' : ''}" type="button" data-act="toggleactive" data-id="${p.id}" style="flex:1">${p.active ? "Désactiver l'accès" : "Réactiver l'accès"}</button>`}</div></form>`;
}
function clientForm(c) {
  const cur = c ? clientColor(c).toUpperCase() : COLORS[S.clients.length % COLORS.length];
  return `<form class="card" id="client-form" data-id="${c?.id || ''}">
    <label class="f" for="cl-name" style="margin-top:0">Nom</label><input class="in" id="cl-name" name="name" required maxlength="80" value="${esc(c?.name || '')}">
    <label class="f">Couleur dans l'agenda</label><div class="sw">${[...new Set([...COLORS, cur])].map((x) => `<button type="button" data-color="${x}" class="${x.toUpperCase() === cur.toUpperCase() ? 'on' : ''}" style="background:${x}" aria-label="Couleur ${x}"></button>`).join('')}</div>
    <input type="hidden" name="color" value="${cur}">
    <div class="row" style="margin-top:20px;flex-wrap:wrap"><button class="btn pri" type="submit" style="flex:2">${c ? 'Enregistrer' : 'Ajouter le client'}</button>
      ${c ? `<button class="btn danger" type="button" data-act="deleteclient" data-id="${c.id}" style="flex:1">Supprimer</button>` : ''}</div></form>`;
}
function accountBody() {
  const pushable = !TAURI && 'serviceWorker' in navigator && 'PushManager' in window;
  return `<form class="card" id="account-form"><div class="row" style="gap:12px">${avatar(S.me, 48)}<div><b>${esc(S.me.full_name || firstName(S.me))}</b><div class="lbl">${esc(S.me.email)}</div></div></div>
    <label class="f" for="ac-name">Nom affiché</label><div class="row"><input class="in" id="ac-name" name="name" maxlength="60" value="${esc(S.me.full_name || '')}" placeholder="Prénom Nom"><button class="btn" type="submit">Enregistrer</button></div></form>
  ${pushable ? `<div class="card" style="margin-top:14px"><div class="row" style="justify-content:space-between;gap:12px;flex-wrap:wrap"><div><b>Notifications</b><div class="lbl" style="margin-top:4px">${S.pushOn && Notification.permission === 'granted' ? 'Activées sur cet appareil.' : Notification.permission === 'denied' ? 'Bloquées dans les réglages de ton navigateur.' : 'Reçois les nouvelles sur cet appareil.'}</div></div>${S.pushOn && Notification.permission === 'granted' ? pill('Actives', '#3DD68C') : Notification.permission === 'denied' ? '' : '<button class="btn pri" data-act="push">Activer</button>'}</div></div>` : ''}
  <button class="btn full danger" data-act="logout" style="margin-top:14px">${small(I.out)}Se déconnecter</button>`;
}

// ---------- connexion ----------
function renderLogin() {
  app.innerHTML = `<div class="login"><div class="tgl-float">${themeToggle('l')}</div><div class="box">
    <div class="logo big" style="margin:0 auto">${LOGO}</div>
    <h1>Minima Studio</h1><p class="muted" style="margin:0 0 26px">Suivi des projets Minimalist Belgium</p>
    <form id="mail-form"><label class="f" for="em" style="text-align:left;margin-top:0">Ton adresse e-mail</label>
      <input class="in" id="em" name="email" type="email" autocomplete="email" inputmode="email" required placeholder="prenom@entreprise.be">
      <button class="btn pri full" type="submit" style="margin-top:12px">${TAURI ? 'Recevoir un code de connexion' : 'Recevoir un lien de connexion'}</button></form>
    ${TAURI ? '' : '<div class="or">ou</div><button class="btn full" data-act="google">Continuer avec Google</button>'}
    <p class="lbl" style="margin-top:22px">Accès réservé aux clients et à l'équipe de Minimalist Belgium.<br><a href="/confidentialite.html" style="color:inherit">Confidentialité</a></p>
  </div></div>`;
}
function renderPending() {
  app.innerHTML = `<div class="login"><div class="tgl-float">${themeToggle('l')}</div><div class="box"><div class="logo big" style="margin:0 auto">${LOGO}</div>
    <h1>Accès en attente</h1><p class="muted">Ton compte ${esc(S.session?.user?.email || '')} n'est pas encore relié à un projet. Demande à Gaston de t'ajouter, puis reviens ici.</p>
    <button class="btn full" data-act="retry" style="margin-top:18px">Réessayer</button>
    <button class="btn full" data-act="logout" style="margin-top:10px">Se déconnecter</button></div></div>`;
}

// ---------- actions ----------
const fail = (r) => { if (r.error) throw r.error; return r; };
const hasClientAccount = (m) => S.profiles.some((p) => p.role === 'client' && p.active && p.client_id === m.client_id);
async function offerNotifyClient(m, status) {
  if (!isAdmin() || !hasClientAccount(m)) return;
  const msg = { v1_delivered: 'La V1 de ta vidéo est prête', fix_delivered: 'Les corrections de ta vidéo sont prêtes', validated: 'Ta vidéo est finalisée' }[status];
  if (!msg) return;
  if (await dialog({ title: 'Prévenir le client ?', body: `Il recevra : « ${msg} »`, ok: 'Prévenir', cancel: 'Plus tard' })) {
    const r = await sb.rpc('notify_client', { m: m.id, msg });
    toast(r.error ? r.error.message : 'Client prévenu');
  }
}
async function setStatus(m, s) {
  const patch = { status: s };
  if (s === 'v1_delivered' && !m.v1_delivered_at) patch.v1_delivered_at = new Date().toISOString();
  if (s === 'validated' && !m.validated_at) patch.validated_at = new Date().toISOString();
  fail(await sb.from('missions').update(patch).eq('id', m.id));
  await refresh(); toast(`Statut : ${STATUS[s][0]}`);
  await offerNotifyClient(m, s);
}
const ACTIONS = {
  newmission: (t) => { const preset = t.dataset.day ? { deadline: new Date(`${t.dataset.day}T18:00`).toISOString() } : null; openSheet({ type: 'new', preset }); },
  newclient: () => openSheet({ type: 'client', id: null }),
  account: () => openSheet({ type: 'account' }),
  theme: () => toggleTheme(),
  edit: (t) => openMission(t.dataset.id, 'edit'),
  view: (t) => openMission(t.dataset.id),
  push: () => enablePush(),
  retry: () => boot(),
  readall: () => markAll(),
  google: () => sb.auth.signInWithOAuth({ provider: 'google', options: { redirectTo: location.origin } }),
  async logout() { if (await dialog({ title: 'Se déconnecter ?', ok: 'Se déconnecter' })) { await sb.auth.signOut(); location.reload(); } },
  async start(t) { fail(await sb.rpc('editor_set_status', { m: t.dataset.id, s: 'editing' })); await refresh(); toast('C\'est parti : mission en montage'); },
  async deliver(t) {
    const m = mission(t.dataset.id); const fix = m.status === 'revisions';
    const url = await dialog({ title: fix ? 'Livrer les corrections' : 'Livrer la V1', body: 'Colle le lien de la version à montrer (Frame.io, Drive, WeTransfer…).', ok: 'Livrer', input: { type: 'url', placeholder: 'https://', required: true } });
    if (!url) return;
    fail(await sb.rpc('set_delivery_url', { m: m.id, url }));
    const s = fix ? 'fix_delivered' : 'v1_delivered';
    fail(await sb.rpc('editor_set_status', { m: m.id, s }));
    await refresh(); toast(isAdmin() ? 'Version livrée' : "Livré, l'admin est prévenu");
    await offerNotifyClient(m, s);
  },
  async notifyclient(t) {
    const m = mission(t.dataset.id);
    if (!hasClientAccount(m)) return toast("Ce client n'a pas encore d'accès. Ajoute-le dans Équipe.");
    if (!m.delivery_url) return toast("Ajoute d'abord le lien de la version.");
    await offerNotifyClient(m, m.status);
  },
  validate: (t) => setStatus(mission(t.dataset.id), 'validated'),
  paid: (t) => setStatus(mission(t.dataset.id), 'paid'),
  async invoice(t) {
    const f = S.finances[t.dataset.id]; if (!f) return; const was = !!f.invoiced;
    fail(await sb.from('mission_finance').update({ invoiced: !was }).eq('mission_id', t.dataset.id));
    await refresh(); toast(was ? 'Marquée non facturée' : 'Marquée facturée');
  },
  async duplicate(t) {
    const m = mission(t.dataset.id);
    const dl = m.deadline ? addDays(d(m.deadline), 7) : null; if (dl) dl.setHours(d(m.deadline).getHours(), d(m.deadline).getMinutes());
    const title = m.title.replace(/(\d+)(?!.*\d)/, (n) => String(Number(n) + 1));
    const ins = fail(await sb.from('missions').insert({ client_id: m.client_id, title: title === m.title ? `${m.title} (copie)` : title, brief: m.brief, editor_budget: m.editor_budget, deadline: dl?.toISOString() || null, status: 'assigned', admin_weight: m.admin_weight }).select().single());
    const id = ins.data.id; const f = S.finances[m.id];
    if (f?.client_price != null) fail(await sb.from('mission_finance').upsert({ mission_id: id, client_price: f.client_price }));
    const ids = memberIds(m.id);
    if (ids.length) fail(await sb.from('mission_members').insert(ids.map((u) => ({ mission_id: id, user_id: u }))));
    await refresh(); openMission(id, 'edit'); toast('Mission dupliquée : vérifie le titre et la date');
  },
  async delete(t) {
    const m = mission(t.dataset.id); const secs = missionSessions(m.id).reduce((a, s) => a + (s.duration_sec || 0), 0);
    if (!(await dialog({ title: `Supprimer « ${m.title} » ?`, body: `C'est définitif.${secs ? ` Le temps enregistré (${hm(secs)}) sera aussi supprimé.` : ''}`, ok: 'Supprimer', danger: true }))) return;
    fail(await sb.from('missions').delete().eq('id', m.id));
    closeSheet(); await refresh(); toast('Mission supprimée');
  },
  async refuse(t) {
    const reason = await dialog({ title: 'Refuser cette demande ?', body: 'Le client est prévenu. Tu peux lui laisser un mot.', ok: 'Refuser', danger: true, input: { type: 'textarea', placeholder: 'Message pour le client (facultatif)' } });
    if (reason === null) return;
    fail(await sb.rpc('refuse_request', { m: t.dataset.id, reason }));
    closeSheet(); await refresh(); toast('Demande refusée, client prévenu');
  },
  async cancelrequest(t) {
    if (!(await dialog({ title: 'Annuler ta demande ?', body: 'Elle sera retirée. Tu pourras en envoyer une nouvelle quand tu veux.', ok: 'Annuler la demande', cancel: 'Garder', danger: true }))) return;
    fail(await sb.rpc('client_cancel_request', { m: t.dataset.id }));
    closeSheet(); await refresh(); toast('Demande annulée');
  },
  async toggleactive(t) {
    const p = profile(t.dataset.id);
    if (p.active && !(await dialog({ title: `Désactiver l'accès de ${firstName(p)} ?`, body: 'Cette personne ne pourra plus se connecter. Son historique est conservé.', ok: 'Désactiver', danger: true }))) return;
    fail(await sb.from('profiles').update({ active: !p.active }).eq('id', p.id));
    closeSheet(); await refresh(); toast(p.active ? 'Accès désactivé' : 'Accès réactivé');
  },
  async deleteclient(t) {
    const c = client(t.dataset.id);
    if (S.missions.some((m) => m.client_id === c.id)) return toast('Ce client a des missions : impossible de le supprimer.');
    if (!(await dialog({ title: `Supprimer ${c.name} ?`, ok: 'Supprimer', danger: true }))) return;
    fail(await sb.from('clients').delete().eq('id', c.id));
    closeSheet(); await refresh(); toast('Client supprimé');
  },
};

document.addEventListener('click', async (e) => {
  const t = e.target.closest('[data-go],[data-notif],[data-open],[data-hweek],[data-close],[data-act],[data-filter],[data-client],[data-month],[data-pick],[data-uninvite],[data-view],[data-ag],[data-ag-editor],[data-ag-client],[data-day],[data-teamtab],[data-member],[data-client-open],[data-color],[data-set]');
  if (!t) return;
  if (t.hasAttribute('data-close') && e.target !== t && !e.target.closest('button[data-close]')) return; // clic dans la feuille
  const D = t.dataset;
  try {
    if (D.go) { closeSheet(); const same = S.route === D.go; S.route = D.go; render(!same); if (!same) window.scrollTo(0, 0); }
    else if (D.notif) { if (D.open) openMission(D.open); markRead(D.open || null, D.notif); }
    else if (D.open) { openMission(D.open); markRead(D.open); }
    else if (D.hweek) { S.hoursWeek = Math.min(0, S.hoursWeek + Number(D.hweek)); render(); }
    else if (t.hasAttribute('data-close')) closeSheet();
    else if (D.act && ACTIONS[D.act]) { e.preventDefault(); await ACTIONS[D.act](t); }
    else if (D.filter) { S.filter = D.filter; S.clientFilter = ''; render(); }
    else if (D.client !== undefined && t.classList.contains('chip')) { S.clientFilter = D.client; render(); }
    else if (D.month) { S.month = new Date(S.month.getFullYear(), S.month.getMonth() + Number(D.month), 1); render(); }
    else if (D.pick) { t.classList.toggle('on'); t.setAttribute('aria-pressed', t.classList.contains('on')); }
    else if (D.color) { t.parentElement.querySelectorAll('.on').forEach((x) => x.classList.remove('on')); t.classList.add('on'); t.closest('form').elements.color.value = D.color; }
    else if (D.uninvite) { fail(await sb.from('team_invites').delete().eq('email', D.uninvite)); await refresh(); }
    else if (D.view) { S.view = D.view; store.set('msAgendaView', D.view); render(); }
    else if (D.ag !== undefined) {
      const n = Number(D.ag); const week = (S.view || 'month') === 'week' && !isMobile();
      S.agDate = n === 0 ? new Date() : week ? addDays(S.agDate, 7 * n) : new Date(S.agDate.getFullYear(), S.agDate.getMonth() + n, 1);
      S.agDay = n === 0 ? ymd(new Date()) : sameMonth(S.agDate, new Date()) ? ymd(new Date()) : ymd(startOfMonth(S.agDate)); render();
    }
    else if (D.agEditor !== undefined) { S.agEditor = D.agEditor; render(); }
    else if (D.agClient !== undefined) { S.agClient = D.agClient; render(); }
    else if (D.day) { S.agDay = D.day; if (fromYmd(D.day).getMonth() !== S.agDate.getMonth()) S.agDate = fromYmd(D.day); render(); }
    else if (D.teamtab) { S.teamTab = D.teamtab; render(); }
    else if (D.set) { const [k, v] = D.set.split(':'); S[k] = v; render(); }
    else if (D.member) openSheet({ type: 'member', id: D.member });
    else if (D.clientOpen) openSheet({ type: 'client', id: D.clientOpen });
  } catch (err) { toast(err.message || String(err)); }
});
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') { if (dialog.close) dialog.close(); else closeSheet(); }
  else if ((e.key === 'Enter' || e.key === ' ') && e.target.matches('div[role=button]')) { e.preventDefault(); e.target.click(); }
});
document.addEventListener('input', (e) => {
  if (e.target.id === 'proj-search') { S.search = e.target.value; document.getElementById('proj-list').innerHTML = projectRows(); }
});
document.addEventListener('focusout', () => { if (S.pending) setTimeout(softRender, 400); });

document.addEventListener('change', async (e) => {
  const sel = e.target;
  if (sel.id === 'nm-client') { document.getElementById('nm-newclient').style.display = sel.value === '__new' ? 'block' : 'none'; return; }
  if (sel.id === 'iv-role') { document.getElementById('iv-client-wrap').style.display = sel.value === 'client' ? '' : 'none'; return; }
  if (sel.id === 'mb-role') { document.getElementById('mb-client-wrap').style.display = sel.value === 'client' ? '' : 'none'; return; }
  if (sel.dataset.status) { try { await setStatus(mission(sel.dataset.status), sel.value); } catch (err) { toast(err.message || String(err)); } }
});

document.addEventListener('submit', async (e) => {
  const f = e.target; e.preventDefault();
  const btn = e.submitter || f.querySelector('[type=submit]'); if (btn) btn.disabled = true;
  try {
    if (f.id === 'mail-form') {
      const email = f.email.value.trim().toLowerCase();
      fail(await sb.auth.signInWithOtp({ email, options: { emailRedirectTo: location.origin } }));
      f.outerHTML = `<form id="code-form" data-email="${esc(email)}" style="text-align:left"><div class="card"><b>Regarde ta boîte mail</b><div class="lbl" style="margin-top:6px">On vient d'envoyer un e-mail à ${esc(email)}. ${TAURI ? 'Entre le code qu\'il contient :' : 'Clique sur le lien, ou entre le code qu\'il contient :'}</div>
        <input class="in" name="code" inputmode="numeric" autocomplete="one-time-code" placeholder="Code reçu par e-mail" aria-label="Code reçu par e-mail" style="margin-top:12px;letter-spacing:.2em;font-size:18px" required>
        <button class="btn pri full" type="submit" style="margin-top:10px">Se connecter</button></div></form>`;
      document.querySelector('#code-form input')?.focus();
    } else if (f.id === 'code-form') {
      const { error } = await sb.auth.verifyOtp({ email: f.dataset.email, token: f.code.value.replace(/\s/g, ''), type: 'email' });
      if (error) throw new Error('Code incorrect ou expiré');
    } else if (f.id === 'new-form') {
      const dl = f.deadline.value ? new Date(f.deadline.value).toISOString() : null;
      fail(await sb.rpc('client_request_project', { t: f.title.value, d: dl, b: f.brief.value, r: f.rushes.value }));
      f.reset(); S.route = 'projects'; await refresh(); window.scrollTo(0, 0); toast('Demande envoyée, merci !');
    } else if (f.id === 'request-edit-form') {
      const dl = f.deadline.value ? new Date(f.deadline.value).toISOString() : null;
      fail(await sb.rpc('client_update_request', { m: f.dataset.id, t: f.title.value, d: dl, b: f.brief.value, r: f.rushes.value }));
      setSheet({ type: 'mission', id: f.dataset.id, mode: 'view' }); await refresh(); toast('Demande mise à jour');
    } else if (f.id === 'mission-form') {
      await saveMission(f);
    } else if (f.id === 'invite-form') {
      const email = f.email.value.trim().toLowerCase(); const role = f.role.value; const cid = f.client.value || null;
      if (role === 'client' && !cid) throw new Error('Choisis le client concerné');
      fail(await sb.from('team_invites').upsert({ email, role, client_id: role === 'client' ? cid : null }));
      f.reset(); await refresh(); toast('Ajouté, il peut se connecter');
    } else if (f.id === 'member-form') {
      const role = f.role.value; const cid = f.client.value || null;
      if (role === 'client' && !cid) throw new Error('Choisis le client concerné');
      fail(await sb.from('profiles').update({ role, client_id: role === 'client' ? cid : null }).eq('id', f.dataset.id));
      closeSheet(); await refresh(); toast('Membre mis à jour');
    } else if (f.id === 'client-form') {
      const row = { name: f.elements.name.value.trim(), color: f.elements.color.value };
      fail(f.dataset.id ? await sb.from('clients').update(row).eq('id', f.dataset.id) : await sb.from('clients').insert(row));
      closeSheet(); await refresh(); toast(f.dataset.id ? 'Client mis à jour' : 'Client ajouté');
    } else if (f.id === 'settings-form') {
      fail(await sb.from('app_settings').upsert(['delivery_link', 'rushes_deposit_link'].map((k) => ({ key: k, value: f[k].value.trim() || null }))));
      await refresh(); toast('Réglages enregistrés');
    } else if (f.id === 'account-form') {
      fail(await sb.from('profiles').update({ full_name: f.elements.name.value.trim() || null }).eq('id', S.me.id));
      await loadMe(); await refresh(); toast('Nom enregistré');
    } else if (f.dataset.comment) {
      const body = f.body.value.trim(); if (!body) { if (btn) btn.disabled = false; return; }
      fail(await sb.rpc('add_comment', { m: f.dataset.comment, body }));
      f.body.value = ''; await loadComments(f.dataset.comment); renderSheet(true); sheetRoot.querySelector('[data-comment] input')?.focus();
    } else if (f.id === 'feedback-form') {
      const approve = e.submitter?.value === '1';
      if (!approve && !f.msg.value.trim()) throw new Error('Écris tes retours avant de les envoyer');
      if (approve && !(await dialog({ title: 'Valider la vidéo ?', body: 'Gaston sera prévenu que tout est bon et finalisera le projet.', ok: 'Valider' }))) { if (btn) btn.disabled = false; return; }
      fail(await sb.rpc('client_feedback', { m: f.dataset.id, approve, msg: f.msg.value }));
      delete S.comments[f.dataset.id]; await refresh(); openMission(f.dataset.id);
      toast(approve ? 'Merci, vidéo validée !' : 'Retours envoyés');
    } else if (f.dataset.link) {
      const id = S.openId; const url = f.url.value.trim(); if (!url || !id) { if (btn) btn.disabled = false; return; }
      fail(f.dataset.link === 'client_rushes' ? await sb.rpc('client_set_rushes', { m: id, url })
        : f.dataset.link === 'delivery' ? await sb.rpc('set_delivery_url', { m: id, url })
          : await sb.from('missions').update({ rushes_url: url, rushes_added_at: new Date().toISOString() }).eq('id', id));
      f.url.value = ''; await refresh(); toast(f.dataset.link === 'delivery' ? 'Nouvelle version enregistrée' : 'Lien enregistré');
    }
  } catch (err) { toast(err.message || String(err)); }
  if (btn && btn.isConnected) btn.disabled = false;
});

async function saveMission(f) {
  const mode = f.dataset.mode; let id = f.dataset.id || null; const old = id ? mission(id) : null;
  let cid = f.client.value || old?.client_id || null;
  if (!cid) throw new Error('Choisis un client');
  if (cid === '__new') {
    const name = f.newclient.value.trim(); if (!name) throw new Error('Donne un nom au nouveau client');
    cid = fail(await sb.from('clients').insert({ name, color: COLORS[S.clients.length % COLORS.length] }).select().single()).data.id;
  }
  const row = { client_id: cid, title: f.title.value.trim(), editor_budget: Number(f.budget.value || 0), deadline: f.deadline.value ? new Date(f.deadline.value).toISOString() : null };
  if (mode !== 'accept') {
    const rushes = f.rushes.value.trim() || null;
    row.brief = f.brief.value.trim() || null; row.rushes_url = rushes;
    if (rushes !== (old?.rushes_url || null)) row.rushes_added_at = rushes ? new Date().toISOString() : null;
  }
  if (mode === 'new') id = fail(await sb.from('missions').insert({ ...row, status: 'assigned' }).select().single()).data.id;
  else fail(await sb.from('missions').update(row).eq('id', id));
  if (f.price.value !== '') fail(await sb.from('mission_finance').upsert({ mission_id: id, client_price: Number(f.price.value) }));
  const picks = [...f.querySelectorAll('[data-pick].on')].map((b) => b.dataset.pick); const cur = old ? memberIds(id) : [];
  const add = picks.filter((u) => !cur.includes(u)); const del = cur.filter((u) => !picks.includes(u));
  if (add.length) fail(await sb.from('mission_members').insert(add.map((u) => ({ mission_id: id, user_id: u }))));
  if (del.length) fail(await sb.from('mission_members').delete().eq('mission_id', id).in('user_id', del));
  if (mode === 'accept') fail(await sb.from('missions').update({ status: 'assigned' }).eq('id', id));
  setSheet({ type: 'mission', id, mode: 'view' });
  if (mode === 'accept') S.filter = 'open';
  await refresh();
  toast(mode === 'new' ? 'Mission créée' : mode === 'accept' ? 'Projet lancé, le client est prévenu' : 'Mission mise à jour');
}

async function markRead(mid, nid = null) {
  const ids = S.notifs.filter((n) => !n.read_at && ((mid && n.mission_id === mid) || n.id === nid)).map((n) => n.id);
  if (!ids.length) return;
  const now = new Date().toISOString();
  S.notifs.forEach((n) => { if (ids.includes(n.id)) n.read_at = now; });
  render();
  await sb.from('notifications').update({ read_at: now }).in('id', ids);
}
async function markAll() {
  const ids = S.notifs.filter((n) => !n.read_at).map((n) => n.id);
  if (ids.length) await sb.from('notifications').update({ read_at: new Date().toISOString() }).in('id', ids);
  await refresh();
}

// ---------- rafraîchissement sans perdre la saisie ----------
const typing = (root) => { const a = document.activeElement; return !!a && root.contains(a) && /^(INPUT|TEXTAREA|SELECT)$/.test(a.tagName); };
function keepFields(root, fn) {
  const key = (el) => `${el.form?.id || el.form?.dataset.comment || el.form?.dataset.link || ''}|${el.name}`;
  const saved = {};
  root.querySelectorAll('input[name],textarea[name]').forEach((el) => { if (!['hidden', 'submit'].includes(el.type)) saved[key(el)] = el.value; });
  fn();
  root.querySelectorAll('input[name],textarea[name]').forEach((el) => { const k = key(el); if (saved[k]) el.value = saved[k]; });
}
// Rendu complet après une action de l'utilisateur.
async function refresh() {
  await loadAll(); S.pending = false;
  render();
  if (S.sheet) { if (S.sheet.type === 'mission' && !mission(S.sheet.id)) closeSheet(); else renderSheet(true); }
  window.dispatchEvent(new Event('ms-refresh'));
}
// Rendu discret quand les données changent en arrière-plan.
function softRender() {
  if (!S.me || S.loading || dialog.close) return;
  if (digest() === S.hash) { S.pending = false; return; }
  if (typing(app) || typing(sheetRoot)) { S.pending = true; return; }
  S.pending = false;
  keepFields(app, () => render());
  if (S.sheet?.type === 'mission' && S.sheet.mode === 'view') { if (!mission(S.sheet.id)) closeSheet(); else keepFields(sheetRoot, () => renderSheet(true)); }
  window.dispatchEvent(new Event('ms-refresh'));
}
let syncing = false;
async function sync() {
  if (!S.me || !S.me.active || S.me.role === 'none' || syncing) return;
  syncing = true;
  try { await loadAll(); softRender(); } catch (err) { console.warn(err); }
  syncing = false;
}
function goLive() {
  if (S.channel) sb.removeChannel(S.channel);
  const bump = debounce(sync, 600);
  const ch = sb.channel('ms-live').on('postgres_changes', { event: '*', schema: 'public', table: 'notifications', filter: `user_id=eq.${S.me.id}` }, bump)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'mission_versions' }, bump)
    .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'mission_comments' }, (p) => { const id = p.new?.mission_id; if (id && S.comments[id] && p.new.author !== S.me.id) loadComments(id); });
  if (!isClient()) ch.on('postgres_changes', { event: '*', schema: 'public', table: 'missions' }, bump).on('postgres_changes', { event: '*', schema: 'public', table: 'mission_members' }, bump);
  S.channel = ch.subscribe();
}

function b64ToBytes(b64) {
  const pad = '='.repeat((4 - (b64.length % 4)) % 4);
  const raw = atob((b64 + pad).replace(/-/g, '+').replace(/_/g, '/'));
  return Uint8Array.from([...raw].map((c) => c.charCodeAt(0)));
}
async function enablePush() {
  try {
    const reg = await navigator.serviceWorker.register('/sw.js');
    const perm = await Notification.requestPermission();
    if (perm !== 'granted') { render(); return toast('Notifications refusées'); }
    const sub = (await reg.pushManager.getSubscription()) || (await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: b64ToBytes(VAPID_PUBLIC) }));
    const j = sub.toJSON();
    fail(await sb.from('push_subscriptions').upsert({ user_id: S.me.id, endpoint: j.endpoint, p256dh: j.keys.p256dh, auth: j.keys.auth }, { onConflict: 'endpoint' }));
    S.pushOn = true; render(); if (S.sheet) renderSheet(true); toast('Notifications activées');
  } catch (err) { toast(err.message || String(err)); }
}
async function checkPush() {
  if (TAURI || !('serviceWorker' in navigator) || !('PushManager' in window)) return;
  const reg = await navigator.serviceWorker.getRegistration('/sw.js');
  S.pushOn = !!(reg && (await reg.pushManager.getSubscription()));
}

async function boot() {
  S.loading = true;
  await loadMe();
  const ok = S.me && S.me.active && S.me.role !== 'none';
  if (ok) await loadAll();
  if (S.me) await checkPush().catch(() => {});
  S.loading = false; render(true); window.dispatchEvent(new Event('ms-refresh'));
  if (ok) goLive();
  if (S.deepLink && S.me) { const id = S.deepLink; S.deepLink = null; history.replaceState(null, '', '/'); if (mission(id)) { openMission(id); markRead(id); } }
}

sb.auth.onAuthStateChange((ev, session) => {
  if (ev === 'SIGNED_OUT' || (ev === 'SIGNED_IN' && session?.user?.id !== S.session?.user?.id)) setTimeout(() => { closeSheet(); boot(); }, 0);
});
boot();
// Filet de sécurité : toutes les 30 s, et au retour sur l'onglet.
setInterval(() => { if (!document.hidden) sync(); }, 30000);
document.addEventListener('visibilitychange', () => { if (!document.hidden) sync(); });
let wasMobile = isMobile();
window.addEventListener('resize', debounce(() => { hideTip(); if (isMobile() !== wasMobile) { wasMobile = isMobile(); if (S.route === 'agenda' && S.me) return render(); } placeThumbs(false); }, 200));
if (document.fonts?.ready) document.fonts.ready.then(() => placeThumbs(false)).catch(() => {});

// Accès pour l'app Windows (desktop.js)
window.MS = { sb, S, render, refresh: () => refresh(), toast, openMission, esc, eur, hm, client, profile, memberIds, split, isAdmin, isEditor, isClient };
window.dispatchEvent(new Event('ms-ready'));
