// Dérush hors ligne (app PC) : syncro, multicam et coupure des micros, via le moteur livré avec l'app.
const T = window.__TAURI__;
const invoke = (cmd, args) => T.core.invoke(cmd, args);

const D = {
  phase: 'idle',     // idle | scanning | config | running | done | finalizing | finalized | error
  folder: null, scan: null, name: '', cams: [], mics: [], wide: 'overlap',
  pct: 0, msg: '', logs: [], warnings: [], result: null, error: null, final: null,
};

function rerender() { if (window.MS && window.MS.S.route === 'derush') window.MS.render(); }
function esc(s) { return window.MS.esc(s == null ? '' : String(s)); }
const base = (p) => String(p || '').split(/[\\/]/).filter(Boolean).pop() || '';

// --- appel du moteur : promesse résolue avec le message "result"
let seq = 0;
function engine(args, config, onLine) {
  const id = `d${Date.now()}_${++seq}`;
  return new Promise((resolve, reject) => {
    let result = null, error = null, un = null;
    T.event.listen('derush-line', (e) => {
      const p = e.payload; if (p.id !== id) return;
      if (p.done) {
        un && un();
        if (result) resolve(result); else reject(new Error(error || `Le moteur s'est arrêté (code ${p.code}).`));
        return;
      }
      let m; try { m = JSON.parse(p.line); } catch (_) { return; }
      if (m.type === 'result') result = m;
      else if (m.type === 'error') error = m.msg;
      else onLine && onLine(m);
    }).then((f) => {
      un = f;
      invoke('derush_exec', { id, args, config: config ? JSON.stringify(config) : null }).catch((e) => { un && un(); reject(new Error(String(e))); });
    });
  });
}

async function pickFolder() {
  const dir = await invoke('plugin:dialog|open', { options: { directory: true, title: "Dossier des rushes de l'épisode" } }).catch(() => null);
  if (!dir) return;
  Object.assign(D, { phase: 'scanning', folder: dir, name: base(dir), scan: null, error: null, result: null, final: null, logs: [], warnings: [] });
  rerender();
  try {
    const r = await engine(['scan', dir]);
    D.scan = r;
    const people = r.cams.filter((c) => c.role !== 'wide').map((c) => c.label);
    D.cams = r.cams.map((c) => ({ label: c.label, files: c.files, role: c.role === 'wide' ? 'wide' : c.label }));
    let k = 0;
    D.mics = r.mics.map((m) => ({ label: m.label, folder: m.folder || '', path: m.path, use: !!m.use, duration: m.duration,
      speaker: m.use ? (people[k++] || m.label) : m.label }));
    D.phase = 'config';
  } catch (e) { D.phase = 'error'; D.error = e.message; }
  rerender();
}

async function run() {
  const speakers = D.mics.filter((m) => m.use).map((m) => m.speaker.trim());
  if (!speakers.length) return window.MS.toast('Coche au moins un micro.');
  if (new Set(speakers).size !== speakers.length) return window.MS.toast('Deux micros ont le même nom : chaque micro doit correspondre à une personne.');
  if (!D.cams.some((c) => speakers.includes(c.role))) return window.MS.toast('Indique au moins une caméra qui filme une des personnes.');
  const cfg = { name: D.name.trim() || base(D.folder), root: D.folder, out_dir: D.folder,
    cams: D.cams.map((c) => ({ label: c.label, files: c.files, role: c.role })),
    mics: D.mics.map((m) => ({ label: m.label, path: m.path, speaker: m.speaker.trim(), use: m.use })),
    options: { wide: D.wide } };
  Object.assign(D, { phase: 'running', pct: 0, msg: 'Démarrage…', logs: [], warnings: [] });
  rerender();
  try {
    D.result = await engine(['run'], cfg, (m) => {
      if (m.type === 'step') { if (m.pct != null) D.pct = m.pct; if (m.msg) D.msg = m.msg; }
      else if (m.type === 'log') D.logs.push(m.msg);
      else if (m.type === 'warning') D.warnings.push(m.msg);
      rerender();
    });
    D.phase = 'done';
  } catch (e) { D.phase = 'error'; D.error = e.message; }
  rerender();
}

async function openPremiere() {
  try { await invoke('open_in_premiere', { path: D.result.xml }); window.MS.toast('Premiere s\'ouvre avec le projet.'); }
  catch (e) { window.MS.toast(String(e)); }
}

async function finalize() {
  const file = await invoke('plugin:dialog|open', { options: { title: 'Projet Premiere enregistré', filters: [{ name: 'Projet Premiere', extensions: ['prproj'] }], defaultPath: D.folder } }).catch(() => null);
  if (!file) return;
  D.phase = 'finalizing'; rerender();
  try { D.final = await engine(['finalize', file, D.result.plan]); D.final.file = file; D.phase = 'finalized'; }
  catch (e) { D.phase = 'error'; D.error = e.message; }
  rerender();
}

// --- rendu
function camRow(c, i, speakers) {
  const opts = [...speakers.map((s) => [s, `Filme ${s}`]), ['wide', 'Plan large'], ['ignore', 'Ne pas utiliser']];
  return `<div class="item"><div class="grow"><div class="t">${esc(c.label)}</div><div class="s">${c.files.length} fichier${c.files.length > 1 ? 's' : ''} · ${esc(c.files.map(base).join(', '))}</div></div>
    <select class="in" style="width:auto" data-dr-cam="${i}">${opts.map(([v, t]) => `<option value="${esc(v)}" ${c.role === v ? 'selected' : ''}>${esc(t)}</option>`).join('')}</select></div>`;
}
function micRow(m, i) {
  return `<div class="item"><label class="row" style="gap:10px;flex:1;min-width:0"><input type="checkbox" data-dr-use="${i}" ${m.use ? 'checked' : ''}>
    <div class="grow"><div class="t">${esc(m.label)}</div><div class="s">${esc(m.folder)}${m.duration ? ` · ${Math.round(m.duration / 60)} min` : ''}${m.use ? '' : ' · ignoré'}</div></div></label>
    <input class="in" style="width:180px" data-dr-spk="${i}" value="${esc(m.speaker)}" placeholder="Qui parle dans ce micro" ${m.use ? '' : 'disabled'}></div>`;
}

function page() {
  const hdr = `<div class="top"><div><div class="lbl">Hors ligne · syncro et multicam</div><h1>Dérush</h1></div></div>`;
  const how = `<p class="lbl" style="margin-top:6px">Un sous-dossier par caméra, les fichiers son des micros dans le même dossier d'épisode. Le moteur synchronise tout sur les micros, coupe sur la personne qui parle et prépare le projet Premiere (SYNCRO, MULTICAM, MONTAGE).</p>`;
  if (D.phase === 'idle') return `${hdr}<div class="card"><h2>Nouvel épisode</h2>${how}<div style="margin-top:16px"><button class="btn pri" data-dr="pick">Choisir le dossier des rushes</button></div></div>`;
  if (D.phase === 'scanning') return `${hdr}<div class="card"><h2>${esc(base(D.folder))}</h2><p class="lbl">Recherche des caméras et des micros…</p></div>`;
  if (D.phase === 'error') return `${hdr}<div class="card"><h2>Ça n'a pas marché</h2><p style="margin-top:8px">${esc(D.error)}</p><div class="row" style="gap:8px;margin-top:16px"><button class="btn" data-dr="reset">Recommencer</button>${D.scan ? '<button class="btn pri" data-dr="back">Revenir aux réglages</button>' : ''}</div></div>`;
  if (D.phase === 'config') {
    const speakers = D.mics.filter((m) => m.use).map((m) => m.speaker.trim()).filter(Boolean);
    return `${hdr}<div class="card"><div class="card-head"><div><h2>${esc(base(D.folder))}</h2><div class="lbl" style="margin-top:3px">Vérifie qui filme qui et qui parle dans quel micro</div></div><button class="btn sm" data-dr="pick">Autre dossier</button></div>
      <div class="lbl" style="margin:4px 0 6px">Nom du projet</div><input class="in" data-dr-name value="${esc(D.name)}">
      <div class="day-h" style="margin:18px 0 4px">Micros</div><div class="list">${D.mics.map(micRow).join('') || '<div class="empty">Aucun fichier son trouvé.</div>'}</div>
      <div class="day-h" style="margin:18px 0 4px">Caméras</div><div class="list">${D.cams.map((c, i) => camRow(c, i, speakers)).join('') || '<div class="empty">Aucune vidéo trouvée.</div>'}</div>
      <div class="day-h" style="margin:18px 0 4px">Plan large</div>
      <select class="in" data-dr-wide style="width:auto">${[['none', 'Jamais'], ['overlap', 'Quand ils parlent en même temps'], ['overlap+breath', 'Aussi toutes les 30 s dans les longues réponses']].map(([v, t]) => `<option value="${v}" ${D.wide === v ? 'selected' : ''}>${t}</option>`).join('')}</select>
      <div style="margin-top:20px"><button class="btn pri" data-dr="run">Lancer le dérush</button></div></div>`;
  }
  if (D.phase === 'running') return `${hdr}<div class="card"><h2>${esc(D.name)}</h2><p class="lbl" style="margin-top:6px">${esc(D.msg)}</p>
      <div style="height:8px;border-radius:6px;background:var(--card3);margin-top:14px;overflow:hidden"><div style="height:100%;width:${D.pct}%;background:var(--blue)"></div></div>
      ${D.logs.length ? `<div class="lbl" style="margin-top:14px;white-space:pre-wrap">${esc(D.logs.slice(-6).join('\n'))}</div>` : ''}</div>`;
  const st = D.result && D.result.stats;
  const summary = st ? `<p style="margin-top:8px">${st.shots} plans, ${st.avg_shot_s} s en moyenne · ${Object.entries(st.per_angle_pct).map(([k, v]) => `${esc(k)} ${v} %`).join(' · ')}</p>` : '';
  const warns = D.warnings.length ? `<div class="card next" style="--c:#F5A524;margin-top:12px;padding:12px 14px">${D.warnings.map(esc).join('<br>')}</div>` : '';
  const syncs = D.logs.length ? `<div class="lbl" style="margin-top:10px;white-space:pre-wrap">${esc(D.logs.join('\n'))}</div>` : '';
  if (D.phase === 'done' || D.phase === 'finalizing') return `${hdr}<div class="card"><h2>Synchro et découpage prêts</h2>${summary}${syncs}${warns}
      <div class="day-h" style="margin:18px 0 6px">Dernière étape dans Premiere</div>
      <ol class="lbl" style="line-height:1.8;padding-left:18px"><li>Ouvre le projet dans Premiere.</li><li>Enregistre-le dans le dossier de l'épisode (Fichier › Enregistrer sous), puis ferme-le.</li><li>Clique sur « Finaliser » et choisis ce projet : le multicam et les micros sont réglés.</li></ol>
      <div class="row" style="gap:8px;margin-top:16px;flex-wrap:wrap"><button class="btn" data-dr="premiere">Ouvrir dans Premiere</button><button class="btn pri" data-dr="finalize" ${D.phase === 'finalizing' ? 'disabled' : ''}>${D.phase === 'finalizing' ? 'Finalisation…' : 'Finaliser le projet'}</button><button class="btn" data-dr="reset">Nouvel épisode</button></div></div>`;
  if (D.phase === 'finalized') return `${hdr}<div class="card"><h2>Projet prêt</h2><p style="margin-top:8px">${D.final.multicam} plans multicam activés, ${D.final.muted} morceaux de micro coupés pendant que la personne écoute.</p>
      <p class="lbl" style="margin-top:6px">${esc(base(D.final.file))} · une copie de sécurité « .avant-minima » est à côté.</p>
      <div class="row" style="gap:8px;margin-top:16px"><button class="btn pri" data-dr="reopen">Rouvrir dans Premiere</button><button class="btn" data-dr="reset">Nouvel épisode</button></div></div>`;
  return hdr;
}

// --- événements (délégués : la page est re-rendue par app.js)
document.addEventListener('click', (e) => {
  const b = e.target.closest('[data-dr]'); if (!b) return;
  const a = b.dataset.dr;
  if (a === 'pick') pickFolder();
  else if (a === 'run') run();
  else if (a === 'premiere') openPremiere();
  else if (a === 'finalize') finalize();
  else if (a === 'reopen') invoke('open_in_premiere', { path: D.final.file }).catch((x) => window.MS.toast(String(x)));
  else if (a === 'back') { D.phase = 'config'; rerender(); }
  else if (a === 'reset') { Object.assign(D, { phase: 'idle', folder: null, scan: null, result: null, final: null, error: null }); rerender(); }
});
document.addEventListener('change', (e) => {
  const t = e.target;
  if (t.dataset.drCam != null) { D.cams[+t.dataset.drCam].role = t.value; }
  else if (t.dataset.drUse != null) { D.mics[+t.dataset.drUse].use = t.checked; rerender(); }
  else if (t.dataset.drWide != null) { D.wide = t.value; }
});
document.addEventListener('input', (e) => {
  const t = e.target;
  if (t.dataset.drSpk != null) {
    const m = D.mics[+t.dataset.drSpk]; const old = m.speaker; m.speaker = t.value;
    D.cams.forEach((c) => { if (c.role === old) c.role = t.value; });
  } else if (t.dataset.drName != null) D.name = t.value;
});
document.addEventListener('focusout', (e) => { if (e.target.dataset && e.target.dataset.drSpk != null) rerender(); });

if (T) {
  window.MSDerush = { page };
  const go = () => { try { window.MS.render(); } catch (_) { /* pas encore connecté */ } };
  if (window.MS) go(); else window.addEventListener('ms-ready', go, { once: true });
}
