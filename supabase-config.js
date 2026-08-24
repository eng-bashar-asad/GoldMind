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

const goldmindClient = supabase.createClient(GOLDMIND_SUPABASE_URL, GOLDMIND_SUPABASE_KEY);

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
async function requireGoldMindSession(redirectTo) {
    const { data: { session } } = await goldmindClient.auth.getSession();
    if (!session) {
        window.location.href = redirectTo || 'login-entry-ar.html';
        return null;
    }

    const timedOut = await goldmindEnforceIdleTimeout();
    if (timedOut) return null;

    // Mandatory privacy-policy acceptance gate — applies to every user (owner
    // or staff), regardless of how they signed up. Skipped only on the gate
    // page itself to avoid a redirect loop.
    if (!window.location.pathname.endsWith('privacy-accept-ar.html')) {
        const { data: profile } = await goldmindClient.from('user_profiles').select('privacy_accepted_at').eq('id', session.user.id).maybeSingle();
        if (!profile || !profile.privacy_accepted_at) {
            const here = window.location.pathname.split('/').pop() || 'index-ar.html';
            window.location.href = 'privacy-accept-ar.html?return=' + encodeURIComponent(here);
            return null;
        }
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
    return session;
}

// Set the active branch for this account and reload into it.
function goldMindSetActiveStore(storeId) {
    localStorage.setItem('goldmind_active_store', storeId);
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
    await goldmindClient.auth.signOut();
    window.location.href = redirectTo || 'login-entry-ar.html';
}
