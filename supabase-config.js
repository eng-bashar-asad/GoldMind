// GoldMind - Shared Supabase configuration
// Publishable/anon key only - safe to expose in client-side code by design.
const GOLDMIND_SUPABASE_URL = 'https://puzkfwbmipldzgwofhjg.supabase.co';
const GOLDMIND_SUPABASE_KEY = 'sb_publishable_QxjJeGblzseQTvTH87eyZw_19Zu206o';

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

// Sign the user out and send them back to the login screen.
// Confirms first since it's a destructive/navigational action.
// Pass a redirectTo (e.g. 'admin-login-ar.html') for pages that live outside
// the normal company/staff flow, so sign-out lands back on the right entry point.
async function goldMindSignOut(redirectTo) {
    if (!confirm('هل تريد تسجيل الخروج؟')) return;
    GOLDMIND_STORE_ID = null;
    GOLDMIND_STAFF_ID = null;
    await goldmindClient.auth.signOut();
    window.location.href = redirectTo || 'login-entry-ar.html';
}
