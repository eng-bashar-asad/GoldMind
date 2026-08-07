// GoldMind shared theming system.
// Each theme sets CSS custom properties on :root. Pages whose Tailwind
// config colors reference these variables (e.g. "primary": "var(--gm-primary)")
// update live when the theme changes — no rebuild/reload needed.
//
// --gm-bg          = dark hero tone (used only by index-ar.html's body)
// --gm-bg-elevated = light page background (used by all other pages' body)
// --gm-surface-*   = white/near-white card surfaces, same across all pages

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
