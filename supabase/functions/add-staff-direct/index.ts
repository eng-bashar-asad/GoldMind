// Supabase Edge Function: add-staff-direct
//
// Creates a working login for a new employee immediately (no confirmation
// email, no OTP wait). Called from staff-permissions-ar.html by the owner or
// anyone with manage_staff.
//
// Username OR email is enough:
//  - username only  -> a private placeholder email is synthesized (never emailed)
//  - email only     -> a username is derived from the email (made unique)
//  - both           -> both are used as given
//
// Security: an email that already has an account is NEVER taken over (no
// password reset, no username change): the caller is told to use the email
// invite instead. A failed add removes the account it just created.

import { serve } from 'https://deno.land/std@0.190.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

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
  // No look-alike characters (0/O, 1/l/I): often read off one screen and typed on another.
  const chars = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
  let out = '';
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  for (let i = 0; i < length; i++) out += chars[bytes[i] % chars.length];
  return out;
}

const USERNAME_RE = /^[a-zA-Z0-9_.]{3,20}$/;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// "Ahmad.Sales+1@gmail.com" -> "ahmad.sales1"
function usernameBaseFromEmail(email: string) {
  let base = email.split('@')[0].toLowerCase().replace(/[^a-z0-9_.]/g, '').replace(/^[._]+|[._]+$/g, '');
  base = base.slice(0, 16);
  if (base.length < 3) base = (base + 'staff').slice(0, 8);
  return base;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const { store_id, full_name, username: rawUsername, email: rawEmail, password: chosenPassword, whatsapp_phone, permissions } = await req.json();

    const givenUsername = rawUsername ? String(rawUsername).trim() : '';
    const givenEmail = rawEmail ? String(rawEmail).trim().toLowerCase() : '';

    if (!store_id || !full_name) return json({ error: 'اسم الموظف ومعرف المتجر مطلوبان' }, 400);
    if (!givenUsername && !givenEmail) return json({ error: 'أدخل اسم مستخدم أو بريد إلكتروني للموظف' }, 400);
    if (givenUsername && !USERNAME_RE.test(givenUsername)) {
      return json({ error: 'اسم المستخدم يجب أن يكون 3-20 خانة (حروف إنجليزية/أرقام/_ فقط، بدون مسافات)' }, 400);
    }
    if (givenEmail && !EMAIL_RE.test(givenEmail)) return json({ error: 'صيغة البريد الإلكتروني غير صحيحة' }, 400);

    const password = (chosenPassword && String(chosenPassword).length >= 6) ? String(chosenPassword) : (chosenPassword ? null : generatePassword());
    if (password === null) return json({ error: 'كلمة السر يجب أن تكون 6 أحرف على الأقل' }, 400);

    const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
    const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
    const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

    const authHeader = req.headers.get('Authorization') || '';
    const callerClient = createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: authHeader } } });
    const { data: { user: callerUser }, error: callerErr } = await callerClient.auth.getUser();
    if (callerErr || !callerUser) return json({ error: 'الجلسة غير صالحة، سجّل الدخول من جديد' }, 401);

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    const { data: callerStaff } = await admin
      .from('staff').select('role, permissions')
      .eq('user_id', callerUser.id).eq('store_id', store_id).maybeSingle();
    const canManageStaff = callerStaff?.role === 'owner' || callerStaff?.permissions?.manage_staff === true;
    if (!canManageStaff) return json({ error: 'ليس لديك صلاحية إضافة موظفين' }, 403);

    // Username: as given (must be free), or derived from the email and made unique.
    let username = givenUsername;
    if (username) {
      const { data: taken } = await admin.from('user_profiles').select('id').ilike('username', username).maybeSingle();
      if (taken) return json({ error: 'اسم المستخدم هذا مستخدم مسبقاً — اختر اسماً غيره' }, 400);
    } else {
      const base = usernameBaseFromEmail(givenEmail);
      username = '';
      for (let i = 0; i < 30 && !username; i++) {
        const candidate = i === 0 ? base : base.slice(0, 16) + (i < 10 ? i : Math.floor(Math.random() * 9000 + 1000));
        const { data: taken } = await admin.from('user_profiles').select('id').ilike('username', candidate).maybeSingle();
        if (!taken) username = candidate;
      }
      if (!username) return json({ error: 'تعذّر توليد اسم مستخدم — أدخل اسم مستخدم يدوياً' }, 400);
    }

    const email = givenEmail || `${username.toLowerCase()}.${String(store_id).slice(0, 8)}@staff.goldmind.app`;

    // Existing account with this email?
    const { data: userList } = await admin.auth.admin.listUsers({ perPage: 1000 });
    const existingUser = userList.users.find((u) => (u.email || '').toLowerCase() === email);

    // An existing account is never modified here (no password reset): this
    // endpoint is open to every company owner, so reusing accounts would let
    // one company take over anyone else's login, including platform admins.
    if (existingUser) {
      const { data: here } = await admin.from('staff').select('id').eq('user_id', existingUser.id).eq('store_id', store_id).maybeSingle();
      if (here) return json({ error: 'هذا الحساب موظف بالفعل في هذا المتجر' }, 400);
      return json({ error: 'هذا البريد الإلكتروني لديه حساب GoldMind مسبقاً. استخدم خيار "دعوة بالبريد الإلكتروني" في الأسفل، وسيدخل الموظف بحسابه نفسه.' }, 400);
    }

    const { data: newUser, error: createErr } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
    if (createErr || !newUser) return json({ error: 'تعذّر إنشاء الحساب: ' + createErr?.message }, 400);
    const userId = newUser.user.id;

    const { error: profileErr } = await admin.from('user_profiles').upsert({ id: userId, username });
    if (profileErr) {
      await admin.auth.admin.deleteUser(userId); // no half-created accounts left behind
      return json({ error: 'تعذّر حفظ اسم المستخدم: ' + profileErr.message }, 400);
    }

    const { error: staffErr } = await admin.from('staff').insert({
      store_id,
      user_id: userId,
      full_name,
      role: 'staff',
      permissions: permissions || {},
      whatsapp_phone: whatsapp_phone || null,
    });
    if (staffErr) {
      await admin.auth.admin.deleteUser(userId);
      return json({ error: 'تعذّر حفظ بيانات الموظف: ' + staffErr.message }, 400);
    }

    return json({ success: true, username, email, temp_password: password });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
