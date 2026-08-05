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
      '--gm-bg-elevated': '#f7f9fb',
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
      '--gm-bg-elevated': '#f3f8f8',
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
      '--gm-bg-elevated': '#f2f8f9',
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
      '--gm-bg': '#1c1710',
      '--gm-bg-elevated': '#faf7f0',
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
  },
  'rose-gold': {
    label: 'الوردي الذهبي',
    swatch: ['#E8B4B8', '#2b1620', '#3d1f2c'],
    vars: {
      '--gm-bg': '#2b1620',
      '--gm-bg-elevated': '#fdf5f6',
      '--gm-surface-lowest': '#ffffff',
      '--gm-surface-low': '#f7eaeb',
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
      '--gm-bg-elevated': '#f6f7f8',
      '--gm-surface-lowest': '#ffffff',
      '--gm-surface-low': '#eef0f2',
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
      '--gm-bg-elevated': '#f2f9f4',
      '--gm-surface-lowest': '#ffffff',
      '--gm-surface-low': '#e8f5eb',
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
      '--gm-bg-elevated': '#f7f5fb',
      '--gm-surface-lowest': '#ffffff',
      '--gm-surface-low': '#efeaf8',
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
  'sapphire-blue': {
    label: 'الياقوتي الأزرق',
    swatch: ['#3B82F6', '#0a1628', '#0f2138'],
    vars: {
      '--gm-bg': '#0a1628',
      '--gm-bg-elevated': '#f3f7fc',
      '--gm-surface-lowest': '#ffffff',
      '--gm-surface-low': '#e9f0fa',
      '--gm-primary': '#0a1628',
      '--gm-on-primary': '#ffffff',
      '--gm-accent': '#3B82F6',
      '--gm-on-accent': '#ffffff',
      '--gm-secondary': '#B4955A',
      '--gm-on-surface': '#0a1628',
      '--gm-on-surface-variant': '#3d4c5e',
      '--gm-outline-variant': '#c9d6e6'
    }
  },
  'ruby-red': {
    label: 'الياقوتي الأحمر',
    swatch: ['#C0392B', '#210a0a', '#2e1010'],
    vars: {
      '--gm-bg': '#210a0a',
      '--gm-bg-elevated': '#fbf3f2',
      '--gm-surface-lowest': '#ffffff',
      '--gm-surface-low': '#f7e6e4',
      '--gm-primary': '#210a0a',
      '--gm-on-primary': '#ffffff',
      '--gm-accent': '#C0392B',
      '--gm-on-accent': '#ffffff',
      '--gm-secondary': '#B4955A',
      '--gm-on-surface': '#210a0a',
      '--gm-on-surface-variant': '#5a3d3a',
      '--gm-outline-variant': '#e6d0cd'
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
