// Ensure every page has a history.state entry. Without this, some mobile
// browsers/WebViews (especially installed standalone PWAs) treat a page
// with no history state as having nothing to go back to, and interpret an
// edge-swipe-back gesture as "exit the app" instead of "go back one page".
if (!history.state) {
  history.replaceState({ gmPage: location.pathname }, '');
}

// ---------- In-app update check (packaged Android APK only) ----------
// The website (GitHub Pages / "add to home screen") always serves the
// latest code on its own — the service worker fetches every page
// network-first. The sideloaded APK is different: it's a snapshot frozen
// at build time inside app/www, so it never updates itself no matter how
// many times the underlying site changes. This checks the APK's own
// baked-in commit (app/www/build-info.json, stamped by the GitHub Actions
// build) against the latest commit on GitHub and — only when they differ,
// and only inside the actual installed app, never on the website — shows
// a small dismissible banner linking to the newest APK download.
(function gmCheckAppUpdate() {
  const isNativeApp = !!(window.Capacitor && typeof window.Capacitor.isNativePlatform === 'function' && window.Capacitor.isNativePlatform());
  if (!isNativeApp) return;

  const DISMISS_KEY = 'goldmind_update_dismissed_sha';
  const APK_URL = 'https://github.com/eng-bashar-asad/GoldMind/releases/download/app-latest/GoldMind.apk';

  // ?t=: never an older copy from a cache (an app update keeps the old service worker for one launch)
  fetch('build-info.json?t=' + Date.now(), { cache: 'no-store' })
    .then(r => r.ok ? r.json() : null)
    .then(buildInfo => {
      if (!buildInfo || !buildInfo.sha) return;
      // Compare with the commit the downloadable APK was actually built from
      // (written in the release notes), not the newest commit on main: a new
      // commit is on main minutes before its APK is ready, and downloading
      // during that gap installed the old APK again — so the banner never went away.
      return fetch('https://api.github.com/repos/eng-bashar-asad/GoldMind/releases/tags/app-latest', { cache: 'no-store' })
        .then(r => r.ok ? r.json() : null)
        .then(rel => {
          const body = String(rel && rel.body || '');
          const m = body.match(/commit ([0-9a-f]{40})/);
          if (!m) return;
          const releaseSha = m[1];
          if (releaseSha === buildInfo.sha) return; // this phone already has the newest APK
          // Same app files, only another commit (tests, SQL, notes): not an update (Bashar 2026-11-02).
          const c = body.match(/content ([0-9a-f]{16})/);
          if (c && buildInfo.content && c[1] === buildInfo.content) return;
          if (localStorage.getItem(DISMISS_KEY) === releaseSha) return; // user already dismissed this exact version
          gmShowUpdateBanner(APK_URL, releaseSha);
        });
    })
    .catch(() => {}); // silent — a failed version check should never block using the app
})();

function gmShowUpdateBanner(apkUrl, latestSha) {
  if (document.getElementById('gm-update-banner')) return;
  const bar = document.createElement('div');
  bar.id = 'gm-update-banner';
  // The app now draws under the phone's status bar (Android 15+, Capacitor 8): keep the bar below it,
  // otherwise the status bar covers it and «تنزيل» can't be tapped.
  const SAFE_TOP = 'max(env(safe-area-inset-top, 0px), var(--safe-area-inset-top, 0px))';
  bar.style.cssText = 'position:fixed;top:0;left:0;right:0;z-index:9999;background:#B4955A;color:#fff;' +
    'display:flex;align-items:center;justify-content:space-between;gap:8px;padding:8px 12px;padding-top:calc(8px + ' + SAFE_TOP + ');' +
    'font-family:Inter,sans-serif;font-size:12.5px;font-weight:600;direction:rtl;box-shadow:0 2px 8px rgba(0,0,0,.15);';
  bar.innerHTML =
    '<span>يتوفر تحديث جديد للتطبيق</span>' +
    '<span style="display:flex;gap:6px;align-items:center;">' +
      // a different link for every version: the phone's browser otherwise offers to "open" the APK it
      // downloaded last time (same address), which reinstalls the old version and the bar comes back.
      '<a href="' + apkUrl + '?v=' + String(latestSha).slice(0, 12) + '" style="background:#fff;color:#7a6222;border-radius:999px;padding:8px 14px;text-decoration:none;font-weight:700;">تنزيل</a>' +
      '<button type="button" aria-label="إخفاء" style="background:transparent;border:none;color:#fff;font-size:18px;line-height:1;cursor:pointer;min-width:44px;min-height:44px;">×</button>' +
    '</span>';
  bar.querySelector('button').onclick = function () {
    localStorage.setItem('goldmind_update_dismissed_sha', latestSha);
    bar.remove();
  };
  document.body.prepend(bar);
  document.body.style.paddingTop = 'calc(' + (document.body.style.paddingTop || '0px') + ' + 44px + max(env(safe-area-inset-top, 0px), var(--safe-area-inset-top, 0px)))';
}

// GoldMind shared theming system.
// Each theme sets CSS custom properties on :root. Pages whose Tailwind
// config colors reference these variables (e.g. "primary": "var(--gm-primary)")
// update live when the theme changes — no rebuild/reload needed.
//
// --gm-bg          = dark hero tone (used only by index-ar.html's body)
// --gm-bg-elevated = light page background (used by all other pages' body)
// --gm-surface-*   = white/near-white card surfaces, same across all pages

// ---------- Display timezone (per-device preference) ----------
// The device's own clock/timezone was already correct all along — every
// created_at is a real UTC instant from the server. This is purely about
// which timezone the app converts that instant into when DISPLAYING it,
// for staff who read the app from a different city than the shop. Stored
// per-device (localStorage), never synced, defaults to the browser's own
// timezone if the person never picked one.
const GOLDMIND_TIMEZONES = [
  { id: 'Africa/Cairo', label: 'GMT+2 — القاهرة' },
  { id: 'Asia/Damascus', label: 'GMT+3 — دمشق' },
  { id: 'Asia/Beirut', label: 'GMT+3 — بيروت' },
  { id: 'Asia/Amman', label: 'GMT+3 — عمّان' },
  { id: 'Asia/Baghdad', label: 'GMT+3 — بغداد' },
  { id: 'Asia/Riyadh', label: 'GMT+3 — الرياض' },
  { id: 'Asia/Kuwait', label: 'GMT+3 — الكويت' },
  { id: 'Asia/Qatar', label: 'GMT+3 — الدوحة' },
  { id: 'Asia/Bahrain', label: 'GMT+3 — المنامة' },
  { id: 'Asia/Dubai', label: 'GMT+4 — دبي/أبوظبي' },
  { id: 'Asia/Muscat', label: 'GMT+4 — مسقط' },
  { id: 'Europe/Istanbul', label: 'GMT+3 — إسطنبول' },
  { id: 'Africa/Casablanca', label: 'GMT+1 — الدار البيضاء' },
  { id: 'Africa/Algiers', label: 'GMT+1 — الجزائر' },
  { id: 'Africa/Tunis', label: 'GMT+1 — تونس' },
  { id: 'Europe/London', label: 'GMT+0/+1 — لندن' },
  { id: 'America/New_York', label: 'GMT-5/-4 — نيويورك' },
];

function gmGetDisplayTimeZone() {
  return localStorage.getItem('goldmind_display_timezone') || Intl.DateTimeFormat().resolvedOptions().timeZone;
}

function gmSetDisplayTimeZone(tz) {
  localStorage.setItem('goldmind_display_timezone', tz);
}

// Drop-in replacement for `new Date(x).toLocaleDateString(...)` /
// `toLocaleTimeString(...)` that always converts into the chosen display
// timezone instead of whatever timezone the device happens to be set to.
// One date format for the whole app: 27/09/2026 01:16 م (day/month/year,
// Latin digits). The numeric form is wrapped in a left-to-right isolate so
// Arabic text around it can't flip the parts (it used to show "2026/9/27"
// or "302026/09/"). Pass only date parts ({day, month, year}) for a date,
// only {hour, minute} for a time; no arguments = now.
function gmFormatDateTime(dateInput, opts) {
  opts = opts || {};
  const d = dateInput == null ? new Date() : dateInput instanceof Date ? dateInput : new Date(dateInput);
  if (isNaN(d)) return '';
  const tz = (typeof gmGetDisplayTimeZone === 'function') ? gmGetDisplayTimeZone() : undefined;
  if (opts.weekday) return d.toLocaleString('ar-EG-u-nu-latn', { ...opts, timeZone: tz });
  const none = !Object.keys(opts).length;
  const wantDate = none || opts.day || opts.month || opts.year;
  const wantTime = none || opts.hour || opts.minute;
  const p = {};
  new Intl.DateTimeFormat('en-GB', { timeZone: tz, day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit', hour12: true })
    .formatToParts(d).forEach(x => { p[x.type] = x.value; });
  // each number group is isolated left-to-right; read right to left the
  // result is: date, time, ص/م
  const iso = t => '\u2066' + t + '\u2069';
  const out = [];
  if (wantDate) out.push(iso(p.day + '/' + p.month + '/' + p.year));
  if (wantTime) out.push(iso(p.hour + ':' + p.minute) + ' ' + (String(p.dayPeriod).toLowerCase().startsWith('p') ? 'م' : 'ص'));
  return out.join(' ');
}


// Renders the small timezone-picker popover. Call gmOpenTimezonePicker()
// from an icon button; expects a #gmTzModal container to exist on the
// page (gmInjectTimezonePicker() creates one if missing).
function gmInjectTimezonePicker() {
  if (document.getElementById('gmTzModal')) return;
  const wrap = document.createElement('div');
  wrap.id = 'gmTzModal';
  wrap.className = 'hidden fixed inset-0 z-[100] flex items-end lg:items-center justify-center bg-black/40';
  wrap.innerHTML = `
    <div class="bg-surface-container-lowest w-full lg:w-96 lg:rounded-2xl rounded-t-2xl p-5 max-h-[80vh] overflow-y-auto">
      <div class="flex items-center justify-between mb-3">
        <h3 class="font-bold text-[15px] text-on-surface">المنطقة الزمنية للعرض</h3>
        <button onclick="gmCloseTimezonePicker()" class="w-8 h-8 flex items-center justify-center rounded-full hover:bg-surface-container-high"><span class="material-symbols-outlined text-on-surface-variant">close</span></button>
      </div>
      <p class="text-[11px] text-on-surface-variant mb-3">يغيّر هذا الإعداد طريقة عرض الأوقات لك على هذا الجهاز فقط — ولا يغيّر وقت الحفظ الفعلي في قاعدة البيانات.</p>
      <div id="gmTzList" class="flex flex-col gap-1"></div>
    </div>`;
  document.body.appendChild(wrap);
  const listEl = wrap.querySelector('#gmTzList');
  const current = gmGetDisplayTimeZone();
  listEl.innerHTML = GOLDMIND_TIMEZONES.map(tz => `
    <button onclick="gmSetDisplayTimeZone('${tz.id}'); gmCloseTimezonePicker(); window.location.reload();"
      class="text-right p-3 rounded-lg text-[13px] flex items-center justify-between ${tz.id === current ? 'bg-primary text-on-primary font-semibold' : 'text-on-surface hover:bg-surface-container-high'}">
      <span>${tz.label}</span>
      ${tz.id === current ? '<span class="material-symbols-outlined text-[16px]">check</span>' : ''}
    </button>`).join('');
}

function gmOpenTimezonePicker() {
  gmInjectTimezonePicker();
  document.getElementById('gmTzModal').classList.remove('hidden');
  document.getElementById('gmTzModal').classList.add('flex');
}

function gmCloseTimezonePicker() {
  const el = document.getElementById('gmTzModal');
  if (el) { el.classList.add('hidden'); el.classList.remove('flex'); }
}

// Arabic count + noun: 2 -> dual ("زبونان"), 3-10 -> plural ("5 زبائن"), otherwise singular ("1 زبون", "12 زبون").
// forms = [singular, dual, plural]
function gmCountLabel(n, forms) {
  if (n === 2) return forms[1];
  const m = n % 100;
  return n + ' ' + (m >= 3 && m <= 10 ? forms[2] : forms[0]);
}
// Random file-name part for uploads, so public file links can't be guessed (16 hex chars).
function gmRandName() {
  const a = new Uint8Array(8); crypto.getRandomValues(a);
  return Array.from(a, b => b.toString(16).padStart(2, '0')).join('');
}


// (customer/company/trader/staff names, notes, search results, etc.)
// and gets injected into the page via innerHTML/template strings must
// be passed through this first, or a maliciously-named record could
// inject and execute arbitrary script in any visitor's browser
// (stored XSS). Safe for null/undefined (returns empty string).
function gmEscapeHtml(value) {
  if (value === null || value === undefined) return '';
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// Formats a plain number with Latin digits, thousands separators, and up
// to 2 decimal places (trailing zeros trimmed). Never Arabic-Indic digits,
// per the app-wide numeral convention.
function gmFormatNumber(value) {
  const num = Number(value);
  if (!isFinite(num)) return '0';
  return num.toLocaleString('en-US', { maximumFractionDigits: 2 });
}

// Formats a money amount in the store's base currency, with the
// store's optional secondary currency shown alongside it in parentheses
// (display-only live conversion — nothing is stored in the secondary
// currency). `store` is the loaded stores row (needs .currency,
// .secondary_currency, .secondary_currency_rate). `amount` is always
// assumed to already be in the store's base currency.
// Falls back gracefully to a single-currency string when no secondary
// currency/rate is configured, or when store is missing.
// An amount is shown only in the currency it was taken in — no converted
// figure next to it (the owner asked for that). The second currency and its
// exchange rate stay saved in company settings for when a conversion is needed.
// Daily cashbox: an invoice edited or re-posted the same day leaves several
// mirrored rows (first posting, reversal, new posting). Show one row per
// invoice per day with the net amount — its final effect; rows that cancel out
// disappear. Totals are unchanged. Rows need e.cm.invoice_id.
function gmCollapseInvoiceRows(entries) {
  const groups = new Map(), out = [];
  for (const e of entries) {
    const inv = e.cm && e.cm.invoice_id;
    if (!inv) { out.push(e); continue; }
    const key = inv + '|' + e.currency + '|' + gmFormatDateTime(e.created_at, { day: '2-digit', month: '2-digit', year: 'numeric' });
    if (!groups.has(key)) { groups.set(key, []); out.push(key); }
    groups.get(key).push(e);
  }
  return gmMergeSaleDebt(out.flatMap(x => {
    if (typeof x !== 'string') return [x];
    const rows = groups.get(x);
    if (rows.length === 1) return rows;
    const net = rows.reduce((s, e) => s + (e.direction === 'in' ? 1 : -1) * Number(e.amount || 0), 0);
    if (Math.abs(net) < 0.005) return [];
    const last = rows[rows.length - 1];
    // label it after the real sale, never after a cancel/restore row
    const undo = /^(إلغاء|استعادة) فاتورة\s*/;
    const base = rows.find(r => !undo.test(r.notes || r.description || '')) || { ...rows[0], notes: rows[0].notes && rows[0].notes.replace(undo, ''), description: rows[0].description && rows[0].description.replace(undo, 'فاتورة ') };
    return [{ ...base, id: last.id, created_at: last.created_at, direction: net > 0 ? 'in' : 'out', amount: Math.round(Math.abs(net) * 100) / 100, merged: rows.length }];
  }));
}
// A sale left partly on debt (بشار 2026-11-16): no "+X بالدين / −X دين على" pair. The sale row
// shows the whole invoice (paid + debt) and is linked to one «باقي على الزبون» row with the debt.
// Display only — the saved rows stay, totals are unchanged. Merged only when paid + debt equals
// the invoice total (an invoice edited later keeps its rows apart). Rows need e.cm.inv for that.
function gmMergeSaleDebt(rows) {
  const day = e => gmFormatDateTime(e.created_at, { day: '2-digit', month: '2-digit', year: 'numeric' });
  const debtIn = rows.filter(e => e.direction === 'in' && /^debt_/.test(e.link_group || '') && / — بالدين$/.test(e.notes || ''));
  if (!debtIn.length) return rows;
  const drop = new Set(), patch = new Map();
  for (const d of debtIn) {
    const num = d.notes.replace(/ — بالدين$/, '').trim();
    const sale = rows.find(e => e !== d && e.direction === 'in' && e.cm && e.cm.inv && e.currency === d.currency && !e.link_group
      && day(e) === day(d) && (e.notes || '').includes(num) && !patch.has(e.id));
    if (!sale) continue;
    const inv = sale.cm.inv, fx = inv.pay_currency && Number(inv.pay_fx_rate) > 0 ? Number(inv.pay_fx_rate) : 1;
    const full = Number(sale.amount) + Number(d.amount);
    if (Math.abs(full - Number(inv.total_amount) * fx) > 0.05) continue;
    drop.add(d.id);
    patch.set(sale.id, { amount: Math.round(full * 100) / 100, link_group: d.link_group });
  }
  return rows.filter(e => !drop.has(e.id)).map(e => patch.has(e.id) ? { ...e, ...patch.get(e.id) }
    : e.direction === 'out' && /^debt_/.test(e.link_group || '') && /^دين على /.test(e.operation_type || '')
      ? { ...e, operation_type: e.operation_type.replace(/^دين على /, 'باقي على ') } : e);
}
// ponytail: quick self-check — 12,500 paid + 100 debt on a 12,600 invoice → one 12,600 row + «باقي على» 100
console.assert((() => { const t = '2026-11-15T16:58:31Z', r = gmMergeSaleDebt([
  { id: 'p', direction: 'in', amount: 12500, currency: 'USD', created_at: t, notes: 'تحصيل جزئي INV-1 (12500 نقداً)', cm: { invoice_id: 'a', inv: { total_amount: 12600 } } },
  { id: 'd', direction: 'in', amount: 100, currency: 'USD', created_at: t, notes: 'INV-1 — بالدين', link_group: 'debt_a' },
  { id: 'o', direction: 'out', amount: 100, currency: 'USD', created_at: t, notes: 'INV-1', operation_type: 'دين على سعيد', link_group: 'debt_a' }]);
  return r.map(e => e.direction + e.amount + (e.link_group || '')).join() === 'in12600debt_a,out100debt_a' && r[1].operation_type === 'باقي على سعيد'; })(), 'gmMergeSaleDebt');
// Same rule for cash_movements lists (home "حركات اليوم", main box), which come newest-first.
function gmCollapseMovements(list) {
  const asc = (list || []).map(m => ({ ...m, cm: { invoice_id: m.invoice_id } })).reverse();
  return gmCollapseInvoiceRows(asc).reverse();
}
// ponytail: quick self-check of the netting rule
console.assert(gmCollapseInvoiceRows([{ id: 1, cm: { invoice_id: 'a' }, currency: 'USD', created_at: '2026-10-01T10:00:00Z', direction: 'out', amount: 1500 },
  { id: 2, cm: { invoice_id: 'a' }, currency: 'USD', created_at: '2026-10-01T10:05:00Z', direction: 'in', amount: 1500 },
  { id: 3, cm: { invoice_id: 'a' }, currency: 'USD', created_at: '2026-10-01T10:05:00Z', direction: 'out', amount: 1700 }]).map(e => e.direction + e.amount).join() === 'out1700', 'gmCollapseInvoiceRows');
console.assert(gmCollapseMovements([{ id: 3, invoice_id: 'b', currency: 'USD', created_at: '2026-10-01T11:00:00Z', direction: 'in', amount: 6370, description: 'استعادة فاتورة X' },
  { id: 2, invoice_id: 'b', currency: 'USD', created_at: '2026-10-01T10:30:00Z', direction: 'out', amount: 6100, description: 'إلغاء فاتورة X' }])
  .map(e => e.direction + e.amount + e.description).join() === 'in270فاتورة X', 'gmCollapseMovements');

// Daily cash box rows posted automatically (sales, purchases, deposits, repairs, returns, transfers):
// document numbers (INV-2026-000055, PINV-…, DEP-000003, REP-…, RET-…) are not written — the row opens
// its document. A note that then only repeats the row's own title is dropped too.
// Used by the box, its search and its printed statement; notes typed by hand are left as they are.
function gmCashNote(e) {
  const n = e.notes || '';
  if (!(e.bank_invoice_id || e.cash_movement_id || (e.cm && e.cm.invoice_id))) return n;
  let t = n.replace(/\s*(?:لل|ل)?(?:(?:فاتورة|سند|تذكرة|رقم)\s*)?\b[A-Z]{2,6}-(?:\d{4}-)?\d+\b/g, ' ')
    .replace(/\s{2,}/g, ' ').replace(/^[\s—–-]+|[\s—–-]+$/g, '').trim();
  const op = (e.operation_type || '').trim();
  if (op && t.startsWith(op)) t = t.slice(op.length).replace(/^[\s—–:-]+/, '').trim();
  return t;
}
console.assert(gmCashNote({ notes: 'INV-2026-000055', cm: { invoice_id: 'x' } }) === '' && gmCashNote({ notes: 'PINV-2026-000022', bank_invoice_id: 'y' }) === ''
  && gmCashNote({ notes: 'تعديل عملات الدفع — المبلغ الجديد للفاتورة INV-2026-000043', bank_invoice_id: 'y' }) === 'تعديل عملات الدفع — المبلغ الجديد'
  && gmCashNote({ operation_type: 'عربون', notes: 'عربون DEP-000003 — راما مملوك', cash_movement_id: 'c' }) === 'راما مملوك'
  && gmCashNote({ notes: 'صيانة REP-2026-000004', cash_movement_id: 'c' }) === 'صيانة'
  && gmCashNote({ notes: 'INV-2026-000055' }) === 'INV-2026-000055', 'gmCashNote');

function gmFormatDualCurrency(amount, store) {
  const base = (store && store.currency) || '';
  return gmFormatNumber(amount) + (base ? ' ' + base : '');
}

const GOLDMIND_THEMES = {
  'warm-ingot': {
    label: 'المسبوكة',
    swatch: ['#9C8552', '#F3EEDF', '#EFE7D2'],
    lightCanvas: true,
    vars: {
      '--gm-bg': '#F3EEDF',
      '--gm-bg-elevated': '#F3EEDF',
      '--gm-surface-lowest': '#FFFFFF',
      '--gm-surface-low': '#EFE7D2',
      '--gm-primary': '#1C1A16',
      '--gm-on-primary': '#FBF8F1',
      '--gm-accent': '#9C8552',
      '--gm-on-accent': '#ffffff',
      '--gm-secondary': '#7A6640',
      '--gm-on-surface': '#211D17',
      '--gm-on-surface-variant': '#6B6355',
      '--gm-outline-variant': '#CBBF9E',
      '--gm-avatar-grad': 'linear-gradient(135deg, #7A6640 0%, #9C8552 100%)'
    }
  },
  'velvet-wine': {
    // Deep wine ("دم الغزال") is now the big canvas colour, like a dark theme,
    // with white cards on it and warm gold as the accent (the daily-cashbox
    // tile turns gold so it stands out on the wine background).
    label: 'الخمري',
    swatch: ['#6A1626', '#C9A24D', '#F6EDEA'],
    lightCanvas: false,
    shimmer: true,
    vars: {
      '--gm-bg': '#6A1626',
      '--gm-bg-elevated': '#6A1626',
      '--gm-surface-lowest': '#FFFFFF',
      '--gm-surface-low': '#F4E6E6',
      '--gm-primary': '#6A1626',
      '--gm-on-primary': '#FFFFFF',
      '--gm-accent': '#C9A24D',
      '--gm-on-accent': '#2A1A08',
      '--gm-secondary': '#8A6A2E',
      '--gm-on-surface': '#2A1418',
      '--gm-on-surface-variant': '#7A5F63',
      '--gm-outline-variant': '#DCC3C7',
      '--gm-shadow-color': 'rgba(40, 6, 12, 0.5)',
      '--gm-shimmer-grad': 'linear-gradient(120deg, #4A0E19 0%, #6A1626 26%, #C9A24D 48%, #E8D3A0 54%, #C9A24D 60%, #6A1626 80%, #4A0E19 100%)',
      '--gm-avatar-grad': 'linear-gradient(135deg, #8A6A2E 0%, #C9A24D 55%, #6A1626 100%)'
    }
  },
  'cosmic-steel': {
    // Deep calm navy base with crisp silver-metallic lines and a single
    // warm terracotta-orange accent (evoking Claude's own star mark) --
    // a "space-tech" feel: dark, precise, and cool, with one warm point
    // of light rather than an all-over glow.
    label: 'الفولاذي',
    swatch: ['#DA7756', '#1B2C46', '#8B94A3'],
    lightCanvas: false,
    shimmer: true,
    vars: {
      '--gm-bg': '#1B2C46',
      '--gm-bg-elevated': '#1B2C46',
      '--gm-surface-lowest': '#FFFFFF',
      '--gm-surface-low': '#E7EAF0',
      '--gm-primary': '#1B2C46',
      '--gm-on-primary': '#FFFFFF',
      '--gm-accent': '#DA7756',
      '--gm-on-accent': '#FFFFFF',
      '--gm-secondary': '#7A8494',
      '--gm-on-surface': '#1B2C46',
      '--gm-on-surface-variant': '#7A8494',
      '--gm-outline-variant': '#AEB9C8',
      '--gm-shadow-color': 'rgba(6, 12, 24, 0.55)',
      '--gm-shimmer-grad': 'linear-gradient(120deg, #1B2C46 0%, #7A8494 26%, #D8DEE7 45%, #DA7756 54%, #D8DEE7 63%, #7A8494 80%, #1B2C46 100%)',
      '--gm-avatar-grad': 'linear-gradient(135deg, #DA7756 0%, #8B94A3 55%, #1B2C46 100%)'
    }
  },
  'black-marble': {
    // «الرخام الأسود» (بشار 2026-11-16): black marble with gold veins (theme-black-marble.jpg),
    // charcoal cards framed in a thin gold line, gold for titles and what matters — like his mockups.
    label: 'الرخام الأسود',
    swatch: ['#0B0B0D', '#D4AF37', '#1C1C21'],
    lightCanvas: false,
    shimmer: true,
    vars: {
      '--gm-bg': '#0B0B0D',
      '--gm-bg-elevated': '#0B0B0D',
      '--gm-surface-lowest': '#17171B',
      '--gm-surface-low': '#202025',
      '--gm-primary': '#1C1913',
      '--gm-on-primary': '#F2DE9E',
      '--gm-accent': '#D4AF37',
      '--gm-on-accent': '#16120A',
      '--gm-secondary': '#B8954A',
      '--gm-on-surface': '#EEE7D6',
      '--gm-on-surface-variant': '#ABA08A',
      '--gm-outline-variant': '#4B4232',
      '--gm-shadow-color': 'rgba(0, 0, 0, 0.7)',
      '--gm-shimmer-grad': 'linear-gradient(120deg, #0B0B0D 0%, #8A6A22 30%, #D4AF37 46%, #FBE7A1 52%, #D4AF37 58%, #8A6A22 75%, #0B0B0D 100%)',
      '--gm-avatar-grad': 'linear-gradient(135deg, #8A6A22 0%, #D4AF37 55%, #1C1913 100%)',
      // brighter glossy inks for dark cards
      '--gmi-g1': '#2FB487', '--gmi-g2': '#4CD3A2', '--gmi-g3': '#9BF0CF',
      '--gmi-r1': '#E0566A', '--gmi-r2': '#F27A8A', '--gmi-r3': '#FFB3BD',
      '--gmi-b1': '#5B8DEF', '--gmi-b2': '#7FA7F5', '--gmi-b3': '#BCD2FB',
      '--gmi-a1': '#C9962B', '--gmi-a2': '#E2B84E', '--gmi-a3': '#F7DE9A',
      '--gmi-v1': '#A57BF0', '--gmi-v2': '#BC9AF5', '--gmi-v3': '#DCCBFB',
      '--gmi-i1': '#B8902F', '--gmi-i2': '#E2C46A', '--gmi-i3': '#FBEBB4',
      // names some pages use with a cream fallback (cash-box filters and totals, phone action bar)
      '--gm-surface-container-low': '#1C1C21',
      '--gm-background': '#0B0B0D',
      '--gm-on-background': '#EEE7D6',
      '--gm-outline': '#8C826E'
    }
  },
  'glass-dark': {
    // «الزجاجي الغامق» (بشار 2026-11-21): deep night canvas with soft gold/emerald glows, frosted see-through cards,
    // thin light edges. Built on the black-marble dark rules (base), with its own surface layer on top.
    label: 'الزجاجي الغامق',
    swatch: ['#070A12', '#D4AF37', '#2FB487'],
    lightCanvas: false,
    shimmer: true,
    base: 'black-marble',
    vars: null // filled from black-marble below
  },
  'beige-marble': {
    // «الرخام البيج» (بشار 2026-11-16): warm beige marble with taupe and gold veins (theme-beige-marble.jpg),
    // cream cards in a thin gold frame (darker sand canvas since 2026-11-16 so it is clearly apart from the default), espresso words, gold accents. A light theme like the default.
    label: 'الرخام البيج',
    swatch: ['#CDB693', '#B8954A', '#2A2116'],
    lightCanvas: true,
    vars: {
      '--gm-bg': '#CDB693',
      '--gm-bg-elevated': '#CDB693',
      '--gm-surface-lowest': '#FAF3E4',
      '--gm-surface-low': '#F0E4CC',
      '--gm-primary': '#2A2116',
      '--gm-on-primary': '#F8F1E3',
      '--gm-accent': '#B8954A',
      '--gm-on-accent': '#FFFFFF',
      '--gm-secondary': '#8A6A2E',
      '--gm-on-surface': '#2A2116',
      '--gm-on-surface-variant': '#4E4232',
      // lines and frames must show on the sand marble too (#CBB58A vanished into it — بشار 2026-11-17)
      '--gm-outline-variant': '#A88B55',
      '--gm-shadow-color': 'rgba(90, 66, 26, 0.18)',
      '--gm-avatar-grad': 'linear-gradient(135deg, #8A6A2E 0%, #B8954A 55%, #E2C88A 100%)'
    }
  },
};
GOLDMIND_THEMES['glass-dark'].vars = Object.assign({}, GOLDMIND_THEMES['black-marble'].vars, {
  '--gm-bg': '#070A12', '--gm-bg-elevated': '#070A12', '--gm-background': '#070A12',
  // opaque on purpose: sticky bars and sheets that use these vars must not show the page through them;
  // the see-through look comes from the glass rules on cards
  '--gm-surface-lowest': '#0E1322', '--gm-surface-low': '#151B2C', '--gm-surface-container-low': '#151B2C',
  '--gm-outline-variant': '#2A3248', '--gm-primary': '#141A2B'
});

// «الرخام الأسود»: black marble canvas, charcoal cards with a thin gold frame, gold titles, dark fields.
// Pages were written for light cards, so the usual light utility classes are mapped to their dark twins here.
(function () {
  var T = 'html[data-gm-theme="black-marble"]';
  var CARD = 'linear-gradient(160deg,#1E1E23 0%,#15151A 100%)';
  var BAR = 'linear-gradient(180deg,#141418 0%,#0E0E11 100%)';
  var FRAME = 'rgba(212,175,55,.30)';
  var GOLD = '#E2C46A', INK = '#EEE7D6', MUTED = '#ABA08A';
  var TT = T + '[data-gm-theme]:not(.gm-x)'; // outranks the glossy layer (html.gm-gloss:not(.gm-plain) …)
  var css = [
    '@media screen{',
    T + ' body{background-color:#0B0B0D!important;background-image:url("theme-black-marble.jpg")!important;background-size:900px 900px!important;background-repeat:repeat!important;color:' + INK + '}',
    T + ' .dsk-app{--dsk-bg:transparent!important}',
    T + ' .dsk-toolbar-label{color:' + GOLD + '}',
    // gold is the "primary" colour for words, icons and lines; solid primary buttons stay dark bronze with gold words
    T + ' .text-primary{color:' + GOLD + '!important}',
    T + ' :is(.border-primary,.border-primary\\/30,.border-primary\\/40){border-color:rgba(212,175,55,.55)!important}',
    T + ' .bg-primary:not(.rounded-lg.p-4):not(.rounded-xl.p-4):not(.gm-cta){background-image:linear-gradient(160deg,#2A2416,#1A1710)!important;border:1px solid rgba(212,175,55,.55)}',
    T + ' .gm-cta{background-image:linear-gradient(135deg,#F3D57A 0%,#D4AF37 50%,#B08A2E 100%)!important;color:#16120A!important;border:0}',
    // top bars and side menu: near-black with a gold rule
    T + ' header:is(.bg-surface-container-lowest,.bg-surface,.bg-background,.bg-white){background:' + BAR + '!important;border-bottom:1px solid rgba(212,175,55,.45)!important}',
    T + ' #gmNav{background:' + BAR + '!important;border-left:1px solid rgba(212,175,55,.45)}',
    T + ' #gmNav.gn-light{background:' + BAR + '!important;-webkit-backdrop-filter:none!important;backdrop-filter:none!important}',
    // cards / boxes: charcoal with a thin gold frame
    T + ' :is(.bg-surface-container-lowest,.bg-white):not(input):not(select):not(textarea){background-color:#17171B!important}',
    T + ' :is(.rounded-lg,.rounded-xl,.rounded-2xl,.rounded-3xl):is(.bg-surface-container-lowest,.bg-white):not(input):not(select):not(textarea):not(button)' +
      '{background-image:' + CARD + '!important;border:1px solid ' + FRAME + '!important;box-shadow:0 12px 28px -16px rgba(0,0,0,.9),inset 0 1px 0 rgba(255,255,255,.04)!important}',
    T + ' button:is(.rounded-lg,.rounded-xl,.rounded-2xl,.rounded-3xl):is(.bg-surface-container-lowest,.bg-white){background-image:' + CARD + '!important;border:1px solid ' + FRAME + '!important}',
    T + ' :is(.bg-surface-container-low,.bg-gray-50,.bg-gray-100,.bg-slate-50,.bg-stone-50,.bg-neutral-50){background-color:#202025!important}',
    T + ' :is(.bg-gray-200,.bg-slate-100,.bg-stone-100){background-color:#2A2A31!important}',
    T + ' :is(.hover\\:bg-gray-50,.hover\\:bg-gray-100,.hover\\:bg-surface-container-low):hover{background-color:#26262C!important}',
    T + ' :is(.gmt-pill,.gmt-panel){background-color:#1C1C21!important;border:1px solid ' + FRAME + '}',
    T + ' :is(div,section,form,fieldset).border:is(.rounded-lg,.rounded-xl,.rounded-2xl):not([class*="bg-"]):not(.border-dashed){background-color:rgba(23,23,27,.94);border-color:' + FRAME + '!important}',
    T + ' .border-dashed:not([class*="bg-"]){background-color:rgba(23,23,27,.9)}',
    // words written for white cards
    T + ' :is(.text-black,.text-gray-900,.text-gray-800,.text-gray-700,.text-slate-900,.text-slate-800,.text-slate-700,.text-stone-800,.text-neutral-800,.text-on-surface){color:' + INK + '!important}',
    T + ' :is(.text-gray-600,.text-gray-500,.text-slate-600,.text-slate-500,.text-stone-500,.text-on-surface-variant){color:' + MUTED + '!important}',
    T + ' :is(.text-gray-400,.text-slate-400,.text-outline){color:#8C826E!important}',
    T + ' :is(.border-gray-100,.border-gray-200,.border-gray-300,.border-slate-200,.border-outline-variant,.divide-gray-100>*,.divide-gray-200>*,.divide-outline-variant>*){border-color:#3A3428!important}',
    // tables
    T + ' :is(thead,th){background-color:#1C1913!important;color:' + GOLD + '!important}',
    T + ' tbody tr:nth-child(even){background-color:rgba(255,255,255,.02)}',
    // fields: dark with a bronze line, light words
    T + ' :is(input,select,textarea):not([type=checkbox]):not([type=radio]):not([type=range]):not([type=color]){background-color:#111114!important;color:' + INK + '!important;border-color:#4B4232!important}',
    T + ' :is(input,textarea)::placeholder{color:#7D7462!important;opacity:1}',
    T + ' :is(input,select,textarea):focus{border-color:#D4AF37!important;box-shadow:0 0 0 1px #D4AF37!important}',
    T + ' select option{background:#17171B;color:' + INK + '}',
    // checkboxes keep بشار's rule: empty = frame only, ticked = solid box (gold here, the light-on-dark equivalent of black)
    T + ' input[type=checkbox]{background-color:transparent!important;border-color:' + GOLD + '!important}',
    T + ' input[type=checkbox]:checked{background-color:' + GOLD + '!important;background-image:none!important}',
    // modals / sheets and their backdrops
    T + ' :is(.bg-white\\/95,.bg-white\\/90,.bg-white\\/80){background-color:rgba(23,23,27,.95)!important}',
    '}',
    // the home page's own boxes (tiles, KPI cards, calculator / currency blocks, online-staff chip)
    T + ' :is(.gm-mcard,.gm-card,.quick-action-icon,.gm-qg,.dsk-action,#gmOnlineBtn,#gmOnlineBtnDsk,.gmc-seg,.gmc-gold-host,.gmc-block){background:' + CARD + '!important;border:1px solid ' + FRAME + '!important;color:' + INK + '}',
    T + ' nav.gm-bottom-tabs{background:' + BAR + '!important;border-top:1px solid rgba(212,175,55,.45)!important}',
    T + ' #gmNav .gn-a{color:#D9CBA6}',
    // the side menu's light mode keeps its own word colours — on the marble they must be light too
    T + ' #gmNav.gn-light{color:#E6DABA!important;border:0!important}',
    T + ' #gmNav.gn-light :is(.gn-h,a.gn-a){color:#E6DABA!important}',
    T + ' #gmNav.gn-light :is(.gn-h .gn-ic,a.gn-a .material-symbols-outlined){color:#D4AF37!important}',
    T + ' #gmNav.gn-light .gn-head b{color:' + GOLD + '!important}',
    T + ' #gmNav.gn-light :is(.gn-x,.gn-mini){background:rgba(255,255,255,.08)!important;color:#E6DABA!important}',
    T + ' #gmNav.gn-light .gn-h .gn-chev{color:#ABA08A!important}',
    T + ' #gmNav.gn-light :is(.gn-head,.gn-foot){border-color:rgba(212,175,55,.25)!important}',
    T + ' #gmNav .gn-a.here{background:rgba(212,175,55,.14)!important;color:' + GOLD + '!important;border:1px solid rgba(212,175,55,.4)}',
    T + ' #gmNav a.gn-a.here .material-symbols-outlined{color:' + GOLD + '!important}',
    T + ' .gmt-pill :is(b,strong){color:' + INK + '!important}',
    T + ' .gmt-pill :is(small,.gmt-sub){color:' + MUTED + '!important}',
    // words on gold chips/buttons stay dark
    T + ' :is(.bg-accent,.bg-secondary,.gold-gradient) :is(.text-primary,.material-symbols-outlined:not([class*="text-"])),' + T + ' :is(.bg-accent,.bg-secondary).text-primary{color:#16120A!important}',
    // status colours written for white cards → their light twins
    T + ' :is(.text-green-600,.text-green-700,.text-green-800,.text-emerald-600,.text-emerald-700,.text-emerald-800,.text-success){color:#4CD3A2!important}',
    T + ' :is(.text-red-600,.text-red-700,.text-red-800,.text-rose-700,.text-error){color:#F27A8A!important}',
    T + ' :is(.text-amber-600,.text-amber-700,.text-amber-800,.text-yellow-700,.text-yellow-800,.text-orange-700){color:#E2B84E!important}',
    T + ' :is(.text-blue-600,.text-blue-700,.text-blue-800,.text-sky-700,.text-indigo-700){color:#7FA7F5!important}',
    // light status chips → dark tinted chips (their words above are now light)
    T + ' :is(.bg-green-50,.bg-green-100,.bg-emerald-50,.bg-emerald-100){background-color:rgba(76,211,162,.14)!important}',
    T + ' :is(.bg-red-50,.bg-red-100,.bg-rose-50,.bg-error-container){background-color:rgba(242,122,138,.14)!important}',
    T + ' :is(.bg-amber-50,.bg-amber-100,.bg-yellow-50,.bg-yellow-100,.bg-orange-50){background-color:rgba(226,184,78,.14)!important}',
    T + ' :is(.bg-blue-50,.bg-blue-100,.bg-sky-50,.bg-indigo-50){background-color:rgba(127,167,245,.14)!important}',
    // the glossy layer paints these chips with light gradients — the marble wants dark tints
    TT + ' :is(.bg-green-50,.bg-emerald-50,.bg-green-100,.bg-success-container,.bg-red-50,.bg-red-100,.bg-error-container,.bg-amber-50,.bg-yellow-50,.bg-amber-100,.bg-amber-200,.bg-blue-50,.bg-sky-50,.bg-secondary-container,.dc-tag.ok,.dc-tag.warn){background-image:none!important;box-shadow:none!important}',
    T + ' :is(.bg-success-container,.dc-tag.ok){background-color:rgba(76,211,162,.14)!important}',
    T + ' :is(.bg-amber-200,.dc-tag.warn){background-color:rgba(226,184,78,.16)!important}',
    T + ' .bg-secondary-container{background-color:rgba(212,175,55,.14)!important}',
    T + ' :is(.border-green-200,.border-red-200,.border-amber-200,.border-blue-200,.border-emerald-200){border-color:rgba(212,175,55,.25)!important}',
    // phone bottom tabs, home KPI numbers, computer KPI colours, the range page's gold-glass day headers
    T + ' nav.gm-bottom-tabs .gm-tab{color:#BDB29A}',
    T + ' nav.gm-bottom-tabs .gm-tab.gm-tab-on{color:' + GOLD + '!important}',
    T + ' .gm-mcard .gm-metric-value{color:' + INK + '!important}',
    T + ' #dskTodaySalesEl{color:#4CD3A2!important}',
    T + ' #dskDebtTotalEl{color:#F27A8A!important}',
    T + ' .gold-glass{background:' + CARD + '!important;box-shadow:none!important;border:1px solid ' + FRAME + '}',
    T + ' button.bg-surface-container-lowest{color:' + INK + '!important}',
    T + ' button.bg-surface-container-lowest .material-symbols-outlined:not([class*="text-"]){color:' + GOLD + '!important}',
    T + ' td[style*="#1B5E20"]{color:#4CD3A2!important}',
    T + ' td[style*="#8A1D17"]{color:#F27A8A!important}',
    T + ' .dsk-age.old{background:rgba(242,122,138,.14)!important;color:#F27A8A!important}',
    T + ' :is(.text-amber-900,.text-yellow-900,.text-orange-800){color:#E2B84E!important}',
    T + ' :is(.text-green-900,.text-emerald-900){color:#4CD3A2!important}',
    T + ' :is(.text-red-900,.text-rose-900){color:#F27A8A!important}',
    T + ' .glass{background:' + CARD + '!important;border:1px solid ' + FRAME + '!important}',
    T + ' #gmNav a.gn-a.here .gn-badge:not(.red):not(.amber):not(.dot){color:' + GOLD + '!important;background:rgba(212,175,55,.15)!important}',
    TT + ' .gm-cta{background-image:linear-gradient(135deg,#F3D57A 0%,#D4AF37 50%,#B08A2E 100%)!important;color:#16120A!important}',
    // page-specific boxes written as white cards (trader account, cash box, sale, customers, stock)
    T + ' :is(.ld-op,.gm-row,.gm-hbtn,.cu-tile,.cu-act,.summary-card,.type-pill,.cf-tabs,.gm-dist,.gm-inv-q,.ns-x,.ns-pb-btn,#ns-pay,.gm-gicon){background:' + CARD + '!important;border-color:' + FRAME + '!important;color:' + INK + '!important}',
    T + ' .dc-seg button[aria-pressed="true"]{background:rgba(212,175,55,.18)!important;color:' + GOLD + '!important}',
    T + ' .gm-status button{background:' + CARD + '!important;border-color:' + FRAME + '!important;color:' + INK + '!important}',
    T + ' .gm-status button[aria-pressed="true"]{background:rgba(212,175,55,.18)!important;color:' + GOLD + '!important;border-color:rgba(212,175,55,.6)!important}',
    T + ' .cf-tabs button.on,' + T + ' :is(.st-seg,.cf-tabs) button[aria-pressed="true"]{background:rgba(212,175,55,.18)!important;color:' + GOLD + '!important}',
    T + ' :is(table.ld-st,table.ld-t) :is(td,tr){background-color:transparent!important}',
    T + ' :is(table.ld-st,table.ld-t){background:rgba(20,20,24,.92)!important;border-color:' + FRAME + '!important}',
    T + ' :is(table.ld-st,table.ld-t) td{border-color:#2E2A22!important}',
    // printing always stays white paper
    '@media print{' + T + ' body{background:#fff!important;color:#000!important}}'
  ].join('\n');
  var st = document.createElement('style');
  st.id = 'gm-theme-marble';
  st.textContent = css;
  (document.head || document.documentElement).appendChild(st);
})();

// «الزجاجي الغامق»: the black-marble dark rules stay underneath (data-gm-theme="black-marble"); this layer swaps the
// marble for a night canvas with soft glows and turns the cards into frosted glass with thin light edges.
(function () {
  var G = 'html[data-gm-theme="black-marble"][data-gm-variant="glass-dark"]';
  var GLASS = 'rgba(255,255,255,.055)', EDGE = 'rgba(255,255,255,.11)', GOLDEDGE = 'rgba(212,175,55,.38)';
  var BLUR = '-webkit-backdrop-filter:blur(16px) saturate(140%);backdrop-filter:blur(16px) saturate(140%);';
  var CARDS = ':is(.rounded-lg,.rounded-xl,.rounded-2xl,.rounded-3xl):is(.bg-surface-container-lowest,.bg-white):not(input):not(select):not(textarea)';
  var BIG = ':is(.gm-mcard,.gm-card,.gm-hero,.dsk-stat,.gm-wk-card,.dsk-action,.gmc-block,.gold-glass,.glass,.summary-card,.cu-tile,.ld-op,.gm-piece)';
  var css = [
    '@media screen{',
    G + ' body{background-color:#070A12!important;background-image:radial-gradient(1100px 650px at 88% -8%,rgba(212,175,55,.20),transparent 62%),radial-gradient(900px 620px at -5% 105%,rgba(47,180,135,.16),transparent 60%),radial-gradient(700px 480px at 50% 45%,rgba(91,141,239,.08),transparent 70%),linear-gradient(165deg,#070A12 0%,#0B1020 48%,#05060A 100%)!important;background-size:auto!important;background-attachment:fixed!important;background-repeat:no-repeat!important}',
    G + ' #gmGlassBg{display:none!important}',
    // frosted cards: see-through, blurred, a thin light edge and a soft top highlight
    G + ' ' + CARDS + ',' + G + ' ' + BIG + '{background:' + GLASS + '!important;background-image:linear-gradient(160deg,rgba(255,255,255,.07),rgba(255,255,255,.02))!important;border:1px solid ' + EDGE + '!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.10),0 18px 40px -22px rgba(0,0,0,.85)!important;' + BLUR + '}',
    G + ' ' + BIG + ':hover{border-color:' + GOLDEDGE + '!important}',
    G + ' :is(.bg-surface-container-low,.bg-gray-50,.bg-gray-100,.bg-slate-50,.bg-stone-50,.bg-neutral-50){background-color:rgba(255,255,255,.06)!important}',
    G + ' :is(.bg-gray-200,.bg-slate-100,.bg-stone-100){background-color:rgba(255,255,255,.10)!important}',
    G + ' :is(div,section,form,fieldset).border:is(.rounded-lg,.rounded-xl,.rounded-2xl):not([class*="bg-"]):not(.border-dashed){background-color:rgba(255,255,255,.04);border-color:' + EDGE + '!important}',
    // top bars, side menu, phone tabs: dark glass
    G + ' header:is(.bg-surface-container-lowest,.bg-surface,.bg-background,.bg-white),' + G + ' #gmNav,' + G + ' nav.gm-bottom-tabs{background:rgba(7,10,18,.72)!important;' + BLUR + 'border-color:' + EDGE + '!important}',
    G + ' #gmNav.gn-light{background:rgba(7,10,18,.72)!important}',
    G + ' #gmNav .gn-a.here{background:rgba(212,175,55,.12)!important;border-color:' + GOLDEDGE + '}',
    // lines, tables, fields
    G + ' :is(.border-gray-100,.border-gray-200,.border-gray-300,.border-slate-200,.border-outline-variant,.divide-gray-100>*,.divide-gray-200>*,.divide-outline-variant>*){border-color:rgba(255,255,255,.10)!important}',
    G + ' :is(thead,th){background-color:rgba(255,255,255,.05)!important}',
    G + ' :is(table.ld-st,table.ld-t){background:rgba(255,255,255,.04)!important;border-color:' + EDGE + '!important;' + BLUR + '}',
    G + ' :is(table.ld-st,table.ld-t) td{border-color:rgba(255,255,255,.07)!important}',
    G + ' :is(input,select,textarea):not([type=checkbox]):not([type=radio]):not([type=range]):not([type=color]){background-color:rgba(255,255,255,.05)!important;border-color:rgba(255,255,255,.16)!important}',
    G + ' select option{background:#0E1220}',
    G + ' :is(.bg-white\\/95,.bg-white\\/90,.bg-white\\/80){background-color:rgba(12,15,26,.88)!important;' + BLUR + '}',
    G + ' .gm-piece{color:#EEE7D6!important}',
    // day cash box: linked entries keep their colour only as the edge line — no pastel blocks on the night canvas
    G + ' #cashbox-table tbody tr.dc-linked{background:rgba(255,255,255,.06)!important;color:#EEE7D6!important}',
    G + ' #cashbox-table tbody tr.dc-linked .dc-amt-in{color:#5FD68A!important;-webkit-text-fill-color:#5FD68A!important}',
    G + ' #cashbox-table tbody tr.dc-linked .dc-amt-out{color:#FF8A7A!important;-webkit-text-fill-color:#FF8A7A!important}',
    // statements / day sheets: glass sheet instead of charcoal
    G + ' .stmt-sheet:not(.gm-pdf){background:rgba(255,255,255,.05)!important;border-color:' + EDGE + '!important}',
    '}',
    '@media (prefers-reduced-transparency: reduce){' + G + ' *{-webkit-backdrop-filter:none!important;backdrop-filter:none!important}}',
    '@media print{' + G + ' body{background:#fff!important}}'
  ].join('\n');
  var st = document.createElement('style');
  st.id = 'gm-theme-glass-dark';
  st.textContent = css;
  (document.head || document.documentElement).appendChild(st);
})();

// «الرخام البيج»: beige marble canvas, white cards framed in a thin gold line, soft cream bars with a gold rule.
(function () {
  var T = 'html[data-gm-theme="beige-marble"]';
  var FRAME = 'rgba(184,149,74,.38)';
  var BAR = 'linear-gradient(180deg,rgba(248,239,220,.96) 0%,rgba(238,226,202,.96) 100%)';
  var css = [
    '@media screen{',
    T + ' body{background-color:#CDB693!important;background-image:url("theme-beige-marble.jpg?v=3")!important;background-size:900px 900px!important;background-repeat:repeat!important}',
    T + ' .dsk-app{--dsk-bg:transparent!important}',
    T + ' header:is(.bg-surface-container-lowest,.bg-surface,.bg-background,.bg-white){background:' + BAR + '!important;border-bottom:1px solid rgba(184,149,74,.55)!important}',
    T + ' :is(.rounded-lg,.rounded-xl,.rounded-2xl,.rounded-3xl):is(.bg-surface-container-lowest,.bg-white):not(input):not(select):not(textarea):not(button)' +
      '{border:1px solid ' + FRAME + '!important;box-shadow:0 10px 26px -18px rgba(90,66,26,.55),inset 0 1px 0 rgba(255,255,255,.7)!important}',
    T + ' button:is(.rounded-lg,.rounded-xl,.rounded-2xl,.rounded-3xl):is(.bg-surface-container-lowest,.bg-white){border:1px solid ' + FRAME + '!important}',
    T + ' nav.gm-bottom-tabs{border-top:1px solid rgba(184,149,74,.55)!important}',
    T + ' :is(thead,th){background-color:#EDE0C5}',
    // words written straight on the sand marble: deep espresso-gold so they read on the darker canvas
    T + ' .gm-on-canvas{color:#3E2C10!important;-webkit-text-fill-color:#3E2C10!important;background-image:none!important;text-shadow:0 1px 0 rgba(255,248,232,.55)!important}',
    T + ' .text-secondary{color:#6E5220!important}',
    // form fields on the sand marble: a cream box with a clear brown frame, so every field is visible (بشار 2026-11-17)
    T + ' :is(input:not([type=checkbox]):not([type=radio]):not([type=range]):not([type=color]):not([type=file]):not([type=hidden]),select,textarea){background-color:rgba(255,250,238,.92)!important;border:1px solid #A88B55!important;color:#2A2116!important;-webkit-text-fill-color:#2A2116}',
    // outlined buttons/links sitting on the marble: a light cream fill so each one reads as a button
    T + ' :is(button,a,label,[role=button]).border-outline-variant:not([class*="bg-"]){background-color:rgba(255,250,238,.55)!important}',
    T + ' :is(input,select,textarea)::placeholder{color:#8A7A5E!important;-webkit-text-fill-color:#8A7A5E!important;opacity:1}',
    T + ' :is(input,select,textarea):focus{border-color:#8A6A1C!important;box-shadow:0 0 0 3px rgba(184,149,74,.35)!important;outline:none}',
    // «زجاجية» mode paints its own art behind frosted cards — here the marble is that background
    T + '.gm-glass.gm-light-canvas{background:#CDB693 url("theme-beige-marble.jpg?v=3") repeat 0 0/900px 900px!important}',
    T + '.gm-glass.gm-light-canvas #gmGlassBg{display:none!important}',
    T + '.gm-glass.gm-light-canvas :is(.bg-surface-container-lowest,.bg-white):is(.rounded-lg,.rounded-xl,.rounded-2xl,.rounded-3xl):not(input):not(select):not(textarea){border-color:' + FRAME + '!important}',
    '}'
  ].join('\n');
  var st = document.createElement('style');
  st.id = 'gm-theme-beige';
  st.textContent = css;
  (document.head || document.documentElement).appendChild(st);
})();

function goldmindApplyTheme(name) {
  const theme = GOLDMIND_THEMES[name] || GOLDMIND_THEMES['warm-ingot'];
  const root = document.documentElement;
  // clear variables only another theme sets (e.g. the marble theme's brighter inks), then set this theme's
  Object.keys(GOLDMIND_THEMES).forEach(function (n) {
    Object.keys(GOLDMIND_THEMES[n].vars).forEach(function (key) { if (!(key in theme.vars)) root.style.removeProperty(key); });
  });
  Object.keys(theme.vars).forEach(function (key) {
    root.style.setProperty(key, theme.vars[key]);
  });
  root.setAttribute('data-gm-display-font', theme.displayFont ? '1' : '0');
  // a theme with a «base» reuses that theme's page rules (data-gm-theme) and adds its own layer (data-gm-variant)
  root.setAttribute('data-gm-theme', GOLDMIND_THEMES[name] ? (theme.base || name) : 'warm-ingot'); // lets page CSS follow the chosen theme
  if (theme.base) root.setAttribute('data-gm-variant', name); else root.removeAttribute('data-gm-variant');
  if (theme.displayFont) gmEnsureDisplayFont();
  root.classList.toggle('gm-light-canvas', !!theme.lightCanvas);
  root.classList.toggle('gm-shimmer', !!theme.shimmer);
  if (theme.shimmer) gmEnsureShimmerStyle();
  localStorage.setItem('goldmind_theme', GOLDMIND_THEMES[name] ? name : 'warm-ingot'); // a removed theme (e.g. the brown «الملكي») falls back to the default
}

// "غروب الذهب" and "مجرة منتصف الليل" pair their palette with a subtle
// animated sheen (a moving gradient sweep), matching the metallic/cosmic
// feel previewed in the theme mockup. Any element can opt in with
// class="gm-shimmer-surface" — it reads the theme's --gm-shimmer-grad
// (set as part of that theme's vars) so the sweep colors always match the
// active theme. Injected lazily/once so non-shimmer themes pay no cost.
let gmShimmerStyleLoaded = false;
function gmEnsureShimmerStyle() {
  if (gmShimmerStyleLoaded) return;
  gmShimmerStyleLoaded = true;
  const style = document.createElement('style');
  style.textContent =
    '.gm-shimmer-surface{background:var(--gm-shimmer-grad, var(--gm-primary));' +
    'background-size:220% 220%;animation:gmShimmerSweep 6s ease-in-out infinite;}' +
    '@keyframes gmShimmerSweep{0%,100%{background-position:0% 50%;}50%{background-position:100% 50%;}}' +
    '@media (prefers-reduced-motion: reduce){.gm-shimmer-surface{animation:none;}}';
  document.head.appendChild(style);
}

// Small "initials" circles (staff/customer/trader avatars) always use a
// two-tone gradient matching the active theme's accent colors, in every
// theme — not just the two shimmer themes. Injected once, globally, so any
// page just needs class="gm-avatar-grad" instead of a flat bg color.
let gmAvatarStyleLoaded = false;
function gmEnsureAvatarStyle() {
  if (gmAvatarStyleLoaded) return;
  gmAvatarStyleLoaded = true;
  const style = document.createElement('style');
  style.textContent =
    '.gm-avatar-grad{background:var(--gm-avatar-grad, var(--gm-accent));color:var(--gm-on-accent);}';
  document.head.appendChild(style);
}

// Shared first-letter initial for name-circle avatars, used consistently
// across staff, customers, and traders instead of each page reimplementing it.
function gmInitials(name) {
  return (name || '؟').trim().charAt(0) || '؟';
}
// The "today at a glance" stat strip (cash box / today's invoices / today's
// sales) gets an animated light sweep in EVERY theme, not just the two
// shimmer ones. Earlier version animated between two very-similar light
// surface tones (near-invisible on a real screen); this is a proper
// diagonal gold streak passing over the card periodically, like a loading
// shimmer — same idea, but actually visible.
let gmStatShimmerStyleLoaded = false;
function gmEnsureStatShimmerStyle() {
  if (gmStatShimmerStyleLoaded) return;
  gmStatShimmerStyleLoaded = true;
  const style = document.createElement('style');
  style.textContent =
    '.gm-stat-shimmer{position:relative;overflow:hidden;}' +
    '.gm-stat-shimmer::after{content:"";position:absolute;top:0;bottom:0;left:-60%;width:45%;' +
    'background:linear-gradient(100deg, transparent 0%, rgba(255,215,110,0.55) 45%, rgba(255,255,255,0.75) 55%, transparent 100%);' +
    'transform:skewX(-20deg);animation:gmStatSweep 4.6s ease-in-out infinite;pointer-events:none;}' +
    '@keyframes gmStatSweep{0%{left:-60%;}45%,100%{left:130%;}}' +
    '@media (prefers-reduced-motion: reduce){.gm-stat-shimmer::after{animation:none;display:none;}}';
  document.head.appendChild(style);
}
gmEnsureAvatarStyle();
gmEnsureStatShimmerStyle();
// A dropdown's open list is drawn by the browser on white; on dark themes the options
// inherited the field's light text and became invisible. Same readable list everywhere.
(function () {
  const style = document.createElement('style');
  style.id = 'gm-native-lists';
  style.textContent = '@media screen { html:root body .gm-cfix-light.gm-cfix-light:not(.gm-z):not(.gm-z) { color: #F3F4F6 !important; } html:root body .gm-cfix-dark.gm-cfix-dark:not(.gm-z):not(.gm-z) { color: #1F1A12 !important; }' +
    ' html:root body :is(.gm-cfix-light,.gm-cfix-dark):not(.gm-z):not(.gm-z):not(.gm-z) { -webkit-text-fill-color: currentColor !important; background-image: none !important; } }' +
    'select option, select optgroup, datalist option { background-color: #ffffff; color: #1a1c1e; }' +
    'select option:disabled { color: #8a8f98; }' +
    'select option:checked { background-color: #E8DFC8; color: #1a1c1e; }';
  document.head.appendChild(style);
})();

// «المخمل» (velvet-wine): titles written straight on the wine canvas take a light gold ink so they read
(function () {
  var st = document.createElement('style'); st.id = 'gm-velvet-titles';
  st.textContent = '@media screen{html[data-gm-theme="velvet-wine"] :is(.gm-on-canvas,.gm-sec,body > header h1,body > header h2){--gmi-i1:#D9B66A;--gmi-i2:#E8CC86;--gmi-i3:#F7E6B5;color:#F1DDA4}}';
  (document.head || document.documentElement).appendChild(st);
})();

// Contrast guard (dark themes): text written for white cards (dark navy / wine) that ends up
// straight on the dark canvas, or light text on a white card, is invisible. After the page
// draws (and whenever it redraws), any text with almost no contrast against what is behind
// it gets a readable color — light on dark, dark on light. Screen only; print is untouched.
// ponytail: a safety net over ~20 pages with hand-made colors. Upgrade path: give those
// elements gm-on-canvas / theme variables in each page and drop this.
(function () {
  if (typeof window === 'undefined' || !window.MutationObserver) return;
  const rgb = s => { const m = (s || '').match(/[\d.]+/g); if (!m) return null; const v = m.map(Number); return /color\(/.test(s) ? [v[0] * 255, v[1] * 255, v[2] * 255, v[3]] : v; };
  const lum = c => { const a = c.slice(0, 3).map(v => { v /= 255; return v <= .03928 ? v / 12.92 : Math.pow((v + .055) / 1.055, 2.4); }); return .2126 * a[0] + .7152 * a[1] + .0722 * a[2]; };
  function bgOf(el) {
    for (let e = el; e && e !== document.documentElement; e = e.parentElement) {
      const cs = getComputedStyle(e);
      if (e === el && /text/.test(cs.webkitBackgroundClip || cs.backgroundClip || '')) continue; // a gradient word: its "background" is its ink
      if (cs.backgroundImage && cs.backgroundImage !== 'none' && e !== document.body) {
        // a colour gradient (a card or button painted by the theme): judge by the average of its colours
        if (/url\(/.test(cs.backgroundImage)) return null; // a picture: can't judge
        const r = e.getBoundingClientRect();
        if (r.width * r.height > innerWidth * innerHeight * .25) return null; // a big wrapper's wash: can't judge
        const stops = (cs.backgroundImage.match(/rgba?\([^)]*\)|color\([^)]*\)/g) || []).map(rgb).filter(c => c && (c[3] === undefined || c[3] > .5));
        if (stops.length) return [0, 1, 2].map(i => stops.reduce((a, c) => a + c[i], 0) / stops.length);
        return null;
      }
      const c = rgb(cs.backgroundColor);
      if (c && (c[3] === undefined || c[3] > .6)) return c;
    }
    return rgb(getComputedStyle(document.body).backgroundColor) || [255, 255, 255];
  }
  function pass() {
    const dark = !document.documentElement.classList.contains('gm-light-canvas');
    const fixed = document.querySelectorAll('.gm-cfix-light, .gm-cfix-dark');
    if (!dark) { fixed.forEach(e => e.classList.remove('gm-cfix-light', 'gm-cfix-dark')); return; } // light themes are designed by hand
    // every word must read (بشار 2026-11-16): dark themes need a clear contrast, the gold-veined marble
    // canvases a little more
    const th = document.documentElement.getAttribute('data-gm-theme') || '';
    const minR = /marble/.test(th) ? 3.6 : 3.0;
    const els = document.body ? document.body.getElementsByTagName('*') : [];
    for (let i = 0; i < els.length && i < 6000; i++) {
      const el = els[i];
      if (el.classList.contains('gm-cfix-light') || el.classList.contains('gm-cfix-dark')) continue;
      if (/^(SCRIPT|STYLE|SVG|svg|path|IMG|CANVAS|OPTION|BR)$/.test(el.tagName)) continue;
      // date boxes draw their text in an overlay that already takes the box's own colour
      if (el.classList.contains('gm-date-native') || el.classList.contains('gm-date-overlay')) continue;
      let own = /^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName);
      if (!own) for (const n of el.childNodes) if (n.nodeType === 3 && n.nodeValue.trim()) { own = true; break; }
      if (!own || !el.getClientRects().length) continue;
      const ecs = getComputedStyle(el);
      // a badge that paints its own gradient (letter avatars) is designed with its text: leave it
      // (the fix would also wipe that gradient — the trader initials lost their circle, بشار 2026-11-18)
      if (ecs.backgroundImage && ecs.backgroundImage !== 'none' && !/text/.test(ecs.webkitBackgroundClip || ecs.backgroundClip || '')) continue;
      // what is painted is the fill colour when a rule sets one (it can differ from `color`)
      let fg = rgb(ecs.webkitTextFillColor && !/text/.test(ecs.webkitBackgroundClip || '') ? ecs.webkitTextFillColor : ecs.color); const bg = bgOf(el);
      // gradient words (gloss colours) have a transparent colour: judge them by their ink's first colour
      if (fg && fg[3] !== undefined && fg[3] < .3 && /text/.test(ecs.webkitBackgroundClip || ecs.backgroundClip || '')) { const m = (ecs.backgroundImage || '').match(/rgba?\([^)]*\)/); fg = m ? rgb(m[0]) : null; }
      if (!fg || !bg || (fg[3] !== undefined && fg[3] < .3)) continue;
      const L1 = lum(fg), L2 = lum(bg);
      if ((Math.max(L1, L2) + .05) / (Math.min(L1, L2) + .05) < minR) el.classList.add(L2 < .3 ? 'gm-cfix-light' : 'gm-cfix-dark');
    }
  }
  let t = null;
  const later = () => { clearTimeout(t); t = setTimeout(pass, 250); };
  function start() {
    later(); setTimeout(pass, 1500);
    new MutationObserver(muts => {
      if (muts.some(m => m.attributeName === 'class' && m.target === document.documentElement))
        document.querySelectorAll('.gm-cfix-light, .gm-cfix-dark').forEach(e => e.classList.remove('gm-cfix-light', 'gm-cfix-dark'));
      if (muts.some(m => m.type === 'childList' || (m.attributeName === 'class' && m.target === document.documentElement))) later();
    })
      .observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['class'] });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
})();

// (Removed: a hardcoded Times New Roman + Amiri Quran site-wide font
// override used to live here. Reverted per feedback back to the app's
// original default font (Inter for Latin, the browser's normal Arabic
// sans-serif fallback) — the font-picker below (GOLDMIND_FONTS /
// theme-picker-ar.html) remains available for anyone who wants to
// choose a different font themselves.)

// Fixes a "need to tap twice" bug on embedded WebViews (e.g. the packaged
// Android app): the first tap on a link/button with a hover style gets
// consumed as a hover-state activation instead of an immediate click, so
// navigation only happens on the second tap. touch-action: manipulation
// tells the browser to skip that hover/double-tap-zoom detection entirely.
(function () {
  const style = document.createElement('style');
  style.textContent = 'a, button, [onclick], [role="button"] { touch-action: manipulation; }';
  document.head.appendChild(style);
})();

// Some themes (currently only "warm-ingot") pair their palette with a
// display serif for headlines/big numbers instead of the site-wide Inter.
// Loaded lazily and only once, and scoped via the data-gm-display-font
// attribute set above so it never affects other themes or a stale cache.
let gmDisplayFontLoaded = false;
let gmDisplayFontReady = false;
let gmDisplayFontCallbacks = [];

// Lets a page register a callback to run once the lazily-loaded display
// font (if this theme uses one) has actually finished loading its real
// glyph data — not just once its stylesheet request was kicked off. Pages
// use this to re-run any text-fitting logic that may have measured against
// the fallback font before the real one swapped in. If the current theme
// has no display font, the callback fires immediately (nothing to wait for).
function gmOnDisplayFontReady(callback) {
  if (typeof callback !== 'function') return;
  const usesDisplayFont = document.documentElement.getAttribute('data-gm-display-font') === '1';
  if (!usesDisplayFont || gmDisplayFontReady) {
    callback();
    return;
  }
  gmDisplayFontCallbacks.push(callback);
}

function gmFireDisplayFontReady() {
  if (gmDisplayFontReady) return;
  gmDisplayFontReady = true;
  const callbacks = gmDisplayFontCallbacks;
  gmDisplayFontCallbacks = [];
  callbacks.forEach(function (cb) { cb(); });
}

function gmEnsureDisplayFont() {
  if (gmDisplayFontLoaded) return;
  gmDisplayFontLoaded = true;
  const link = document.createElement('link');
  link.rel = 'stylesheet';
  link.href = 'https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,500;9..144,600&display=swap';
  // The stylesheet finishing to download only means the @font-face rules
  // are registered — the actual WOFF2 glyph data can still be fetching.
  // document.fonts.load() gives a promise that resolves only once the
  // real glyphs are ready to paint, which is what re-fitting text needs.
  link.onload = function () {
    if (document.fonts && document.fonts.load) {
      Promise.all([
        document.fonts.load('600 16px Fraunces'),
        document.fonts.load('500 16px Fraunces')
      ]).then(gmFireDisplayFontReady).catch(gmFireDisplayFontReady);
    } else {
      gmFireDisplayFontReady();
    }
  };
  // Safety net: if the stylesheet load event never fires for any reason
  // (blocked request, unusual browser behavior), don't leave callers
  // waiting forever — fire after a generous timeout regardless.
  setTimeout(gmFireDisplayFontReady, 4000);
  document.head.appendChild(link);
  const style = document.createElement('style');
  style.textContent = '[data-gm-display-font="1"] .font-headline-md, ' +
    '[data-gm-display-font="1"] .font-headline-lg, ' +
    '[data-gm-display-font="1"] .font-headline-xl, ' +
    '[data-gm-display-font="1"] .font-headline-xl-mobile { font-family: "Fraunces", serif; letter-spacing: -0.01em; }';
  document.head.appendChild(style);
}

// -----------------------------------------------------------------------
// App-wide font picker (settings → مظهر التطبيق). Lets the user pick a
// font family for the whole app, independent of theme colors. The list
// mixes system fonts (no loading needed — Times New Roman, Arial, etc,
// same idea as Word's font list) and Google-hosted Arabic/Latin fonts
// (loaded lazily only when actually selected). Because a browser
// automatically falls back to the page's default font for any character
// a chosen font doesn't cover, picking a Latin-only font like "Times New
// Roman" naturally only affects Latin text/numbers and leaves Arabic
// labels on the site's normal Arabic font — no language-detection needed.
const GOLDMIND_FONTS = {
  'default': { label: 'افتراضي التطبيق', family: null },
  'times-new-roman': { label: 'Times New Roman', family: '"Times New Roman", Times, serif' },
  'georgia': { label: 'Georgia', family: 'Georgia, "Times New Roman", serif' },
  'arial': { label: 'Arial', family: 'Arial, Helvetica, sans-serif' },
  'tahoma': { label: 'Tahoma', family: 'Tahoma, Geneva, sans-serif' },
  'verdana': { label: 'Verdana', family: 'Verdana, Geneva, sans-serif' },
  'trebuchet-ms': { label: 'Trebuchet MS', family: '"Trebuchet MS", sans-serif' },
  'cairo': { label: 'Cairo', family: '"Cairo", sans-serif', google: 'Cairo:wght@400;500;600;700' },
  'tajawal': { label: 'Tajawal', family: '"Tajawal", sans-serif', google: 'Tajawal:wght@400;500;700' },
  'almarai': { label: 'Almarai', family: '"Almarai", sans-serif', google: 'Almarai:wght@400;700' },
  'amiri': { label: 'أميري (Amiri)', family: '"Amiri", serif', google: 'Amiri:wght@400;700' },
  'noto-kufi-arabic': { label: 'Noto Kufi Arabic', family: '"Noto Kufi Arabic", sans-serif', google: 'Noto+Kufi+Arabic:wght@400;500;700' },
  'playfair-display': { label: 'Playfair Display', family: '"Playfair Display", serif', google: 'Playfair+Display:wght@500;600;700' },
};

let gmFontOverrideInjected = false;
let gmFontsLoaded = {};
let gmFontReady = true;
let gmFontCallbacks = [];

// Same idea as gmOnDisplayFontReady above, but for the user-chosen
// app-wide font: fires only once the real glyph data has finished
// loading (not just once the request started), so pages that need to
// re-measure text (e.g. the dashboard's fitStatNumber) never race a font
// swap that hasn't actually happened yet.
function gmOnFontReady(callback) {
  if (typeof callback !== 'function') return;
  if (gmFontReady) { callback(); return; }
  gmFontCallbacks.push(callback);
}

function gmFireFontReady() {
  gmFontReady = true;
  const callbacks = gmFontCallbacks;
  gmFontCallbacks = [];
  callbacks.forEach(function (cb) { cb(); });
}

function gmEnsureFontOverrideStyle() {
  if (gmFontOverrideInjected) return;
  gmFontOverrideInjected = true;
  const style = document.createElement('style');
  style.id = 'gm-font-override';
  style.textContent = 'body, button, input, select, textarea, ' +
    '.font-headline-md, .font-headline-sm, .font-headline-lg, ' +
    '.font-body-md, .font-body-lg, .font-label-md, .font-label-sm, ' +
    '.font-display-lg, .font-display-lg-mobile { font-family: var(--gm-font-family) !important; }';
  document.head.appendChild(style);
}

function goldmindApplyFont(key) {
  const font = GOLDMIND_FONTS[key] || GOLDMIND_FONTS['default'];
  localStorage.setItem('goldmind_font', key);
  const existingOverride = document.getElementById('gm-font-override');
  if (!font.family) {
    // Back to the app's own per-page default font — remove our override
    // entirely rather than leaving an empty CSS variable behind, which
    // would otherwise make font-family compute as invalid.
    if (existingOverride) existingOverride.remove();
    gmFontOverrideInjected = false;
    gmFireFontReady();
    return;
  }
  document.documentElement.style.setProperty('--gm-font-family', font.family);
  gmEnsureFontOverrideStyle();
  if (!font.google) {
    gmFireFontReady();
    return;
  }
  if (gmFontsLoaded[key]) {
    gmFireFontReady();
    return;
  }
  gmFontsLoaded[key] = true;
  gmFontReady = false;
  const link = document.createElement('link');
  link.rel = 'stylesheet';
  link.href = 'https://fonts.googleapis.com/css2?family=' + font.google + '&display=swap';
  const familyNameOnly = font.family.split(',')[0].replace(/"/g, '');
  link.onload = function () {
    if (document.fonts && document.fonts.load) {
      document.fonts.load('16px ' + familyNameOnly).then(gmFireFontReady).catch(gmFireFontReady);
    } else {
      gmFireFontReady();
    }
  };
  setTimeout(gmFireFontReady, 4000);
  document.head.appendChild(link);
}

function goldmindLoadSavedFont() {
  // The font-picker (theme-picker-ar.html) was removed per بشار's request —
  // no more per-device choice/variety. This is now the one fixed combo,
  // forced everywhere below regardless of this call.
  goldmindApplyFont('default');
}


function goldmindLoadSavedTheme() {
  const saved = localStorage.getItem('goldmind_theme') || 'warm-ingot';
  goldmindApplyTheme(saved);
  return saved;
}

// Print-preview pages (a white paper on a grey page): on screen, the page around the paper follows the
// chosen theme; controls that sit straight on the page get a light panel. Printing is unchanged (white).
(function () {
  var st = document.createElement('style');
  st.id = 'gm-paper-pages-theme';
  st.textContent = '@media screen{'
    // colour only: a theme's own picture (the marble, بشار 2026-11-19) stays behind the paper
    + 'html:not(.gm-light-canvas) body.bg-gray-100,html:not(.gm-light-canvas) body.gm-paper-page{background-color:var(--gm-bg)!important}'
    + 'html:not(.gm-light-canvas) body.bg-gray-100>.no-print:not(.sticky):not(.hidden),html:not(.gm-light-canvas) body.gm-paper-page .gm-paper-controls{background:#fff;border-radius:12px;padding:10px 12px;color:#1F1A12}'
    // black marble: that panel is dark too, like the rest of the page (بشار 2026-11-19)
    + 'html[data-gm-theme="black-marble"] body.bg-gray-100>.no-print:not(.sticky):not(.hidden),html[data-gm-theme="black-marble"] body.gm-paper-page .gm-paper-controls{background:#1C1D22;color:#ECE6D8;box-shadow:0 0 0 1px rgba(212,175,55,.22)}'
    + '}';
  (document.head || document.documentElement).appendChild(st);
})();

// Apply immediately on script load (before first paint as much as possible)
goldmindLoadSavedTheme();
goldmindLoadSavedFont();

// Body text is intentionally light (on-primary) so it reads on the dark
// page background used site-wide. But that means any plain text sitting
// inside a light/white card (bg-surface-container*, bg-white) with no
// text-color class of its own would inherit that light color and become
// invisible against its own light card. Rather than hunting down every
// such element across every page (and every one added in the future),
// set the correct dark default directly on the light-surface classes
// themselves via the CSS variable — this works even on pages whose own
// Tailwind config doesn't map "on-surface", since it targets the plain
// class name and the CSS variable, not a Tailwind-generated utility.
// Any element with its own explicit text-* class is unaffected, since an
// element's own declared color always wins over an inherited one.
(function () {
  const style = document.createElement('style');
  style.textContent = `
    .bg-surface-container-lowest, .bg-surface-container-low,
    .bg-surface-container, .bg-surface-container-high,
    .bg-surface-container-highest, .bg-white {
      color: var(--gm-on-surface, #191c1e);
    }
  `;
  document.head.appendChild(style);
})();

// Same root cause, different shape: plain <input>/<select>/<textarea>
// elements across several pages (company-settings, account-security,
// ledger's trader form, invoice forms, etc.) were given a border but no
// background or text-color class at all. They render on the browser's
// native white input background while still inheriting the page's light
// body text color -> invisible white-on-white text. Pages that
// deliberately want a dark, see-through input (bg-transparent +
// text-on-background, used e.g. on customer-add-ar.html) are explicitly
// excluded so they keep their intended look.
(function () {
  const style = document.createElement('style');
  style.textContent = `
    input:not([type=checkbox]):not([type=radio]):not(.bg-transparent):not(.text-on-background),
    select:not(.bg-transparent):not(.text-on-background),
    textarea:not(.bg-transparent):not(.text-on-background) {
      color: var(--gm-on-surface, #191c1e);
      background-color: var(--gm-surface-lowest, #ffffff);
    }
    /* checkboxes/radios (بشار's rule): empty = a light box with a frame only; ticked = the whole box solid black.
       No native box inside our frame (appearance none) and no tick from the forms plugin (background-image none). */
    html input:is([type=checkbox], [type=radio]):not([class*="w-"]) { width: 20px; height: 20px; }
    html input[type=checkbox], html input[type=radio] {
      -webkit-appearance: none; appearance: none; flex-shrink: 0; margin: 0; padding: 0;
      vertical-align: middle; cursor: pointer;
      border: 2px solid var(--gm-outline, #76777d); border-radius: 5px;
      background: #fff none !important; color: transparent; box-shadow: none;
      transition: background-color .12s, border-color .12s;
    }
    html input[type=radio] { border-radius: 999px; }
    html input[type=checkbox]:checked, html input[type=radio]:checked {
      background: #000 none !important; border-color: #000;
    }
    html input[type=checkbox]:focus-visible, html input[type=radio]:focus-visible { outline: 2px solid #B4955A; outline-offset: 2px; box-shadow: none; }
    html input[type=checkbox]:disabled, html input[type=radio]:disabled { opacity: .45; cursor: not-allowed; }
    @media (prefers-reduced-motion: reduce) { html input[type=checkbox], html input[type=radio] { transition: none; } }
  `;
  document.head.appendChild(style);
})();

// Third shape of the same problem: muted "hint"/secondary text classes
// (text-on-surface-variant, text-outline) were designed to sit on a white
// card — they're a mid/dark grey, readable there. Several pages use them
// directly on the page's own dark background (intro paragraphs under a
// header, empty-state messages, small captions next to icons, floating
// form-field labels) instead of inside a card, so that same dark grey
// becomes near-invisible on the dark navy/teal/purple page background
// every theme uses. First attempt used a translucent white, but that
// still read as too washed out (small/tracked-out label text especially).
// Switched to each theme's own --gm-outline-variant — already a solid,
// per-theme-tuned light tone proven visible against these dark
// backgrounds (it's what draws every card/input border already). Rather
// than hunting every such paragraph across ~35 pages (and every one added
// later), default both classes to that color and only switch them back
// to the card-mode grey when they actually are nested inside a light
// surface — pure CSS, so it also covers content injected later.
// !important guards against Tailwind's own same-specificity utility
// (e.g. the page-local ".text-outline { color: #76777d }") winning on
// injection-order alone; a genuinely more specific rule still wins.
(function () {
  const lightSurfaces = ['bg-surface-container-lowest', 'bg-surface-container-low', 'bg-surface-container', 'bg-surface-container-high', 'bg-surface-container-highest', 'bg-white'];
  const mutedClasses = ['text-on-surface-variant', 'text-outline'];
  const overrideSelectors = [];
  lightSurfaces.forEach(function (surface) {
    mutedClasses.forEach(function (cls) {
      overrideSelectors.push('.' + surface + ' .' + cls);
      overrideSelectors.push('.' + surface + '.' + cls);
    });
  });
  const style = document.createElement('style');
  style.textContent = `
    .text-on-surface-variant, .text-outline {
      color: var(--gm-outline-variant, #c6c6cd) !important;
    }
    ${overrideSelectors.join(',\n    ')} {
      color: var(--gm-on-surface-variant, #45464d) !important;
    }
  `;
  document.head.appendChild(style);
})();

// Fourth shape: the dark, see-through inputs deliberately excluded from
// the earlier white-background input fix (bg-transparent + text-on-
// background — barcode/weight/description fields on inventory-add.html
// etc.) never got a placeholder color at all, so the browser's own
// default (assumes a light input background) rendered their placeholder
// hint text almost invisible against the dark page. Give them the same
// visible, per-theme outline-variant tone as the muted-text fix above.
(function () {
  const style = document.createElement('style');
  style.textContent = `
    input.text-on-background::placeholder,
    textarea.text-on-background::placeholder {
      color: var(--gm-outline-variant, #c6c6cd);
      opacity: 0.85;
    }
  `;
  document.head.appendChild(style);
})();

// Fifth shape: plain text with no color class at all (e.g. a trader or
// customer name rendered as `<p class="font-bold text-[14px]">`) inherits
// color straight from <body>, which on a dark-background theme is a
// light/white tone meant for the page's own dark canvas -- not for text
// sitting inside a white/light card. Result: a name that's invisible on a
// white row and barely a pale smear on a slightly tinted one (exactly the
// zebra-striped trader rows). Setting color on the light-surface
// container itself relies on normal CSS inheritance -- any child that
// already has its own explicit text-* class (text-error, text-success,
// text-secondary, the muted classes above, etc.) keeps winning, since a
// directly-applied rule always beats an inherited value regardless of
// specificity. No !important needed here for that reason.
(function () {
  const lightSurfaces = ['bg-surface-container-lowest', 'bg-surface-container-low', 'bg-surface-container', 'bg-surface-container-high', 'bg-surface-container-highest', 'bg-white'];
  const style = document.createElement('style');
  style.textContent = `
    ${lightSurfaces.map(function (s) { return '.' + s; }).join(', ')} {
      color: var(--gm-on-surface, #191c1e);
    }
  `;
  document.head.appendChild(style);
})();

// Fifth shape: same placeholder-legibility gap, but for the WHITE-background
// inputs from the second fix above (company-settings, ledger forms, etc.).
// Their typed text is now dark (on-surface) via that fix, but an empty
// field's placeholder still used the browser's own default grey, which
// reads as too faint/washed-out on some devices. Give those placeholders
// a deliberate, readable mid-grey tied to the theme instead.
(function () {
  const style = document.createElement('style');
  style.textContent = `
    input:not(.bg-transparent):not(.text-on-background)::placeholder,
    select:not(.bg-transparent):not(.text-on-background)::placeholder,
    textarea:not(.bg-transparent):not(.text-on-background)::placeholder {
      color: var(--gm-on-surface-variant, #45464d);
      opacity: 0.75;
    }
  `;
  document.head.appendChild(style);
})();

// Sixth shape: the "warm-ingot" theme (and any future theme with
// lightCanvas:true) uses a light page canvas instead of the dark one every
// other theme uses. .text-on-primary / body.text-on-background were always
// safe to assume "light text, because the canvas under it is dark" — that
// assumption breaks here. Default them to dark ink (on-surface) site-wide
// for this theme, then explicitly restore the light color wherever
// text-on-primary sits together with bg-primary on the same element (the
// standard "solid dark button" pattern used across ~30 pages) or bg-accent,
// since those chips stay dark/brass on purpose and still need light text.
(function () {
  const style = document.createElement('style');
  style.textContent = `
    html.gm-light-canvas .text-on-primary,
    html.gm-light-canvas .text-on-background {
      color: var(--gm-on-surface, #191c1e);
    }
    html.gm-light-canvas .bg-primary.text-on-primary,
    html.gm-light-canvas .bg-accent.text-on-primary {
      color: var(--gm-on-primary, #ffffff);
    }
    html.gm-light-canvas input.text-on-background::placeholder,
    html.gm-light-canvas textarea.text-on-background::placeholder {
      color: var(--gm-on-surface-variant, #45464d);
      opacity: 0.75;
    }
    /* On a light canvas, muted/hint text (text-on-surface-variant, text-
       outline) no longer needs the "made visible against a dark page"
       swap to outline-variant — the canvas is now as light as a card, so
       the normal card-tone muted color already reads fine everywhere. */
    html.gm-light-canvas .text-on-surface-variant,
    html.gm-light-canvas .text-outline {
      color: var(--gm-on-surface-variant, #45464d) !important;
    }
  `;
  document.head.appendChild(style);
})();

// Seventh shape: installed as a standalone PWA (manifest display:standalone),
// the app draws under the device's status bar, gesture nav bar, and rounded
// screen corners with no OS chrome to keep content clear of them. Every
// inner page's sticky top-0 header and any fixed bottom bar/nav sat flush
// against the true screen edge, so icons/buttons placed near those edges
// could get visually clipped by the status bar, gesture bar, or a curved
// screen edge depending on the device. Ensure the viewport opts in to
// drawing under those system areas (viewport-fit=cover) then pad the
// header/bottom-bar/FAB elements with the actual safe-area-inset values
// (0 on devices/browsers that don't need it, so this is a no-op there).
(function () {
  const vp = document.querySelector('meta[name="viewport"]');
  // Inside the installed Android app (Capacitor 8) "cover" makes the WebView draw under the status bar:
  // the clock and notifications disappear and the top buttons (PDF…) can't be tapped. Without it
  // Capacitor keeps the page below the status bar, as before the upgrade. Only the website/PWA uses cover.
  const isNativeApp = !!(window.Capacitor && typeof window.Capacitor.isNativePlatform === 'function' && window.Capacitor.isNativePlatform());
  if (vp && isNativeApp) vp.content = vp.content.replace(/,?\s*viewport-fit=cover/, '');
  else if (vp && !/viewport-fit/.test(vp.content)) {
    vp.content = vp.content.replace(/\s*$/, '') + ', viewport-fit=cover';
  }
  const style = document.createElement('style');
  style.textContent = `
    header.sticky.top-0, header.fixed.top-0 {
      padding-top: max(env(safe-area-inset-top, 0px), var(--safe-area-inset-top, 0px));
    }
    /* a fixed-height header grows by the status bar instead of squeezing its content up under it */
    header.fixed.top-0.h-16, header.sticky.top-0.h-16 { height: calc(4rem + max(env(safe-area-inset-top, 0px), var(--safe-area-inset-top, 0px))); }
    header.fixed.top-0.h-16 ~ main.pt-20 { padding-top: calc(5rem + max(env(safe-area-inset-top, 0px), var(--safe-area-inset-top, 0px))); }
    nav.sticky.bottom-0, nav.fixed.bottom-0,
    div.sticky.bottom-0, div.fixed.bottom-0 {
      padding-bottom: max(env(safe-area-inset-bottom, 0px), var(--safe-area-inset-bottom, 0px));
    }
    header.sticky.top-0 > div:first-child,
    header.fixed.top-0 > div:first-child {
      padding-left: max(1rem, env(safe-area-inset-left, 0px));
      padding-right: max(1rem, env(safe-area-inset-right, 0px));
    }
  `;
  document.head.appendChild(style);
})();

// Eighth shape: several pages (index-ar.html's dashboard among them) use a
// custom Tailwind "margin-mobile" spacing token (px-margin-mobile) fixed at
// 16px for their header/main/bottom-nav side padding. On some real devices
// that still reads as "touching the edge" (rounded screen corners eat into
// a flat 16px, and it never grows to clear the safe-area inset). Override
// it site-wide to a slightly larger, safe-area-aware value.
(function () {
  const style = document.createElement('style');
  style.textContent = `
    .px-margin-mobile {
      padding-left: max(20px, env(safe-area-inset-left, 0px)) !important;
      padding-right: max(20px, env(safe-area-inset-right, 0px)) !important;
    }
  `;
  document.head.appendChild(style);
})();

// Context-aware "back" for header back buttons across the app (rolled out
// site-wide — see conversation with بشار, Aug 23 2026; reworked Aug 26 2026
// after the document.referrer/history.length approach turned out unreliable
// inside the Android WebView the APK runs in -- document.referrer is often
// empty there even for genuine in-app navigation (unlike a normal desktop
// browser tab), so the button was silently falling through to the fallback
// page instead of actually stepping back.
//
// Replaced with an explicit sessionStorage-based navigation stack instead,
// which doesn't depend on the WebView's referrer/history quirks at all:
// every GoldMind page pushes its own URL onto gm_nav_stack on load (unless
// it just arrived via gmSmartBack itself, flagged by gm_nav_going_back, in
// which case it's already sitting at the top and shouldn't be pushed again
// -- that flag is what prevents the earlier A→B→back-to-A→forward-to-B-again
// "ping-pong" bug). gmSmartBack() pops the current entry and navigates to
// whatever is now on top. Falls back to the given href only when the stack
// has nothing left (fresh tab, deep link, bookmark, or storage unavailable).
(function () {
  try {
    var STACK_KEY = 'gm_nav_stack';
    var AUTH_PAGES = ['login-entry-ar.html', 'login-ar-4.html', 'auth-callback-ar.html', 'admin-login-ar.html', 'landing-ar.html'];
    var stack = JSON.parse(sessionStorage.getItem(STACK_KEY) || '[]');
    var here = location.pathname + location.search;
    var pageName = location.pathname.split('/').pop();
    var wasBack = sessionStorage.getItem('gm_nav_going_back') === '1';
    window.__gmCameBack = wasBack; // read by the page-transition code below
    sessionStorage.removeItem('gm_nav_going_back');
    // Auth pages themselves never get pushed (there's nothing to "go back
    // to" there), and any that are ALREADY sitting in an existing stack
    // from before this fix get swept out here too -- otherwise repeated
    // gmSmartBack() presses could still walk down to one of them and load
    // it while the person is fully signed in, which some of those pages
    // treat as an error state and sign out of.
    stack = stack.filter(function (entry) {
      var name = entry.split('?')[0].split('/').pop();
      return AUTH_PAGES.indexOf(name) === -1;
    });
    if (AUTH_PAGES.indexOf(pageName) === -1 && !wasBack && stack[stack.length - 1] !== here) {
      // Arriving at a page that's already further down (e.g. list → invoice →
      // edit → save → same invoice): cut back to it instead of stacking a
      // copy, otherwise "back" ping-pongs between the invoice and its edit page.
      var seen = stack.lastIndexOf(here);
      if (seen !== -1) stack = stack.slice(0, seen + 1);
      else stack.push(here);
    }
    sessionStorage.setItem(STACK_KEY, JSON.stringify(stack.slice(-30)));
  } catch (e) { /* sessionStorage unavailable (private mode etc.) -- gmSmartBack falls back to fallbackHref every time */ }
})();

// ---- moving between pages (View Transitions): a new page slides in from the start side,
// going back slides the other way. Browsers without support just open the page.
(function () {
  try {
    var css = document.createElement('style');
    css.textContent =
      '@view-transition{navigation:auto}' +
      '::view-transition-old(root){animation:gmVtOut .2s cubic-bezier(.4,0,1,1) both}' +
      '::view-transition-new(root){animation:gmVtIn .28s cubic-bezier(.22,1,.36,1) both}' +
      'html:active-view-transition-type(back)::view-transition-old(root){animation-name:gmVtOutBack}' +
      'html:active-view-transition-type(back)::view-transition-new(root){animation-name:gmVtInBack}' +
      /* RTL: forward = the new page comes from the left */
      '@keyframes gmVtOut{to{opacity:0;transform:translateX(24px)}}@keyframes gmVtIn{from{opacity:0;transform:translateX(-36px)}}' +
      '@keyframes gmVtOutBack{to{opacity:0;transform:translateX(-24px)}}@keyframes gmVtInBack{from{opacity:0;transform:translateX(36px)}}' +
      /* the computer side menu and the phone tabs stay still */
      '#gmNav{view-transition-name:gm-nav}nav.gm-bottom-tabs{view-transition-name:gm-tabs}' +
      '::view-transition-group(gm-nav),::view-transition-group(gm-tabs){animation:none}' +
      '::view-transition-old(gm-nav),::view-transition-old(gm-tabs){display:none}::view-transition-new(gm-nav),::view-transition-new(gm-tabs){animation:none}' +
      '@media (prefers-reduced-motion:reduce){@view-transition{navigation:none}}';
    document.head.appendChild(css);
    var isBack = function (e, fromFlag) {
      if (fromFlag) return true;
      try { var a = window.navigation && navigation.activation; return !!(a && a.navigationType === 'traverse' && a.from && a.entry && a.from.index > a.entry.index); } catch (x) { return false; }
    };
    // old page: leaving through gmSmartBack (flag set just before) or the browser's back
    window.addEventListener('pageswap', function (e) {
      if (!e.viewTransition) return;
      var back = sessionStorage.getItem('gm_nav_going_back') === '1' ||
        (e.activation && e.activation.navigationType === 'traverse' && e.activation.from && e.activation.entry && e.activation.from.index > e.activation.entry.index);
      if (back) e.viewTransition.types.add('back');
    });
    // new page: theme.js runs in <head>, before the first paint (window.__gmCameBack is set by the back-stack code above)
    window.addEventListener('pagereveal', function (e) {
      if (e.viewTransition && isBack(e, window.__gmCameBack)) e.viewTransition.types.add('back');
    });
  } catch (e) { /* ignore */ }
})();

// A page that only forwards somewhere else must not stay in the back-stack,
// otherwise "back" lands on it and it forwards again — an endless loop.
function gmReplace(url) {
  try {
    var stack = JSON.parse(sessionStorage.getItem('gm_nav_stack') || '[]');
    if (stack[stack.length - 1] === location.pathname + location.search) {
      stack.pop();
      sessionStorage.setItem('gm_nav_stack', JSON.stringify(stack));
    }
  } catch (e) { /* ignore */ }
  location.replace(url);
}

function gmSmartBack(fallbackHref) {
  try {
    var stack = JSON.parse(sessionStorage.getItem('gm_nav_stack') || '[]');
    if (stack.length > 1) {
      stack.pop(); // drop the current page
      var target = stack[stack.length - 1]; // new top = where we actually came from
      sessionStorage.setItem('gm_nav_stack', JSON.stringify(stack));
      sessionStorage.setItem('gm_nav_going_back', '1');
      window.location.href = target;
      return;
    }
    // Nothing to go back to: the fallback page becomes the new start. Leaving the current page
    // in the stack made the fallback's own back button return here — A → back → B → back → A …
    sessionStorage.setItem('gm_nav_stack', '[]');
  } catch (e) { /* fall through to hard navigation */ }
  window.location.href = fallbackHref;
}

// Android hardware / gesture back (called by MainActivity). Returns 'exit' when the app should go to
// the background (home or sign-in pages), otherwise steps back exactly like the page's own back button.
// A page can handle it first (close its own popup) by defining window.gmOnHardwareBack() returning true.
function gmHardwareBack() {
  try {
    if (typeof window.gmOnHardwareBack === 'function' && window.gmOnHardwareBack() === true) return 'done';
    var dlg = document.querySelector('dialog[open]');
    if (dlg) { dlg.close(); return 'done'; }
    var name = location.pathname.split('/').pop() || 'index.html';
    if (['index-ar.html', 'index.html', 'login-entry-ar.html', 'login-ar-4.html', 'auth-callback-ar.html',
         'admin-login-ar.html', 'landing-ar.html'].indexOf(name) !== -1) return 'exit';
    var btn = Array.prototype.find.call(document.querySelectorAll('.gm-back-btn-3d'), function (b) { return b.offsetParent !== null; });
    if (btn) { btn.click(); return 'done'; }
    gmSmartBack('index-ar.html');
    return 'done';
  } catch (e) { return 'exit'; }
}

// Ninth shape: every header "back" button across the app used to be a bare
// flat glyph (a plain unicode arrow or an unstyled Material Symbol) — easy
// to miss and visually flat/"dry". Give every one of them a consistent,
// clearly-tappable 3D raised gold badge instead, site-wide, without having
// to touch each page's markup individually. This runs after each page's own
// scripts wire up the button's onclick handler, so the click BEHAVIOR
// (gmSmartBack's context-aware step-back, or a page's own bespoke goBack()/
// headerBack()/history.back()) is completely untouched — only the button's
// look is normalized.
(function () {
  const style = document.createElement('style');
  style.textContent = `
    .gm-back-btn-3d {
      width: 40px !important; height: 40px !important; min-width: 40px; border-radius: 50% !important;
      flex: none; display: inline-flex !important; align-items: center; justify-content: center;
      background: linear-gradient(150deg, #B4955A 0%, #8a6d3f 45%, #6d5530 100%) !important;
      box-shadow:
        0 1px 0 rgba(255,255,255,.35) inset,
        0 -2px 3px rgba(60,45,15,.4) inset,
        0 3px 6px rgba(60,45,15,.35),
        0 6px 14px rgba(60,45,15,.25);
      border: none !important; cursor: pointer;
      transition: transform .12s ease, box-shadow .12s ease;
      padding: 0 !important;
    }
    .gm-back-btn-3d:active {
      transform: translateY(1px) scale(.94);
      box-shadow:
        0 1px 0 rgba(255,255,255,.25) inset,
        0 -1px 2px rgba(60,45,15,.35) inset,
        0 1px 2px rgba(60,45,15,.35);
    }
    .gm-back-btn-3d .material-symbols-outlined {
      font-size: 22px !important; line-height: 1 !important; color: #fdf6e8 !important;
      font-variation-settings: 'FILL' 1, 'wght' 700 !important;
    }
  `;
  document.head.appendChild(style);

  const selector = '[onclick^="gmSmartBack"], [onclick^="goBack"], [onclick^="headerBack"], [onclick*="history.back"]';
  function applyBackBtnStyle() {
    document.querySelectorAll(selector).forEach(function (btn) {
      btn.className = 'gm-back-btn-3d';
      btn.innerHTML = '<span class="material-symbols-outlined">arrow_forward</span>';
    });
  }
  // theme.js loads in <head>, before <body> (and the back button itself)
  // exists in the DOM yet — running the query immediately found nothing.
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', applyBackBtnStyle);
  } else {
    applyBackBtnStyle();
  }
})();


// Eleventh shape: native <select> dropdown arrows across the app were
// rendering right on top of the selected text instead of sitting cleanly
// to the side (worse in RTL, where the browser's built-in arrow placement
// is inconsistent). Replace the native arrow with a manually positioned
// one, center the text, and reserve real padding so the two never overlap
// again — applied site-wide so every dropdown in the app gets this at
// once, not just the ones someone happens to notice.
(function () {
  const style = document.createElement('style');
  style.textContent = `
    select {
      -webkit-appearance: none !important;
      -moz-appearance: none !important;
      appearance: none !important;
      text-align: center !important;
      text-align-last: center !important;
      background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23745a25' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpolyline points='6 9 12 15 18 9'%3E%3C/polyline%3E%3C/svg%3E") !important;
      background-repeat: no-repeat !important;
      background-position: left 10px center !important;
      background-size: 16px !important;
      padding-left: 34px !important;
    }
  `;
  document.head.appendChild(style);
})();

// Twelfth shape: one fixed, non-optional site-wide font combo per بشار —
// Times New Roman for Latin/numbers, Arial for Arabic — no more picker,
// no more per-device variety. A single font-family list lets the browser's
// normal per-character fallback do the work: Times New Roman has no Arabic
// glyphs, so Arabic characters automatically fall through to Arial (which
// does have real Arabic coverage), while Latin letters and digits render in
// Times New Roman. This also fixes the داشبورد "كاش الصندوق" card showing
// two different fonts for the AED and USD lines — both are covered by this
// same blanket rule now.
(function () {
  const style = document.createElement('style');
  style.textContent = `
    *, *::before, *::after {
      font-family: 'Times New Roman', Arial, sans-serif !important;
    }
    .material-symbols-outlined {
      font-family: 'Material Symbols Outlined' !important;
    }
  `;
  document.head.appendChild(style);
})();

// One side menu on every page: gm-nav.js (replaces the old partial laptop rail).
(function () {
  if (window.GM_NAV_DISABLED || document.querySelector('script[src^="gm-nav.js"]')) return;
  var sc = document.createElement('script');
  sc.src = 'gm-nav.js?v=33';
  document.head.appendChild(sc);
})();

// Money for display: thousands separators, always 2 decimals (1,234.50).
function gmMoney(v) {
  return Number(v || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}
console.assert(gmMoney(1234.5) === '1,234.50' && gmMoney(null) === '0.00');

// GoldMind favicon on every page (the emblem), unless a page sets its own.
(function () {
  if (document.querySelector('link[rel~="icon"]')) return;
  const l = document.createElement('link');
  l.rel = 'icon'; l.type = 'image/png'; l.href = 'favicon.png';
  (document.head || document.documentElement).appendChild(l);
})();

// ---------- UI polish (applies to every page) ----------
// Built from the ui-ux-pro-max checklist (fonts stay as chosen: Times New Roman
// + Arial, see "Twelfth shape" above): visible keyboard focus, steady-width numbers, reduced motion, no tap delay,
// and screen-reader names for icon-only buttons and placeholder-only fields.
(function gmUiPolish() {
  const css = `
  body{-webkit-font-smoothing:antialiased;text-rendering:optimizeLegibility;}
  /* dates read day/month/year left-to-right even on an Arabic phone
     (an Arabic system locale otherwise jumbles the parts: "261970/09/") */
  /* An Arabic phone writes the date with invisible right-to-left marks between
     the parts ("30‏/09‏/2026"); bidi-override shows the characters in their
     real order, so it reads 30/09/2026 instead of "302026/09/". */
  input[type=date],input[type=datetime-local],input[type=month],input[type=time]{direction:ltr;unicode-bidi:bidi-override;-webkit-locale:"en-GB";text-align:right;}
  input[type=date]::-webkit-datetime-edit,input[type=datetime-local]::-webkit-datetime-edit,input[type=month]::-webkit-datetime-edit{direction:ltr;unicode-bidi:bidi-override;}
  /* money and weights line up in columns */
  .font-data-mono,td,th,input[type=number],[dir=ltr]{font-variant-numeric:tabular-nums;}
  /* keyboard focus is always visible (mouse/touch clicks stay clean) */
  :focus-visible{outline:2px solid var(--gm-secondary,#9C8552)!important;outline-offset:2px;border-radius:6px;}
  input:focus-visible,select:focus-visible,textarea:focus-visible{outline-offset:0;}
  /* no 300ms tap delay, no grey flash on Android */
  a,button,[role=button],label,summary,select{touch-action:manipulation;-webkit-tap-highlight-color:transparent;}
  button:disabled,[aria-disabled=true]{cursor:not-allowed;opacity:.55;}
  [aria-busy=true]{cursor:progress;}
  /* small icon buttons keep their look but get a finger-sized (44px) tap area */
  .gm-hit{position:relative;}
  .gm-hit::before{content:'';position:absolute;left:50%;top:50%;width:max(100%,44px);height:max(100%,44px);transform:translate(-50%,-50%);}
  /* bottom navigation labels were 10px: too small to read on a phone */
  nav.fixed.bottom-0 .text-\\[10px\\]{font-size:11.5px;}
  @media (prefers-reduced-motion: reduce){*,*::before,*::after{animation-duration:.01ms!important;animation-iteration-count:1!important;transition-duration:.01ms!important;scroll-behavior:auto!important;}}
  `;
  const style = document.createElement('style');
  style.id = 'gm-ui-polish';
  style.textContent = css;
  (document.head || document.documentElement).appendChild(style);

  const ICON_LABELS = {
    arrow_forward: 'رجوع', arrow_back: 'رجوع', close: 'إغلاق', search: 'بحث', menu: 'القائمة', more_vert: 'خيارات إضافية',
    add: 'إضافة', delete: 'حذف', edit: 'تعديل', print: 'طباعة', refresh: 'تحديث', share: 'مشاركة', download: 'تنزيل',
    photo_camera: 'تصوير', qr_code_scanner: 'مسح الرمز', barcode_scanner: 'مسح الباركود', mic: 'إدخال بالصوت',
    filter_list: 'تصفية', tune: 'تخصيص', settings: 'الإعدادات', logout: 'تسجيل الخروج', history: 'السجل',
    schedule: 'السجل', attach_money: 'العملة', paid: 'العملة', notifications: 'التنبيهات', dark_mode: 'الوضع الليلي',
    light_mode: 'الوضع النهاري', expand_more: 'عرض المزيد', expand_less: 'عرض أقل', chevron_left: 'التالي', chevron_right: 'السابق', visibility: 'إظهار',
    visibility_off: 'إخفاء', content_copy: 'نسخ', swap_horiz: 'تبديل', check: 'تأكيد', remove: 'إنقاص', info: 'معلومات'
  };
  const iconName = el => { const i = el.querySelector('.material-symbols-outlined'); return i ? i.textContent.trim() : ''; };

  function label(root) {
    // icon ligature names ("search", "arrow_forward") must not be read aloud
    root.querySelectorAll('.material-symbols-outlined:not([aria-hidden])').forEach(i => i.setAttribute('aria-hidden', 'true'));
    root.querySelectorAll('button:not([aria-label]), a:not([aria-label]), [role=button]:not([aria-label])').forEach(b => {
      const icon = iconName(b);
      const text = b.textContent.replace(icon, '').trim();
      if (text) return;
      const name = b.getAttribute('title') || ICON_LABELS[icon];
      if (name) b.setAttribute('aria-label', name);
      if (icon && !b.classList.contains('gm-hit')) {
        const r = b.getBoundingClientRect();
        if (r.width && r.width < 44 && r.height < 44 && getComputedStyle(b).position === 'static') b.classList.add('gm-hit');
      }
    });
    root.querySelectorAll('input[type=number]:not([inputmode])').forEach(f => f.setAttribute('inputmode', 'decimal'));
    root.querySelectorAll('input[type=tel]:not([inputmode])').forEach(f => f.setAttribute('inputmode', 'tel'));
    root.querySelectorAll('input:not([type=hidden]):not([aria-label]), select:not([aria-label]), textarea:not([aria-label])').forEach(f => {
      if (f.labels && f.labels.length) return;
      const name = f.getAttribute('placeholder') || f.getAttribute('title');
      if (name) f.setAttribute('aria-label', name.replace(/\.\.\.$/, ''));
    });
  }
  let queued = false;
  function run() { queued = false; if (document.body) label(document.body); }
  document.addEventListener('DOMContentLoaded', () => {
    run();
    new MutationObserver(() => { if (!queued) { queued = true; requestAnimationFrame(run); } })
      .observe(document.body, { childList: true, subtree: true });
  });
})();

// ---- Photo source chooser ----
// Every <input type="file" capture> (take a photo) now asks first:
// camera or a picture already on the device. Works for buttons that call
// input.click() and for inputs tapped directly, on pages built later too.
(function gmPhotoSourceChooser() {
  if (window.__gmPhotoChooser) return;
  window.__gmPhotoChooser = true;

  function openInput(input, useCamera) {
    var cap = input.getAttribute('capture');
    if (!useCamera) input.removeAttribute('capture');
    input.__gmBypass = true;
    try { input.click(); } finally {
      input.__gmBypass = false;
      if (!useCamera && cap !== null) setTimeout(function () { input.setAttribute('capture', cap); }, 1500);
    }
  }

  function showSheet(input) {
    var old = document.getElementById('gm-photo-sheet');
    if (old) old.remove();
    var back = document.createElement('div');
    back.id = 'gm-photo-sheet';
    back.dir = 'rtl';
    back.style.cssText = 'position:fixed;inset:0;z-index:2147483600;background:rgba(0,0,0,.45);display:flex;align-items:flex-end;justify-content:center;';
    back.innerHTML =
      '<div role="dialog" aria-label="اختيار مصدر الصورة" style="width:100%;max-width:480px;background:#fff;color:#1c1b1b;border-radius:18px 18px 0 0;padding:16px 16px calc(16px + env(safe-area-inset-bottom));display:flex;flex-direction:column;gap:10px;font-family:inherit;">' +
      '<div style="font-weight:700;font-size:15px;text-align:center;margin-bottom:4px">إضافة صورة</div>' +
      '<button type="button" data-src="camera" style="min-height:52px;border-radius:12px;border:0;background:#1c1b1b;color:#fff;font-size:15px;font-weight:700;display:flex;align-items:center;justify-content:center;gap:8px;font-family:inherit;"><span class="material-symbols-outlined" aria-hidden="true">photo_camera</span>التقاط صورة بالكاميرا</button>' +
      '<button type="button" data-src="gallery" style="min-height:52px;border-radius:12px;border:1px solid #d6cfc0;background:#fff;color:#1c1b1b;font-size:15px;font-weight:700;display:flex;align-items:center;justify-content:center;gap:8px;font-family:inherit;"><span class="material-symbols-outlined" aria-hidden="true">photo_library</span>اختيار صورة من الجهاز</button>' +
      '<button type="button" data-src="cancel" style="min-height:44px;border:0;background:none;color:#6b6b6b;font-size:14px;font-family:inherit;">إلغاء</button>' +
      '</div>';
    document.body.appendChild(back);
    function close() { back.remove(); document.removeEventListener('keydown', onKey, true); }
    function onKey(e) { if (e.key === 'Escape') close(); }
    document.addEventListener('keydown', onKey, true);
    back.addEventListener('click', function (e) {
      if (e.target === back) { close(); return; }
      var b = e.target.closest && e.target.closest('button[data-src]');
      if (!b) return;
      var src = b.getAttribute('data-src');
      close();
      if (src !== 'cancel') openInput(input, src === 'camera');
    });
    var first = back.querySelector('button[data-src="camera"]');
    if (first) first.focus();
  }

  document.addEventListener('click', function (e) {
    var input = e.target;
    if (!input || input.tagName !== 'INPUT' || input.type !== 'file' || !input.hasAttribute('capture')) return;
    if (input.__gmBypass) return;
    // "Choose from files" in the desktop camera window (gm-camera.js) goes straight to the gallery.
    // (A nested input.click() here would be ignored by the browser, so let this click go ahead without capture.)
    if (window.__gmPreferGallery) {
      window.__gmPreferGallery = false;
      var cap = input.getAttribute('capture');
      input.removeAttribute('capture');
      setTimeout(function () { input.setAttribute('capture', cap); }, 1500);
      return;
    }
    e.preventDefault();
    e.stopPropagation();
    showSheet(input);
  }, true);
})();

// ---------- Typed dates (day/month/year) ----------
// Native date pickers on Arabic Android phones jumble the parts
// ("261970/09/") and make old dates (birthdays) slow to reach. Inputs marked
// data-gm-date become plain LTR text typed as DD/MM/YYYY; slashes are added
// automatically and Arabic digits are accepted. Read/write with
// gmDateGet(el) -> 'YYYY-MM-DD' | null (empty) | undefined (invalid) and
// gmDateSet(el, 'YYYY-MM-DD').
function gmDateNormalize(v) {
  const d = String(v || '').replace(/[٠-٩]/g, (c) => String(c.charCodeAt(0) - 0x660)).replace(/\D/g, '').slice(0, 8);
  return d.length > 4 ? d.slice(0, 2) + '/' + d.slice(2, 4) + '/' + d.slice(4)
       : d.length > 2 ? d.slice(0, 2) + '/' + d.slice(2) : d;
}
function gmDateGet(el) {
  const v = el.value.trim();
  if (!v) return null;
  const m = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(v);
  if (!m) return undefined;
  const iso = m[3] + '-' + m[2] + '-' + m[1];
  const t = new Date(iso + 'T00:00:00Z');
  return (!isNaN(t) && t.toISOString().slice(0, 10) === iso) ? iso : undefined;
}
function gmDateSet(el, iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso || '');
  el.value = m ? m[3] + '/' + m[2] + '/' + m[1] : '';
}
function gmDateInit(el) {
  if (el.__gmDate) return;
  el.__gmDate = true;
  el.type = 'text';
  el.setAttribute('inputmode', 'numeric');
  el.setAttribute('dir', 'ltr');
  el.setAttribute('autocomplete', 'off');
  el.setAttribute('maxlength', '10');
  if (!el.placeholder) el.placeholder = 'DD/MM/YYYY';
  el.addEventListener('input', () => { el.value = gmDateNormalize(el.value); });
}
(function () {
  const run = () => document.querySelectorAll('input[data-gm-date]').forEach(gmDateInit);
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', run); else run();
})();

// Pages without their own Tailwind colour config (trader-edit, hr-leaves,
// company-register, …) still use bg-background / bg-primary etc. Those
// classes then did nothing: floating field labels had no background (the
// input border ran through the text) and dark buttons were invisible.
// :where() keeps these at zero specificity, so any page that does define
// the colours keeps its own values.
(function () {
  const style = document.createElement('style');
  style.textContent = `
    :where(.bg-background){background-color:var(--gm-bg-elevated,#F3EEDF)}
    :where(.bg-surface-container-lowest){background-color:var(--gm-surface-lowest,#fff)}
    :where(.bg-surface-container-low){background-color:var(--gm-surface-low,#EFE7D2)}
    :where(.bg-primary){background-color:var(--gm-primary,#1C1A16)}
    :where(.text-on-primary){color:var(--gm-on-primary,#fff)}
    :where(.border-outline-variant){border-color:var(--gm-outline-variant,#CBBF9E)}
  `;
  document.head.appendChild(style);
})();

// Visible file pickers (ID photos, licences) showed the browser's own
// "Choose File / No file chosen" — English on many phones. Replace the look
// with an Arabic button + file name; the real <input> stays in place (just
// invisible) so every page's existing .files / change handlers still work.
function gmPrettyFileInputs(root) {
  (root || document).querySelectorAll('input[type="file"].border-dashed:not([data-gm-file])').forEach(function (inp) {
    inp.setAttribute('data-gm-file', '1');
    if (!inp.id) inp.id = 'gmf' + Math.random().toString(36).slice(2, 8);
    var lab = document.createElement('label');
    lab.htmlFor = inp.id;
    lab.className = inp.className + ' flex items-center gap-2 cursor-pointer';
    lab.innerHTML = '<span class="material-symbols-outlined" style="font-size:18px;">upload_file</span>'
      + '<span style="font-weight:600;">اختر ملفاً</span>'
      + '<span data-gm-fname style="opacity:.7;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;min-width:0;">لم يُختر أي ملف</span>';
    inp.style.cssText += ';position:absolute;width:1px;height:1px;opacity:0;overflow:hidden;';
    inp.parentNode.insertBefore(lab, inp.nextSibling);
    var sync = function () {
      var f = inp.files && inp.files[0];
      lab.querySelector('[data-gm-fname]').textContent = f ? f.name : 'لم يُختر أي ملف';
    };
    inp.addEventListener('change', sync);
    inp.addEventListener('input', sync);
  });
}
if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', function () { gmPrettyFileInputs(); });
else gmPrettyFileInputs();

// Barcodes are often stored zero-padded ("000123"). Staff type "123" (or the
// scanner drops the zeros) and the exact lookup found nothing. These give
// every spelling of the same number, and a loose match for the inventory search.
// Phone keyboards can send Arabic-Indic digits (٠١٢…) or slip invisible
// direction marks in front of a number typed in an Arabic field.
function gmCleanCode(v) {
  return String(v || '')
    .replace(/[\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]/g, '')
    .replace(/[\u0660-\u0669]/g, function (d) { return String(d.charCodeAt(0) - 0x0660); })
    .replace(/[\u06F0-\u06F9]/g, function (d) { return String(d.charCodeAt(0) - 0x06F0); })
    .trim();
}
function gmBarcodeVariants(code) {
  var c = gmCleanCode(code);
  var v = [c, c.toUpperCase()];
  if (/^\d+$/.test(c)) {
    var n = c.replace(/^0+/, '') || '0';
    v.push(n);
    for (var L = n.length + 1; L <= 12; L++) v.push(n.padStart(L, '0'));
  }
  return v.filter(function (x, i) { return x && v.indexOf(x) === i; });
}
// A replaced (cancelled) barcode number -> the piece's current barcode, or null.
// Used by the search screens so an old sticker still finds its piece.
async function gmCurrentBarcodeFor(code) {
  var r = await goldmindClient.from('piece_barcode_history').select('new_barcode')
    .eq('store_id', GOLDMIND_STORE_ID).in('old_barcode', gmBarcodeVariants(code)).limit(1).maybeSingle();
  return r.data ? r.data.new_barcode : null;
}
function gmBarcodeMatches(barcode, query) {
  var norm = function (s) { return String(s || '').toLowerCase().replace(/\s+/g, '').replace(/^0+(?=\d)/, ''); };
  var b = String(barcode || '').toLowerCase(), q = gmCleanCode(query).toLowerCase();
  if (!q) return true;
  return norm(b).startsWith(norm(q)) || b.replace(/\s+/g, '').includes(q.replace(/\s+/g, ''));
}

// iPhone Safari zooms the whole page in when a field with text under 16px is
// tapped, and doesn't zoom back out -- the screen then looks cut off on both
// sides. Capping the scale on iOS stops that auto-zoom; iOS still lets people
// pinch-zoom (it ignores maximum-scale for pinch), and Android is untouched.
(function () {
  var ios = /iP(hone|ad|od)/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  if (!ios) return;
  var m = document.querySelector('meta[name="viewport"]');
  if (m && !/maximum-scale/.test(m.content)) m.content += ', maximum-scale=1';
})();

// ---- Photo viewer (any page): gmPhotoViewer(url) shows the photo large over
// the page; ✕, a tap outside it or Esc closes it and you carry on where you were.
// "فتح بصفحة مستقلة" opens it on its own page (from there it can be saved).
function gmPhotoViewer(url) {
  if (!url) return;
  let box = document.getElementById('gm-photo-viewer');
  if (!box) {
    box = document.createElement('div');
    box.id = 'gm-photo-viewer';
    box.className = 'no-print';
    box.setAttribute('role', 'dialog');
    box.setAttribute('aria-label', 'عرض الصورة');
    box.style.cssText = 'position:fixed;inset:0;z-index:10000;background:rgba(0,0,0,.88);display:none;flex-direction:column;align-items:center;justify-content:center;padding:56px 12px 16px';
    box.innerHTML =
      '<button type="button" data-close aria-label="إغلاق" style="position:absolute;top:10px;left:10px;width:44px;height:44px;border-radius:50%;border:0;background:#fff;color:#111;font-size:24px;line-height:44px;cursor:pointer">✕</button>' +
      '<a data-open target="_blank" rel="noopener" style="position:absolute;top:14px;right:12px;height:36px;padding:0 14px;border-radius:18px;background:rgba(255,255,255,.15);color:#fff;font:600 13px system-ui;display:flex;align-items:center;text-decoration:none">فتح بصفحة مستقلة</a>' +
      '<img alt="صورة" style="max-width:100%;max-height:100%;object-fit:contain;border-radius:10px;background:#fff">';
    box.addEventListener('click', e => { if (e.target === box || e.target.closest('[data-close]')) gmClosePhotoViewer(); });
    document.addEventListener('keydown', e => { if (e.key === 'Escape') gmClosePhotoViewer(); });
    document.body.appendChild(box);
  }
  box.querySelector('img').src = url;
  box.querySelector('[data-open]').href = url;
  box.style.display = 'flex';
}
function gmClosePhotoViewer() {
  const box = document.getElementById('gm-photo-viewer');
  if (box) box.style.display = 'none';
}

// ---- Date boxes: our own DD/MM/YYYY display on top of the phone's date box.
// The native picker still opens on tap, but the text inside the box is drawn by
// us from the box's value (always YYYY-MM-DD), so an Arabic phone can no longer
// jumble it ("302026/09/"). Works for values typed, picked or set by the page.
(function gmDateBoxes() {
  if (window.__gmDateBoxes) return; window.__gmDateBoxes = true;
  const fmt = v => { const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(v || ''); return m ? m[3] + '/' + m[2] + '/' + m[1] : ''; };
  function sync(el) {
    const o = el.__gmDateOverlay; if (!o) return;
    const t = fmt(el.value);
    o.textContent = t || 'يوم/شهر/سنة';
    // the overlay sits on the box's own fill: paint it in the box's text colour (on dark themes the box
    // is dark inside a light panel, so inheriting the panel's colour left dark-on-dark, بشار 2026-11-18)
    el.classList.remove('gm-date-native');
    const ink = getComputedStyle(el).color;
    el.classList.add('gm-date-native');
    o.style.color = t ? ink : '#9a9a9a';
  }
  function setup(el) {
    if (el.__gmDateOverlay || el.type !== 'date' || el.hasAttribute('data-gm-date')) return;
    const cs = getComputedStyle(el);
    const wrap = document.createElement('span');
    wrap.style.cssText = 'position:relative;display:' + (cs.display === 'inline' || cs.display === 'inline-block' ? 'inline-block' : 'block') + ';' +
      (el.classList.contains('w-full') || cs.display === 'block' ? 'width:100%;' : '');
    el.parentNode.insertBefore(wrap, el);
    wrap.appendChild(el);
    const o = document.createElement('span');
    o.className = 'gm-date-overlay';
    o.setAttribute('aria-hidden', 'true');
    o.style.cssText = 'position:absolute;inset:0;display:flex;align-items:center;pointer-events:none;direction:ltr;unicode-bidi:isolate;' +
      'justify-content:center;padding:0 26px;font:inherit;font-size:' + cs.fontSize + ';color:inherit;white-space:nowrap;overflow:hidden';
    wrap.appendChild(o);
    el.__gmDateOverlay = o;
    el.classList.add('gm-date-native');
    el.addEventListener('input', () => sync(el));
    el.addEventListener('change', () => sync(el));
    el.addEventListener('click', () => { try { el.showPicker && el.showPicker(); } catch (e) { /* not allowed here */ } });
    sync(el);
  }
  // values set by page code (el.value = '2026-09-30') update the display too
  const desc = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
  Object.defineProperty(HTMLInputElement.prototype, 'value', {
    configurable: true, enumerable: desc.enumerable,
    get() { return desc.get.call(this); },
    set(v) { desc.set.call(this, v); if (this.__gmDateOverlay) sync(this); }
  });
  // six :not()s: themes paint every input's text with !important (beige marble's (0,7,2) beat the old three);
  // on Android the date's own text then showed under the overlay — two dates on top of each other (بشار 2026-11-27)
  const st = document.createElement('style');
  st.textContent = 'html:root body input.gm-date-native.gm-date-native:not(.gm-z):not(.gm-z):not(.gm-z):not(.gm-z):not(.gm-z):not(.gm-z){color:transparent !important;-webkit-text-fill-color:transparent !important;caret-color:transparent}' +
    'input.gm-date-native::-webkit-datetime-edit{color:transparent !important}' +
    'input.gm-date-native::-webkit-calendar-picker-indicator{opacity:.7;cursor:pointer}';
  (document.head || document.documentElement).appendChild(st);
  const scan = root => (root.querySelectorAll ? root.querySelectorAll('input[type=date]') : []).forEach(setup);
  const start = () => {
    scan(document);
    new MutationObserver(ms => ms.forEach(m => m.addedNodes.forEach(n => {
      if (n.nodeType !== 1) return;
      if (n.matches && n.matches('input[type=date]')) setup(n); else scan(n);
    }))).observe(document.body, { childList: true, subtree: true });
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
})();

// -----------------------------------------------------------------------
// Number boxes: no up/down arrows, and the mouse wheel never changes the
// number (scrolling the page over a focused box used to silently change it).
// -----------------------------------------------------------------------
(function () {
  const style = document.createElement('style');
  style.textContent = 'input[type=number]::-webkit-inner-spin-button,input[type=number]::-webkit-outer-spin-button{-webkit-appearance:none;margin:0}' +
    'input[type=number]{-moz-appearance:textfield;appearance:textfield}';
  document.head.appendChild(style);
  // wheel over the focused number box: drop focus so the wheel scrolls the page instead
  document.addEventListener('wheel', function (e) {
    const el = document.activeElement;
    if (el && el.type === 'number' && e.target === el) el.blur();
  }, { passive: true });
})();

// ===== design study 2026-11-10 =====
(function () {
  var st = document.createElement('style');
  st.textContent =
    // one look for the main action on every screen
    '.gm-cta{position:relative;overflow:hidden;background:linear-gradient(125deg,#7a5a16 0%,#c89a3c 18%,#f6e2a6 30%,#d4a64a 42%,#8a6a1f 58%,#e2bd67 76%,#fff0bf 88%,#b58a33 100%)!important;background-size:220% 220%!important;color:#2A1F08!important;border:0!important;box-shadow:0 6px 16px -6px rgba(122,90,22,.55),inset 0 1px 0 rgba(255,255,255,.55)!important}';
    // data pages: the big logo behind the content is much fainter
  document.head.appendChild(st);
  if (!/(^|\/)(index-ar|login-entry-ar|login-2fa-ar|landing-ar)\.html/.test(location.pathname)) document.documentElement.classList.add('gm-data-page');
})();

// ===== Gloss colours (بشار, 2026-11-10): no flat red/green/blue/yellow — words, icons, chips,
// buttons and cards use gradient, shiny colours. Screen only: print pages and PDF captures
// (html2canvas cannot draw gradient text) get the plain colours back via html.gm-plain.
(function () {
  var root = document.documentElement;
  if (/print/i.test(location.pathname)) return;
  root.classList.add('gm-gloss');
  // PDF export: switch the gloss off while html2canvas draws the page
  var h2c;
  try {
    Object.defineProperty(window, 'html2canvas', { configurable: true, get: function () { return h2c; }, set: function (fn) {
      h2c = typeof fn !== 'function' ? fn : function () {
        root.classList.add('gm-plain');
        var p = fn.apply(this, arguments);
        var off = function () { root.classList.remove('gm-plain'); };
        if (p && p.then) p.then(off, off); else off();
        return p;
      };
    } });
  } catch (e) { /* already defined: leave it */ }

  var G = 'html.gm-gloss:not(.gm-plain) ';
  var noBg = ':not([class*="bg-"]):not(input):not(select):not(textarea):not(option)';
  // gradient "inks": one calm wave per word/number — dark at both ends, a soft shine in the middle
  // (بشار 2026-11-15: the old off-centre bright glint hurt the eyes)
  var wave = function (edge, mid, shine) { return 'linear-gradient(110deg,' + edge + ' 0%,' + mid + ' 32%,' + shine + ' 50%,' + mid + ' 68%,' + edge + ' 100%)'; };
  var INK = {
    // each wave reads --gmi-* first, so a dark theme («الرخام الأسود») can brighten them for dark cards
    green:  wave('var(--gmi-g1,#065F46)', 'var(--gmi-g2,#0A7356)', 'var(--gmi-g3,#178F6C)'),
    red:    wave('var(--gmi-r1,#8E1330)', 'var(--gmi-r2,#A91D3A)', 'var(--gmi-r3,#C8394F)'),
    blue:   wave('var(--gmi-b1,#1E3A8A)', 'var(--gmi-b2,#284BAE)', 'var(--gmi-b3,#3F67CC)'),
    amber:  wave('var(--gmi-a1,#7C4A03)', 'var(--gmi-a2,#955C08)', 'var(--gmi-a3,#B57A17)'),
    violet: wave('var(--gmi-v1,#5B21B6)', 'var(--gmi-v2,#6D2BD0)', 'var(--gmi-v3,#8A4DE6)'),
    accent: wave('var(--gm-secondary)', 'var(--gm-accent)', 'color-mix(in srgb,var(--gm-accent) 75%,#fff)'),
    ink:    wave('var(--gmi-i1,var(--gm-primary))', 'var(--gmi-i2,color-mix(in srgb,var(--gm-primary) 85%,var(--gm-accent)))', 'var(--gmi-i3,color-mix(in srgb,var(--gm-primary) 65%,var(--gm-accent)))')
  };
  var INKED = [];
  // table cells usually carry their own background, so the ink goes on what is inside them;
  // !important so a page's own `background:` shorthand can't leave the text invisible.
  // The wave is sized to the words themselves (--gm-ink-x/-w, measured below), not the whole block width.
  var text = function (sel, ink) {
    INKED.push(sel);
    return sel.split(',').map(function (s) { s = s.trim(); return G + s + noBg + ':not(td):not(th),' + G + s + ':is(td,th) > :not([class*="bg-"])'; }).join(',') +
      '{background-image:' + ink + '!important;-webkit-background-clip:text!important;background-clip:text!important;-webkit-text-fill-color:transparent;color:transparent;' +
      'background-size:var(--gm-ink-w,100%) 100%!important;background-position:var(--gm-ink-x,0px) 0!important;background-repeat:no-repeat!important}';
  };
  // soft chips / blocks: a tinted gradient with a white reflection on top
  var GLASS = 'linear-gradient(180deg,rgba(255,255,255,.7) 0%,rgba(255,255,255,0) 55%)';
  var chip = function (sel, a, b, line) {
    return sel.split(',').map(function (s) { return G + s.trim(); }).join(',') +
      '{background-image:' + GLASS + ',linear-gradient(135deg,' + a + ' 0%,' + b + ' 100%)!important;' + (line ? 'border-color:' + line + ';' : '') +
      'box-shadow:inset 0 1px 0 rgba(255,255,255,.85),0 1px 2px rgba(0,0,0,.04)}';
  };
  // solid buttons: deep gradient + glossy top half
  var solid = function (sel, a, b) {
    return sel.split(',').map(function (s) { return G + s.trim(); }).join(',') +
      '{background-image:linear-gradient(180deg,rgba(255,255,255,.22) 0%,rgba(255,255,255,.04) 48%,rgba(0,0,0,0) 52%),linear-gradient(135deg,' + a + ' 0%,' + b + ' 100%)!important;' +
      'box-shadow:inset 0 1px 0 rgba(255,255,255,.35),0 6px 14px -8px ' + a + '}';
  };
  var btn = function (cls) { return ['button.' + cls, 'a.' + cls, 'label.' + cls, '[role=button].' + cls, 'span.' + cls + '.rounded-full', '.' + cls + '.rounded-full'].join(','); };
  var css = [
    // the transparent fill is inherited: anything inside a gradient word that has a colour or a
    // background of its own gets its normal fill back (zero specificity, so a gradient rule on it still wins)
    ':where(html.gm-gloss) :where(.text-primary,.text-secondary,.text-success,.text-error,.dc-amt-in,.dc-amt-out,.gm-ink-green,.gm-ink-red,.gm-ink-blue,.gm-ink-amber,.gm-ink-violet,h1,h2) :where(.text-white,.text-on-surface,.text-on-surface-variant,.text-outline,.text-on-primary,.text-on-secondary,[class*="bg-"],button,input,select,textarea){-webkit-text-fill-color:currentColor}',
    // words
    text('.gm-ink-green,.text-success,.text-green-600,.text-green-700,.text-green-800,.text-emerald-700,.text-emerald-800,.text-teal-700', INK.green),
    text('.gm-ink-red,.text-error,.text-red-400,.text-red-600,.text-red-700,.text-red-800,.text-rose-700', INK.red),
    text('.gm-ink-blue,.text-blue-700,.text-indigo-800,.text-sky-700', INK.blue),
    text('.gm-ink-amber,.text-amber-700,.text-amber-800,.text-amber-900,.text-orange-700,.text-yellow-700', INK.amber),
    // hard-coded page colours (inline styles and a few page classes)
    text('.dc-amt-in', INK.green),
    text('.dc-amt-out', INK.red),
    chip('.dc-tag.ok', '#E6F8EF', '#CDEFE3', ''),
    chip('.dc-tag.warn', '#FFF3DA', '#F9DFA6', ''),
    text('.gm-ink-violet,.text-purple-700,.text-violet-700', INK.violet),
    text('.text-secondary,h1:not([class*="text-"]),h2:not([class*="text-"])', INK.accent),
    text('.text-primary', INK.ink),
    // icons with no colour of their own, on light cards, take the theme's metal
    text(':is(.bg-surface-container-lowest,.bg-surface-container-low,.bg-white) > .material-symbols-outlined:not([class*="text-"]),:is(.bg-surface-container-lowest,.bg-surface-container-low,.bg-white) > :not(button) > .material-symbols-outlined:not([class*="text-"])', INK.accent),
    // chips and soft blocks
    chip('.bg-green-50,.bg-emerald-50', '#ECFDF5', '#D5F5EC', '#A7E8D2'),
    chip('.bg-green-100,.bg-success-container', '#DDF8EC', '#C3EEE2', '#9FDDC8'),
    chip('.bg-red-50', '#FFF1F2', '#FFE0DB', '#FBC6C0'),
    chip('.bg-red-100,.bg-error-container', '#FFE4E6', '#FECDCA', '#F9AFAA'),
    chip('.bg-amber-50,.bg-yellow-50', '#FFF8E6', '#FCEBC2', '#F2D795'),
    chip('.bg-amber-100,.bg-amber-200', '#FFF0C8', '#F8DC97', '#E9C46A'),
    chip('.bg-blue-50,.bg-sky-50', '#EEF2FF', '#DDEBFF', '#BFD3FB'),
    chip('.bg-secondary-container', 'color-mix(in srgb,var(--gm-accent) 14%,#fff)', 'color-mix(in srgb,var(--gm-accent) 30%,#fff)', ''),
    // solid buttons and badges
    solid(btn('bg-primary'), 'var(--gm-primary)', 'color-mix(in srgb,var(--gm-primary) 62%,var(--gm-accent))'),
    solid(btn('bg-secondary'), 'var(--gm-secondary)', 'color-mix(in srgb,var(--gm-accent) 80%,#fff)'),
    solid(btn('bg-error') + ',' + btn('bg-red-600'), '#9F1239', '#F43F5E'),
    solid(btn('bg-success') + ',' + btn('bg-green-600') + ',' + btn('bg-green-700'), '#047857', '#14B8A6'),
    solid(btn('bg-amber-600'), '#9A5B05', '#E8B53A'),
    // cards: pearl gradient, a faint diagonal reflection and a gold-tinted shadow
    G + ':is(.rounded-xl,.rounded-2xl,.rounded-3xl):is(.bg-surface-container-lowest,.bg-white):not(input):not(select):not(textarea):not(button)' +
      '{background-image:linear-gradient(112deg,rgba(255,255,255,0) 0 34%,rgba(255,255,255,.65) 40%,rgba(255,255,255,0) 47%),linear-gradient(160deg,#fff 0%,color-mix(in srgb,var(--gm-surface-low,#EFE7D2) 38%,#fff) 100%);' +
      'box-shadow:inset 0 1px 0 #fff,0 1px 2px rgba(0,0,0,.04),0 4px 10px -8px color-mix(in srgb,var(--gm-accent) 60%,transparent)}',
    // selected options (radio/checkbox chips, tabs) shine in the theme's metal
    G + ':is(label,button)[class*="has-[:checked]"]:has(:checked),' + G + '[aria-selected="true"]:not(option),' + G + '[aria-pressed="true"]' +
      '{background-image:' + GLASS + ',linear-gradient(135deg,color-mix(in srgb,var(--gm-accent) 22%,#fff),color-mix(in srgb,var(--gm-accent) 42%,#fff))!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.9),0 0 0 1px color-mix(in srgb,var(--gm-accent) 55%,transparent);color:#1F1A12!important}',
    // the shine is light, so the words on it are black (a dark tile's cream text vanished on it — بشار 2026-11-14)
    G + ':is(label,button)[class*="has-[:checked]"]:has(:checked) :is(span,b,strong,small,em,i:not(.material-symbols-outlined)),' + G + '[aria-selected="true"]:not(option) :is(span,b,strong,small,em),' + G + '[aria-pressed="true"] :is(span,b,strong,small,em)' +
      '{color:#1F1A12!important;-webkit-text-fill-color:#1F1A12!important;background-image:none!important}',
    // a slow wave across page titles and the main action
  ].join('\n');
  css = '@media screen{' + css + '}';
  var st = document.createElement('style');
  st.id = 'gm-gloss';
  st.textContent = css;
  (document.head || root).appendChild(st);

  // A block element (a <p> or <div> holding a number) is as wide as the card, so the wave would be
  // stretched over the empty space and the number only got a slice of it. Fit the wave to the text box.
  var SEL = INKED.join(',');
  var fitOne = function (el) {
    if (/^inline/.test(getComputedStyle(el).display)) return; // inline boxes already hug their text
    var r = document.createRange(); r.selectNodeContents(el);
    var t = r.getBoundingClientRect(), b = el.getBoundingClientRect();
    if (!t.width || !b.width) return;
    // letters such as the Arabic alif reach a little past the text box: give the wave a margin on both sides
    var pad = Math.ceil(parseFloat(getComputedStyle(el).fontSize) * .3) || 4;
    el.style.setProperty('--gm-ink-x', Math.round(t.left - b.left - el.clientLeft - pad) + 'px');
    el.style.setProperty('--gm-ink-w', Math.ceil(t.width + 2 * pad) + 'px');
  };
  var queued = 0;
  var fitAll = function () {
    queued = 0;
    if (!document.body) return;
    document.querySelectorAll(SEL).forEach(function (el) {
      if (/^T[DH]$/.test(el.tagName)) Array.prototype.forEach.call(el.children, fitOne); else fitOne(el);
    });
  };
  var queue = function () { if (!queued) queued = requestAnimationFrame(fitAll); };
  var start = function () {
    queue();
    new MutationObserver(queue).observe(document.body, { childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ['class'] });
    addEventListener('resize', queue);
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(queue);
  };
  if (document.body) start(); else document.addEventListener('DOMContentLoaded', start);
})();

// Clickable table rows (بشار 2026-11-16): on hover the row keeps its own colours (no light fill that
// hides light text on dark themes) and lifts out a little with a gold edge, so it reads as "open me".
(function () {
  var st = document.createElement('style');
  st.id = 'gm-row-lift';
  st.textContent = 'tr.gm-lift{transition:transform .18s ease,box-shadow .18s ease;transform-origin:center}' +
    '@media (hover:hover){tr.gm-lift:hover{transform:scale(1.012) translateY(-1px);position:relative;z-index:1;' +
    'box-shadow:0 10px 24px -8px rgba(0,0,0,.45),inset 0 0 0 1.5px var(--gm-primary,#D4AF37)}}' +
    'tr.gm-lift:active{transform:scale(.996)}' +
    '@media (prefers-reduced-motion:reduce){tr.gm-lift,tr.gm-lift:hover{transition:none;transform:none}}';
  (document.head || document.documentElement).appendChild(st);
})();

/* ===== Shared donut (بشار 2026-11-21): a progress ring for the inventory count today, reusable elsewhere.
   gmDonut(pct 0–100, big centre text, small line under it) → SVG markup string. Colours follow the theme. ===== */
function gmDonut(pct, center, sub) {
  var p = Math.max(0, Math.min(100, Number(pct) || 0)), r = 52, c = 2 * Math.PI * r;
  var esc = function (s) { return String(s == null ? '' : s).replace(/[&<>"]/g, function (ch) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[ch]; }); };
  return '<svg class="gm-donut" viewBox="0 0 128 128" role="img" aria-label="' + esc(center + ' ' + (sub || '')) + '">' +
    '<defs><linearGradient id="gmDonutG" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FFE9A8"/><stop offset=".55" stop-color="#D4AF37"/><stop offset="1" stop-color="#9C7A22"/></linearGradient></defs>' +
    '<circle cx="64" cy="64" r="' + r + '" fill="none" stroke="currentColor" stroke-opacity=".14" stroke-width="12"/>' +
    '<circle cx="64" cy="64" r="' + r + '" fill="none" stroke="url(#gmDonutG)" stroke-width="12" stroke-linecap="round" transform="rotate(-90 64 64)"' +
    ' stroke-dasharray="' + (c * p / 100).toFixed(1) + ' ' + c.toFixed(1) + '" style="transition:stroke-dasharray .9s cubic-bezier(.22,1,.36,1)"/>' +
    '<text x="64" y="64" text-anchor="middle" font-size="24" font-weight="800" fill="currentColor" dominant-baseline="middle">' + esc(center) + '</text>' +
    (sub ? '<text x="64" y="88" text-anchor="middle" font-size="10.5" fill="currentColor" fill-opacity=".65">' + esc(sub) + '</text>' : '') + '</svg>';
}

/* ===== Skeleton loading (بشار 2026-11-21): while a page fetches, its «جارِ التحميل...» box shows grey shimmering
   rows shaped like what is coming, in every theme. Pages keep hiding #loading-state exactly as before. ===== */
(function gmSkeletons() {
  var css = '.gm-skel{display:grid;gap:10px;padding:6px 0;text-align:initial}' +
    '.gm-sk-row{display:flex;align-items:center;gap:12px;padding:12px 14px;border-radius:16px;background:var(--gm-surface-lowest,#fff);border:1px solid var(--gm-outline-variant,#E7DFCC)}' +
    '.gm-sk-b{display:block;border-radius:8px;background:linear-gradient(90deg,rgba(140,130,110,.14) 25%,rgba(140,130,110,.28) 37%,rgba(140,130,110,.14) 63%);background-size:400% 100%;animation:gmSk 1.3s ease infinite}' +
    '.gm-sk-c{width:42px;height:42px;border-radius:12px;flex:none}.gm-sk-l{flex:1;display:grid;gap:8px;min-width:0}' +
    '@keyframes gmSk{0%{background-position:100% 50%}100%{background-position:0 50%}}' +
    '@media (prefers-reduced-motion: reduce){.gm-sk-b{animation:none}}';
  function rows(n) {
    var h = '';
    for (var i = 0; i < n; i++) {
      h += '<div class="gm-sk-row"><span class="gm-sk-b gm-sk-c"></span><span class="gm-sk-l"><span class="gm-sk-b" style="height:12px;width:' + (55 + (i * 17) % 35) + '%"></span>' +
        '<span class="gm-sk-b" style="height:10px;width:' + (30 + (i * 11) % 25) + '%"></span></span><span class="gm-sk-b" style="height:14px;width:64px;flex:none"></span></div>';
    }
    return '<div class="gm-skel" role="status" aria-label="جارِ التحميل">' + h + '</div>';
  }
  window.gmSkeletonRows = rows;
  function apply() {
    if (!document.getElementById('gm-skel-css')) { var st = document.createElement('style'); st.id = 'gm-skel-css'; st.textContent = css; document.head.appendChild(st); }
    var boxes = document.querySelectorAll('#loading-state, .dsk-empty, .gmc-empty');
    for (var i = 0; i < boxes.length; i++) {
      var b = boxes[i];
      if (!/^\s*(جارِ|جاري) (ال)?تحميل/.test(b.textContent || '') || b.querySelector('.gm-skel')) continue; // only the plain loading text
      b.classList.remove('py-16', 'text-center');
      b.innerHTML = rows(b.id === 'loading-state' ? 6 : 3);
    }
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', apply); else apply();
})();
