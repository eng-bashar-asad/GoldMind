import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// The Brevo key lives in the BREVO_API_KEY secret (Supabase > Edge Functions > Secrets), never in code.
const SITE_URL = "https://eng-bashar-asad.github.io/GoldMind";
const SENDER_EMAIL = "eng.bashar.asad@gmail.com";
const SENDER_NAME = "GoldMind";

const esc = (s: string) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));

function decodeJwtSub(authHeader: string | null): string | null {
  if (!authHeader) return null;
  const token = authHeader.replace(/^Bearer\s+/i, "");
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  try {
    const payload = JSON.parse(atob(parts[1].replace(/-/g, "+").replace(/_/g, "/")));
    return payload.sub || null;
  } catch {
    return null;
  }
}

Deno.serve(async (req: Request) => {
  const cors = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
  const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  try {
    // verify_jwt is on, so the gateway has already checked the token's signature
    const callerId = decodeJwtSub(req.headers.get("Authorization"));
    if (!callerId) return json({ error: "NOT_AUTHENTICATED" }, 401);

    const { store_id, invite_email } = await req.json();
    if (!store_id || !invite_email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(invite_email)) || String(invite_email).length > 254) {
      return json({ error: "MISSING_FIELDS" }, 400);
    }

    const BREVO_API_KEY = Deno.env.get("BREVO_API_KEY");
    if (!BREVO_API_KEY) { console.error("BREVO_API_KEY secret is missing"); return json({ error: "EMAIL_NOT_CONFIGURED" }, 500); }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(supabaseUrl, serviceRoleKey);

    // Authorized if: platform admin (any store), OR owner/manage_staff staff of this store
    const { data: isAdminRow } = await admin.from("platform_admins").select("id").eq("id", callerId).maybeSingle();
    let authorized = !!isAdminRow;
    if (!authorized) {
      const { data: staffRow } = await admin.from("staff")
        .select("role, permissions")
        .eq("user_id", callerId).eq("store_id", store_id).maybeSingle();
      authorized = !!staffRow && (staffRow.role === "owner" || staffRow.permissions?.manage_staff === true);
    }
    if (!authorized) return json({ error: "NOT_AUTHORIZED" }, 403);

    const { data: store } = await admin.from("stores").select("name").eq("id", store_id).maybeSingle();
    const companyName = store?.name || "شركتك";

    const html = `
      <div dir="rtl" style="font-family:Arial,sans-serif;background:#0f172a;padding:32px;color:#fff;">
        <div style="max-width:480px;margin:0 auto;background:#1e293b;border-radius:12px;padding:32px;border:1px solid rgba(212,175,55,0.3);">
          <h2 style="color:#D4AF37;margin-top:0;">دعوة للانضمام إلى GoldMind</h2>
          <p>تمت دعوتك للانضمام إلى <strong>${esc(companyName)}</strong> على منصة GoldMind لإدارة محلات الذهب والمجوهرات.</p>
          <p>للانضمام، افتح الرابط التالي، واختر «الدخول إلى شركتي» ثم «الدخول عن طريق البريد»، وأدخل بريدك الإلكتروني (${esc(invite_email)}) ليصلك رمز الدخول.</p>
          <p style="text-align:center;margin:28px 0;">
            <a href="${SITE_URL}/login-entry-ar.html" style="background:linear-gradient(135deg,#F5D77A,#D4AF37);color:#0f172a;text-decoration:none;padding:14px 28px;border-radius:8px;font-weight:bold;display:inline-block;">الدخول الآن</a>
          </p>
          <p style="font-size:12px;color:#94a3b8;">إذا لم تكن تتوقع هذه الدعوة، يمكنك تجاهل هذه الرسالة.</p>
        </div>
      </div>`;

    const brevoRes = await fetch("https://api.brevo.com/v3/smtp/email", {
      method: "POST",
      headers: { "api-key": BREVO_API_KEY, "Content-Type": "application/json", "Accept": "application/json" },
      body: JSON.stringify({
        sender: { name: SENDER_NAME, email: SENDER_EMAIL },
        to: [{ email: invite_email }],
        subject: `دعوة للانضمام إلى ${companyName} على GoldMind`,
        htmlContent: html,
      }),
    });
    if (!brevoRes.ok) {
      console.error("brevo", brevoRes.status, await brevoRes.text().catch(() => ""));
      return json({ error: "BREVO_SEND_FAILED" }, 502);
    }
    return json({ success: true });
  } catch (err) {
    console.error("send-invite-email", err);
    return json({ error: "UNEXPECTED" }, 500);
  }
});
