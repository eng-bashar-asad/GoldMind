// GoldMind - Shared Supabase configuration
// Publishable/anon key only - safe to expose in client-side code by design.
const GOLDMIND_SUPABASE_URL = 'https://puzkfwbmipldzgwofhjg.supabase.co';
const GOLDMIND_SUPABASE_KEY = 'sb_publishable_QxjJeGblzseQTvTH87eyZw_19Zu206o';
const GOLDMIND_STORE_ID = '4db051dc-e1c7-44ae-b050-c15be386ab7c'; // Al-Fares Gold Shop

const goldmindClient = supabase.createClient(GOLDMIND_SUPABASE_URL, GOLDMIND_SUPABASE_KEY);

// Redirect to the login entry screen if there's no active session.
// Call this at the top of any page that requires a logged-in user.
async function requireGoldMindSession(redirectTo) {
    const { data: { session } } = await goldmindClient.auth.getSession();
    if (!session) {
        window.location.href = redirectTo || 'login-entry-ar.html';
        return null;
    }
    return session;
}
