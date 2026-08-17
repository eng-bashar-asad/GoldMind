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
function gmFormatDateTime(dateInput, opts) {
  return new Date(dateInput).toLocaleString('ar-EG-u-nu-latn', { ...opts, timeZone: gmGetDisplayTimeZone() });
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
      <p class="text-[11px] text-on-surface-variant mb-3">هاد بيغيّر بس كيف تنعرض الأوقات إلك على هالجهاز — مش وقت الحفظ الفعلي بقاعدة البيانات.</p>
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
function gmFormatDualCurrency(amount, store) {
  const base = (store && store.currency) || '';
  const baseStr = gmFormatNumber(amount) + (base ? ' ' + base : '');
  if (!store || !store.secondary_currency || !store.secondary_currency_rate) {
    return baseStr;
  }
  const rate = Number(store.secondary_currency_rate);
  if (!isFinite(rate) || rate <= 0) return baseStr;
  const converted = Number(amount) * rate;
  return baseStr + ' (' + gmFormatNumber(converted) + ' ' + store.secondary_currency + ')';
}

const GOLDMIND_THEMES = {
  'royal-gold': {
    label: 'الذهبي الملكي',
    swatch: ['#FFD700', '#0f232a', '#1e333b'],
    vars: {
      '--gm-bg': '#0f172a',
      '--gm-bg-elevated': '#0f172a',
      '--gm-surface-lowest': '#ffffff',
      '--gm-surface-low': '#eaeef5',
      '--gm-primary': '#000000',
      '--gm-on-primary': '#ffffff',
      '--gm-accent': '#FFD700',
      '--gm-on-accent': '#0f172a',
      '--gm-secondary': '#745a25',
      '--gm-on-surface': '#191c1e',
      '--gm-on-surface-variant': '#45464d',
      '--gm-outline-variant': '#c6c6cd',
      '--gm-avatar-grad': 'linear-gradient(135deg, #745a25 0%, #FFD700 100%)'
    }
  },
  'rose-gold': {
    label: 'الوردي الملكي',
    swatch: ['#E8B4B8', '#2b1620', '#3d1f2c'],
    vars: {
      '--gm-bg': '#2b1620',
      '--gm-bg-elevated': '#2b1620',
      '--gm-surface-lowest': '#ffffff',
      '--gm-surface-low': '#f4dfe1',
      '--gm-primary': '#2b1620',
      '--gm-on-primary': '#ffffff',
      '--gm-accent': '#B76E79',
      '--gm-on-accent': '#ffffff',
      '--gm-secondary': '#9c5a63',
      '--gm-on-surface': '#2b1620',
      '--gm-on-surface-variant': '#5e4249',
      '--gm-outline-variant': '#e3cdd1',
      '--gm-avatar-grad': 'linear-gradient(135deg, #9c5a63 0%, #E8B4B8 100%)'
    }
  },
  'warm-ingot': {
    label: 'المسبوكة الهادئة',
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
  'golden-hour': {
    label: 'غروب الذهب',
    swatch: ['#D4AF37', '#FBF6EA', '#F4ECD6'],
    lightCanvas: true,
    shimmer: true,
    vars: {
      '--gm-bg': '#FBF6EA',
      '--gm-bg-elevated': '#FBF6EA',
      '--gm-surface-lowest': '#FFFFFF',
      '--gm-surface-low': '#F4ECD6',
      '--gm-primary': '#4A403A',
      '--gm-on-primary': '#FBF8F1',
      '--gm-accent': '#D4AF37',
      '--gm-on-accent': '#3c2f00',
      '--gm-secondary': '#8A6A1F',
      '--gm-on-surface': '#211D17',
      '--gm-on-surface-variant': '#6B6355',
      '--gm-outline-variant': '#CBBF9E',
      '--gm-shimmer-grad': 'linear-gradient(120deg, #7a5a12 0%, #d4af37 28%, #fff2b8 50%, #d4af37 72%, #b8860b 100%)',
      '--gm-avatar-grad': 'linear-gradient(135deg, #8A6A1F 0%, #D4AF37 60%, #fff2b8 100%)'
    }
  },
  'midnight-galaxy': {
    label: 'مجرة منتصف الليل',
    swatch: ['#A490C2', '#1c1430', '#241a3d'],
    shimmer: true,
    vars: {
      '--gm-bg': '#1c1430',
      '--gm-bg-elevated': '#1c1430',
      '--gm-surface-lowest': '#ffffff',
      '--gm-surface-low': '#e6e2f5',
      '--gm-primary': '#1c1430',
      '--gm-on-primary': '#ffffff',
      '--gm-accent': '#A490C2',
      '--gm-on-accent': '#1c1430',
      '--gm-secondary': '#4A4E8F',
      '--gm-on-surface': '#1c1430',
      '--gm-on-surface-variant': '#5b4f78',
      '--gm-outline-variant': '#d6cfe8',
      '--gm-shimmer-grad': 'linear-gradient(120deg, #241a3d 0%, #4a4e8f 30%, #d9d2f0 50%, #4a4e8f 70%, #241a3d 100%)',
      '--gm-avatar-grad': 'linear-gradient(135deg, #4A4E8F 0%, #A490C2 100%)'
    }
  },
};

function goldmindApplyTheme(name) {
  const theme = GOLDMIND_THEMES[name] || GOLDMIND_THEMES['royal-gold'];
  const root = document.documentElement;
  Object.keys(theme.vars).forEach(function (key) {
    root.style.setProperty(key, theme.vars[key]);
  });
  root.setAttribute('data-gm-display-font', theme.displayFont ? '1' : '0');
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

// Site-wide font: Times New Roman everywhere except icon glyphs (which are
// rendered via a dedicated icon font — overriding it would turn every icon
// into garbled text instead of a symbol).
(function () {
  const style = document.createElement('style');
  style.textContent = '*:not(.material-symbols-outlined) { font-family: "Times New Roman", Times, serif !important; }';
  document.head.appendChild(style);
})();

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
  const saved = localStorage.getItem('goldmind_font') || 'default';
  goldmindApplyFont(saved);
}


function goldmindLoadSavedTheme() {
  const saved = localStorage.getItem('goldmind_theme') || 'royal-gold';
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
    input:not(.bg-transparent):not(.text-on-background),
    select:not(.bg-transparent):not(.text-on-background),
    textarea:not(.bg-transparent):not(.text-on-background) {
      color: var(--gm-on-surface, #191c1e);
      background-color: var(--gm-surface-lowest, #ffffff);
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
