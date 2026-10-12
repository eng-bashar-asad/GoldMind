import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// Second step of a password sign-in: an 8-digit code emailed to the account, valid 1 minute.
// action "send"   → (re)sends a code for the caller's current session
// action "verify" → checks the code; on success the session is marked verified
// The server-side gate (gm_session_ok / gm_pre_request) reads public.login_2fa.
// verify_jwt is on: the gateway has already checked the token's signature.

const SENDER_EMAIL = "eng.bashar.asad@gmail.com";
const CODE_TTL_MS = 60_000;      // 1 minute
const RESEND_GAP_MS = 20_000;    // at most one email every 20 s
const MAX_SENDS = 8;             // per session
const MAX_ATTEMPTS = 5;          // wrong codes before a new code is needed
const PLACEHOLDER = "@staff.goldmind.app";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

function claims(auth: string | null): Record<string, any> | null {
  const t = (auth || "").replace(/^Bearer\s+/i, "").split(".");
  if (t.length !== 3) return null;
  try { return JSON.parse(atob(t[1].replace(/-/g, "+").replace(/_/g, "/"))); } catch { return null; }
}
async function sha256(s: string) {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return Array.from(new Uint8Array(d)).map((b) => b.toString(16).padStart(2, "0")).join("");
}
function code8() {
  const a = new Uint32Array(1);
  do { crypto.getRandomValues(a); } while (a[0] >= 4_200_000_000); // no modulo bias
  return String(a[0] % 100_000_000).padStart(8, "0");
}
function maskEmail(e: string) {
  const [u, d] = e.split("@");
  return (u.length <= 2 ? u[0] + "*" : u.slice(0, 2) + "*".repeat(Math.min(6, u.length - 2))) + "@" + d;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const c = claims(req.headers.get("Authorization"));
    if (!c || !c.sub || !c.session_id) return json({ error: "انتهت الجلسة، سجّل الدخول من جديد" }, 401);
    const methods: string[] = Array.isArray(c.amr) ? c.amr.map((a: any) => a && a.method) : [];
    const email = String(c.email || "").toLowerCase();
    if (!methods.includes("password") || methods.some((m) => m !== "password") || !email || email.endsWith(PLACEHOLDER)) {
      return json({ ok: true, not_needed: true });
    }

    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { action, code } = await req.json().catch(() => ({}));
    const { data: row } = await admin.from("login_2fa").select("*").eq("session_id", c.session_id).maybeSingle();
    if (row && row.user_id !== c.sub) return json({ error: "جلسة غير صالحة" }, 403);
    if (row && row.verified_at) return json({ ok: true, verified: true });

    if (action === "send") {
      const now = Date.now();
      if (row && row.last_sent_at && now - Date.parse(row.last_sent_at) < RESEND_GAP_MS) {
        return json({ error: "انتظر قليلاً قبل طلب رمز جديد", wait: Math.ceil((RESEND_GAP_MS - (now - Date.parse(row.last_sent_at))) / 1000) }, 429);
      }
      if (row && row.sent_count >= MAX_SENDS) return json({ error: "تجاوزت عدد الرموز المسموح. سجّل الدخول من جديد." }, 429);
      const key = Deno.env.get("BREVO_API_KEY");
      if (!key) { console.error("BREVO_API_KEY missing"); return json({ error: "تعذّر إرسال الرمز حالياً" }, 500); }
      const theCode = code8();
      const html = `<div dir="rtl" style="font-family:Arial,sans-serif;background:#0f172a;padding:32px;color:#fff;">
        <div style="max-width:440px;margin:0 auto;background:#1e293b;border-radius:12px;padding:28px;border:1px solid rgba(212,175,55,0.3);text-align:center;">
          <h2 style="color:#D4AF37;margin-top:0;">رمز الدخول إلى GoldMind</h2>
          <p>استخدم هذا الرمز لإكمال تسجيل الدخول:</p>
          <p style="font-size:34px;letter-spacing:6px;font-weight:bold;direction:ltr;background:#0f172a;border-radius:8px;padding:14px;margin:18px 0;">${theCode}</p>
          <p>الرمز صالح لمدة <b>دقيقة واحدة</b> فقط.</p>
          <p style="font-size:12px;color:#94a3b8;">إذا لم تحاول تسجيل الدخول الآن، فقد تكون كلمة السر الخاصة بك معروفة لشخص آخر — غيّرها فوراً.</p>
        </div></div>`;
      const res = await fetch("https://api.brevo.com/v3/smtp/email", {
        method: "POST",
        headers: { "api-key": key, "Content-Type": "application/json", Accept: "application/json" },
        body: JSON.stringify({ sender: { name: "GoldMind", email: SENDER_EMAIL }, to: [{ email }], subject: "رمز الدخول: " + theCode, htmlContent: html }),
      });
      if (!res.ok) { console.error("brevo", res.status, await res.text().catch(() => "")); return json({ error: "تعذّر إرسال الرمز، حاول مرة أخرى" }, 502); }
      await admin.from("login_2fa").upsert({
        session_id: c.session_id, user_id: c.sub, code_hash: await sha256(c.session_id + ":" + theCode),
        expires_at: new Date(now + CODE_TTL_MS).toISOString(), attempts: 0,
        sent_count: (row ? row.sent_count : 0) + 1, last_sent_at: new Date(now).toISOString(),
      });
      return json({ ok: true, sent: true, to: maskEmail(email), ttl: CODE_TTL_MS / 1000 });
    }

    if (action === "verify") {
      const given = String(code || "").replace(/\D/g, "");
      if (!row || !row.code_hash) return json({ error: "اطلب رمزاً أولاً" }, 400);
      if (row.attempts >= MAX_ATTEMPTS) return json({ error: "محاولات خاطئة كثيرة — اطلب رمزاً جديداً" }, 429);
      if (Date.parse(row.expires_at) < Date.now()) return json({ error: "انتهت صلاحية الرمز — اطلب رمزاً جديداً", expired: true }, 400);
      if (given.length !== 8 || (await sha256(c.session_id + ":" + given)) !== row.code_hash) {
        await admin.from("login_2fa").update({ attempts: row.attempts + 1 }).eq("session_id", c.session_id);
        return json({ error: "الرمز غير صحيح", left: MAX_ATTEMPTS - row.attempts - 1 }, 400);
      }
      await admin.from("login_2fa").update({ verified_at: new Date().toISOString(), code_hash: null }).eq("session_id", c.session_id);
      return json({ ok: true, verified: true });
    }
    return json({ error: "طلب غير معروف" }, 400);
  } catch (e) {
    console.error("login-2fa", e);
    return json({ error: "حدث خطأ، حاول مرة أخرى" }, 500);
  }
});
