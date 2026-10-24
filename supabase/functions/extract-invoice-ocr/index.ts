import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// Reads a photographed paper purchase invoice (from a gold trader) and returns suggested values to
// prefill the purchase forms (trader receive-goods voucher, purchase invoice). It NEVER writes to the
// database: staff always review the lines and save them themselves.
//
// The Gemini key lives only here (GEMINI_API_KEY secret). Google retires model names from time to
// time (gemini-2.5-flash stopped working for this key in 2026-10), so the model is picked from the
// key's own model list instead of being hard-coded; GEMINI_MODEL can still force one.

const EXTRACTION_PROMPT = `أنت تقرأ فاتورة ذهب مصوّرة (فاتورة بيع من تاجر ذهب لمحل مجوهرات). قد تكون بالعربية أو الإنجليزية.
أرجع JSON فقط بهذا الشكل بالضبط، بدون أي نص آخر:
{
  "trader_name": string أو null (اسم التاجر/الشركة البائعة كما في رأس الفاتورة),
  "invoice_number": string أو null,
  "invoice_date": string أو null (YYYY-MM-DD),
  "vat_rate": number أو null (نسبة الضريبة % إن ذُكرت),
  "items": [
    {
      "description": string أو null (مثلاً "خاتم" أو "سلسلة"),
      "karat": number أو null (18 أو 21 أو 22 أو 24؛ حوّل 750→18، 875→21، 916→22، 999→24),
      "quantity": number أو null (عدد القطع في السطر),
      "gross_weight_grams": number أو null (الوزن القائم),
      "net_weight_grams": number أو null (الوزن الصافي/المحاسبي إن وُجد عمود منفصل، وإلا null),
      "fab_fee_per_gram": number أو null (المصنعية للغرام),
      "fab_fee_total": number أو null (مجموع مصنعية السطر)
    }
  ],
  "weight_grams": number أو null (مجموع الوزن),
  "karat": number أو null (عيار أغلب البضاعة),
  "price_per_gram_or_total": number أو null,
  "is_total_not_per_gram": boolean,
  "fabrication_fee": number أو null (مجموع المصنعية),
  "description": string أو null,
  "confidence_note": string (جملة قصيرة بالعربي عن أي رقم غير واضح أو حقل لم يُقرأ)
}
سطر لكل سطر في جدول الفاتورة. لا تخترع أرقاماً: الرقم غير المقروء يكون null واذكره في confidence_note.
إذا لم تكن الصورة فاتورة ذهب، أرجع items فارغة وكل الحقول null مع السبب في confidence_note.`;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

let cachedModels: string[] | null = null;

// Flash models this key can call with generateContent, newest first (stable before preview, no lite/image/tts).
async function candidateModels(key: string): Promise<string[]> {
  const forced = Deno.env.get("GEMINI_MODEL");
  if (forced) return [forced];
  if (cachedModels) return cachedModels;
  const names: string[] = [];
  try {
    let page = "";
    for (let i = 0; i < 5; i++) {
      const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models?pageSize=200${page ? "&pageToken=" + page : ""}`,
        { headers: { "x-goog-api-key": key } });
      if (!r.ok) break;
      const d = await r.json();
      for (const m of d.models || []) {
        const n = String(m.name || "").replace(/^models\//, "");
        if ((m.supportedGenerationMethods || []).includes("generateContent") && /^gemini-[\d.]+-flash/.test(n)
            && !/lite|image|tts|audio|live|thinking|embedding/.test(n)) names.push(n);
      }
      page = d.nextPageToken || "";
      if (!page) break;
    }
  } catch (_e) { /* fall through to the defaults */ }
  const ver = (n: string) => parseFloat((n.match(/gemini-([\d.]+)/) || [])[1] || "0");
  names.sort((a, b) => (ver(b) - ver(a)) || (Number(/preview|exp/.test(a)) - Number(/preview|exp/.test(b))) || a.length - b.length);
  cachedModels = names.length ? names : ["gemini-flash-latest", "gemini-2.5-flash"];
  return cachedModels;
}

async function signedInUser(req: Request): Promise<boolean> {
  const auth = req.headers.get("Authorization") || "";
  const url = Deno.env.get("SUPABASE_URL"), anon = Deno.env.get("SUPABASE_ANON_KEY");
  if (!auth.startsWith("Bearer ") || !url || !anon) return false;
  const r = await fetch(url + "/auth/v1/user", { headers: { Authorization: auth, apikey: anon } });
  return r.ok;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const body = await req.json();
    // signed-in users only, the health check too (it spends the Gemini quota)
    if (!(await signedInUser(req))) return json({ error: "NOT_SIGNED_IN" }, 401);
    // Health check (no image, fixed one-word prompt): which model answers. Lets us see quickly that the
    // key and model still work after Google renames models.
    if (body && body.selftest === true) {
      const key = Deno.env.get("GEMINI_API_KEY");
      if (!key) return json({ ok: false, error: "SERVER_NOT_CONFIGURED" });
      const models = await candidateModels(key);
      for (const model of models.slice(0, 4)) {
        const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
          method: "POST", headers: { "Content-Type": "application/json", "x-goog-api-key": key },
          body: JSON.stringify({ contents: [{ parts: [{ text: "Reply with the single word OK." }] }] }),
        });
        if (r.ok) return json({ ok: true, model, candidates: models.slice(0, 6) });
        if (r.status !== 404) return json({ ok: false, model, status: r.status, detail: (await r.text()).slice(0, 300) });
        cachedModels = (cachedModels || []).filter((m) => m !== model);
      }
      return json({ ok: false, error: "NO_MODEL_AVAILABLE", candidates: models.slice(0, 6) });
    }
    const { image_base64, mime_type } = body || {};
    if (!image_base64 || typeof image_base64 !== "string") return json({ error: "MISSING_IMAGE" }, 400);
    const key = Deno.env.get("GEMINI_API_KEY");
    if (!key) return json({ error: "SERVER_NOT_CONFIGURED" }, 500);

    let lastErr = "";
    for (const model of (await candidateModels(key)).slice(0, 4)) {
      const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-goog-api-key": key },
        body: JSON.stringify({
          contents: [{ parts: [{ text: EXTRACTION_PROMPT }, { inline_data: { mime_type: mime_type || "image/jpeg", data: image_base64 } }] }],
          generationConfig: { temperature: 0.1, responseMimeType: "application/json" },
        }),
      });
      if (!r.ok) {
        lastErr = (await r.text()).slice(0, 400);
        if (r.status === 404) { cachedModels = (cachedModels || []).filter((m) => m !== model); continue; } // retired model name
        return json({ error: "GEMINI_REQUEST_FAILED", status: r.status, detail: lastErr }, 502);
      }
      const d = await r.json();
      const raw = (d?.candidates?.[0]?.content?.parts || []).map((p: { text?: string }) => p.text || "").join("");
      if (!raw) return json({ error: "NO_RESULT_FROM_MODEL", model }, 502);
      try {
        const extracted = JSON.parse(raw.replace(/^```(json)?|```$/g, "").trim());
        if (!Array.isArray(extracted.items)) extracted.items = [];
        return json({ extracted, model });
      } catch (_e) {
        return json({ error: "MODEL_RETURNED_INVALID_JSON", raw: raw.slice(0, 400) }, 502);
      }
    }
    return json({ error: "NO_MODEL_AVAILABLE", detail: lastErr }, 502);
  } catch (err) {
    return json({ error: "UNEXPECTED_ERROR", detail: String(err) }, 500);
  }
});
