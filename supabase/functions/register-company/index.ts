import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// Public self-service company registration: a new business registers itself
// and immediately gets an owner login plus a 30-day trial.
//
// verify_jwt is FALSE deliberately: a brand-new visitor has no session yet.
//
// Security: this endpoint is anonymous, so it must NEVER touch an existing
// account (no password reset, no reuse) — otherwise anyone who knows an email
// could take that account over. An email that already exists is refused and
// the person is told to sign in instead.

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function generatePassword(length = 10) {
  const chars = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
  let out = '';
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  for (let i = 0; i < length; i++) out += chars[bytes[i] % chars.length];
  return out;
}

const TRIAL_DAYS = 30;

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const { company_name, owner_name, owner_email: rawEmail, owner_phone } = await req.json();

    if (!company_name || !owner_name || !rawEmail) {
      return json({ error: 'اسم الشركة واسمك وبريدك الإلكتروني حقول مطلوبة' }, 400);
    }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(rawEmail)) {
      return json({ error: 'صيغة البريد الإلكتروني غير صحيحة' }, 400);
    }
    const email = String(rawEmail).trim().toLowerCase();

    const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
    const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    const { data: userList } = await admin.auth.admin.listUsers({ perPage: 1000 });
    const existingUser = userList.users.find((u) => (u.email || '').toLowerCase() === email);
    if (existingUser) {
      return json({ error: 'هذا البريد الإلكتروني مسجّل مسبقاً. سجّل الدخول بحسابك الحالي بدلاً من إنشاء حساب جديد.' }, 400);
    }

    const { data: basicPlan, error: planErr } = await admin
      .from('plans').select('id').eq('key', 'basic').maybeSingle();
    if (planErr || !basicPlan) return json({ error: 'تعذّر تجهيز خطة الاشتراك الافتراضية' }, 500);

    const tempPassword = generatePassword();
    const { data: newUser, error: createErr } = await admin.auth.admin.createUser({
      email,
      password: tempPassword,
      email_confirm: true,
    });
    if (createErr || !newUser) return json({ error: 'تعذّر إنشاء الحساب: ' + createErr?.message }, 400);
    const userId = newUser.user.id;

    const { data: newStore, error: storeErr } = await admin.from('stores').insert({
      name: company_name,
      phone: owner_phone || null,
      email,
      manager_name: owner_name,
    }).select('id').single();
    if (storeErr || !newStore) {
      await admin.auth.admin.deleteUser(userId);
      return json({ error: 'تعذّر إنشاء سجل الشركة: ' + storeErr?.message }, 400);
    }

    const { error: staffErr } = await admin.from('staff').insert({
      store_id: newStore.id,
      user_id: userId,
      full_name: owner_name,
      role: 'owner',
      permissions: {},
      whatsapp_phone: owner_phone || null,
    });
    if (staffErr) return json({ error: 'تعذّر إنشاء حساب المالك: ' + staffErr.message }, 400);

    const trialEnd = new Date();
    trialEnd.setDate(trialEnd.getDate() + TRIAL_DAYS);
    const { error: subErr } = await admin.from('subscriptions').insert({
      store_id: newStore.id,
      plan_id: basicPlan.id,
      status: 'trialing',
      trial_end: trialEnd.toISOString(),
    });
    if (subErr) return json({ error: 'أُنشئت الشركة لكن تعذّر تفعيل التجربة المجانية: ' + subErr.message }, 400);

    return json({ success: true, email, temp_password: tempPassword, store_id: newStore.id });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
