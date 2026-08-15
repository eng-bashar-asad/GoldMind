// GoldMind shared theming system.
// Each theme sets CSS custom properties on :root. Pages whose Tailwind
// config colors reference these variables (e.g. "primary": "var(--gm-primary)")
// update live when the theme changes — no rebuild/reload needed.
//
// --gm-bg          = dark hero tone (used only by index-ar.html's body)
// --gm-bg-elevated = light page background (used by all other pages' body)
// --gm-surface-*   = white/near-white card surfaces, same across all pages

// Shared HTML-escaping helper. Any value that came from user/DB input
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
      '--gm-outline-variant': '#c6c6cd'
    }
  },
  'deep-teal': {
    label: 'الفيروزي الداكن',
    swatch: ['#C9A227', '#0d2b30', '#153a40'],
    vars: {
      '--gm-bg': '#0d2b30',
      '--gm-bg-elevated': '#0d2b30',
      '--gm-surface-lowest': '#ffffff',
      '--gm-surface-low': '#dcefed',
      '--gm-primary': '#0d2b30',
      '--gm-on-primary': '#ffffff',
      '--gm-accent': '#C9A227',
      '--gm-on-accent': '#0d2b30',
      '--gm-secondary': '#1c6b6b',
      '--gm-on-surface': '#0d2b30',
      '--gm-on-surface-variant': '#3c5457',
      '--gm-outline-variant': '#c7d6d6'
    }
  },
  'night-cyan': {
    label: 'الليلي الفيروزي',
    swatch: ['#00E0EF', '#0a1420', '#132030'],
    vars: {
      '--gm-bg': '#0a1420',
      '--gm-bg-elevated': '#0a1420',
      '--gm-surface-lowest': '#ffffff',
      '--gm-surface-low': '#daedf0',
      '--gm-primary': '#0a1420',
      '--gm-on-primary': '#ffffff',
      '--gm-accent': '#00E0EF',
      '--gm-on-accent': '#0a1420',
      '--gm-secondary': '#8A6D1B',
      '--gm-on-surface': '#0a1420',
      '--gm-on-surface-variant': '#40525e',
      '--gm-outline-variant': '#c3ced4'
    }
  },
  'light-gold': {
    label: 'الفاتح الذهبي',
    swatch: ['#C9A227', '#faf7f0', '#ffffff'],
    vars: {
      '--gm-bg': '#1c1710',
      '--gm-bg-elevated': '#1c1710',
      '--gm-surface-lowest': '#ffffff',
      '--gm-surface-low': '#f0e5cb',
      '--gm-primary': '#191c1e',
      '--gm-on-primary': '#ffffff',
      '--gm-accent': '#B4955A',
      '--gm-on-accent': '#ffffff',
      '--gm-secondary': '#8A6D1B',
      '--gm-on-surface': '#191c1e',
      '--gm-on-surface-variant': '#5a544a',
      '--gm-outline-variant': '#e3dbc9'
    }
  },
  'rose-gold': {
    label: 'الوردي الذهبي',
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
      '--gm-outline-variant': '#e3cdd1'
    }
  },
  'platinum-silver': {
    label: 'الفضي البلاتيني',
    swatch: ['#B9C2CB', '#14181c', '#1e242a'],
    vars: {
      '--gm-bg': '#14181c',
      '--gm-bg-elevated': '#14181c',
      '--gm-surface-lowest': '#ffffff',
      '--gm-surface-low': '#dfe3e7',
      '--gm-primary': '#14181c',
      '--gm-on-primary': '#ffffff',
      '--gm-accent': '#9FA8B0',
      '--gm-on-accent': '#14181c',
      '--gm-secondary': '#5b6670',
      '--gm-on-surface': '#14181c',
      '--gm-on-surface-variant': '#454e56',
      '--gm-outline-variant': '#ccd1d6'
    }
  },
  'emerald': {
    label: 'الزمردي',
    swatch: ['#0F9D58', '#0a1f14', '#123321'],
    vars: {
      '--gm-bg': '#0a1f14',
      '--gm-bg-elevated': '#0a1f14',
      '--gm-surface-lowest': '#ffffff',
      '--gm-surface-low': '#d6ecdc',
      '--gm-primary': '#0a1f14',
      '--gm-on-primary': '#ffffff',
      '--gm-accent': '#0F9D58',
      '--gm-on-accent': '#ffffff',
      '--gm-secondary': '#1c6b3e',
      '--gm-on-surface': '#0a1f14',
      '--gm-on-surface-variant': '#3c5445',
      '--gm-outline-variant': '#c8dccf'
    }
  },
  'royal-purple': {
    label: 'الأرجواني الملكي',
    swatch: ['#8B5CF6', '#1a1024', '#241533'],
    vars: {
      '--gm-bg': '#1a1024',
      '--gm-bg-elevated': '#1a1024',
      '--gm-surface-lowest': '#ffffff',
      '--gm-surface-low': '#e6ddf4',
      '--gm-primary': '#1a1024',
      '--gm-on-primary': '#ffffff',
      '--gm-accent': '#8B5CF6',
      '--gm-on-accent': '#ffffff',
      '--gm-secondary': '#6B46C1',
      '--gm-on-surface': '#1a1024',
      '--gm-on-surface-variant': '#4d4358',
      '--gm-outline-variant': '#d9d0e8'
    }
  },
  'aurum-night': {
    label: 'الذهبي الليلي (Aurum)',
    swatch: ['#f2ca50', '#081425', '#111c2d'],
    vars: {
      '--gm-bg': '#081425',
      '--gm-bg-elevated': '#081425',
      '--gm-surface-lowest': '#ffffff',
      '--gm-surface-low': '#f7edd3',
      '--gm-primary': '#081425',
      '--gm-on-primary': '#ffffff',
      '--gm-accent': '#f2ca50',
      '--gm-on-accent': '#081425',
      '--gm-secondary': '#404756',
      '--gm-on-surface': '#0f1b2e',
      '--gm-on-surface-variant': '#4a5568',
      '--gm-outline-variant': '#ddd6c4'
    }
  },
};

function goldmindApplyTheme(name) {
  const theme = GOLDMIND_THEMES[name] || GOLDMIND_THEMES['royal-gold'];
  const root = document.documentElement;
  Object.keys(theme.vars).forEach(function (key) {
    root.style.setProperty(key, theme.vars[key]);
  });
  localStorage.setItem('goldmind_theme', name);
}

function goldmindLoadSavedTheme() {
  const saved = localStorage.getItem('goldmind_theme') || 'royal-gold';
  goldmindApplyTheme(saved);
  return saved;
}

// Apply immediately on script load (before first paint as much as possible)
goldmindLoadSavedTheme();

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
