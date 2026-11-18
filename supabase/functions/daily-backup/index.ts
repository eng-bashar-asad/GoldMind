// Supabase Edge Function: daily-backup (بشار 2026-11-18)
//
// One backup file per company per day, kept forever as its own file:
//   storage bucket «store-backups» / <store_id>/<YYYY-MM-DD>.json.gz
// The date is the business day the file closes (taken at 03:00 company time, so the
// 03:00 run on 2 Jan saves «1 Jan»). A manual «نسخة الآن» is <date>_<HHMM>.json.gz.
//
// action="cron"        — pg_cron calls it every hour with x-backup-key (checked against the
//                        vault by gm_backup_key_ok); backs up each company where it is 03:00.
// action="backup_now"  — owner: make a backup of this company now.
// action="list"        — owner: the backups of this company.
// action="url"         — owner: a short-lived download link for one backup.
// action="restore"     — owner: bring back one deleted item (gm_backup_restore).
//
// DEPLOY (verify_jwt off — the function checks the key or the caller itself):
//   supabase functions deploy daily-backup --no-verify-jwt --project-ref puzkfwbmipldzgwofhjg

import { createClient } from 'npm:@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-backup-key',
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

const BUCKET = 'store-backups';
const BACKUP_HOUR = 3;
// company time zone from its country (stores.country); anything else → Dubai
const TZ: Record<string, string> = {
  AE: 'Asia/Dubai', SY: 'Asia/Damascus', SA: 'Asia/Riyadh', KW: 'Asia/Kuwait', QA: 'Asia/Qatar',
  BH: 'Asia/Bahrain', OM: 'Asia/Muscat', JO: 'Asia/Amman', LB: 'Asia/Beirut', IQ: 'Asia/Baghdad',
  EG: 'Africa/Cairo', TR: 'Europe/Istanbul', US: 'America/New_York', FR: 'Europe/Paris', NL: 'Europe/Amsterdam',
};

function localParts(tz: string, d = new Date()) {
  const p = Object.fromEntries(new Intl.DateTimeFormat('en-CA', {
    timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).formatToParts(d).map((x) => [x.type, x.value]));
  return { date: `${p.year}-${p.month}-${p.day}`, hour: Number(p.hour), hhmm: `${p.hour}${p.minute}` };
}
const dayBefore = (ymd: string) => {
  const d = new Date(ymd + 'T12:00:00Z'); d.setUTCDate(d.getUTCDate() - 1); return d.toISOString().slice(0, 10);
};

async function gzip(text: string) {
  const stream = new Blob([text]).stream().pipeThrough(new CompressionStream('gzip'));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}
async function gunzip(blob: Blob) {
  return await new Response(blob.stream().pipeThrough(new DecompressionStream('gzip'))).text();
}

// deno-lint-ignore no-explicit-any
async function backupStore(admin: any, storeId: string, name: string) {
  const { data: snap, error } = await admin.rpc('gm_store_snapshot', { sid: storeId });
  if (error) throw new Error('snapshot: ' + error.message);
  const body = JSON.stringify({ version: 1, store_id: storeId, taken_at: new Date().toISOString(), tables: snap });
  const bytes = await gzip(body);
  const { error: upErr } = await admin.storage.from(BUCKET).upload(`${storeId}/${name}.json.gz`, bytes, {
    contentType: 'application/gzip', upsert: false,
  });
  if (upErr && !/exists|duplicate/i.test(upErr.message)) throw new Error('upload: ' + upErr.message);
  return { file: `${name}.json.gz`, size: bytes.length, skipped: !!upErr };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const body = await req.json().catch(() => ({}));
    const { action } = body;
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

    if (action === 'cron') {
      const { data: ok } = await admin.rpc('gm_backup_key_ok', { k: req.headers.get('x-backup-key') || '' });
      if (ok !== true) return json({ error: 'forbidden' }, 403);
      const { data: stores } = await admin.from('stores').select('id, country');
      const done: unknown[] = [];
      for (const s of stores || []) {
        const lp = localParts(TZ[String(s.country || '').toUpperCase()] || 'Asia/Dubai');
        if (lp.hour !== BACKUP_HOUR && body.force !== true) continue;
        const name = body.force === true ? `${lp.date}_${lp.hhmm}` : dayBefore(lp.date); // a forced run is named like «نسخة الآن»
        try { done.push({ store: s.id, ...(await backupStore(admin, s.id, name)) }); }
        catch (e) { done.push({ store: s.id, error: String(e) }); }
      }
      return json({ ok: true, done });
    }

    // owner actions — the caller's own session decides
    const caller = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: req.headers.get('Authorization') || '' } },
    });
    const { data: { user } } = await caller.auth.getUser();
    if (!user) return json({ error: 'الجلسة غير صالحة، سجّل الدخول من جديد' }, 401);
    const { data: twoFaOk } = await caller.rpc('gm_session_ok');
    if (twoFaOk !== true) return json({ error: 'أكمل التحقق برمز البريد الإلكتروني أولاً ثم أعد المحاولة' }, 403);
    const storeId = String(body.store_id || '');
    const { data: me } = await admin.from('staff').select('role').eq('user_id', user.id).eq('store_id', storeId).maybeSingle();
    if (me?.role !== 'owner') return json({ error: 'النسخ الاحتياطية متاحة لمالك الشركة فقط' }, 403);
    const { data: store } = await admin.from('stores').select('id, country').eq('id', storeId).maybeSingle();
    if (!store) return json({ error: 'الشركة غير موجودة' }, 404);
    const safeFile = (f: unknown) => /^\d{4}-\d{2}-\d{2}(_\d{4})?\.json\.gz$/.test(String(f || '')) ? String(f) : null;

    if (action === 'list') {
      const { data, error } = await admin.storage.from(BUCKET).list(storeId, { limit: 1000, sortBy: { column: 'name', order: 'desc' } });
      if (error) return json({ error: error.message }, 400);
      return json({ files: (data || []).filter((f) => safeFile(f.name)).map((f) => ({ name: f.name, size: f.metadata?.size ?? null, at: f.created_at })) });
    }

    if (action === 'backup_now') {
      const lp = localParts(TZ[String(store.country || '').toUpperCase()] || 'Asia/Dubai');
      return json({ ok: true, ...(await backupStore(admin, storeId, `${lp.date}_${lp.hhmm}`)) });
    }

    if (action === 'url') {
      const f = safeFile(body.file);
      if (!f) return json({ error: 'ملف غير صحيح' }, 400);
      const { data, error } = await admin.storage.from(BUCKET).createSignedUrl(`${storeId}/${f}`, 120);
      if (error) return json({ error: error.message }, 400);
      return json({ url: data.signedUrl });
    }

    if (action === 'restore') {
      const f = safeFile(body.file);
      if (!f || !body.table || !body.id) return json({ error: 'بيانات ناقصة' }, 400);
      const { data: blob, error } = await admin.storage.from(BUCKET).download(`${storeId}/${f}`);
      if (error || !blob) return json({ error: 'تعذّر فتح النسخة' }, 400);
      const parsed = JSON.parse(await gunzip(blob));
      if (parsed.store_id !== storeId) return json({ error: 'النسخة لا تخص هذه الشركة' }, 400);
      const { data, error: rErr } = await admin.rpc('gm_backup_restore', {
        sid: storeId, tbl: String(body.table), rid: String(body.id), who: user.id,
        // only what a restore can touch (keeps the call small)
        snap: { [String(body.table)]: parsed.tables[String(body.table)] || [],
                cash_movements: parsed.tables.cash_movements || [], daily_cash_log: parsed.tables.daily_cash_log || [] },
      });
      if (rErr) return json({ error: rErr.message }, 400);
      return json(data);
    }

    return json({ error: 'إجراء غير معروف' }, 400);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
