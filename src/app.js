// Minima Studio, version web (iPhone + espace client)
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/+esm';

const SUPABASE_URL = 'https://jkfighpoftczgszgoidp.supabase.co';
const SUPABASE_KEY = 'sb_publishable_-DmB0APAPx5v6SnUdD8LMQ_jhyKFJUF';
const VAPID_PUBLIC = 'BE4XpKacAUXegzud16JVWqGHPUF8Kh4tolfppRy76697dUafBLkg4V-RC5M6OnRP86fklC4WlumRei9QW7ouUIc';
const LOGO = '<img class="logo-img" src="/logo.png" alt="Minimalist Belgium">';
const sb = createClient(SUPABASE_URL, SUPABASE_KEY, {
  auth: { flowType: 'pkce', persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
});

// ---------- état ----------
const S = {
  session: null, me: null, route: null, loading: true,
  clients: [], missions: [], profiles: [], members: [], finances: {}, sessions: [], notifs: [],
  filter: 'open', clientFilter: '', month: startOfMonth(new Date()), invites: [], comments: {},
  deepLink: new URLSearchParams(location.search).get('m'),
};
const app = document.getElementById('app');
const sheetRoot = document.getElementById('sheet-root');

// ---------- outils ----------
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const eur = (n) => new Intl.NumberFormat('fr-BE', { style: 'currency', currency: 'EUR', maximumFractionDigits: Math.abs(n) % 1 ? 2 : 0 }).format(n || 0);
const hm = (sec) => { sec = Math.round(sec || 0); const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60); return `${h}h ${String(m).padStart(2, '0')}`; };
const d = (s) => (s ? new Date(s) : null);
function startOfMonth(x) { return new Date(x.getFullYear(), x.getMonth(), 1); }
const sameMonth = (a, b) => a && a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth();
const isToday = (x) => x && x.toDateString() === new Date().toDateString();
const fmtTime = (x) => x.toLocaleTimeString('fr-BE', { hour: '2-digit', minute: '2-digit' });
const fmtDay = (x) => x.toLocaleDateString('fr-BE', { weekday: 'short', day: 'numeric', month: 'short' });
function deadlineLabel(m) {
  const x = d(m.deadline); if (!x) return 'Sans deadline';
  const t = new Date(); t.setDate(t.getDate() + 1);
  if (isToday(x)) return `Auj. ${fmtTime(x)}`;
  if (x.toDateString() === t.toDateString()) return `Demain ${fmtTime(x)}`;
  return `${fmtDay(x)} ${fmtTime(x)}`;
}
function relative(x) {
  const s = (Date.now() - x.getTime()) / 1000;
  if (s < 60) return "à l'instant"; if (s < 3600) return `il y a ${Math.floor(s / 60)} min`;
  if (s < 86400) return `il y a ${Math.floor(s / 3600)} h`; return `il y a ${Math.floor(s / 86400)} j`;
}
function toast(t) { const el = document.getElementById('toast'); el.textContent = t; el.classList.add('on'); clearTimeout(toast.t); toast.t = setTimeout(() => el.classList.remove('on'), 2600); }

const STATUS = {
  requested: ['Demande', '#F472B6'], assigned: ['Assignée', '#8B8D94'], editing: ['En montage', '#4C8DFF'],
  v1_delivered: ['V1 livrée', '#3DD68C'], revisions: ['Retouches', '#F5A524'], fix_delivered: ['Corrections livrées', '#C084FC'],
  validated: ['Validée', '#3DD68C'], paid: ['Payée', '#8B8D94'],
};
const CLIENT_STATUS = {
  requested: 'Demande envoyée', assigned: 'Projet lancé', editing: 'En montage', v1_delivered: 'Première version prête',
  revisions: 'Retours en cours', fix_delivered: 'Corrections prêtes', validated: 'Terminé', paid: 'Terminé',
};
const STEPS = ['assigned', 'editing', 'v1_delivered', 'revisions', 'validated', 'paid'];
const stepIndex = (s) => (s === 'fix_delivered' ? 3 : Math.max(0, STEPS.indexOf(s)));
const isOpen = (m) => !['validated', 'paid'].includes(m.status);
const isDelivered = (m) => ['v1_delivered', 'fix_delivered', 'validated', 'paid'].includes(m.status);
const isLate = (m) => d(m.deadline) && d(m.deadline) < new Date() && ['assigned', 'editing'].includes(m.status);
function pill(text, color) { return `<span class="pill" style="background:${color}26;color:${tint(color)}">${esc(text)}</span>`; }
function tint(hex) { const n = parseInt(hex.slice(1), 16); const r = n >> 16, g = (n >> 8) & 255, b = n & 255; const f = (c) => Math.round(c + (255 - c) * 0.45); return `rgb(${f(r)},${f(g)},${f(b)})`; }
const statusPill = (s) => pill((STATUS[s] || [s])[0], (STATUS[s] || [0, '#8B8D94'])[1]);

const client = (id) => S.clients.find((c) => c.id === id);
const profile = (id) => S.profiles.find((p) => p.id === id);
const firstName = (p) => (p?.full_name || p?.email || '?').split(' ')[0];
const memberIds = (mid) => S.members.filter((x) => x.mission_id === mid).map((x) => x.user_id);
const missionSessions = (mid) => S.sessions.filter((s) => s.mission_id === mid);
const liveSessions = () => S.sessions.filter((s) => s.live && d(s.ended_at) && Date.now() - d(s.ended_at).getTime() < 120000);
const isAdmin = () => S.me?.role === 'admin' && S.me.active;
const isClient = () => S.me?.role === 'client' && S.me.active;
const isEditor = () => S.me?.role === 'editor' && S.me.active;
const AV = ['#A78BFA', '#34D399', '#F5A524', '#F472B6', '#2DD4BF', '#4C8DFF'];
function avatar(p, size = 26) {
  if (!p) return '';
  const ini = (p.full_name || p.email || '?').split(/\s+/).map((x) => x[0]).join('').slice(0, 2).toUpperCase();
  const col = p.color ? `#${p.color.replace('#', '')}` : AV[(p.email || '').length % AV.length];
  const img = p.avatar_url ? `<img src="${esc(p.avatar_url)}" alt="" referrerpolicy="no-referrer">` : esc(ini);
  return `<span class="av" style="width:${size}px;height:${size}px;background:${col};font-size:${Math.round(size * 0.4)}px">${img}</span>`;
}
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
const monthOf = (m) => d(m.deadline) || d(m.created_at);

// ---------- données ----------
async function loadAll() {
  if (isClient()) {
    const [c, m, n] = await Promise.all([
      sb.from('clients').select('*'),
      sb.rpc('client_projects'),
      sb.from('notifications').select('*').order('created_at', { ascending: false }).limit(30),
    ]);
    S.clients = c.data || []; S.missions = m.data || []; S.notifs = n.data || [];
    return;
  }
  const q = [
    sb.from('clients').select('*').order('name'),
    sb.from('missions').select('*').order('deadline', { ascending: true, nullsFirst: false }),
    sb.from('profiles').select('*'),
    sb.from('mission_members').select('*'),
    sb.from('sessions').select('*').order('started_at', { ascending: false }).limit(3000),
    sb.from('notifications').select('*').order('created_at', { ascending: false }).limit(40),
  ];
  if (isAdmin()) q.push(sb.from('mission_finance').select('*'), sb.from('team_invites').select('*').order('invited_at', { ascending: false }));
  const r = await Promise.all(q);
  const err = r.find((x) => x.error); if (err) console.warn(err.error);
  [S.clients, S.missions, S.profiles, S.members, S.sessions, S.notifs] = r.slice(0, 6).map((x) => x.data || []);
  S.finances = {}; (r[6]?.data || []).forEach((f) => { S.finances[f.mission_id] = f; });
  S.invites = r[7]?.data || [];
}

async function loadMe() {
  const { data: { session } } = await sb.auth.getSession();
  S.session = session;
  if (!session) { S.me = null; return; }
  const { data } = await sb.from('profiles').select('*').eq('id', session.user.id).maybeSingle();
  S.me = data;
}

// ---------- icônes ----------
const I = {
  home: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path d="M3 11l9-7 9 7v9a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/></svg>',
  film: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><rect x="3" y="5" width="18" height="15" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/></svg>',
  inbox: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path d="M4 13l2-8h12l2 8M4 13v6h16v-6M4 13h5l1 2h4l1-2h5"/></svg>',
  euro: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path d="M4 19V9M10 19V5M16 19v-7M22 19H2"/></svg>',
  plus: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>',
  bell: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path d="M6 8a6 6 0 0 1 12 0c0 7 3 8 3 8H3s3-1 3-8M10 20a2 2 0 0 0 4 0"/></svg>',
  team: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c.8-3.5 3.4-5.5 6.5-5.5s5.7 2 6.5 5.5M16 4.5a3.5 3.5 0 0 1 0 7M18 14.6c2 .7 3.2 2.6 3.5 5.4"/></svg>',
  out: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path d="M15 4h4v16h-4M10 8l-4 4 4 4M6 12h11"/></svg>',
};

function routesFor() {
  if (isAdmin()) {
    const req = S.missions.filter((m) => m.status === 'requested').length;
    return [['home', 'Accueil', I.home], ['projects', 'Projets', I.film, S.missions.filter(isOpen).length], ['requests', 'Demandes', I.inbox, 0, req], ['finance', 'Finances', I.euro], ['team', 'Équipe', I.team], ['notifs', 'Activité', I.bell, 0, unread()]];
  }
  if (isClient()) return [['projects', 'Mes projets', I.film], ['new', 'Nouveau', I.plus], ['notifs', 'Activité', I.bell, 0, unread()]];
  return [['projects', 'Mes missions', I.film], ['notifs', 'Activité', I.bell, 0, unread()]];
}
const unread = () => S.notifs.filter((n) => !n.read_at).length;

// ---------- rendu ----------
function render() {
  if (S.loading) return;
  if (!S.session) return renderLogin();
  if (!S.me || S.me.role === 'none' || !S.me.active) return renderPending();
  const routes = routesFor();
  if (!S.route || !routes.some((r) => r[0] === S.route)) S.route = routes[0][0];
  const nav = routes.map(([k, t, ic, count, badge]) => `<button class="nav ${S.route === k ? 'on' : ''}" data-go="${k}">${ic}${t}${badge ? `<span class="badge">${badge}</span>` : count ? `<span class="count">${count}</span>` : ''}</button>`).join('');
  const tabs = routes.map(([k, t, ic, , badge]) => `<button class="${S.route === k ? 'on' : ''}" data-go="${k}" aria-label="${t}">${ic}<span>${t}</span>${badge ? `<span class="badge">${badge}</span>` : ''}</button>`).join('');
  const role = isAdmin() ? 'Admin' : isClient() ? esc(client(S.me.client_id)?.name || 'Client') : 'Monteur';
  app.innerHTML = `
  <div class="shell">
    <nav class="side" aria-label="Navigation">
      <div class="brand"><div class="logo">${LOGO}</div><div><b>Minima Studio</b><span class="lbl">${role}</span></div></div>
      ${nav}
      <div class="foot">${avatar(S.me, 30)}<div style="flex:1;min-width:0"><div style="font-size:13px;font-weight:500">${esc(firstName(S.me))}</div><div class="lbl" style="font-size:11.5px">${esc(S.me.email)}</div></div>
        <button class="x" data-act="logout" title="Se déconnecter" aria-label="Se déconnecter" style="width:30px;height:30px">${I.out}</button></div>
    </nav>
    <main>
      <div class="mobile-head"><div class="row"><div class="logo">${LOGO}</div><div><b style="font-size:14.5px">Minima Studio</b><div class="lbl" style="font-size:11.5px">${role}</div></div></div>
        <button class="row" data-act="logout" style="background:none;border:0;cursor:pointer" aria-label="Se déconnecter">${avatar(S.me, 32)}</button></div>
      ${page()}
    </main>
    <nav class="tabbar" aria-label="Onglets">${tabs}</nav>
  </div>`;
}

function page() {
  switch (S.route) {
    case 'home': return homePage();
    case 'projects': return isClient() ? clientProjectsPage() : projectsPage();
    case 'requests': return requestsPage();
    case 'finance': return financePage();
    case 'new': return newProjectPage();
    case 'notifs': return notifsPage();
    case 'team': return teamPage();
    default: return '';
  }
}

function header(kicker, title, right = '') {
  return `<div class="top"><div><div class="lbl">${esc(kicker)}</div><h1>${esc(title)}</h1></div>${right}</div>`;
}

// --- Accueil admin
function homePage() {
  const now = new Date();
  const month = S.missions.filter((m) => sameMonth(monthOf(m), now) && m.status !== 'requested');
  const billed = month.reduce((a, m) => a + (S.finances[m.id]?.client_price || 0), 0);
  const payout = month.reduce((a, m) => a + editorPayout(m), 0);
  const margin = billed - payout;
  const open = S.missions.filter((m) => isOpen(m) && m.status !== 'requested');
  const late = open.filter(isLate).length;
  const delivered = S.missions.filter((m) => isOpen(m) && isDelivered(m));
  const req = S.missions.filter((m) => m.status === 'requested');
  const day = now.toLocaleDateString('fr-BE', { weekday: 'long', day: 'numeric', month: 'long' });
  return `${header(day.charAt(0).toUpperCase() + day.slice(1), `Bonjour ${firstName(S.me)}`, `<button class="btn pri" data-act="newmission">${I.plus.replace('<svg', '<svg width="16" height="16"')}Nouvelle mission</button>`)}
  <div class="grid">
    ${stat(`Facturé · ${now.toLocaleDateString('fr-BE', { month: 'long' })}`, eur(billed), `${month.length} mission${month.length > 1 ? 's' : ''}`)}
    ${stat('À payer aux monteurs', eur(Math.round(payout)))}
    ${stat('Ta marge', eur(Math.round(margin)), billed ? `${Math.round((margin / billed) * 100)} % du facturé` : '', margin >= 0 ? 'var(--green)' : 'var(--red)')}
    ${stat('En cours', String(open.length), late ? `${late} en retard` : 'Tout est à l’heure', late ? 'var(--red)' : 'var(--green)')}
  </div>
  ${req.length ? `<div class="card" style="margin-bottom:16px;border-color:rgba(244,114,182,.35)"><div class="card-head"><h2>Demandes clients</h2>${pill(`${req.length} à valider`, '#F472B6')}</div><div class="list">${req.map(missionItem).join('')}</div></div>` : ''}
  <div class="cols">
    <div class="wide stack">
      <div class="card"><div class="card-head"><h2>En cours</h2><button class="btn" data-go="projects" style="min-height:34px">Tout voir</button></div><div class="list">${open.filter((m) => !isDelivered(m)).slice(0, 8).map(missionItem).join('') || '<div class="empty">Aucune mission en cours.</div>'}</div></div>
      <div class="card"><div class="card-head"><h2>Livrées, en attente de validation</h2><span class="lbl">${delivered.length}</span></div><div class="list">${delivered.map(missionItem).join('') || '<div class="empty">Rien à valider.</div>'}</div></div>
    </div>
    <div class="narrow stack">${liveCard()}</div>
  </div>`;
}
function stat(label, value, foot = '', color = 'var(--muted)') {
  return `<div class="card"><div class="lbl">${esc(label)}</div><div class="big">${esc(value)}</div>${foot ? `<div class="foot-note" style="color:${color}">${esc(foot)}</div>` : ''}</div>`;
}
function liveCard() {
  const live = liveSessions();
  const team = S.profiles.filter((p) => p.active && (p.role === 'editor' || p.role === 'admin'));
  const rows = team.map((p) => {
    const s = live.find((x) => x.user_id === p.id);
    const m = s && S.missions.find((x) => x.id === s.mission_id);
    const last = S.sessions.find((x) => x.user_id === p.id);
    const sub = m ? `${esc(m.title)} · en ce moment` : last ? `Dernière session ${relative(d(last.ended_at || last.started_at))}` : 'Pas encore actif';
    return `<div class="item" ${m ? `data-open="${m.id}"` : ''}>${avatar(p, 28)}<div class="grow"><div class="t">${esc(firstName(p))}</div><div class="s">${sub}</div></div>
      <span class="mono" style="font-size:13px;color:${s ? 'var(--green)' : 'var(--muted)'}">${s ? hm(s.duration_sec) : ''}</span></div>`;
  }).join('');
  return `<div class="card"><div class="card-head"><h2>En direct</h2>${pill(live.length ? `${live.length} actif${live.length > 1 ? 's' : ''}` : 'Personne', live.length ? '#3DD68C' : '#8B8D94')}</div><div class="list">${rows || '<div class="empty">Aucun membre.</div>'}</div></div>`;
}
function missionItem(m) {
  const c = client(m.client_id);
  const people = memberIds(m.id).map(profile).filter(Boolean);
  const live = liveSessions().some((s) => s.mission_id === m.id);
  const sub = [c?.name, isClient() ? null : people.map(firstName).join(' + ') || (m.status === 'requested' ? null : 'Personne'), deadlineLabel(m)].filter(Boolean).join(' · ');
  return `<button class="item" data-open="${m.id}"><span class="dot" style="background:${clientColor(c)}"></span>
    <div class="grow"><div class="t">${esc(m.title)}${live ? ' <span class="dot" style="background:var(--green);width:6px;height:6px;vertical-align:middle"></span>' : ''}</div><div class="s" style="${isLate(m) ? 'color:var(--red)' : ''}">${esc(sub)}</div></div>
    ${isClient() ? pill(CLIENT_STATUS[m.status] || m.status, (STATUS[m.status] || [0, '#8B8D94'])[1]) : statusPill(m.status)}</button>`;
}

// --- Projets (admin et monteur)
function projectsPage() {
  const base = S.missions.filter((m) => m.status !== 'requested');
  const groups = { open: base.filter((m) => isOpen(m) && !isDelivered(m)), delivered: base.filter((m) => isOpen(m) && isDelivered(m)), done: base.filter((m) => !isOpen(m)), all: base };
  let list = groups[S.filter] || groups.open;
  const clientsIn = S.clients.filter((c) => list.some((m) => m.client_id === c.id));
  if (S.clientFilter) list = list.filter((m) => m.client_id === S.clientFilter);
  if (S.filter === 'done') list = [...list].reverse();
  const seg = [['open', 'En cours'], ['delivered', 'Livrées'], ['done', 'Terminées'], ['all', 'Toutes']]
    .map(([k, t]) => `<button class="${S.filter === k ? 'on' : ''}" data-filter="${k}">${t}<span class="n">${groups[k].length}</span></button>`).join('');
  const chips = clientsIn.length > 1 ? `<div class="chips"><button class="chip ${!S.clientFilter ? 'on' : ''}" data-client="">Tous les clients</button>${clientsIn.map((c) => `<button class="chip ${S.clientFilter === c.id ? 'on' : ''}" data-client="${c.id}" style="${S.clientFilter === c.id ? `background:${clientColor(c)}2e;border-color:${clientColor(c)}99` : ''}"><span class="dot" style="background:${clientColor(c)}"></span>${esc(c.name)}</button>`).join('')}</div>` : '';
  return `${header(`${groups.open.length} en cours · ${groups.delivered.length} livrées`, isEditor() ? 'Mes missions' : 'Projets', isAdmin() ? `<button class="btn pri" data-act="newmission">${I.plus.replace('<svg', '<svg width="16" height="16"')}Nouvelle mission</button>` : '')}
  <div style="margin-bottom:12px"><div class="seg">${seg}</div></div>${chips}
  <div class="card" style="padding-top:6px;padding-bottom:6px"><div class="list">${list.map(missionItem).join('') || '<div class="empty">Rien ici.</div>'}</div></div>`;
}

// --- Demandes (admin)
function requestsPage() {
  const req = S.missions.filter((m) => m.status === 'requested');
  return `${header('Projets proposés par tes clients', 'Demandes')}
  <div class="card" style="padding-top:6px;padding-bottom:6px"><div class="list">${req.map(missionItem).join('') || '<div class="empty">Aucune demande en attente.</div>'}</div></div>
  <p class="lbl" style="margin-top:14px">Ouvre une demande pour fixer le budget, le prix client et le monteur, puis accepte-la. Le client est prévenu automatiquement.</p>`;
}

// --- Finances (admin)
function financePage() {
  const mo = S.month;
  const list = S.missions.filter((m) => m.status !== 'requested' && sameMonth(monthOf(m), mo));
  const billed = list.reduce((a, m) => a + (S.finances[m.id]?.client_price || 0), 0);
  const payout = list.reduce((a, m) => a + editorPayout(m), 0);
  const toBill = list.filter((m) => S.finances[m.id]?.client_price && !S.finances[m.id]?.invoiced);
  const label = mo.toLocaleDateString('fr-BE', { month: 'long', year: 'numeric' });
  const byEditor = {};
  list.forEach((m) => split(m).filter((r) => profile(r.u)?.role !== 'admin').forEach((r) => {
    const e = (byEditor[r.u] ||= { amount: 0, secs: 0, n: 0 }); e.amount += r.amount; e.secs += r.secs; e.n += 1;
  }));
  const rows = list.map((m) => {
    const f = S.finances[m.id]; const p = f?.client_price; const pay = editorPayout(m);
    return `<button class="item" data-open="${m.id}"><span class="dot" style="background:${clientColor(client(m.client_id))}"></span>
      <div class="grow"><div class="t">${esc(m.title)}</div><div class="s">${esc(client(m.client_id)?.name || 'Sans client')} · ${p ? eur(p) : 'prix à renseigner'} → ${eur(Math.round(pay))}</div></div>
      <div style="text-align:right"><div class="mono" style="font-weight:600;color:${p == null ? 'var(--muted)' : p - pay >= 0 ? 'var(--green)' : 'var(--red)'}">${p == null ? '–' : eur(Math.round(p - pay))}</div>
      <div class="lbl" style="font-size:11px">${f?.invoiced ? 'Facturée' : p ? 'À facturer' : ''}</div></div></button>`;
  }).join('');
  return `${header('Visible uniquement par toi', 'Finances', `<div class="seg"><button data-month="-1" aria-label="Mois précédent">‹</button><button class="on" style="min-width:140px">${esc(label.charAt(0).toUpperCase() + label.slice(1))}</button><button data-month="1" aria-label="Mois suivant">›</button></div>`)}
  <div class="grid">
    ${stat('Facturé aux clients', eur(billed), `${list.length} missions · HTVA`)}
    ${stat('Reversé aux monteurs', eur(Math.round(payout)), billed ? `${Math.round((payout / billed) * 100)} % du facturé` : '')}
    ${stat('Ta marge', eur(Math.round(billed - payout)), billed ? `${Math.round(((billed - payout) / billed) * 100)} % du facturé` : '', 'var(--green)')}
    ${stat('À facturer', String(toBill.length), toBill.length ? eur(toBill.reduce((a, m) => a + S.finances[m.id].client_price, 0)) : 'Tout est facturé')}
  </div>
  <div class="cols">
    <div class="wide card" style="padding-top:14px;padding-bottom:6px"><div class="card-head"><h2>Missions du mois</h2><span class="lbl">Marge</span></div><div class="list">${rows || '<div class="empty">Aucune mission ce mois-ci.</div>'}</div></div>
    <div class="narrow card"><div class="card-head"><h2>Par monteur</h2></div>
      ${Object.entries(byEditor).map(([u, e]) => `<div class="kv"><span class="row">${avatar(profile(u), 24)}${esc(firstName(profile(u)))}<span class="lbl">${e.secs >= 600 ? `${eur(Math.round(e.amount / (e.secs / 3600)))}/h` : ''}</span></span><span class="mono" style="font-weight:600">${eur(Math.round(e.amount))}</span></div>`).join('') || '<div class="empty">Pas encore de temps enregistré.</div>'}
    </div>
  </div>`;
}

// --- Client : mes projets
function clientProjectsPage() {
  const c = client(S.me.client_id);
  const open = S.missions.filter(isOpen); const done = S.missions.filter((m) => !isOpen(m));
  return `${header(c?.name || 'Espace client', 'Mes projets', `<button class="btn pri" data-go="new">${I.plus.replace('<svg', '<svg width="16" height="16"')}Nouveau projet</button>`)}
  <div class="card" style="padding-top:6px;padding-bottom:6px;margin-bottom:16px"><div class="list">${open.map(missionItem).join('') || '<div class="empty">Aucun projet en cours. Propose-en un avec « Nouveau projet ».</div>'}</div></div>
  ${done.length ? `<h2 style="margin:6px 0 10px">Terminés</h2><div class="card" style="padding-top:6px;padding-bottom:6px"><div class="list">${done.map(missionItem).join('')}</div></div>` : ''}`;
}

// --- Client : nouveau projet
function newProjectPage() {
  const min = new Date(Date.now() + 86400000); min.setMinutes(0, 0, 0);
  const local = new Date(min.getTime() - min.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
  return `${header(client(S.me.client_id)?.name || '', 'Nouveau projet')}
  <form class="card" id="new-form" style="max-width:640px">
    <label class="f" for="np-title" style="margin-top:0">Nom du projet</label>
    <input class="in" id="np-title" name="title" required placeholder="Ex. Podcast épisode 12" maxlength="120">
    <label class="f" for="np-date">Pour quand ?</label>
    <input class="in" id="np-date" name="deadline" type="datetime-local" value="${local}">
    <label class="f" for="np-brief">Ce que tu veux</label>
    <textarea class="in" id="np-brief" name="brief" placeholder="Format, durée, ton, références, ce qu'il faut couper…"></textarea>
    <label class="f" for="np-rushes">Lien des rushes (WeTransfer, Drive…)</label>
    <input class="in" id="np-rushes" name="rushes" type="url" inputmode="url" placeholder="https://">
    <p class="lbl" style="margin:14px 0 18px">Tu peux ajouter le lien des rushes plus tard. Gaston reçoit ta demande et te confirme le lancement.</p>
    <button class="btn pri full" type="submit">Envoyer la demande</button>
  </form>`;
}

// --- Activité
function pushCard() {
  if (window.__TAURI__) return '';
  if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
    const ios = /iphone|ipad/i.test(navigator.userAgent);
    return ios ? '<div class="card" style="margin-bottom:16px"><b>Notifications sur iPhone</b><div class="lbl" style="margin-top:6px">Ajoute d\'abord cette page à ton écran d\'accueil (Partager › Sur l\'écran d\'accueil), ouvre-la depuis l\'icône, puis reviens ici.</div></div>' : '';
  }
  if (Notification.permission === 'granted' && S.pushOn) return '';
  if (Notification.permission === 'denied') return '<div class="card" style="margin-bottom:16px"><b>Notifications bloquées</b><div class="lbl" style="margin-top:6px">Autorise-les dans les réglages de ton navigateur ou de ton iPhone pour Minima Studio.</div></div>';
  return '<div class="card" style="margin-bottom:16px;display:flex;align-items:center;gap:14px;flex-wrap:wrap"><div style="flex:1;min-width:200px"><b>Recevoir les notifications</b><div class="lbl" style="margin-top:4px">Nouvelle demande, V1 livrée, retours… directement sur ton téléphone.</div></div><button class="btn pri" data-act="push">Activer</button></div>';
}

function notifsPage() {
  return `${header('Les dernières nouvelles', 'Activité', unread() ? '<button class="btn" data-act="readall">Tout marquer lu</button>' : '')}${pushCard()}
  <div class="card" style="padding-top:6px;padding-bottom:6px"><div class="list">${S.notifs.map((n) => `
    <button class="item" ${n.mission_id ? `data-open="${n.mission_id}"` : ''}><span class="dot" style="background:${n.read_at ? 'transparent' : 'var(--blue)'}"></span>
      <div class="grow"><div class="t" style="white-space:normal">${esc(n.title)}</div><div class="s">${esc(n.body || '')}${n.body ? ' · ' : ''}${relative(d(n.created_at))}</div></div></button>`).join('') || '<div class="empty">Rien de neuf.</div>'}</div></div>`;
}

// --- Équipe (admin) : inviter depuis le téléphone
const ROLE_LABEL = { admin: 'Admin', editor: 'Monteur', client: 'Client', none: 'Sans accès' };
function teamPage() {
  const members = S.profiles.filter((p) => p.active && p.role !== 'none');
  const pending = S.invites.filter((i) => !i.accepted_at);
  return `${header(`${members.length} personnes`, 'Équipe')}
  <form class="card" id="invite-form" style="margin-bottom:16px">
    <h2>Ajouter quelqu'un</h2>
    <label class="f" for="iv-mail">Adresse e-mail</label><input class="in" id="iv-mail" name="email" type="email" required placeholder="prenom@entreprise.be" autocomplete="off">
    <label class="f" for="iv-role">Rôle</label>
    <select class="in" id="iv-role" name="role"><option value="client">Client (espace web)</option><option value="editor">Monteur (app Mac)</option><option value="admin">Admin</option></select>
    <label class="f" for="iv-client">Client concerné</label>
    <select class="in" id="iv-client" name="client"><option value="">Choisir…</option>${S.clients.map((c) => `<option value="${c.id}">${esc(c.name)}</option>`).join('')}</select>
    <button class="btn pri full" type="submit" style="margin-top:16px">Ajouter</button>
    <p class="lbl" style="margin:10px 0 0">Un client se connecte ensuite sur studio.minimalistbelgium.com avec cette adresse. Un monteur installe l'app Mac.</p>
  </form>
  <div class="card" style="padding-top:14px;padding-bottom:6px;margin-bottom:16px"><div class="card-head"><h2>Membres</h2></div><div class="list">
    ${members.map((p) => `<div class="item">${avatar(p, 30)}<div class="grow"><div class="t">${esc(p.full_name || p.email)}</div><div class="s">${esc(p.email)}${p.role === 'client' ? ` · ${esc(client(p.client_id)?.name || '')}` : ''}</div></div>${pill(ROLE_LABEL[p.role] || p.role, p.role === 'admin' ? '#4C8DFF' : p.role === 'client' ? '#F472B6' : '#3DD68C')}</div>`).join('')}
  </div></div>
  ${pending.length ? `<div class="card" style="padding-top:14px;padding-bottom:6px"><div class="card-head"><h2>Invitations en attente</h2></div><div class="list">${pending.map((i) => `<div class="item"><div class="grow"><div class="t">${esc(i.email)}</div><div class="s">${ROLE_LABEL[i.role] || ''}${i.client_id ? ` · ${esc(client(i.client_id)?.name || '')}` : ''}</div></div><button class="btn" data-uninvite="${esc(i.email)}" style="min-height:34px">Annuler</button></div>`).join('')}</div></div>` : ''}`;
}

// ---------- détail d'une mission ----------
function openMission(id) {
  const m = S.missions.find((x) => x.id === id); if (!m) return;
  S.openId = id;
  if (!S.comments[id]) loadComments(id);
  const c = client(m.client_id);
  let body = '';
  if (isClient()) body = clientDetail(m);
  else if (m.status === 'requested' && isAdmin()) body = acceptForm(m);
  else body = teamDetail(m);
  sheetRoot.innerHTML = `<div class="scrim" data-close><div class="sheet" role="dialog" aria-modal="true" aria-label="${esc(m.title)}">
    <div class="grab"></div>
    <div class="sheet-head"><div style="flex:1;min-width:0"><div class="lbl">${esc(c?.name || 'Sans client')}</div><h2>${esc(m.title)}</h2>
      <div class="row" style="flex-wrap:wrap">${isClient() ? pill(CLIENT_STATUS[m.status] || m.status, (STATUS[m.status] || [0, '#8B8D94'])[1]) : statusPill(m.status)}<span class="lbl" style="${isLate(m) ? 'color:var(--red)' : ''}">${esc(deadlineLabel(m))}</span></div></div>
      <button class="x" data-close aria-label="Fermer">×</button></div>
    ${body}</div></div>`;
  document.body.style.overflow = 'hidden';
}
async function loadComments(id) {
  const { data } = await sb.from('mission_comments').select('*').eq('mission_id', id).order('created_at');
  S.comments[id] = data || [];
  if (S.openId === id) openMission(id);
}
function commentsCard(m) {
  const list = S.comments[m.id];
  const who = (c) => (c.author === S.me.id ? 'Toi' : firstName(profile(c.author)) !== '?' ? firstName(profile(c.author)) : (isClient() ? 'Minimalist Belgium' : client(m.client_id)?.name || 'Client'));
  const tag = (c) => (c.kind === 'approve' ? pill('Validé', '#3DD68C') : c.kind === 'changes' ? pill('Retours', '#F5A524') : '');
  return `<div class="card" style="margin-top:14px"><h2 style="margin-bottom:6px">Échanges</h2>
    ${list == null ? '<div class="empty">Chargement…</div>' : list.map((c) => `<div class="kv" style="align-items:flex-start;flex-direction:column;gap:4px"><div class="row" style="gap:8px"><b style="font-size:13px">${esc(who(c))}</b>${tag(c)}<span class="lbl" style="font-size:11.5px">${relative(d(c.created_at))}</span></div><div style="white-space:pre-wrap;color:var(--text2);font-size:14px;line-height:1.5">${esc(c.body)}</div></div>`).join('') || '<div class="empty">Aucun message pour l\'instant.</div>'}
    <form data-comment="${m.id}" style="display:flex;gap:8px;margin-top:10px"><input class="in" name="body" placeholder="Écrire un message…" style="min-height:42px"><button class="btn" type="submit" style="min-height:42px">Envoyer</button></form></div>`;
}

function openNewMission() {
  const team = S.profiles.filter((p) => p.active && (p.role === 'editor' || p.role === 'admin'));
  const dl = new Date(Date.now() + 3 * 86400000); dl.setHours(18, 0, 0, 0);
  const local = new Date(dl.getTime() - dl.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
  S.openId = null;
  sheetRoot.innerHTML = `<div class="scrim" data-close><div class="sheet" role="dialog" aria-modal="true" aria-label="Nouvelle mission" style="max-width:640px">
    <div class="grab"></div>
    <div class="sheet-head"><div style="flex:1"><div class="lbl">Minima Studio</div><h2>Nouvelle mission</h2></div><button class="x" data-close aria-label="Fermer">×</button></div>
    <form class="card" id="newmission-form">
      <label class="f" for="nm-client" style="margin-top:0">Client</label>
      <select class="in" id="nm-client" name="client" required><option value="" disabled selected>Choisir le client…</option>${S.clients.map((c) => `<option value="${c.id}">${esc(c.name)}</option>`).join('')}<option value="__new">+ Nouveau client…</option></select>
      <input class="in" id="nm-newclient" name="newclient" placeholder="Nom du nouveau client" style="margin-top:8px;display:none">
      <label class="f" for="nm-title">Titre</label><input class="in" id="nm-title" name="title" required placeholder="Ex. Cover épisode 50" maxlength="120">
      <label class="f" for="nm-dl">Deadline</label><input class="in" id="nm-dl" name="deadline" type="datetime-local" value="${local}">
      <div class="cols" style="margin:0;gap:12px">
        <div style="flex:1 1 150px"><label class="f" for="nm-price">Prix client HTVA (€)</label><input class="in" id="nm-price" name="price" type="number" inputmode="decimal" min="0" step="1"></div>
        <div style="flex:1 1 150px"><label class="f" for="nm-budget">Budget montage (€)</label><input class="in" id="nm-budget" name="budget" type="number" inputmode="decimal" min="0" step="1" required></div>
      </div>
      <label class="f">Qui monte ?</label>
      <div class="pick">${team.map((p) => `<button type="button" data-pick="${p.id}">${avatar(p, 22)}${esc(p.id === S.me.id ? 'Moi' : firstName(p))}</button>`).join('')}</div>
      <label class="f" for="nm-rushes">Lien des rushes</label><input class="in" id="nm-rushes" name="rushes" type="url" inputmode="url" placeholder="https:// (facultatif)">
      <label class="f" for="nm-brief">Brief</label><textarea class="in" id="nm-brief" name="brief" placeholder="Format, durée, consignes… (facultatif)"></textarea>
      <button class="btn pri full" type="submit" style="margin-top:18px">Créer la mission</button>
      <p class="lbl" style="margin:10px 0 0">Les monteurs choisis reçoivent une notification. Pour joindre un PDF au brief, passe par l'app Mac.</p>
    </form></div></div>`;
  document.body.style.overflow = 'hidden';
}

function closeSheet() { sheetRoot.innerHTML = ''; S.openId = null; document.body.style.overflow = ''; }

function stepsHtml(m, labels) {
  const cur = stepIndex(m.status);
  return `<div class="card" style="margin-bottom:14px"><div class="steps">${STEPS.map((s, i) => {
    const done = i < cur && m.status !== 'requested', now = i === cur && m.status !== 'requested';
    const col = now ? (STATUS[m.status] || [0, '#4C8DFF'])[1] : done ? '#3DD68C' : 'rgba(255,255,255,.08)';
    return `<div class="step"><div class="bar" style="background:${col}"></div><div class="n" style="color:${now ? tint(col) : done ? 'var(--text)' : 'var(--muted)'}">${esc(labels(s, now))}</div></div>`;
  }).join('')}</div></div>`;
}

function linkBlock(title, url, action, color, editable, field) {
  return `<div class="card" style="flex:1 1 240px"><div class="card-head" style="margin-bottom:10px"><h2>${title}</h2></div>
    ${url ? `<a class="btn full" href="${esc(url)}" target="_blank" rel="noopener" style="color:${color};background:${color}1f;border-color:${color}40;justify-content:space-between">${action}<span>↗</span></a>` : '<div class="lbl" style="min-height:44px;display:flex;align-items:center">Pas encore de lien.</div>'}
    ${editable ? `<form data-link="${field}" style="display:flex;gap:8px;margin-top:10px"><input class="in" name="url" type="url" placeholder="${url ? 'Remplacer le lien' : 'Coller le lien'}" style="min-height:40px"><button class="btn" type="submit" style="min-height:40px">OK</button></form>` : ''}</div>`;
}

function clientDetail(m) {
  const labels = (s, now) => (now ? CLIENT_STATUS[m.status] : { assigned: 'Lancé', editing: 'Montage', v1_delivered: 'V1', revisions: 'Retours', validated: 'Terminé', paid: 'Facturé' }[s]);
  return `${m.status === 'requested' ? '<div class="card" style="margin-bottom:14px;border-color:rgba(244,114,182,.35)"><b>Demande envoyée</b><div class="lbl" style="margin-top:6px">Gaston va regarder ta demande et lancer le projet. Tu recevras une notification.</div></div>' : stepsHtml(m, labels)}
  ${m.delivery_url ? `<div class="card" style="margin-bottom:14px;border-color:rgba(61,214,140,.35)"><h2>Ta vidéo</h2>
    <a class="btn green full" href="${esc(m.delivery_url)}" target="_blank" rel="noopener" style="margin-top:12px">Regarder la version ↗</a>
    ${['v1_delivered', 'fix_delivered'].includes(m.status) ? `<form id="feedback-form" data-id="${m.id}" style="margin-top:14px"><label class="f" for="fb" style="margin-top:0">Tes retours (si tu en as)</label><textarea class="in" id="fb" name="msg" placeholder="Ex. à 2:14, couper la phrase… / changer la musique…" style="min-height:90px"></textarea>
      <div style="display:flex;gap:10px;margin-top:12px;flex-wrap:wrap"><button class="btn green" type="submit" name="approve" value="1" style="flex:1">Valider la vidéo</button><button class="btn" type="submit" name="approve" value="0" style="flex:1">Envoyer mes retours</button></div></form>` : ''}</div>` : ''}
  <div class="cols" style="margin-bottom:0">${linkBlock('Tes rushes', m.rushes_url, 'Voir le lien', '#4C8DFF', true, 'client_rushes')}</div>
  ${m.brief ? `<div class="card" style="margin-top:14px"><h2 style="margin-bottom:10px">Brief</h2><div style="white-space:pre-wrap;color:var(--text2);line-height:1.55;font-size:14px">${esc(m.brief)}</div></div>` : ''}
  ${m.status !== 'requested' ? commentsCard(m) : ''}`;
}

function teamDetail(m) {
  const rows = split(m);
  const ses = missionSessions(m.id).filter((s) => isAdmin() || s.user_id === S.me.id);
  const f = S.finances[m.id];
  const labels = (s, now) => (now ? STATUS[m.status][0] : STATUS[s][0]);
  const statusMenu = isAdmin()
    ? `<label class="f" for="st" style="margin-top:0">Changer le statut</label><select class="in" id="st" data-status="${m.id}">${Object.keys(STATUS).filter((k) => k !== 'requested').map((k) => `<option value="${k}" ${k === m.status ? 'selected' : ''}>${STATUS[k][0]}</option>`).join('')}</select>`
    : isOpen(m) ? `<label class="f" for="st" style="margin-top:0">Où j'en suis</label><select class="in" id="st" data-edstatus="${m.id}">${['editing', 'v1_delivered', 'fix_delivered'].map((k) => `<option value="${k}" ${k === m.status ? 'selected' : ''}>${STATUS[k][0]}</option>`).join('')}${['editing', 'v1_delivered', 'fix_delivered'].includes(m.status) ? '' : `<option selected disabled>${STATUS[m.status][0]}</option>`}</select>` : '';
  const me = rows.find((r) => r.u === S.me.id);
  const right = isAdmin()
    ? `<div class="card" style="border-color:rgba(76,141,255,.35)"><div class="card-head"><h2>Répartition</h2>${pill('Calcul auto', '#4C8DFF')}</div>
        <div class="lbl">Budget montage</div><div class="big" style="margin:6px 0 14px">${eur(m.editor_budget)}</div>
        ${rows.length ? `<div style="display:flex;height:10px;border-radius:5px;overflow:hidden;margin-bottom:8px">${rows.map((r, i) => `<div style="width:${r.pct}%;background:${profile(r.u)?.role === 'admin' ? '#4C8DFF' : AV[i % AV.length]}"></div>`).join('')}</div>` : '<div class="lbl">Pas encore de temps enregistré.</div>'}
        ${rows.map((r) => `<div class="kv"><span>${esc(r.u === S.me.id ? 'Toi' : firstName(profile(r.u)))} · ${Math.round(r.pct)} % <span class="lbl">${hm(r.secs)}</span></span><span class="mono" style="font-weight:600">${eur(Math.round(r.amount * 100) / 100)}</span></div>`).join('')}
        ${f?.client_price != null ? `<div class="kv"><span>Prix client</span><span class="mono">${eur(f.client_price)}</span></div><div class="kv"><span>Ta marge</span><span class="mono" style="font-weight:600;color:var(--green)">${eur(Math.round(f.client_price - editorPayout(m)))}</span></div>` : ''}
      </div>`
    : `<div class="card"><div class="lbl">Budget de la mission</div><div class="big" style="margin:6px 0 14px">${eur(m.editor_budget)}</div>
        <div class="kv"><span>Ta part</span><span class="mono" style="font-weight:600;color:var(--green)">${eur(Math.round((me?.amount ?? m.editor_budget ?? 0) * 100) / 100)}</span></div>
        <div class="kv"><span>Ton temps</span><span class="mono">${hm(me?.secs)}</span></div>
        <div class="kv"><span>Ton taux horaire</span><span class="mono">${me && me.secs >= 300 ? `${eur(Math.round(me.amount / (me.secs / 3600)))}/h` : '–'}</span></div></div>`;
  return `${stepsHtml(m, labels)}
  <div class="cols"><div class="wide stack">
    <div class="cols" style="margin-bottom:0">${linkBlock('Rushes', m.rushes_url, 'Télécharger les rushes', '#4C8DFF', isAdmin(), 'rushes')}${linkBlock('Version à montrer au client', m.delivery_url, 'Ouvrir la version', '#3DD68C', true, 'delivery')}</div>
    ${m.brief ? `<div class="card"><h2 style="margin-bottom:10px">Brief</h2><div style="white-space:pre-wrap;color:var(--text2);line-height:1.55;font-size:14px">${esc(m.brief)}</div></div>` : ''}
    <div class="card"><div class="card-head"><h2>${isAdmin() ? 'Sessions' : 'Mes sessions'}</h2><span class="lbl mono">${hm(ses.reduce((a, s) => a + (s.duration_sec || 0), 0))}</span></div>
      ${ses.slice(0, 10).map((s) => `<div class="kv"><span class="row">${avatar(profile(s.user_id), 22)}${esc(s.user_id === S.me.id ? 'Toi' : firstName(profile(s.user_id)))}</span><span class="lbl">${fmtDay(d(s.started_at))} ${fmtTime(d(s.started_at))}</span><span class="mono">${hm(s.duration_sec)}</span></div>`).join('') || '<div class="empty">Aucune session.</div>'}</div>
    ${m.client_id ? commentsCard(m).replace('margin-top:14px', 'margin-top:0') : ''}
  </div><div class="narrow stack">
    <div class="card">${statusMenu}<div class="lbl" style="margin-top:10px">Équipe : ${esc(memberIds(m.id).map((u) => firstName(profile(u))).join(', ') || 'personne')}</div></div>
    ${right}
  </div></div>`;
}

function acceptForm(m) {
  const team = S.profiles.filter((p) => p.active && (p.role === 'editor' || p.role === 'admin'));
  const dl = d(m.deadline); const local = dl ? new Date(dl.getTime() - dl.getTimezoneOffset() * 60000).toISOString().slice(0, 16) : '';
  return `<div class="card" style="margin-bottom:14px;border-color:rgba(244,114,182,.35)"><b>Demande du client</b>
    <div class="lbl" style="margin-top:6px">Envoyée ${relative(d(m.created_at))}${m.rushes_url ? ' · rushes fournis' : ' · pas encore de rushes'}</div>
    ${m.brief ? `<div style="white-space:pre-wrap;color:var(--text2);line-height:1.55;font-size:14px;margin-top:12px">${esc(m.brief)}</div>` : ''}
    ${m.rushes_url ? `<a class="btn" style="margin-top:12px" href="${esc(m.rushes_url)}" target="_blank" rel="noopener">Voir les rushes ↗</a>` : ''}</div>
  <form class="card" id="accept-form" data-id="${m.id}">
    <h2>Lancer le projet</h2>
    <label class="f" for="ac-title">Titre</label><input class="in" id="ac-title" name="title" value="${esc(m.title)}" required>
    <div class="cols" style="margin:0;gap:12px">
      <div style="flex:1 1 160px"><label class="f" for="ac-price">Prix client HTVA (€)</label><input class="in" id="ac-price" name="price" type="number" inputmode="decimal" min="0" step="1"></div>
      <div style="flex:1 1 160px"><label class="f" for="ac-budget">Budget montage (€)</label><input class="in" id="ac-budget" name="budget" type="number" inputmode="decimal" min="0" step="1" required></div>
    </div>
    <label class="f" for="ac-dl">Deadline</label><input class="in" id="ac-dl" name="deadline" type="datetime-local" value="${local}">
    <label class="f">Qui monte ?</label>
    <div class="pick">${team.map((p) => `<button type="button" data-pick="${p.id}">${avatar(p, 22)}${esc(p.id === S.me.id ? 'Moi' : firstName(p))}</button>`).join('')}</div>
    <div style="display:flex;gap:10px;margin-top:20px;flex-wrap:wrap"><button class="btn pri" type="submit" style="flex:2">Accepter et lancer</button><button class="btn danger" type="button" data-refuse="${m.id}" style="flex:1">Refuser</button></div>
  </form>`;
}

// ---------- connexion ----------
function renderLogin() {
  app.innerHTML = `<div class="login"><div class="box">
    <div class="logo big" style="margin:0 auto">${LOGO}</div>
    <h1>Minima Studio</h1><p class="muted" style="margin:0 0 26px">Suivi des projets Minimalist Belgium</p>
    <form id="mail-form"><label class="f" for="em" style="text-align:left;margin-top:0">Ton adresse e-mail</label>
      <input class="in" id="em" name="email" type="email" autocomplete="email" inputmode="email" required placeholder="prenom@entreprise.be">
      <button class="btn pri full" type="submit" style="margin-top:12px">Recevoir un lien de connexion</button></form>
    ${window.__TAURI__ ? '' : '<div class="or">ou</div><button class="btn full" data-act="google">Continuer avec Google</button>'}
    <p class="lbl" style="margin-top:22px">Accès réservé aux clients et à l'équipe de Minimalist Belgium.<br><a href="/confidentialite.html" style="color:var(--muted)">Confidentialité</a></p>
  </div></div>`;
}
function renderPending() {
  app.innerHTML = `<div class="login"><div class="box"><div class="logo big" style="margin:0 auto">${LOGO}</div>
    <h1>Accès en attente</h1><p class="muted">Ton compte ${esc(S.session?.user?.email || '')} n'est pas encore relié à un projet. Demande à Gaston de t'ajouter, puis reviens ici.</p>
    <button class="btn full" data-act="retry" style="margin-top:18px">Réessayer</button>
    <button class="btn full" data-act="logout" style="margin-top:10px">Se déconnecter</button></div></div>`;
}

// ---------- actions ----------
document.addEventListener('click', async (e) => {
  const t = e.target.closest('[data-go],[data-open],[data-close],[data-act],[data-filter],[data-client],[data-month],[data-pick],[data-refuse],[data-uninvite]');
  if (!t) return;
  if (t.hasAttribute('data-close') && e.target !== t && !e.target.closest('button[data-close]')) return; // clic dans la feuille
  if (t.dataset.go) { closeSheet(); S.route = t.dataset.go; render(); window.scrollTo(0, 0); }
  else if (t.dataset.open) { openMission(t.dataset.open); markRead(t.dataset.open); }
  else if (t.hasAttribute('data-close')) closeSheet();
  else if (t.dataset.filter) { S.filter = t.dataset.filter; S.clientFilter = ''; render(); }
  else if (t.dataset.client !== undefined && t.classList.contains('chip')) { S.clientFilter = t.dataset.client; render(); }
  else if (t.dataset.month) { S.month = new Date(S.month.getFullYear(), S.month.getMonth() + Number(t.dataset.month), 1); render(); }
  else if (t.dataset.pick) t.classList.toggle('on');
  else if (t.dataset.uninvite) { await sb.from('team_invites').delete().eq('email', t.dataset.uninvite); await refresh(); }
  else if (t.dataset.act === 'push') { await enablePush(); }
  else if (t.dataset.act === 'newmission') { openNewMission(); }
  else if (t.dataset.refuse) {
    if (!confirm('Refuser cette demande ? Elle sera supprimée.')) return;
    const { error } = await sb.from('missions').delete().eq('id', t.dataset.refuse);
    if (error) return toast(error.message);
    closeSheet(); await refresh(); toast('Demande refusée');
  } else if (t.dataset.act === 'logout') { if (confirm('Se déconnecter ?')) { await sb.auth.signOut(); location.reload(); } }
  else if (t.dataset.act === 'retry') { await boot(); }
  else if (t.dataset.act === 'readall') { await markAll(); }
  else if (t.dataset.act === 'google') {
    await sb.auth.signInWithOAuth({ provider: 'google', options: { redirectTo: location.origin } });
  }
});
document.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeSheet(); });

document.addEventListener('change', async (e) => {
  const sel = e.target;
  if (sel.id === 'nm-client') { document.getElementById('nm-newclient').style.display = sel.value === '__new' ? 'block' : 'none'; return; }
  if (sel.dataset.status) {
    const m = S.missions.find((x) => x.id === sel.dataset.status); const s = sel.value;
    const patch = { status: s };
    if (s === 'v1_delivered' && !m.v1_delivered_at) patch.v1_delivered_at = new Date().toISOString();
    if (s === 'validated' && !m.validated_at) patch.validated_at = new Date().toISOString();
    const { error } = await sb.from('missions').update(patch).eq('id', m.id);
    if (error) return toast(error.message);
    await refresh(); openMission(m.id); toast(`Statut : ${STATUS[s][0]}`);
    const hasClient = S.profiles.some((p) => p.role === 'client' && p.active && p.client_id === m.client_id);
    if (hasClient && ['v1_delivered', 'fix_delivered', 'validated'].includes(s)) {
      const msg = { v1_delivered: 'La V1 de ta vidéo est prête', fix_delivered: 'Les corrections de ta vidéo sont prêtes', validated: 'Ta vidéo est finalisée' }[s];
      if (confirm(`Prévenir le client ?\n« ${msg} »`)) {
        const r = await sb.rpc('notify_client', { m: m.id, msg });
        toast(r.error ? r.error.message : 'Client prévenu');
      }
    }
  } else if (sel.dataset.edstatus) {
    const { error } = await sb.rpc('editor_set_status', { m: sel.dataset.edstatus, s: sel.value });
    if (error) return toast(error.message);
    await refresh(); openMission(sel.dataset.edstatus); toast("Statut envoyé à l'admin");
  }
});

document.addEventListener('submit', async (e) => {
  const f = e.target; e.preventDefault();
  const btn = f.querySelector('[type=submit]'); if (btn) btn.disabled = true;
  try {
    if (f.id === 'mail-form') {
      const email = f.email.value.trim().toLowerCase();
      const { error } = await sb.auth.signInWithOtp({ email, options: { emailRedirectTo: location.origin } });
      if (error) throw error;
      f.outerHTML = `<form id="code-form" data-email="${esc(email)}" style="text-align:left"><div class="card"><b>Regarde ta boîte mail</b><div class="lbl" style="margin-top:6px">On vient d'envoyer un e-mail à ${esc(email)}. ${window.__TAURI__ ? 'Entre le code qu\'il contient :' : 'Clique sur le lien, ou entre le code qu\'il contient :'}</div>
        <input class="in" name="code" inputmode="numeric" autocomplete="one-time-code" placeholder="Code reçu par e-mail" style="margin-top:12px;letter-spacing:.2em;font-size:18px" required>
        <button class="btn pri full" type="submit" style="margin-top:10px">Se connecter</button></div></form>`;
    } else if (f.id === 'code-form') {
      const { error } = await sb.auth.verifyOtp({ email: f.dataset.email, token: f.code.value.replace(/\s/g, ''), type: 'email' });
      if (error) throw new Error('Code incorrect ou expiré');
    } else if (f.id === 'new-form') {
      const dl = f.deadline.value ? new Date(f.deadline.value).toISOString() : null;
      const { error } = await sb.rpc('client_request_project', { t: f.title.value, d: dl, b: f.brief.value, r: f.rushes.value });
      if (error) throw error;
      toast('Demande envoyée, merci !'); S.route = 'projects'; await refresh();
    } else if (f.id === 'newmission-form') {
      let cid = f.client.value || null;
      if (!cid) throw new Error('Choisis un client');
      if (cid === '__new') {
        const name = f.newclient.value.trim(); if (!name) throw new Error('Donne un nom au nouveau client');
        const colors = ['#F472B6', '#2DD4BF', '#F5A524', '#A78BFA', '#34D399', '#4C8DFF', '#FB7185'];
        const c = await sb.from('clients').insert({ name, color: colors[S.clients.length % colors.length] }).select().single();
        if (c.error) throw c.error; cid = c.data.id;
      }
      const rushes = f.rushes.value.trim();
      const ins = await sb.from('missions').insert({
        client_id: cid, title: f.title.value.trim(), brief: f.brief.value.trim() || null,
        editor_budget: Number(f.budget.value || 0), deadline: f.deadline.value ? new Date(f.deadline.value).toISOString() : null,
        rushes_url: rushes || null, rushes_added_at: rushes ? new Date().toISOString() : null, status: 'assigned',
      }).select().single();
      if (ins.error) throw ins.error;
      const id = ins.data.id;
      if (f.price.value !== '') { const r = await sb.from('mission_finance').upsert({ mission_id: id, client_price: Number(f.price.value) }); if (r.error) throw r.error; }
      const picks = [...f.querySelectorAll('[data-pick].on')].map((b) => b.dataset.pick);
      if (picks.length) { const r = await sb.from('mission_members').insert(picks.map((u) => ({ mission_id: id, user_id: u }))); if (r.error) throw r.error; }
      closeSheet(); await refresh(); openMission(id); toast('Mission créée');
    } else if (f.id === 'accept-form') {
      const id = f.dataset.id; const picks = [...f.querySelectorAll('[data-pick].on')].map((b) => b.dataset.pick);
      const dl = f.deadline.value ? new Date(f.deadline.value).toISOString() : null;
      let r = await sb.from('missions').update({ title: f.title.value.trim(), editor_budget: Number(f.budget.value || 0), deadline: dl }).eq('id', id);
      if (r.error) throw r.error;
      if (f.price.value !== '') { r = await sb.from('mission_finance').upsert({ mission_id: id, client_price: Number(f.price.value) }); if (r.error) throw r.error; }
      if (picks.length) { r = await sb.from('mission_members').insert(picks.map((u) => ({ mission_id: id, user_id: u }))); if (r.error) throw r.error; }
      r = await sb.from('missions').update({ status: 'assigned' }).eq('id', id); if (r.error) throw r.error;
      closeSheet(); await refresh(); toast('Projet lancé, le client est prévenu');
    } else if (f.id === 'invite-form') {
      const email = f.email.value.trim().toLowerCase(); const role = f.role.value; const cid = f.client.value || null;
      if (role === 'client' && !cid) throw new Error('Choisis le client concerné');
      const r = await sb.from('team_invites').upsert({ email, role, client_id: role === 'client' ? cid : null });
      if (r.error) throw r.error;
      await refresh(); toast('Ajouté, il peut se connecter');
    } else if (f.dataset.comment) {
      const body = f.body.value.trim(); if (!body) return;
      const r = await sb.rpc('add_comment', { m: f.dataset.comment, body }); if (r.error) throw r.error;
      delete S.comments[f.dataset.comment]; openMission(f.dataset.comment);
    } else if (f.id === 'feedback-form') {
      const approve = e.submitter?.value === '1';
      if (approve && !confirm('Valider la vidéo ? Gaston sera prévenu que tout est bon.')) { if (btn) btn.disabled = false; return; }
      const r = await sb.rpc('client_feedback', { m: f.dataset.id, approve, msg: f.msg.value });
      if (r.error) throw r.error;
      delete S.comments[f.dataset.id]; await refresh(); openMission(f.dataset.id);
      toast(approve ? 'Merci, vidéo validée !' : 'Retours envoyés');
    } else if (f.dataset.link) {
      const id = S.openId;
      const url = f.url.value.trim(); if (!url || !id) return;
      const r = f.dataset.link === 'client_rushes'
        ? await sb.rpc('client_set_rushes', { m: id, url })
        : f.dataset.link === 'delivery'
          ? await sb.rpc('set_delivery_url', { m: id, url })
          : await sb.from('missions').update({ rushes_url: url, rushes_added_at: new Date().toISOString() }).eq('id', id);
      if (r.error) throw r.error;
      await refresh(); openMission(id); toast('Lien enregistré');
    }
  } catch (err) { toast(err.message || String(err)); }
  if (btn) btn.disabled = false;
});

async function markRead(mid) {
  const ids = S.notifs.filter((n) => !n.read_at && n.mission_id === mid).map((n) => n.id);
  if (!ids.length) return;
  await sb.from('notifications').update({ read_at: new Date().toISOString() }).in('id', ids);
  S.notifs.forEach((n) => { if (ids.includes(n.id)) n.read_at = new Date().toISOString(); });
}
async function markAll() {
  const ids = S.notifs.filter((n) => !n.read_at).map((n) => n.id);
  if (ids.length) await sb.from('notifications').update({ read_at: new Date().toISOString() }).in('id', ids);
  await refresh();
}

async function refresh() { await loadAll(); render(); window.dispatchEvent(new Event('ms-refresh')); }

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
    const { error } = await sb.from('push_subscriptions').upsert({ user_id: S.me.id, endpoint: j.endpoint, p256dh: j.keys.p256dh, auth: j.keys.auth }, { onConflict: 'endpoint' });
    if (error) throw error;
    S.pushOn = true; render(); toast('Notifications activées');
  } catch (err) { toast(err.message || String(err)); }
}
async function checkPush() {
  if (!('serviceWorker' in navigator) || !('PushManager' in window)) return;
  const reg = await navigator.serviceWorker.getRegistration('/sw.js');
  S.pushOn = !!(reg && (await reg.pushManager.getSubscription()));
}

async function boot() {
  S.loading = true;
  await loadMe();
  if (S.me && S.me.active && S.me.role !== 'none') await loadAll();
  if (S.me) await checkPush();
  S.loading = false; render(); window.dispatchEvent(new Event('ms-refresh'));
  if (S.deepLink && S.me) { const id = S.deepLink; S.deepLink = null; history.replaceState(null, '', '/'); if (S.missions.some((m) => m.id === id)) openMission(id); }
}

sb.auth.onAuthStateChange((ev) => { if (ev === 'SIGNED_IN' || ev === 'SIGNED_OUT') boot(); });
boot();
// Rafraîchissement : toutes les 30 s, et au retour sur l'onglet.
setInterval(() => { if (S.me && !document.hidden && !sheetRoot.innerHTML) refresh(); }, 30000);
document.addEventListener('visibilitychange', () => { if (!document.hidden && S.me) refresh(); });

// Accès pour l'app Windows (desktop.js)
window.MS = { sb, S, render, refresh: () => refresh(), toast, openMission, esc, eur, hm, client, profile, memberIds, split, isAdmin, isEditor, isClient };
window.dispatchEvent(new Event('ms-ready'));
