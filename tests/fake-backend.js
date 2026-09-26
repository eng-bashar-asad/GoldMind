// Stands in for the CDNs and Supabase so pages run without internet or real data.
const fs = require('fs'), path = require('path');
const SUPABASE_UMD = fs.readFileSync(require.resolve('@supabase/supabase-js/dist/umd/supabase.js'), 'utf8');
const STORE = '11111111-1111-1111-1111-111111111111';
const USER = '22222222-2222-2222-2222-222222222222';
const STAFF = '33333333-3333-3333-3333-333333333333';

function fakeSession() {
  const exp = Math.floor(Date.now() / 1000) + 3600;
  const b64 = o => Buffer.from(JSON.stringify(o)).toString('base64url');
  const jwt = b64({ alg: 'HS256', typ: 'JWT' }) + '.' + b64({ sub: USER, exp, role: 'authenticated' }) + '.sig';
  return { access_token: jwt, refresh_token: 'r', token_type: 'bearer', expires_in: 3600, expires_at: exp,
    user: { id: USER, email: 't@example.com', aud: 'authenticated', role: 'authenticated' } };
}

function matches(row, key, expr) {
  const m = /^(eq|neq|gt|gte|lt|lte|in|is|ilike)\.(.*)$/.exec(expr); if (!m) return true;
  const v = row[key], raw = m[2];
  switch (m[1]) {
    case 'eq': return String(v) === raw; case 'neq': return String(v) !== raw;
    case 'gt': return Number(v) > Number(raw); case 'gte': return Number(v) >= Number(raw);
    case 'lt': return Number(v) < Number(raw); case 'lte': return Number(v) <= Number(raw);
    case 'in': return raw.replace(/[()"]/g, '').split(',').includes(String(v));
    case 'is': return raw === 'null' ? v == null : String(v) === raw;
    default: return v != null && String(v).toLowerCase().includes(raw.replace(/[*%]/g, '').toLowerCase());
  }
}

// db: { table: rows[] }, rpc: { name: (args) => ({status, body}) }
async function install(page, { db = {}, rpc = {}, generic = false, realCdn = false } = {}) {
  const calls = [];
  // Playwright's offline mode doesn't stop routed requests, so we cut them here.
  const state = { offline: false };
  page.__gmNet = state;
  if (!realCdn) await page.route(/cdn\.tailwindcss\.com/, r => r.fulfill({ contentType: 'text/javascript', body: 'window.tailwind={config:{}};' }));
  await page.route(/cdn\.jsdelivr\.net\/npm\/@supabase/, r => r.fulfill({ contentType: 'text/javascript', body: SUPABASE_UMD }));
  if (!realCdn) await page.route(/fonts\.(googleapis|gstatic)\.com/, r => r.fulfill({ contentType: 'text/css', body: '' }));
  await page.route(/cdnjs\.cloudflare\.com|cdn\.jsdelivr\.net\/npm\/(?!@supabase)|unpkg\.com|api\.github\.com/, r => r.fulfill({ contentType: 'text/javascript', body: '' }));
  await page.route(/\.supabase\.co\//, async route => {
    if (state.offline) return route.abort('internetdisconnected');
    const req = route.request(), url = new URL(req.url());
    const [, kind, name] = url.pathname.match(/^\/(rest\/v1\/rpc|rest\/v1|auth\/v1|storage\/v1)\/?([^/]*)/) || [];
    calls.push({ method: req.method(), kind, name, url: req.url(), body: req.postData() });
    if (kind === 'auth/v1') return route.fulfill({ json: name === 'user' ? fakeSession().user : fakeSession() });
    if (kind === 'rest/v1/rpc') {
      const h = rpc[name];
      const out = h ? await h(JSON.parse(req.postData() || '{}')) : { status: 200, body: null };
      return route.fulfill({ status: out.status || 200, contentType: 'application/json', body: JSON.stringify(out.body) });
    }
    if (kind === 'rest/v1') {
      if (req.method() !== 'GET') return route.fulfill({ status: 201, json: [] });
      let rows = db[name] || (generic ? [genericRow()] : []);
      if (!db[name] && generic) url.searchParams.forEach(() => {}); // generic row matches any filter
      else url.searchParams.forEach((expr, key) => {
        if (['select', 'order', 'limit', 'offset'].includes(key)) return;
        if (key === 'or') return;
        rows = rows.filter(r => matches(r, key, expr));
      });
      const single = (req.headers()['accept'] || '').includes('vnd.pgrst.object');
      if (single) return rows[0] ? route.fulfill({ json: rows[0] }) : route.fulfill({ status: 406, json: { code: 'PGRST116', message: 'none' } });
      return route.fulfill({ json: rows });
    }
    return route.fulfill({ json: {} });
  });
  await page.addInitScript(([s, store, staff, user]) => {
    if (location.protocol !== 'http:') return;
    localStorage.setItem('sb-puzkfwbmipldzgwofhjg-auth-token', JSON.stringify(s));
    localStorage.setItem('goldmind_active_store', store);
    localStorage.setItem('goldmind_last_activity', String(Date.now()));
    localStorage.setItem('gm_membership', JSON.stringify({ user, store, staff }));
  }, [fakeSession(), STORE, STAFF, USER]);
  return calls;
}

function genericRow() {
  return { id: STAFF, store_id: STORE, user_id: USER, role: 'owner', permissions: {}, full_name: 'Test', name: 'Test',
    currency: 'USD', privacy_accepted_at: '2026-01-01T00:00:00Z', karat: 18, price_per_gram: 100, status: 'available' };
}

module.exports = { install, STORE, USER, STAFF };
