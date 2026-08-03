// GoldMind - Shared Supabase configuration
// Publishable/anon key only - safe to expose in client-side code by design.
const GOLDMIND_SUPABASE_URL = 'https://puzkfwbmipldzgwofhjg.supabase.co';
const GOLDMIND_SUPABASE_KEY = 'sb_publishable_QxjJeGblzseQTvTH87eyZw_19Zu206o';

// Resolved per logged-in user (multi-tenant): each account belongs to exactly
// one company/store, looked up from their staff row. Do not hardcode this.
let GOLDMIND_STORE_ID = null;

const goldmindClient = supabase.createClient(GOLDMIND_SUPABASE_URL, GOLDMIND_SUPABASE_KEY);

// Redirect to the login entry screen if there's no active session.
// Also resolves GOLDMIND_STORE_ID to the current user's own company.
// Call this at the top of any page that requires a logged-in user.
async function requireGoldMindSession(redirectTo) {
    const { data: { session } } = await goldmindClient.auth.getSession();
    if (!session) {
        window.location.href = redirectTo || 'login-entry-ar.html';
        return null;
    }
    if (!GOLDMIND_STORE_ID) {
        const { data: staffRow } = await goldmindClient
            .from('staff')
            .select('store_id')
            .eq('id', session.user.id)
            .maybeSingle();
        if (staffRow) GOLDMIND_STORE_ID = staffRow.store_id;
    }
    return session;
}

// Sign the user out and send them back to the login screen.
// Confirms first since it's a destructive/navigational action.
async function goldMindSignOut() {
    if (!confirm('هل تريد تسجيل الخروج؟')) return;
    GOLDMIND_STORE_ID = null;
    await goldmindClient.auth.signOut();
    window.location.href = 'login-entry-ar.html';
}
