// GoldMind - Shared Supabase configuration
// Publishable/anon key only - safe to expose in client-side code by design.
const GOLDMIND_SUPABASE_URL = 'https://puzkfwbmipldzgwofhjg.supabase.co';
const GOLDMIND_SUPABASE_KEY = 'sb_publishable_QxjJeGblzseQTvTH87eyZw_19Zu206o';

// International calling codes for the countries offered on
// company-settings-ar.html's "الدولة" field. Used wherever we build a
// wa.me WhatsApp link, so the prefix matches the store's own country
// instead of being hardcoded to one region.
const GOLDMIND_COUNTRY_PHONE_MAP = {
    'AE': '971', 'SA': '966', 'KW': '965', 'QA': '974', 'BH': '973',
    'OM': '968', 'EG': '20', 'JO': '962', 'LB': '961', 'IQ': '964',
    'SY': '963', 'US': '1'
};
const GOLDMIND_DEFAULT_PHONE_CODE = '971'; // fallback if store has no country set

// Resolved per logged-in user. Multi-branch aware: one email can now belong
// to several stores (branches). If the account has more than one, the active
// one is remembered in localStorage and can be changed on switch-branch-ar.html.
let GOLDMIND_STORE_ID = null;

// The staff.id row for the ACTIVE branch. No longer always equal to the auth
// user id now that one email can have a staff row in multiple stores — use
// this (not session.user.id) whenever a query needs a staff.id (created_by,
// staff_id, invited_by, etc).
let GOLDMIND_STAFF_ID = null;

// ---- Offline reads ----
// Every successful data read is kept on the device. When the internet is gone,
// the same read is answered from that copy, and table lookups (barcode, customer
// search...) are answered from the last full snapshot (see gmRefreshSnapshots).
const GM_DATA_CACHE = 'gm-data-v1';
const GM_SNAPSHOT_URL = 'https://gm-snapshot.local/';
function gmIsNetworkError(e) {
    return !navigator.onLine || /Failed to fetch|NetworkError|Network request failed|Load failed|fetch failed/i.test(String(e && (e.message || e)));
}
async function gmFetch(input, init) {
    const req = new Request(input, init);
    const isRead = req.method === 'GET' && req.url.indexOf('/rest/v1/') !== -1;
    try {
        const res = await fetch(req);
        if (isRead && res.ok && window.caches) {
            const copy = res.clone();
            caches.open(GM_DATA_CACHE).then(function (c) { return c.put(req.url, copy); }).catch(function () {});
        }
        return res;
    } catch (e) {
        if (!isRead || !window.caches) throw e;
        const answer = await gmOfflineAnswer(req).catch(function () { return null; });
        if (answer) return answer;
        throw e;
    }
}

// Minimal PostgREST filter emulation over a cached snapshot: eq, neq, gt, gte,
// lt, lte, in, is, or=(x.ilike.*q*,...), limit. select/order are ignored.
// ponytail: embedded relations (select=*,rel(...)) come back without the relation.
function gmMatchFilter(row, col, expr) {
    const m = /^(not\.)?(eq|neq|gt|gte|lt|lte|in|is|ilike|like)\.(.*)$/.exec(expr);
    if (!m) return true;
    const v = row[col], raw = m[3];
    let ok;
    switch (m[2]) {
        case 'eq': ok = String(v) === raw; break;
        case 'neq': ok = String(v) !== raw; break;
        case 'gt': ok = Number(v) > Number(raw); break;
        case 'gte': ok = Number(v) >= Number(raw); break;
        case 'lt': ok = Number(v) < Number(raw); break;
        case 'lte': ok = Number(v) <= Number(raw); break;
        case 'in': ok = raw.replace(/^\(|\)$/g, '').split(',').map(function (x) { return x.replace(/^"|"$/g, ''); }).indexOf(String(v)) !== -1; break;
        case 'is': ok = raw === 'null' ? v == null : String(v) === raw; break;
        default: {
            const needle = raw.replace(/^[*%]|[*%]$/g, '').toLowerCase();
            ok = v != null && String(v).toLowerCase().indexOf(needle) !== -1;
        }
    }
    return m[1] ? !ok : ok;
}
function gmSplitOr(body) { // "a.ilike.*x*,b.eq.1" -> [["a","ilike.*x*"],...]
    return body.split(',').map(function (part) { const i = part.indexOf('.'); return [part.slice(0, i), part.slice(i + 1)]; });
}
async function gmOfflineAnswer(req) {
    const cache = await caches.open(GM_DATA_CACHE);
    const exact = await cache.match(req.url);
    if (exact) return exact;
    const url = new URL(req.url);
    const table = url.pathname.split('/rest/v1/')[1];
    const snap = await cache.match(GM_SNAPSHOT_URL + table);
    if (!snap) return null;
    let rows = await snap.json();
    let limit = null;
    url.searchParams.forEach(function (expr, key) {
        if (key === 'select' || key === 'order' || key === 'offset') return;
        if (key === 'limit') { limit = parseInt(expr, 10); return; }
        if (key === 'or') {
            const conds = gmSplitOr(expr.replace(/^\(|\)$/g, ''));
            rows = rows.filter(function (r) { return conds.some(function (c) { return gmMatchFilter(r, c[0], c[1]); }); });
            return;
        }
        rows = rows.filter(function (r) { return gmMatchFilter(r, key, expr); });
    });
    if (limit != null) rows = rows.slice(0, limit);
    const single = (req.headers.get('Accept') || '').indexOf('vnd.pgrst.object') !== -1;
    if (single && rows.length !== 1) return new Response(JSON.stringify({ code: 'PGRST116', message: 'no rows (offline copy)' }), { status: 406, headers: { 'Content-Type': 'application/json' } });
    return new Response(JSON.stringify(single ? rows[0] : rows), { status: 200, headers: { 'Content-Type': 'application/json', 'X-GM-Offline': '1' } });
}

const goldmindClient = supabase.createClient(GOLDMIND_SUPABASE_URL, GOLDMIND_SUPABASE_KEY, { global: { fetch: gmFetch } });

// Mobile app (Capacitor WebView) background/foreground fix: Supabase's
// built-in auto-refresh relies on a JS timer scheduled ahead of the access
// token's expiry, but mobile OSes throttle/suspend JS timers while the app
// is backgrounded to save battery. That scheduled refresh can be missed
// entirely, so the token is already expired by the time the person reopens
// the app — and with nothing re-checking it on resume, every page's
// requireGoldMindSession() then reads that as "no session" and bounces to
// the login screen, even though the person never actually signed out. This
// is the officially recommended fix for Supabase in WebView/React-Native-
// style apps: explicitly re-verify/refresh right when the page becomes
// visible again, instead of only relying on the background timer.
document.addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'visible') {
        goldmindClient.auth.startAutoRefresh();
        goldmindClient.auth.refreshSession().catch(function () {});
    } else {
        goldmindClient.auth.stopAutoRefresh();
    }
});

// ---- Idle timeout: auto sign-out after 2 hours with no activity ----
const GOLDMIND_IDLE_TIMEOUT_MS = 2 * 60 * 60 * 1000; // 2 hours
const GOLDMIND_IDLE_KEY = 'goldmind_last_activity';
const GOLDMIND_IDLE_TOUCH_MIN_INTERVAL_MS = 60 * 1000; // don't write on every single click

function goldmindTouchActivity() {
    localStorage.setItem(GOLDMIND_IDLE_KEY, Date.now().toString());
}

// Returns true if the session was idle too long and has now been signed out.
async function goldmindEnforceIdleTimeout() {
    const last = parseInt(localStorage.getItem(GOLDMIND_IDLE_KEY), 10);
    if (last && (Date.now() - last) > GOLDMIND_IDLE_TIMEOUT_MS) {
        GOLDMIND_STORE_ID = null;
        GOLDMIND_STAFF_ID = null;
        localStorage.removeItem(GOLDMIND_IDLE_KEY);
        await goldmindClient.auth.signOut();
        if (!window.location.pathname.endsWith('login-entry-ar.html')) {
            window.location.href = 'login-entry-ar.html?idle=1';
        }
        return true;
    }
    goldmindTouchActivity();
    return false;
}

// Keep the activity timestamp fresh while a page is actually being used,
// throttled so it's not writing to localStorage on every keystroke/click.
(function () {
    let lastTouch = 0;
    function throttledTouch() {
        const now = Date.now();
        if (now - lastTouch > GOLDMIND_IDLE_TOUCH_MIN_INTERVAL_MS) {
            lastTouch = now;
            goldmindTouchActivity();
        }
    }
    ['click', 'keydown', 'touchstart', 'scroll'].forEach(function (evt) {
        window.addEventListener(evt, throttledTouch, { passive: true });
    });
    // Also catch a tab left open and idle with no interaction at all —
    // checked periodically so it doesn't need a page navigation to trigger.
    setInterval(function () {
        if (GOLDMIND_STORE_ID) goldmindEnforceIdleTimeout();
    }, 60 * 1000);
})();

// Redirect to the login entry screen if there's no active session.
// Also resolves GOLDMIND_STORE_ID/GOLDMIND_STAFF_ID to the current user's
// active branch. If the account belongs to more than one branch and none is
// remembered yet, redirects to the branch picker instead (unless already there).
// Call this at the top of any page that requires a logged-in user.
// The saved login, read straight from the device (used when there's no internet,
// so an expired token can't be refreshed but the person is still signed in).
function gmStoredSession() {
    try {
        const raw = localStorage.getItem('sb-' + GOLDMIND_SUPABASE_URL.split('//')[1].split('.')[0] + '-auth-token');
        const s = raw && JSON.parse(raw);
        return s && s.user ? s : null;
    } catch (e) { return null; }
}

async function requireGoldMindSession(redirectTo) {
    let session = null;
    if (navigator.onLine) {
        ({ data: { session } } = await goldmindClient.auth.getSession());
    }
    if (!session && (!navigator.onLine)) session = gmStoredSession();
    if (!session) {
        window.location.href = redirectTo || 'login-entry-ar.html';
        return null;
    }

    const timedOut = await goldmindEnforceIdleTimeout();
    if (timedOut) return null;

    // Mandatory privacy-policy acceptance gate — applies to every user (owner
    // or staff), regardless of how they signed up. Skipped only on the gate
    // page itself to avoid a redirect loop.
    if (navigator.onLine && !window.location.pathname.endsWith('privacy-accept-ar.html')) {
        const { data: profile } = await goldmindClient.from('user_profiles').select('privacy_accepted_at').eq('id', session.user.id).maybeSingle();
        if (!profile || !profile.privacy_accepted_at) {
            const here = window.location.pathname.split('/').pop() || 'index-ar.html';
            window.location.href = 'privacy-accept-ar.html?return=' + encodeURIComponent(here);
            return null;
        }
    }

    if (!GOLDMIND_STORE_ID && !navigator.onLine) {
        // offline: reuse the branch this device was last signed into
        try {
            const m = JSON.parse(localStorage.getItem('gm_membership') || 'null');
            if (m && m.user === session.user.id) { GOLDMIND_STORE_ID = m.store; GOLDMIND_STAFF_ID = m.staff; }
        } catch (e) { /* ignore */ }
    }
    if (!GOLDMIND_STORE_ID) {
        const { data: memberships } = await goldmindClient
            .from('staff')
            .select('id, store_id')
            .eq('user_id', session.user.id);

        if (memberships && memberships.length === 1) {
            GOLDMIND_STORE_ID = memberships[0].store_id;
            GOLDMIND_STAFF_ID = memberships[0].id;
        } else if (memberships && memberships.length > 1) {
            const saved = localStorage.getItem('goldmind_active_store');
            const match = saved && memberships.find(m => m.store_id === saved);
            if (match) {
                GOLDMIND_STORE_ID = match.store_id;
                GOLDMIND_STAFF_ID = match.id;
            } else if (!window.location.pathname.endsWith('switch-branch-ar.html')) {
                window.location.href = 'switch-branch-ar.html';
                return null;
            }
        }
    }
    if (GOLDMIND_STORE_ID && GOLDMIND_STAFF_ID) {
        try { localStorage.setItem('gm_membership', JSON.stringify({ user: session.user.id, store: GOLDMIND_STORE_ID, staff: GOLDMIND_STAFF_ID })); } catch (e) { /* ignore */ }
    }
    return session;
}

// Set the active branch for this account and reload into it.
function goldMindSetActiveStore(storeId) {
    localStorage.setItem('goldmind_active_store', storeId);
    // per-company display caches: don't flash the previous company's name,
    // logo or currency after switching
    ['goldmind_store_name', 'goldmind_store_logo', 'goldmind_currency_code'].forEach(function (k) {
        try { localStorage.removeItem(k); } catch (e) { /* ignore */ }
    });
    GOLDMIND_STORE_ID = storeId;
    GOLDMIND_STAFF_ID = null;
    window.location.href = 'index-ar.html';
}

// Checks the store's subscription status (computed live server-side, no
// background job needed -- safe even if the free-tier project was paused).
// Call after requireGoldMindSession() on pages that should be locked once a
// subscription has expired. Owners/platform admins are never redirected so
// they can always reach subscription-ar.html to renew; everyone else gets
// sent there with a message. Returns the status string either way.
async function goldMindSubscriptionGuard() {
    if (!GOLDMIND_STORE_ID) return null;
    const { data: status } = await goldmindClient.rpc('get_subscription_status', { p_store_id: GOLDMIND_STORE_ID });
    if (status === 'expired' || status === 'canceled') {
        const { data: me } = await goldmindClient
            .from('staff').select('role').eq('id', GOLDMIND_STAFF_ID).maybeSingle();
        const isOwner = me && me.role === 'owner';
        if (!isOwner && !window.location.pathname.endsWith('subscription-ar.html')) {
            window.location.href = 'subscription-ar.html?locked=1';
            return status;
        }
    }
    return status;
}

// Sign the user out and send them back to the login screen.
// Confirms first since it's a destructive/navigational action.
// Pass a redirectTo (e.g. 'admin-login-ar.html') for pages that live outside
// the normal company/staff flow, so sign-out lands back on the right entry point.
async function goldMindSignOut(redirectTo) {
    if (!confirm('هل تريد تسجيل الخروج؟')) return;
    GOLDMIND_STORE_ID = null;
    GOLDMIND_STAFF_ID = null;
    localStorage.removeItem(GOLDMIND_IDLE_KEY);
    localStorage.removeItem('gm_membership');
    if (window.caches) await caches.delete(GM_DATA_CACHE).catch(function () {});
    await goldmindClient.auth.signOut();
    window.location.href = redirectTo || 'login-entry-ar.html';
}

// ---- Offline sales: queue on the device, post automatically when back online ----
// Each queued sale carries a client_ref; post_sale_invoice ignores a repeat of
// the same ref, so a retry after a dropped connection can never double-post.
// ponytail: queue lives in localStorage (fine for dozens of sales); move to
// IndexedDB if shops ever queue hundreds while offline.
const GM_QUEUE_KEY = 'gm_offline_sales';
const GM_SNAPSHOT_TABLES = {
    pieces: 'status=eq.available',
    customers: '',
    diamond_pieces: 'status=eq.available',
    gold_stock_lots: 'weight_grams_remaining=gt.0',
    gold_prices: ''
};

function gmQueue() { try { return JSON.parse(localStorage.getItem(GM_QUEUE_KEY)) || []; } catch (e) { return []; } }
function gmSaveQueue(q) { localStorage.setItem(GM_QUEUE_KEY, JSON.stringify(q)); gmRenderOfflineBadge(); }
// Change one queued sale (found by its client_ref) on a fresh read of the queue,
// so a sale saved while a sync is running is never overwritten.
function gmUpdateQueued(ref, fn) {
    const q = gmQueue();
    const i = q.findIndex(function (x) { return x.payload.client_ref === ref; });
    if (i === -1) return;
    const out = fn(q[i]);
    if (out === null) q.splice(i, 1); else q[i] = out || q[i];
    gmSaveQueue(q);
}

function gmFriendlyError(msg) {
    msg = String(msg || '');
    if (msg.indexOf('LOW_PRICE:') === 0) return 'يوجد سطر سعره أقل من نصف قيمة الذهب:' + msg.slice(10);
    const map = { INSUFFICIENT_STOCK: 'رصيد الجملة لا يكفي لهذا الوزن', LOT_NOT_FOUND: 'رصيد الجملة غير موجود', NOT_A_POOLED_LOT: 'رصيد الجملة ليس من نوع المصنعية المجمّعة', NOT_AUTHORIZED: 'ليست لديك صلاحية على هذا المحل', INVALID_AMOUNT: 'كمية غير صحيحة' };
    for (const k in map) if (msg.indexOf(k) !== -1) return map[k];
    return msg;
}
// Server busy / paused / login expired: try again later instead of giving up.
function gmIsRetryable(error) {
    return gmIsNetworkError(error) || /JWT|expired|5\d\d|timeout|Service Unavailable|Bad Gateway/i.test(String(error && (error.message || error.code || '')));
}

// Downloads the tables the sale screen searches, so it keeps working offline.
async function gmRefreshSnapshots() {
    if (!navigator.onLine || !GOLDMIND_STORE_ID || !window.caches) return;
    const cache = await caches.open(GM_DATA_CACHE);
    for (const table of Object.keys(GM_SNAPSHOT_TABLES)) {
        let rows = [], from = 0;
        for (;;) {
            let q = goldmindClient.from(table).select('*').eq('store_id', GOLDMIND_STORE_ID).range(from, from + 999);
            const f = GM_SNAPSHOT_TABLES[table];
            if (f) { const [col, expr] = f.split('='); const [op, val] = [expr.slice(0, expr.indexOf('.')), expr.slice(expr.indexOf('.') + 1)]; q = q.filter(col, op, val); }
            const { data, error } = await q;
            if (error) return;
            rows = rows.concat(data || []);
            if (!data || data.length < 1000) break;
            from += 1000;
        }
        await cache.put(GM_SNAPSHOT_URL + table, new Response(JSON.stringify(rows), { headers: { 'Content-Type': 'application/json' } }));
    }
    localStorage.setItem('gm_snapshot_at', String(Date.now()));
}

async function gmEditSnapshot(table, fn) {
    if (!window.caches) return;
    const cache = await caches.open(GM_DATA_CACHE);
    const res = await cache.match(GM_SNAPSHOT_URL + table);
    if (!res) return;
    const rows = fn(await res.json());
    await cache.put(GM_SNAPSHOT_URL + table, new Response(JSON.stringify(rows), { headers: { 'Content-Type': 'application/json' } }));
    // exact-URL copies of old searches could still show a sold piece: drop them
    const keys = await cache.keys();
    await Promise.all(keys.filter(function (k) { return k.url.indexOf('/rest/v1/' + table + '?') !== -1; }).map(function (k) { return cache.delete(k); }));
}

// Same checks the server does, done on the device before queueing offline.
async function gmLocalLowPriceLines(payload) {
    if (!window.caches) return [];
    const res = await (await caches.open(GM_DATA_CACHE)).match(GM_SNAPSHOT_URL + 'gold_prices');
    if (!res) return [];
    const gp = {}; (await res.json()).forEach(function (r) { gp[r.karat] = Number(r.price_per_gram); });
    const snap = await (await caches.open(GM_DATA_CACHE)).match(GM_SNAPSHOT_URL + 'pieces');
    const pieces = {}; (snap ? await snap.json() : []).forEach(function (r) { pieces[r.id] = r; });
    return payload.items.filter(function (it) {
        const pc = it.piece_id && pieces[it.piece_id];
        const karat = pc ? pc.karat : it.karat;
        const w = Number(pc ? (pc.accounting_weight_grams != null ? pc.accounting_weight_grams : pc.weight_grams) : (it.accounting_weight || it.weight || 0));
        return karat && gp[karat] && w > 0 && Number(it.price) < gp[karat] * w * 0.5;
    }).map(function (it) { return '\n• ' + (it.barcode || it.description || it.karat + 'K') + ': ' + it.price; });
}

// Posts a sale (see post_sale_invoice). Online: saved now. Offline: queued.
// Returns {id, invoice_number} | {queued: true} | {error}.
async function gmPostSale(payload, meta) {
    if (navigator.onLine) {
        let { data, error } = await goldmindClient.rpc('post_sale_invoice', { p: payload });
        if (error && String(error.message).indexOf('LOW_PRICE:') === 0) {
            if (!confirm('انتبه: ' + gmFriendlyError(error.message) + '\n\nقد يكون هناك خطأ في العملة أو السعر. هل أنت متأكد أنك تريد المتابعة؟')) {
                return { error: 'لم تُحفظ الفاتورة — راجع الأسعار.' };
            }
            payload.confirm_low_price = true;
            ({ data, error } = await goldmindClient.rpc('post_sale_invoice', { p: payload }));
        }
        if (!error) return data;
        if (!gmIsNetworkError(error)) return { error: gmFriendlyError(error.message) };
    }
    const low = payload.confirm_low_price ? [] : await gmLocalLowPriceLines(payload);
    if (low.length) {
        if (!confirm('انتبه: يوجد سطر سعره أقل من نصف قيمة الذهب:' + low.join('') + '\n\nهل أنت متأكد أنك تريد المتابعة؟')) return { error: 'لم تُحفظ الفاتورة — راجع الأسعار.' };
        payload.confirm_low_price = true;
    }
    payload.sold_at = new Date().toISOString(); // the real time of an offline sale (online sales use server time)
    const q = gmQueue();
    q.push({ payload: payload, meta: meta || {}, queued_at: payload.sold_at, status: 'pending' });
    gmSaveQueue(q);
    // this device must not sell the same piece twice while offline
    const sold = payload.items.map(function (i) { return i.piece_id; }).filter(Boolean);
    const soldD = payload.items.map(function (i) { return i.diamond_piece_id; }).filter(Boolean);
    await gmEditSnapshot('pieces', function (rows) { return rows.filter(function (r) { return sold.indexOf(r.id) === -1; }); });
    await gmEditSnapshot('diamond_pieces', function (rows) { return rows.filter(function (r) { return soldD.indexOf(r.id) === -1; }); });
    await gmEditSnapshot('gold_stock_lots', function (rows) {
        payload.items.forEach(function (i) { if (i.lot_id) rows.forEach(function (r) { if (r.id === i.lot_id) r.weight_grams_remaining = Number(r.weight_grams_remaining) - Number(i.weight || 0); }); });
        return rows;
    });
    return { queued: true };
}

let gmSyncing = false;
async function gmSyncQueue() {
    if (gmSyncing || !navigator.onLine) return;
    if (!gmQueue().some(function (x) { return x.status === 'pending'; })) return;
    // one sync at a time, also across open tabs
    if (navigator.locks) return navigator.locks.request('gm-sale-sync', { ifAvailable: true }, function (lock) { return lock ? gmRunSync() : null; });
    return gmRunSync();
}
async function gmRunSync() {
    gmSyncing = true;
    let posted = 0;
    try {
        const { data: { session } } = await goldmindClient.auth.getSession();
        if (!session) return;
        const refs = gmQueue().filter(function (x) { return x.status === 'pending'; }).map(function (x) { return x.payload.client_ref; });
        for (const ref of refs) {
            const item = gmQueue().find(function (x) { return x.payload.client_ref === ref; });
            if (!item || item.status !== 'pending') continue;
            const { data, error } = await goldmindClient.rpc('post_sale_invoice', { p: item.payload });
            if (!error) { gmUpdateQueued(ref, function () { return null; }); posted++; continue; }
            if (gmIsRetryable(error)) break;
            gmUpdateQueued(ref, function (x) { x.status = 'failed'; x.error = gmFriendlyError(error.message); return x; });
        }
    } finally {
        gmSyncing = false;
        gmRenderOfflineBadge();
    }
    if (posted) {
        gmToast('تم ترحيل ' + posted + ' فاتورة كانت محفوظة على الجهاز');
        gmRefreshSnapshots().catch(function () {});
    }
}

function gmToast(text) {
    const t = document.createElement('div');
    t.setAttribute('role', 'status');
    t.style.cssText = 'position:fixed;left:50%;bottom:88px;transform:translateX(-50%);z-index:9999;background:#1f2937;color:#fff;padding:10px 16px;border-radius:12px;font-size:13px;font-weight:600;box-shadow:0 6px 20px rgba(0,0,0,.25);max-width:90vw;text-align:center;';
    t.textContent = text;
    document.body.appendChild(t);
    setTimeout(function () { t.remove(); }, 4000);
}

// Small pill: "no internet" / "N sales waiting" / "N sales failed" (tap for details).
function gmRenderOfflineBadge() {
    if (!document.body) return;
    let b = document.getElementById('gm-offline-badge');
    const q = gmQueue();
    const pending = q.filter(function (x) { return x.status === 'pending'; }).length;
    const failed = q.filter(function (x) { return x.status === 'failed'; }).length;
    const offline = !navigator.onLine;
    if (!offline && !pending && !failed) { if (b) b.remove(); return; }
    if (!b) {
        b = document.createElement('button');
        b.id = 'gm-offline-badge';
        b.type = 'button';
        b.className = 'no-print';
        b.onclick = gmShowQueue;
        b.style.cssText = 'position:fixed;left:12px;bottom:84px;z-index:9998;display:flex;align-items:center;gap:6px;padding:8px 12px;border-radius:999px;font-size:12px;font-weight:700;box-shadow:0 4px 14px rgba(0,0,0,.18);border:0;cursor:pointer;';
        document.body.appendChild(b);
    }
    const parts = [];
    if (offline) parts.push('بدون إنترنت');
    if (pending) parts.push(pending + ' فاتورة بانتظار الترحيل');
    if (failed) parts.push(failed + ' لم تُرحَّل');
    b.style.background = failed ? '#FDECEA' : offline ? '#FFF4E0' : '#E6F0FF';
    b.style.color = failed ? '#8A1C12' : offline ? '#7A4B00' : '#1D3F7A';
    b.innerHTML = '<span class="material-symbols-outlined" aria-hidden="true" style="font-size:16px">' + (failed ? 'error' : offline ? 'cloud_off' : 'cloud_upload') + '</span><span></span>';
    b.lastChild.textContent = parts.join(' · ');
    b.setAttribute('aria-label', parts.join('، '));
}

function gmShowQueue() {
    const q = gmQueue();
    if (!q.length) { alert(navigator.onLine ? 'لا توجد فواتير معلّقة.' : 'لا يوجد اتصال بالإنترنت. يمكنك متابعة البيع، وستُرحَّل الفواتير تلقائياً عند عودة الاتصال.'); return; }
    let d = document.getElementById('gm-queue-dialog');
    if (d) d.remove();
    d = document.createElement('dialog');
    d.id = 'gm-queue-dialog';
    d.setAttribute('dir', 'rtl');
    d.style.cssText = 'border:0;border-radius:16px;padding:0;max-width:440px;width:92vw;';
    const esc = function (v) { return typeof gmEscapeHtml === 'function' ? gmEscapeHtml(String(v == null ? '' : v)) : String(v == null ? '' : v); };
    d.innerHTML = '<div style="padding:16px 16px 8px;font-weight:800;font-size:15px">فواتير محفوظة على الجهاز</div>' +
        '<div style="padding:0 16px 8px;font-size:12px;color:#555">ستُرحَّل تلقائياً عند توفر الاتصال بالإنترنت.</div>' +
        q.map(function (x) {
            const total = x.payload.items.reduce(function (s, it) { return s + Number(it.price || 0); }, 0);
            return '<div style="border-top:1px solid #eee;padding:10px 16px;font-size:12.5px">' +
                '<div style="display:flex;justify-content:space-between;gap:8px"><b>' + esc(x.meta.customerName || 'زبون') + '</b><span>' + total.toFixed(2) + '</span></div>' +
                '<div style="color:#666">' + new Date(x.queued_at).toLocaleString('ar') + ' · ' + x.payload.items.length + ' قطعة</div>' +
                (x.status === 'failed' ? '<div style="color:#B3261E;margin-top:4px">' + esc(x.error) + '</div>' +
                  '<div style="display:flex;gap:8px;margin-top:6px"><button data-retry="' + esc(x.payload.client_ref) + '" style="padding:6px 10px;border-radius:8px;border:1px solid #ccc;background:#fff">إعادة المحاولة</button>' +
                  '<button data-drop="' + esc(x.payload.client_ref) + '" style="padding:6px 10px;border-radius:8px;border:1px solid #F5C2BC;background:#FDECEA;color:#8A1C12">حذف من الجهاز</button></div>' : '') +
                '</div>';
        }).join('') +
        '<div style="display:flex;gap:8px;padding:12px 16px;border-top:1px solid #eee"><button data-sync style="flex:1;padding:10px;border-radius:10px;border:0;background:#111;color:#fff;font-weight:700">رحّل الآن</button><button data-close style="padding:10px 14px;border-radius:10px;border:1px solid #ccc;background:#fff">إغلاق</button></div>';
    document.body.appendChild(d);
    d.addEventListener('click', async function (e) {
        const t = e.target;
        if (t.dataset.close !== undefined) d.close();
        if (t.dataset.sync !== undefined) { d.close(); await gmSyncQueue(); }
        if (t.dataset.retry !== undefined) {
            const item = gmQueue().find(function (x) { return x.payload.client_ref === t.dataset.retry; });
            if (!item) { d.close(); return; }
            const low = item.error && /أقل من نصف? قيمة الذهب/.test(item.error);
            if (low && !confirm(item.error + '\n\nهل أنت متأكد أنك تريد ترحيلها كما هي؟')) return;
            gmUpdateQueued(t.dataset.retry, function (x) { if (low) x.payload.confirm_low_price = true; x.status = 'pending'; delete x.error; return x; });
            d.close(); await gmSyncQueue();
        }
        if (t.dataset.drop !== undefined && confirm('هل أنت متأكد أنك تريد حذف هذه الفاتورة من الجهاز؟ لن تُحفظ.')) {
            gmUpdateQueued(t.dataset.drop, function () { return null; }); d.close();
        }
    });
    d.showModal();
}

window.addEventListener('online', function () { gmRenderOfflineBadge(); gmSyncQueue(); });
window.addEventListener('offline', gmRenderOfflineBadge);
document.addEventListener('DOMContentLoaded', function () { gmRenderOfflineBadge(); setTimeout(gmSyncQueue, 1500); });
setInterval(gmSyncQueue, 30000);

// Save a finished html2pdf job. In the browser this downloads the file as
// before; inside the Android app (a WebView that ignores browser downloads)
// the PDF is written to the app cache and the system share sheet opens, so
// the user can save it to Files, send it on WhatsApp, print it, etc.
async function gmSavePdf(worker, filename, title) {
    var P = window.Capacitor && window.Capacitor.isNativePlatform && window.Capacitor.isNativePlatform() && window.Capacitor.Plugins;
    if (!P || !P.Filesystem || !P.Share) return worker.save(filename);
    var safe = String(filename || 'GoldMind.pdf').replace(/[\\/:*?"<>|]+/g, '-');
    if (!/\.pdf$/i.test(safe)) safe += '.pdf';
    var dataUri = await worker.outputPdf('datauristring');
    var base64 = dataUri.slice(dataUri.indexOf(',') + 1);
    await P.Filesystem.writeFile({ path: safe, data: base64, directory: 'CACHE' });
    var res = await P.Filesystem.getUri({ path: safe, directory: 'CACHE' });
    await P.Share.share({ title: title || safe, url: res.uri, dialogTitle: 'حفظ الملف أو مشاركته' });
}

// Printing inside the Android app: the WebView ignores window.print(), so hand
// the page to Android's print service (GMPrintPlugin.java). Browsers keep the
// normal print dialog.
(function () {
    var browserPrint = window.print ? window.print.bind(window) : null;
    window.print = function () {
        var C = window.Capacitor;
        var plugin = C && C.isNativePlatform && C.isNativePlatform() && C.Plugins && C.Plugins.GMPrint;
        if (!plugin) return browserPrint && browserPrint();
        plugin.print({ name: (document.title || 'GoldMind').trim() }).catch(function () {
            alert('تعذّرت الطباعة. حدّث التطبيق إلى آخر نسخة ثم حاول مرة أخرى.');
        });
    };
})();
