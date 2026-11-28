// Builds assistant-knowledge.json (site root, published with the site) for the
// assistant Edge Function, from the user guides (gm-guides.js) and each
// page's <title>. The function fetches it from GitHub Pages.
// Run from the repo root after changing guides or adding pages:
//   node supabase/functions/assistant/build-knowledge.js
// tests/assistant.spec.js fails if assistant-knowledge.json is out of date.
const fs = require('fs'), path = require('path'), vm = require('vm');

const ROOT = path.resolve(__dirname, '../../..');
const OUT = path.join(ROOT, 'assistant-knowledge.json');
// Pages a store user never needs pointed at (admin, auth flow, previews, print-only).
const SKIP = /^(admin-|auth-|login|logo-|landing|voice-lab|index\.html|.*-print|.*print-ar|.*_\d+\.html$)/;

function build() {
  const ctx = { window: {} };
  vm.runInNewContext(fs.readFileSync(path.join(ROOT, 'gm-guides.js'), 'utf8'), ctx);
  const guides = (ctx.window.GM_GUIDES || []).map((g) => ({
    id: g.id, group: g.group, title: g.title, summary: g.summary, keywords: g.keywords, md: g.md.trim(),
  }));
  const pages = fs.readdirSync(ROOT)
    .filter((f) => f.endsWith('.html') && !SKIP.test(f))
    .sort()
    .map((f) => {
      const t = /<title>([\s\S]*?)<\/title>/i.exec(fs.readFileSync(path.join(ROOT, f), 'utf8'));
      return { page: f, title: t ? t[1].replace(/\s+/g, ' ').trim() : '' };
    })
    .filter((p) => p.title);
  return { guides, pages };
}

module.exports = { build, OUT };
if (require.main === module) {
  const k = build();
  fs.writeFileSync(OUT, JSON.stringify(k) + '\n');
  console.log(`assistant-knowledge.json: ${k.guides.length} guides, ${k.pages.length} pages, ${fs.statSync(OUT).size} bytes`);
}
