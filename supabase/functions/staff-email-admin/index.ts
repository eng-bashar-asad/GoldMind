// Supabase Edge Function: staff-email-admin
//
// Staff login emails live in Supabase Auth (auth.users), not in the
// public `staff` table, so the browser can never read or change them
// directly no matter what RLS on `staff` allows. This function is the
// one narrow, permission-checked door into that admin-only data —
// called from staff-permissions-ar.html when the owner/manager opens a
// staff member's detail card.
//
// action="get":    returns the current login email for a staff row.
// action="update": changes that staff member's login email. This is a
//                   real credential change — it takes effect immediately
//                   and the old email can no longer be used to sign in.
// action="set_username": changes the username they sign in with (بشار 2026-11-18).
// action="set_password": sets a new password chosen by the manager. Passwords are
//                   never readable — this is the only way to "give" one.
// get also returns the username, and whether the email is only the private
// placeholder of a username-only account (@staff.goldmind.app, never emailed).
//
// DEPLOY:
//   supabase functions deploy staff-email-admin --project-ref puzkfwbmipldzgwofhjg

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

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const { action, store_id, staff_id, new_email: rawNewEmail, new_username: rawUsername, new_password: newPassword } = await req.json();

    if (!action || !store_id || !staff_id) {
      return json({ error: 'بيانات ناقصة' }, 400);
    }

    const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
    const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
    const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

    // Client scoped to the CALLER's own session — confirms who's asking.
    const authHeader = req.headers.get('Authorization') || '';
    const callerClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user: callerUser }, error: callerErr } = await callerClient.auth.getUser();
    if (callerErr || !callerUser) return json({ error: 'الجلسة غير صالحة، سجّل الدخول من جديد' }, 401);
    // a password sign-in must have finished the emailed-code step (same rule as the database: gm_session_ok)
    const { data: twoFaOk } = await callerClient.rpc('gm_session_ok');
    if (twoFaOk !== true) return json({ error: 'أكمل التحقق برمز البريد الإلكتروني أولاً ثم أعد المحاولة', code: '2FA_REQUIRED' }, 403);

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    const { data: callerStaff } = await admin
      .from('staff').select('role, permissions')
      .eq('user_id', callerUser.id).eq('store_id', store_id).is('suspended_at', null).maybeSingle(); // a suspended manager can't

    const isOwner = callerStaff?.role === 'owner';
    const canManageStaff = isOwner || callerStaff?.permissions?.manage_staff === true;
    if (!canManageStaff) return json({ error: 'ليس لديك صلاحية عرض بيانات الموظفين أو تعديلها' }, 403);

    // Target staff row must belong to the same store the caller manages —
    // otherwise a manager at store A could probe/change emails at store B.
    const { data: targetStaff } = await admin
      .from('staff').select('id, user_id, role').eq('id', staff_id).eq('store_id', store_id).maybeSingle();
    if (!targetStaff || !targetStaff.user_id) return json({ error: 'الموظف غير موجود' }, 404);

    const PLACEHOLDER = '@staff.goldmind.app';

    if (action === 'get') {
      const [{ data: userRes, error: getErr }, { data: prof }] = await Promise.all([
        admin.auth.admin.getUserById(targetStaff.user_id),
        admin.from('user_profiles').select('username').eq('id', targetStaff.user_id).maybeSingle(),
      ]);
      if (getErr || !userRes?.user) return json({ error: 'تعذّر جلب البريد الإلكتروني: ' + (getErr?.message || '') }, 400);
      const email = userRes.user.email || null;
      return json({ email, username: prof?.username || null, placeholder: !!email && email.toLowerCase().endsWith(PLACEHOLDER) });
    }

    // Changing a login (email, username, password) — same guards for all three.
    // Only the owner may change the owner's login; a manager with manage_staff
    // must not be able to take over the owner account.
    if (targetStaff.role === 'owner' && !isOwner) {
      return json({ error: 'لا يمكن تغيير بيانات دخول مالك الشركة إلا من المالك نفسه' }, 403);
    }
    // The login is shared by every company this person belongs to, so one
    // company must not change it when the account is also used elsewhere.
    const [{ data: otherStores }, { data: isPlatformAdmin }] = await Promise.all([
      admin.from('staff').select('id').eq('user_id', targetStaff.user_id).neq('store_id', store_id).limit(1),
      admin.from('platform_admins').select('id').eq('id', targetStaff.user_id).maybeSingle(),
    ]);
    if ((otherStores && otherStores.length > 0) || isPlatformAdmin) {
      return json({ error: 'هذا الحساب مرتبط بشركات أخرى، ولا يمكن تغيير بيانات دخوله من هنا. يستطيع صاحب الحساب تغييرها بنفسه.' }, 403);
    }

    if (action === 'set_password') {
      const pw = String(newPassword || '');
      if (pw.length < 8 || pw.length > 72) return json({ error: 'كلمة المرور يجب أن تكون من 8 إلى 72 خانة' }, 400);
      const { error: pwErr } = await admin.auth.admin.updateUserById(targetStaff.user_id, { password: pw });
      if (pwErr) return json({ error: 'تعذّر تغيير كلمة المرور: ' + pwErr.message }, 400);
      return json({ success: true });
    }

    if (action === 'set_username') {
      const username = String(rawUsername || '').trim();
      if (!/^[a-zA-Z0-9_.]{3,20}$/.test(username)) {
        return json({ error: 'اسم المستخدم يجب أن يكون 3-20 خانة (حروف إنجليزية/أرقام/_ فقط، بدون مسافات)' }, 400);
      }
      const { data: taken } = await admin.from('user_profiles').select('id').ilike('username', username.replace(/[_%\\]/g, '\\$&')).neq('id', targetStaff.user_id).maybeSingle();
      if (taken) return json({ error: 'اسم المستخدم هذا مستخدم في حساب آخر' }, 400);
      const { error: upErr } = await admin.from('user_profiles').upsert({ id: targetStaff.user_id, username }, { onConflict: 'id' });
      if (upErr) return json({ error: 'تعذّر حفظ اسم المستخدم: ' + upErr.message }, 400);
      // a username-only account's private email follows the new username (it's never shown or emailed)
      const { data: userRes } = await admin.auth.admin.getUserById(targetStaff.user_id);
      const cur = (userRes?.user?.email || '').toLowerCase();
      if (cur.endsWith(PLACEHOLDER)) {
        await admin.auth.admin.updateUserById(targetStaff.user_id, {
          email: `${username.toLowerCase()}.${String(store_id).slice(0, 8)}${PLACEHOLDER}`, email_confirm: true,
        });
      }
      return json({ success: true, username });
    }

    if (action === 'update') {
      if (!rawNewEmail || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(rawNewEmail)) {
        return json({ error: 'صيغة البريد الإلكتروني غير صحيحة' }, 400);
      }
      const newEmail = rawNewEmail.trim().toLowerCase();

      const { data: userList } = await admin.auth.admin.listUsers({ perPage: 1000 });
      const clash = userList.users.find((u) => u.id !== targetStaff.user_id && (u.email || '').toLowerCase() === newEmail);
      if (clash) return json({ error: 'هذا البريد الإلكتروني مستخدم في حساب آخر' }, 400);

      const { error: updErr } = await admin.auth.admin.updateUserById(targetStaff.user_id, {
        email: newEmail,
        email_confirm: true, // takes effect immediately, no confirmation email required
      });
      if (updErr) return json({ error: 'تعذّر تحديث البريد الإلكتروني: ' + updErr.message }, 400);

      return json({ success: true, email: newEmail });
    }

    return json({ error: 'إجراء غير معروف' }, 400);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
