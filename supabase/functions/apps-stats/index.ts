// Tableau « Apps et site » de Minima Studio (admin uniquement).
// Rassemble : FastSign / MinimaClap / Agora (base FastSign, chiffres agrégés), App Store Connect
// (téléchargements et revenus) et Cloudflare Web Analytics (visites du site). Résultat gardé 1 h en cache.
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

// Types de produits Apple : téléchargements (1, 1F, 1T, F1…), mises à jour (7…), achats intégrés et abonnements (IA…)
const isDownload = (t: string) => ['1', '1F', '1T', 'F1', '1E', '1EP', '1EU'].includes(t);
const isIap = (t: string) => t.startsWith('IA') || t === 'FI1';

async function appStore(s: Record<string, string>) {
  const need = ['asc_issuer_id', 'asc_key_id', 'asc_private_key', 'asc_vendor_number'];
  if (need.some((k) => !s[k])) return { ok: false, missing: true };
  let token: string;
  try { token = await ascToken(s); } catch (e) { return { ok: false, error: 'Clé privée illisible : ' + String(e).slice(0, 120) }; }
  // Les rapports quotidiens arrivent avec 1 à 2 jours de retard : on lit les 30 derniers disponibles.
  const days = Array.from({ length: 30 }, (_, i) => ymd(daysAgo(i + 1)));
  const apps: Record<string, { name: string; downloads: number; downloads7: number; proceeds: Record<string, number>; iapUnits: number }> = {};
  const daily: Record<string, number> = {};
  let lastError = '';
  await Promise.all(days.map(async (day, i) => {
    const u = `https://api.appstoreconnect.apple.com/v1/salesReports?filter[frequency]=DAILY&filter[reportDate]=${day}&filter[reportSubType]=SUMMARY&filter[reportType]=SALES&filter[vendorNumber]=${encodeURIComponent(s.asc_vendor_number)}`;
    const r = await fetch(u, { headers: { Authorization: `Bearer ${token}`, Accept: 'application/a-gzip' } });
    if (r.status === 404) return; // pas de ventes ce jour-là, ou rapport pas encore prêt
    if (!r.ok) { lastError = `App Store ${r.status} : ${(await r.text()).slice(0, 160)}`; return; }
    const lines = (await gunzipText(await r.arrayBuffer())).trim().split('\n');
    const head = lines.shift()!.split('\t');
    const col = (n: string) => head.indexOf(n);
    const cTitle = col('Title'), cUnits = col('Units'), cProc = col('Developer Proceeds'), cType = col('Product Type Identifier'),
      cCur = col('Currency of Proceeds'), cApple = col('Apple Identifier'), cParent = col('Parent Identifier'), cSku = col('SKU');
    for (const l of lines) {
      const f = l.split('\t');
      const type = f[cType] || ''; const units = Number(f[cUnits] || 0);
      // Un achat intégré pointe vers son app par « Parent Identifier » (le SKU de l'app)
      const appKey = isIap(type) ? (f[cParent] || f[cSku]) : (f[cSku] || f[cApple]);
      const a = (apps[appKey] ||= { name: isIap(type) ? appKey : f[cTitle], downloads: 0, downloads7: 0, proceeds: {}, iapUnits: 0 });
      if (!isIap(type) && f[cTitle]) a.name = f[cTitle];
      if (isDownload(type)) { a.downloads += units; if (i < 7) a.downloads7 += units; daily[day] = (daily[day] || 0) + units; }
      if (isIap(type)) a.iapUnits += units;
      const p = Number(f[cProc] || 0) * units;
      if (p) a.proceeds[f[cCur] || '?'] = (a.proceeds[f[cCur] || '?'] || 0) + p;
    }
  }));
  if (lastError && !Object.keys(apps).length) return { ok: false, error: lastError };
  return { ok: true, apps: Object.values(apps), daily: days.slice().reverse().map((d) => ({ d, n: daily[d] || 0 })) };
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
  // Admin seulement
  const auth = req.headers.get('Authorization') || '';
  const user = createClient(URL_, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: auth } }, auth: { persistSession: false } });
  const { data: admin } = await user.rpc('is_admin');
  if (admin !== true) return json({ error: 'forbidden' }, 403);

  const refresh = new URL(req.url).searchParams.get('refresh') === '1';
  if (!refresh) {
    const { data: c } = await sb.from('app_stats_cache').select('data,at').eq('key', 'all').maybeSingle();
    if (c && Date.now() - new Date(c.at).getTime() < 3600_000) return json({ ...c.data, cached: c.at });
  }
  const s = await secrets();
  const [base, store, site] = await Promise.all([
    fastsign(s.fastsign_stats_key).catch((e) => ({ ok: false, error: String(e) })),
    appStore(s).catch((e) => ({ ok: false, error: String(e).slice(0, 200) })),
    website(s).catch((e) => ({ ok: false, error: String(e).slice(0, 200) })),
  ]);
  const out = { base, store, site, at: new Date().toISOString() };
  await sb.from('app_stats_cache').upsert({ key: 'all', data: out, at: out.at });
  return json(out);
});
