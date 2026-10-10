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

  fetch('build-info.json', { cache: 'no-store' })
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
          const m = rel && String(rel.body || '').match(/commit ([0-9a-f]{40})/);
          if (!m) return;
          const releaseSha = m[1];
          if (releaseSha === buildInfo.sha) return; // this phone already has the newest APK
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
  bar.style.cssText = 'position:fixed;top:0;left:0;right:0;z-index:9999;background:#B4955A;color:#fff;' +
    'display:flex;align-items:center;justify-content:space-between;gap:8px;padding:8px 12px;' +
    'font-family:Inter,sans-serif;font-size:12.5px;font-weight:600;direction:rtl;box-shadow:0 2px 8px rgba(0,0,0,.15);';
  bar.innerHTML =
    '<span>يتوفر تحديث جديد للتطبيق</span>' +
    '<span style="display:flex;gap:6px;align-items:center;">' +
      '<a href="' + apkUrl + '" style="background:#fff;color:#7a6222;border-radius:999px;padding:5px 12px;text-decoration:none;font-weight:700;">تنزيل</a>' +
      '<button type="button" style="background:transparent;border:none;color:#fff;font-size:16px;line-height:1;cursor:pointer;padding:2px 4px;">×</button>' +
    '</span>';
  bar.querySelector('button').onclick = function () {
    localStorage.setItem('goldmind_update_dismissed_sha', latestSha);
    bar.remove();
  };
  document.body.prepend(bar);
  document.body.style.paddingTop = (document.body.style.paddingTop ? 'calc(' + document.body.style.paddingTop + ' + 38px)' : '38px');
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
  return out.flatMap(x => {
    if (typeof x !== 'string') return [x];
    const rows = groups.get(x);
    if (rows.length === 1) return rows;
    const net = rows.reduce((s, e) => s + (e.direction === 'in' ? 1 : -1) * Number(e.amount || 0), 0);
    if (Math.abs(net) < 0.005) return [];
    const last = rows[rows.length - 1];
    return [{ ...rows[0], id: last.id, created_at: last.created_at, direction: net > 0 ? 'in' : 'out', amount: Math.round(Math.abs(net) * 100) / 100, merged: rows.length }];
  });
}
// ponytail: quick self-check of the netting rule
console.assert(gmCollapseInvoiceRows([{ id: 1, cm: { invoice_id: 'a' }, currency: 'USD', created_at: '2026-10-01T10:00:00Z', direction: 'out', amount: 1500 },
  { id: 2, cm: { invoice_id: 'a' }, currency: 'USD', created_at: '2026-10-01T10:05:00Z', direction: 'in', amount: 1500 },
  { id: 3, cm: { invoice_id: 'a' }, currency: 'USD', created_at: '2026-10-01T10:05:00Z', direction: 'out', amount: 1700 }]).map(e => e.direction + e.amount).join() === 'out1700', 'gmCollapseInvoiceRows');

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
};

function goldmindApplyTheme(name) {
  const theme = GOLDMIND_THEMES[name] || GOLDMIND_THEMES['warm-ingot'];
  const root = document.documentElement;
  Object.keys(theme.vars).forEach(function (key) {
    root.style.setProperty(key, theme.vars[key]);
  });
  root.setAttribute('data-gm-display-font', theme.displayFont ? '1' : '0');
  root.setAttribute('data-gm-theme', GOLDMIND_THEMES[name] ? name : 'warm-ingot'); // lets page CSS follow the chosen theme
  if (theme.displayFont) gmEnsureDisplayFont();
  root.classList.toggle('gm-light-canvas', !!theme.lightCanvas);
  root.classList.toggle('gm-shimmer', !!theme.shimmer);
  if (theme.shimmer) gmEnsureShimmerStyle();
  localStorage.setItem('goldmind_theme', name);
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
    /* checkboxes/radios: a visible frame, and the tick shows when checked
       (the white background above used to hide both) */
    input[type=checkbox], input[type=radio] {
      border: 1.5px solid var(--gm-outline, #76777d);
      accent-color: var(--gm-primary, #1F1A12);
    }
    input[type=checkbox]:checked, input[type=radio]:checked {
      background-color: var(--gm-primary, #1F1A12);
      border-color: var(--gm-primary, #1F1A12);
    }
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
  if (vp && !/viewport-fit/.test(vp.content)) {
    vp.content = vp.content.replace(/\s*$/, '') + ', viewport-fit=cover';
  }
  const style = document.createElement('style');
  style.textContent = `
    header.sticky.top-0, header.fixed.top-0 {
      padding-top: env(safe-area-inset-top, 0px);
    }
    nav.sticky.bottom-0, nav.fixed.bottom-0,
    div.sticky.bottom-0, div.fixed.bottom-0 {
      padding-bottom: env(safe-area-inset-bottom, 0px);
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
  } catch (e) { /* fall through to hard navigation */ }
  window.location.href = fallbackHref;
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
  sc.src = 'gm-nav.js?v=8';
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
    e.preventDefault();
    e.stopPropagation();
    // "Choose from files" in the desktop camera window (gm-camera.js) goes straight to the gallery.
    if (window.__gmPreferGallery) { window.__gmPreferGallery = false; openInput(input, false); return; }
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
    o.style.color = t ? '' : '#9a9a9a';
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
  const st = document.createElement('style');
  st.textContent = 'input.gm-date-native{color:transparent !important;caret-color:transparent}' +
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
