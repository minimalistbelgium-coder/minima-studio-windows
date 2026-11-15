// Tableau « Apps et site » de Minima Studio (admin uniquement).
// Rassemble : FastSign / MinimaClap / Agora (base FastSign, chiffres agrégés), App Store Connect
// (téléchargements, revenus, abonnements), Instagram et Cloudflare Web Analytics. Résultat gardé 1 h en cache.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { SignJWT, importPKCS8 } from 'npm:jose@5.9.6';

const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, apikey, x-client-info', 'Access-Control-Allow-Methods': 'POST, GET, OPTIONS' };
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } });
const URL_ = Deno.env.get('SUPABASE_URL')!;
const sb = createClient(URL_, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });

const FASTSIGN_URL = 'https://jkcuftjcmexvjluydagl.supabase.co';
const FASTSIGN_ANON = 'sb_publishable_cGfUhAK9rwQEp4tVck8U9g_fxFkbs_V';

const ymd = (d: Date) => d.toISOString().slice(0, 10);
const daysAgo = (n: number) => { const d = new Date(); d.setUTCDate(d.getUTCDate() - n); return d; };

async function secrets(): Promise<Record<string, string>> {
  const { data } = await sb.from('app_secrets').select('key,value');
  return Object.fromEntries((data || []).map((r) => [r.key, r.value]));
}

// ---------- base FastSign (FastSign, MinimaClap, Agora) ----------
async function fastsign(key?: string) {
  if (!key) return { ok: false, error: 'Clé interne manquante' };
  const r = await fetch(`${FASTSIGN_URL}/rest/v1/rpc/ms_stats`, {
    method: 'POST', headers: { apikey: FASTSIGN_ANON, Authorization: `Bearer ${FASTSIGN_ANON}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ k: key }),
  });
  if (!r.ok) return { ok: false, error: `FastSign ${r.status}` };
  return { ok: true, ...(await r.json()) };
}

// ---------- App Store Connect : rapports de ventes quotidiens ----------
async function ascToken(s: Record<string, string>) {
  const pem = s.asc_private_key.includes('BEGIN') ? s.asc_private_key : `-----BEGIN PRIVATE KEY-----\n${s.asc_private_key}\n-----END PRIVATE KEY-----`;
  const key = await importPKCS8(pem.replace(/\\n/g, '\n'), 'ES256');
  return new SignJWT({}).setProtectedHeader({ alg: 'ES256', kid: s.asc_key_id, typ: 'JWT' })
    .setIssuer(s.asc_issuer_id).setIssuedAt().setExpirationTime('15m').setAudience('appstoreconnect-v1').sign(key);
}

async function gunzipText(buf: ArrayBuffer) {
  const stream = new Blob([buf]).stream().pipeThrough(new DecompressionStream('gzip'));
  return await new Response(stream).text();
}

// Types de produits Apple : téléchargements (1, 1F, 1T, F1…), retéléchargements (3…), mises à jour (7…), achats intégrés et abonnements (IA…)
const isDownload = (t: string) => ['1', '1F', '1T', 'F1', '1E', '1EP', '1EU'].includes(t);
const isRedownload = (t: string) => ['3', '3F', '3T', 'F3'].includes(t);
const isUpdate = (t: string) => ['7', '7F', '7T', 'F7'].includes(t);
const DEVICES: Record<string, string> = { iPhone: 'iPhone', iPad: 'iPad', Desktop: 'Mac', 'Apple TV': 'Apple TV', 'Apple Watch': 'Apple Watch', 'iPod touch': 'iPod' };

async function salesReport(s: Record<string, string>, token: string, day: string) {
  const u = `https://api.appstoreconnect.apple.com/v1/salesReports?filter[frequency]=DAILY&filter[reportDate]=${day}&filter[reportSubType]=SUMMARY&filter[reportType]=SALES&filter[vendorNumber]=${encodeURIComponent(s.asc_vendor_number)}`;
  const r = await fetch(u, { headers: { Authorization: `Bearer ${token}`, Accept: 'application/a-gzip' } });
  if (r.status === 404) return { status: 404 as const, rows: [] as Record<string, string>[] };
  if (!r.ok) return { status: r.status, error: `App Store ${r.status} : ${(await r.text()).slice(0, 160)}`, rows: [] as Record<string, string>[] };
  const lines = (await gunzipText(await r.arrayBuffer())).trim().split('\n');
  const head = lines.shift()!.split('\t');
  return { status: 200, rows: lines.map((l) => { const f = l.split('\t'); return Object.fromEntries(head.map((h, i) => [h, f[i] ?? ''])); }) };
}
const isIap = (t: string) => t.startsWith('IA') || t === 'FI1';

type AppAgg = { name: string; appleId: string; downloads: number; downloads7: number; redownloads: number; updates: number; proceeds: Record<string, number>; iapUnits: number;
  countries: Record<string, number>; devices: Record<string, number>; daily: Record<string, number>; rating?: number | null; ratings?: number; version?: string; released?: string; icon?: string; url?: string };

async function appStore(s: Record<string, string>) {
  const need = ['asc_issuer_id', 'asc_key_id', 'asc_private_key', 'asc_vendor_number'];
  if (need.some((k) => !s[k])) return { ok: false, missing: true };
  let token: string;
  try { token = await ascToken(s); } catch (e) { return { ok: false, error: 'Clé privée illisible : ' + String(e).slice(0, 120) }; }
  // Les rapports quotidiens arrivent avec 1 à 2 jours de retard : on lit les 30 derniers disponibles.
  const days = Array.from({ length: 30 }, (_, i) => ymd(daysAgo(i + 1)));
  const apps: Record<string, AppAgg> = {};
  const daily: Record<string, number> = {};
  let lastError = ''; let lastDay = '';
  await Promise.all(days.map(async (day, i) => {
    const rep = await salesReport(s, token, day);
    if (rep.status === 404) return; // pas de ventes ce jour-là, ou rapport pas encore prêt
    if (rep.status !== 200) { lastError = rep.error || ''; return; }
    if (day > lastDay) lastDay = day;
    for (const f of rep.rows) {
      const type = f['Product Type Identifier'] || ''; const units = Number(f['Units'] || 0);
      // Un achat intégré pointe vers son app par « Parent Identifier » (le SKU de l'app)
      const appKey = isIap(type) ? (f['Parent Identifier'] || f['SKU']) : (f['SKU'] || f['Apple Identifier']);
      const a = (apps[appKey] ||= { name: isIap(type) ? appKey : f['Title'], appleId: '', downloads: 0, downloads7: 0, redownloads: 0, updates: 0, proceeds: {}, iapUnits: 0, countries: {}, devices: {}, daily: {} });
      if (!isIap(type) && f['Title']) { a.name = f['Title']; a.appleId = f['Apple Identifier'] || a.appleId; }
      if (isDownload(type)) {
        a.downloads += units; if (i < 7) a.downloads7 += units; daily[day] = (daily[day] || 0) + units;
        a.daily[day] = (a.daily[day] || 0) + units;
        const c = f['Country Code'] || '?'; a.countries[c] = (a.countries[c] || 0) + units;
        const dv = DEVICES[f['Device']] || f['Device'] || '?'; a.devices[dv] = (a.devices[dv] || 0) + units;
      }
      if (isRedownload(type)) a.redownloads += units;
      if (isUpdate(type)) a.updates += units;
      if (isIap(type)) a.iapUnits += units;
      const p = Number(f['Developer Proceeds'] || 0) * units;
      if (p) a.proceeds[f['Currency of Proceeds'] || '?'] = (a.proceeds[f['Currency of Proceeds'] || '?'] || 0) + p;
    }
  }));
  if (lastError && !Object.keys(apps).length) return { ok: false, error: lastError };
  // Note, version et icône publiques (App Store belge)
  const list = Object.values(apps).filter((a) => a.appleId);
  if (list.length) {
    try {
      const r = await fetch(`https://itunes.apple.com/lookup?id=${list.map((a) => a.appleId).join(',')}&country=be`);
      const j = await r.json();
      for (const it of j.results || []) {
        const a = list.find((x) => x.appleId === String(it.trackId));
        if (!a) continue;
        a.rating = it.userRatingCount ? it.averageUserRating : null; a.ratings = it.userRatingCount || 0;
        a.version = it.version; a.released = it.currentVersionReleaseDate; a.icon = it.artworkUrl100; a.url = it.trackViewUrl;
      }
    } catch (_) { /* pas grave */ }
  }
  const order = days.slice().reverse();
  return {
    ok: true, lastDay,
    apps: Object.values(apps).map((a) => ({ ...a, daily: order.map((d) => ({ d, n: a.daily[d] || 0 })) })),
    daily: order.map((d) => ({ d, n: daily[d] || 0 })),
  };
}

// ---------- Notification quotidienne des téléchargements (appelée par pg_cron) ----------
const nextDay = (d: string) => { const x = new Date(d + 'T00:00:00Z'); x.setUTCDate(x.getUTCDate() + 1); return ymd(x); };
const frDay = (d: string) => new Date(d + 'T12:00:00Z').toLocaleDateString('fr-BE', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'UTC' });
// Sur l'App Store, MinimaClap s'appelle encore Topclap : on garde le bon nom dans les notifications
const shortName = (t: string) => (t || '').split(/\s+[:\-–]\s+/)[0].trim().replace(/topclap|minimatime/gi, 'MinimaClap');

async function dailyDownloads(s: Record<string, string>) {
  const need = ['asc_issuer_id', 'asc_key_id', 'asc_private_key', 'asc_vendor_number'];
  if (need.some((k) => !s[k])) return { ok: false, missing: true };
  const token = await ascToken(s);
  const { data: st } = await sb.from('app_notif_state').select('value').eq('key', 'asc_last_day').maybeSingle();
  let last = st?.value || ymd(daysAgo(3));
  const yesterday = ymd(daysAgo(1)); const sent: string[] = [];
  for (let d = nextDay(last); d <= yesterday; d = nextDay(d)) {
    const rep = await salesReport(s, token, d);
    if (rep.status === 404) {
      // Rapport pas encore prêt : on attend, sauf s'il a plus de 3 jours (alors aucune vente ce jour-là)
      if (d >= ymd(daysAgo(3))) break;
    } else if (rep.status !== 200) break;
    else {
      const per: Record<string, { n: number; re: number }> = {};
      for (const f of rep.rows) {
        const t = f['Product Type Identifier'] || ''; const u = Number(f['Units'] || 0);
        if (!isDownload(t) && !isRedownload(t)) continue;
        const k = shortName(f['Title']); const o = (per[k] ||= { n: 0, re: 0 });
        if (isDownload(t)) o.n += u; else o.re += u;
      }
      const total = Object.values(per).reduce((x, o) => x + o.n, 0);
      const re = Object.values(per).reduce((x, o) => x + o.re, 0);
      if (total > 0 || re > 0) {
        const parts = Object.entries(per).filter(([, o]) => o.n > 0).sort((a, b) => b[1].n - a[1].n).map(([k, o]) => `${k} ${o.n}`);
        const title = total > 0 ? `${total} téléchargement${total > 1 ? 's' : ''} ${frDay(d).split(' ')[0]}` : `${re} retéléchargement${re > 1 ? 's' : ''} ${frDay(d).split(' ')[0]}`;
        const body = `${parts.join(' · ')}${parts.length ? '. ' : ''}${re ? `${re} retéléchargement${re > 1 ? 's' : ''}. ` : ''}Chiffres Apple du ${frDay(d)}.`;
        await sb.rpc('notify_admins_app', { t: title, b: body });
        sent.push(d);
      }
    }
    last = d;
    await sb.from('app_notif_state').upsert({ key: 'asc_last_day', value: last, at: new Date().toISOString() });
  }
  return { ok: true, last, sent };
}

// ---------- App Store Connect : abonnements actifs (dernier rapport disponible) ----------
async function subscriptions(s: Record<string, string>) {
  const need = ['asc_issuer_id', 'asc_key_id', 'asc_private_key', 'asc_vendor_number'];
  if (need.some((k) => !s[k])) return { ok: false, missing: true };
  const token = await ascToken(s);
  for (let back = 1; back <= 5; back++) {
    const day = ymd(daysAgo(back));
    const u = `https://api.appstoreconnect.apple.com/v1/salesReports?filter[frequency]=DAILY&filter[reportDate]=${day}&filter[reportSubType]=SUMMARY&filter[reportType]=SUBSCRIPTION&filter[vendorNumber]=${encodeURIComponent(s.asc_vendor_number)}&filter[version]=1_3`;
    const r = await fetch(u, { headers: { Authorization: `Bearer ${token}`, Accept: 'application/a-gzip' } });
    if (r.status === 404) continue;
    if (!r.ok) return { ok: false, error: `Abonnements ${r.status} : ${(await r.text()).slice(0, 160)}` };
    const lines = (await gunzipText(await r.arrayBuffer())).trim().split('\n');
    const head = lines.shift()!.split('\t');
    const cApp = head.indexOf('App Name'), cSub = head.indexOf('Subscription Name');
    const paidCols = head.map((h, i) => (/^Active (Standard|Pay)/i.test(h) ? i : -1)).filter((i) => i >= 0);
    const trialCols = head.map((h, i) => (/Free Trial/i.test(h) ? i : -1)).filter((i) => i >= 0);
    const out: Record<string, { app: string; plan: string; paid: number; trial: number }> = {};
    for (const l of lines) {
      const f = l.split('\t');
      const k = `${f[cApp]}|${f[cSub]}`;
      const o = (out[k] ||= { app: f[cApp], plan: f[cSub], paid: 0, trial: 0 });
      paidCols.forEach((i) => { o.paid += Number(f[i] || 0); });
      trialCols.forEach((i) => { o.trial += Number(f[i] || 0); });
    }
    return { ok: true, day, plans: Object.values(out) };
  }
  return { ok: true, day: null, plans: [] };
}

// ---------- Instagram (via le jeton d'Agora, dans le projet FastSign) ----------
async function instagram(key?: string) {
  if (!key) return { ok: false, error: 'Clé interne manquante' };
  const { data: list } = await sb.from('ig_accounts').select('handle,label,sort').order('sort');
  const handles = (list || []).map((a) => a.handle);
  if (!handles.length) return { ok: true, accounts: [] };
  const r = await fetch(`${FASTSIGN_URL}/functions/v1/ms-instagram`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ k: key, handles }) });
  const j = await r.json().catch(() => ({}));
  if (!j.ok) return { ok: false, error: j.error || `Instagram ${r.status}` };
  // Relevé du jour et comparaison avec il y a 7 et 30 jours
  const today = ymd(new Date());
  const rows = j.accounts.filter((a: any) => a.ok && a.followers != null).map((a: any) => ({ handle: a.handle, day: today, followers: a.followers, posts: a.posts }));
  if (rows.length) await sb.from('ig_snapshots').upsert(rows);
  const { data: hist } = await sb.from('ig_snapshots').select('handle,day,followers').gte('day', ymd(daysAgo(31))).order('day');
  const past = (h: string, n: number) => {
    const lim = ymd(daysAgo(n));
    const older = (hist || []).filter((x) => x.handle === h && x.day <= lim);
    return older.length ? older[older.length - 1].followers : null;
  };
  await markPublished(j.accounts).catch((e) => console.error('programme', e));
  const labels = Object.fromEntries((list || []).map((a) => [a.handle, a.label]));
  return {
    ok: true,
    accounts: j.accounts.map((a: any) => ({
      ...a, label: labels[a.handle] || a.name,
      d7: a.followers != null && past(a.handle, 7) != null ? a.followers - past(a.handle, 7)! : null,
      d30: a.followers != null && past(a.handle, 30) != null ? a.followers - past(a.handle, 30)! : null,
      series: (hist || []).filter((x) => x.handle === a.handle).map((x) => ({ d: x.day, n: x.followers })),
    })),
  };
}

// ---------- Programme de publication ----------
const brusselsDay = (iso: string) => new Date(iso).toLocaleDateString('en-CA', { timeZone: 'Europe/Brussels' });
async function markPublished(accounts: any[]) {
  const since = new Date(Date.now() - 21 * 86400_000).toISOString();
  const { data: rows } = await sb.from('ig_schedule').select('id,handle,at,format,status').gte('at', since).lte('at', new Date(Date.now() + 86400_000).toISOString()).neq('format', 'Story').neq('status', 'Publié');
  if (!rows?.length) return;
  const used = new Set<number>();
  for (const a of accounts) {
    if (!a.ok) continue;
    for (const m of a.media || []) {
      if (!m.at) continue;
      const day = brusselsDay(m.at);
      const want = m.type === 'CAROUSEL_ALBUM' ? 'Carrousel' : m.type === 'VIDEO' ? 'Reel' : null;
      const cands = rows.filter((r) => r.handle === a.handle && !used.has(r.id) && brusselsDay(r.at) === day);
      const hit = cands.find((r) => r.format === want) || cands.find((r) => r.format !== "Reel d'essai") || cands[0];
      if (!hit) continue;
      used.add(hit.id);
      await sb.from('ig_schedule').update({ status: 'Publié', post_url: m.url || null, updated_at: new Date().toISOString() }).eq('id', hit.id);
    }
  }
}

async function schedule() {
  const from = new Date(Date.now() - 14 * 86400_000).toISOString(), to = new Date(Date.now() + 28 * 86400_000).toISOString();
  const { data, error } = await sb.from('ig_schedule').select('id,handle,at,format,title,status,ref,post_url').gte('at', from).lte('at', to).order('at');
  if (error) return { ok: false, error: error.message };
  const { data: todo } = await sb.from('ig_schedule').select('id,handle,at,title').eq('status', 'À créer').order('at');
  const { data: last } = await sb.from('ig_schedule').select('handle,at').order('at', { ascending: false }).limit(1);
  return { ok: true, rows: data || [], todo: todo || [], until: last?.[0]?.at || null };
}

// ---------- Cloudflare Web Analytics ----------
async function website(s: Record<string, string>) {
  if (!s.cf_api_token || !s.cf_account_id || !s.cf_site_tag) return { ok: false, missing: true };
  const from = ymd(daysAgo(30)), to = ymd(new Date()), from7 = ymd(daysAgo(7));
  const filt = (f: string) => `{siteTag: $site, date_geq: "${f}", date_leq: "${to}"}`;
  const query = `query($acc: String!, $site: String!) { viewer { accounts(filter: {accountTag: $acc}) {
    days: rumPageloadEventsAdaptiveGroups(limit: 40, filter: ${filt(from)}, orderBy: [date_ASC]) { count sum { visits } dimensions { date } }
    pages: rumPageloadEventsAdaptiveGroups(limit: 8, filter: ${filt(from)}, orderBy: [count_DESC]) { count dimensions { requestPath } }
    countries: rumPageloadEventsAdaptiveGroups(limit: 6, filter: ${filt(from)}, orderBy: [count_DESC]) { count dimensions { countryName } }
    refs: rumPageloadEventsAdaptiveGroups(limit: 6, filter: ${filt(from)}, orderBy: [count_DESC]) { count dimensions { refererHost } }
    week: rumPageloadEventsAdaptiveGroups(limit: 1, filter: ${filt(from7)}) { count sum { visits } }
  } } }`;
  const r = await fetch('https://api.cloudflare.com/client/v4/graphql', {
    method: 'POST', headers: { Authorization: `Bearer ${s.cf_api_token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query, variables: { acc: s.cf_account_id, site: s.cf_site_tag } }),
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok || j.errors?.length) return { ok: false, error: (j.errors?.[0]?.message || `Cloudflare ${r.status}`).slice(0, 200) };
  const a = j.data?.viewer?.accounts?.[0] || {};
  return {
    ok: true,
    days: (a.days || []).map((x: any) => ({ d: x.dimensions.date, views: x.count, visits: x.sum?.visits || 0 })),
    pages: (a.pages || []).map((x: any) => ({ k: x.dimensions.requestPath, n: x.count })),
    countries: (a.countries || []).map((x: any) => ({ k: x.dimensions.countryName, n: x.count })),
    refs: (a.refs || []).map((x: any) => ({ k: x.dimensions.refererHost || 'Accès direct', n: x.count })),
    week: { views: a.week?.[0]?.count || 0, visits: a.week?.[0]?.sum?.visits || 0 },
  };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: cors });
  const mode = new URL(req.url).searchParams.get('mode');
  // Tâche planifiée (pg_cron) : notification des téléchargements de la veille
  if (mode === 'daily') {
    const s = await secrets();
    if (!s.cron_key || req.headers.get('x-cron-key') !== s.cron_key) return json({ error: 'forbidden' }, 403);
    try { return json(await dailyDownloads(s)); } catch (e) { return json({ ok: false, error: String(e).slice(0, 200) }, 500); }
  }
  // Admin seulement
  const auth = req.headers.get('Authorization') || '';
  const user = createClient(URL_, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: auth } }, auth: { persistSession: false } });
  const { data: admin } = await user.rpc('is_admin');
  if (admin !== true) return json({ error: 'forbidden' }, 403);

  const refresh = new URL(req.url).searchParams.get('refresh') === '1';
  if (!refresh) {
    const { data: c } = await sb.from('app_stats_cache').select('data,at').eq('key', 'all').maybeSingle();
    if (c && Date.now() - new Date(c.at).getTime() < 3600_000) return json({ ...c.data, sched: await schedule(), cached: c.at });
  }
  const s = await secrets();
  const [base, store, site, ig, subs] = await Promise.all([
    fastsign(s.fastsign_stats_key).catch((e) => ({ ok: false, error: String(e) })),
    appStore(s).catch((e) => ({ ok: false, error: String(e).slice(0, 200) })),
    website(s).catch((e) => ({ ok: false, error: String(e).slice(0, 200) })),
    instagram(s.fastsign_stats_key).catch((e) => ({ ok: false, error: String(e).slice(0, 200) })),
    subscriptions(s).catch((e) => ({ ok: false, error: String(e).slice(0, 200) })),
  ]);
  // Le programme se lit après Instagram (qui coche les posts publiés) et n'est jamais mis en cache
  const out = { base, store, site, ig, subs, at: new Date().toISOString() };
  await sb.from('app_stats_cache').upsert({ key: 'all', data: out, at: out.at });
  return json({ ...out, sched: await schedule() });
});
