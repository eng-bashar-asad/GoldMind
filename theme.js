// GoldMind shared theming system.
// Each theme sets CSS custom properties on :root. Pages whose Tailwind
// config colors reference these variables (e.g. "primary": "var(--gm-primary)")
// update live when the theme changes — no rebuild/reload needed.

const GOLDMIND_THEMES = {
  'royal-gold': {
    label: 'الذهبي الملكي',
    swatch: ['#FFD700', '#0f232a', '#1e333b'],
    vars: {
      '--gm-bg': '#0f172a',
      '--gm-bg-elevated': '#1e293b',
      '--gm-surface-lowest': '#ffffff',
      '--gm-surface-low': '#f2f4f6',
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
      '--gm-bg-elevated': '#153a40',
      '--gm-surface-lowest': '#ffffff',
      '--gm-surface-low': '#eef5f5',
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
      '--gm-bg-elevated': '#132030',
      '--gm-surface-lowest': '#ffffff',
      '--gm-surface-low': '#eef6f8',
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
      '--gm-bg': '#faf7f0',
      '--gm-bg-elevated': '#ffffff',
      '--gm-surface-lowest': '#ffffff',
      '--gm-surface-low': '#f2ede1',
      '--gm-primary': '#191c1e',
      '--gm-on-primary': '#ffffff',
      '--gm-accent': '#B4955A',
      '--gm-on-accent': '#ffffff',
      '--gm-secondary': '#8A6D1B',
      '--gm-on-surface': '#191c1e',
      '--gm-on-surface-variant': '#5a544a',
      '--gm-outline-variant': '#e3dbc9'
    }
  }
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
