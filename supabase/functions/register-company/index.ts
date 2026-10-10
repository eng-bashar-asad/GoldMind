import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// Public self-service company registration: a new business registers itself
// and gets an owner login plus a 30-day trial.
//
// verify_jwt is FALSE deliberately: a brand-new visitor has no session yet.
//
// Security:
// - never touches an existing account (an email that exists is refused)
// - the temporary password is EMAILED (Brevo, sender "GoldMind"), never returned
//   to the browser, so only the real owner of the address can sign in.
//   Until the BREVO_API_KEY secret is set the old behaviour stays (password shown).
// - rate limited: 3 registrations an hour per address, 20 a day in total
// - field lengths capped; internal error details go to the logs only

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

const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!));
const TRIAL_DAYS = 30;
const PER_IP_PER_HOUR = 3;
const TOTAL_PER_DAY = 20;
const SITE_URL = 'https://eng-bashar-asad.github.io/GoldMind';
const SENDER_EMAIL = 'eng.bashar.asad@gmail.com';
const GENERIC = 'تعذّر إنشاء الحساب، حاول مرة أخرى لاحقاً.';

async function sendPasswordEmail(key: string, to: string, ownerName: string, company: string, password: string) {
  const html = `
    <div dir="rtl" style="font-family:Arial,sans-serif;background:#0f172a;padding:32px;color:#fff;">
      <div style="max-width:480px;margin:0 auto;background:#1e293b;border-radius:12px;padding:32px;border:1px solid rgba(212,175,55,0.3);">
        <h2 style="color:#D4AF37;margin-top:0;">مرحباً بك في GoldMind</h2>
        <p>أهلاً ${esc(ownerName)}، تم إنشاء حساب <strong>${esc(company)}</strong> مع تجربة مجانية لمدة ${TRIAL_DAYS} يوماً.</p>
        <p>بيانات الدخول:</p>
        <p style="background:#0f172a;border-radius:8px;padding:12px;direction:ltr;text-align:left;font-family:monospace;">
          ${esc(to)}<br>${esc(password)}
        </p>
        <p>ننصحك بتغيير كلمة المرور بعد أول دخول.</p>
        <p style="text-align:center;margin:28px 0;">
          <a href="${SITE_URL}/login-entry-ar.html" style="background:linear-gradient(135deg,#F5D77A,#D4AF37);color:#0f172a;text-decoration:none;padding:14px 28px;border-radius:8px;font-weight:bold;display:inline-block;">الدخول الآن</a>
        </p>
        <p style="font-size:12px;color:#94a3b8;">إذا لم تقم بإنشاء هذا الحساب، يمكنك تجاهل هذه الرسالة.</p>
      </div>
    </div>`;
  const res = await fetch('https://api.brevo.com/v3/smtp/email', {
    method: 'POST',
    headers: { 'api-key': key, 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify({
      sender: { name: 'GoldMind', email: SENDER_EMAIL },
      to: [{ email: to }],
      subject: 'بيانات الدخول إلى GoldMind',
      htmlContent: html,
    }),
  });
  if (!res.ok) throw new Error('brevo ' + res.status + ' ' + (await res.text().catch(() => '')));
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: GENERIC }, 405);

  try {
    const body = await req.json().catch(() => ({}));
    const company_name = String(body.company_name || '').trim();
    const owner_name = String(body.owner_name || '').trim();
    const owner_phone = String(body.owner_phone || '').trim();
    const email = String(body.owner_email || '').trim().toLowerCase();

    if (!company_name || !owner_name || !email) {
      return json({ error: 'اسم الشركة واسمك وبريدك الإلكتروني حقول مطلوبة' }, 400);
    }
    if (company_name.length > 100 || owner_name.length > 80 || owner_phone.length > 30 || email.length > 254) {
      return json({ error: 'أحد الحقول أطول من المسموح' }, 400);
    }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return json({ error: 'صيغة البريد الإلكتروني غير صحيحة' }, 400);
    }

    const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
    const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const BREVO_API_KEY = Deno.env.get('BREVO_API_KEY') || '';
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    // rate limit
    const ip = (req.headers.get('cf-connecting-ip') || req.headers.get('x-real-ip') ||
      (req.headers.get('x-forwarded-for') || 'unknown').split(',')[0]).trim().slice(0, 64);
    const hourAgo = new Date(Date.now() - 3600_000).toISOString();
    const dayAgo = new Date(Date.now() - 86400_000).toISOString();
    const [{ count: ipCount }, { count: dayCount }] = await Promise.all([
      admin.from('company_register_attempts').select('id', { count: 'exact', head: true }).eq('caller_ip', ip).gte('attempted_at', hourAgo),
      admin.from('company_register_attempts').select('id', { count: 'exact', head: true }).gte('attempted_at', dayAgo),
    ]);
    if ((ipCount ?? 0) >= PER_IP_PER_HOUR || (dayCount ?? 0) >= TOTAL_PER_DAY) {
      return json({ error: 'تم تجاوز عدد محاولات التسجيل المسموح. حاول مرة أخرى بعد ساعة.' }, 429);
    }
    await admin.from('company_register_attempts').insert({ caller_ip: ip });
    await admin.from('company_register_attempts').delete().lt('attempted_at', dayAgo);

    // existing email → refuse (never touch an existing account)
    const { data: userList } = await admin.auth.admin.listUsers({ perPage: 1000 });
    if (userList?.users.find((u) => (u.email || '').toLowerCase() === email)) {
      return json({ error: 'هذا البريد الإلكتروني مسجّل مسبقاً. سجّل الدخول بحسابك الحالي بدلاً من إنشاء حساب جديد.' }, 400);
    }

    const { data: basicPlan, error: planErr } = await admin.from('plans').select('id').eq('key', 'basic').maybeSingle();
    if (planErr || !basicPlan) { console.error('plan', planErr); return json({ error: GENERIC }, 500); }

    const tempPassword = generatePassword(12);
    const { data: newUser, error: createErr } = await admin.auth.admin.createUser({ email, password: tempPassword, email_confirm: true });
    if (createErr || !newUser) { console.error('createUser', createErr); return json({ error: GENERIC }, 400); }
    const userId = newUser.user.id;

    // email first: if it cannot be delivered, undo the account so the address stays free
    if (BREVO_API_KEY) {
      try {
        await sendPasswordEmail(BREVO_API_KEY, email, owner_name, company_name, tempPassword);
      } catch (e) {
        console.error('email', e);
        await admin.auth.admin.deleteUser(userId);
        return json({ error: 'تعذّر إرسال البريد إلى هذا العنوان. تأكد من البريد الإلكتروني وحاول مرة أخرى.' }, 502);
      }
    }

    const { data: newStore, error: storeErr } = await admin.from('stores').insert({
      name: company_name, phone: owner_phone || null, email, manager_name: owner_name,
    }).select('id').single();
    if (storeErr || !newStore) {
      console.error('store', storeErr);
      await admin.auth.admin.deleteUser(userId);
      return json({ error: GENERIC }, 400);
    }

    const { error: staffErr } = await admin.from('staff').insert({
      store_id: newStore.id, user_id: userId, full_name: owner_name, role: 'owner', permissions: {}, whatsapp_phone: owner_phone || null,
    });
    if (staffErr) { console.error('staff', staffErr); return json({ error: GENERIC }, 400); }

    const trialEnd = new Date();
    trialEnd.setDate(trialEnd.getDate() + TRIAL_DAYS);
    const { error: subErr } = await admin.from('subscriptions').insert({
      store_id: newStore.id, plan_id: basicPlan.id, status: 'trialing', trial_end: trialEnd.toISOString(),
    });
    if (subErr) { console.error('subscription', subErr); return json({ error: 'أُنشئت الشركة لكن تعذّر تفعيل التجربة المجانية، تواصل معنا.' }, 400); }

    return BREVO_API_KEY
      ? json({ success: true, email, emailed: true })
      : json({ success: true, email, temp_password: tempPassword }); // ponytail: until BREVO_API_KEY secret is set
  } catch (e) {
    console.error('register-company', e);
    return json({ error: GENERIC }, 500);
  }
});
