// Supabase Edge Function: biometric-auth (deployed with verify_jwt = false:
// the login actions run before the user has a session; enroll actions check
// the caller's session themselves).
//
// Logic lives in core.js (shared with the tests). This file only wires it to
// Supabase: the tables from the biometric_login migration and a one-time
// sign-in token from auth.admin.generateLink (nothing is emailed).
//
// Settings (optional secrets, for when the site moves to its own domain):
//   WEBAUTHN_RP_ID    default eng-bashar-asad.github.io
//   WEBAUTHN_ORIGINS  comma separated, default https://eng-bashar-asad.github.io
// Passkeys are tied to the domain: after a domain change people re-enable them once.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import * as swa from 'npm:@simplewebauthn/server@14.0.3';
import { handle } from './core.js';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

const cfg = {
  rpID: Deno.env.get('WEBAUTHN_RP_ID') || 'eng-bashar-asad.github.io',
  rpName: 'GoldMind',
  origins: (Deno.env.get('WEBAUTHN_ORIGINS') || 'https://eng-bashar-asad.github.io').split(',').map((s) => s.trim()).filter(Boolean),
};

function must<T>({ data, error }: { data: T; error: unknown }): T {
  if (error) throw error;
  return data;
}

const db = {
  async biometricAllowed(userId: string) {
    const rows = must(await admin.from('staff').select('role, stores(allow_biometric_login)').eq('user_id', userId)) as any[];
    if (!rows || rows.length === 0) return true;
    return rows.some((r) => r.role === 'owner' || !r.stores || r.stores.allow_biometric_login !== false);
  },
  async userLabel(userId: string) {
    const { data: p } = await admin.from('user_profiles').select('username').eq('id', userId).maybeSingle();
    if (p?.username) return p.username;
    const { data } = await admin.auth.admin.getUserById(userId);
    return data?.user?.email || 'GoldMind';
  },
  async listPasskeys(userId: string) {
    return must(await admin.from('auth_passkeys').select('id, transports').eq('user_id', userId)) as any[];
  },
  async createChallenge(row: { challenge: string; user_id: string | null; kind: string }) {
    await admin.from('auth_webauthn_challenges').delete().lt('expires_at', new Date().toISOString());
    const r = must(await admin.from('auth_webauthn_challenges').insert(row).select('id').single()) as any;
    return r.id;
  },
  async takeChallenge(id: string, kind: string) {
    if (!id) return null;
    const rows = must(await admin.from('auth_webauthn_challenges').delete().eq('id', id).eq('kind', kind).select('challenge, user_id, expires_at')) as any[];
    const r = rows && rows[0];
    if (!r || new Date(r.expires_at).getTime() < Date.now()) return null;
    return r;
  },
  async insertPasskey(row: Record<string, unknown>) {
    must(await admin.from('auth_passkeys').insert(row));
  },
  async getPasskey(id: string) {
    return must(await admin.from('auth_passkeys').select('*').eq('id', id).maybeSingle());
  },
  async touchPasskey(id: string, counter: number) {
    await admin.from('auth_passkeys').update({ counter, last_used_at: new Date().toISOString() }).eq('id', id);
  },
  async insertDeviceKey(row: Record<string, unknown>) {
    const r = must(await admin.from('auth_device_keys').insert(row).select('id').single()) as any;
    return r.id;
  },
  async getDeviceKey(id: string) {
    if (!/^[0-9a-f-]{36}$/i.test(id)) return null;
    return must(await admin.from('auth_device_keys').select('id, user_id, secret_hash').eq('id', id).maybeSingle());
  },
  async touchDeviceKey(id: string) {
    await admin.from('auth_device_keys').update({ last_used_at: new Date().toISOString() }).eq('id', id);
  },
};

async function mint(userId: string) {
  const { data: u, error: uErr } = await admin.auth.admin.getUserById(userId);
  if (uErr || !u?.user?.email) throw new Error('user not found');
  const { data, error } = await admin.auth.admin.generateLink({ type: 'magiclink', email: u.user.email });
  if (error || !data?.properties?.hashed_token) throw new Error('could not start session');
  return { token_hash: data.properties.hashed_token, type: data.properties.verification_type || 'magiclink' };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  let body: any = {};
  try { body = await req.json(); } catch { /* empty body */ }

  let userId: string | null = null;
  const auth = req.headers.get('Authorization') || '';
  if (auth.startsWith('Bearer ') && auth.slice(7) !== ANON_KEY) {
    const caller = createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: auth } }, auth: { persistSession: false } });
    const { data } = await caller.auth.getUser();
    userId = data?.user?.id || null;
  }

  const out = await handle({ swa, db, mint, cfg, userId }, body);
  return new Response(JSON.stringify(out.body), { status: out.status, headers: { ...cors, 'Content-Type': 'application/json' } });
});
