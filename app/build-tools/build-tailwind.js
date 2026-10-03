// Precompiles Tailwind for a folder of bundled pages (the GitHub Pages site or
// the APK's www) and swaps each page's runtime Play CDN script for a static
// stylesheet.
//
// Pages carry different inline `tailwind.config` blocks (22 variants: some
// redefine `primary`, `rounded-xl`, or add font sizes like `text-label-md`), so
// one merged config loses or overrides parts of them. Instead, pages are grouped
// by their exact config + CDN plugins, and each group gets its own CSS built from
// that config, scanning the group's pages plus the shared *.js files (the side
// menu and helpers build markup with classes too).
//
// Usage: node build-tools/build-tailwind.js --dir=../_site
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execFileSync } = require('child_process');

const dirArg = process.argv.find(a => a.startsWith('--dir='));
const dir = path.resolve(process.cwd(), dirArg ? dirArg.slice(6) : '../www');
const appDir = path.resolve(__dirname, '..');
const tmp = fs.mkdtempSync(path.join(require('os').tmpdir(), 'gm-tw-'));

const CDN_RE = /<script src="https:\/\/cdn\.tailwindcss\.com([^"]*)"><\/script>\s*\n?/;
const CFG_RE = /<script id="tailwind-config">([\s\S]*?)<\/script>\s*\n?/;

function readConfig(src) {
  const i = src.indexOf('{', src.indexOf('tailwind.config'));
  let depth = 0;
  for (let j = i; j < src.length; j++) {
    if (src[j] === '{') depth++;
    else if (src[j] === '}' && --depth === 0) return new Function('return ' + src.slice(i, j + 1))();
  }
  throw new Error('unbalanced tailwind.config');
}

const groups = new Map();
for (const file of fs.readdirSync(dir).filter(f => f.endsWith('.html'))) {
  const html = fs.readFileSync(path.join(dir, file), 'utf8');
  const cdn = html.match(CDN_RE);
  if (!cdn) continue;
  const cfgTag = html.match(CFG_RE);
  const cfg = cfgTag ? readConfig(cfgTag[1]) : {};
  const plugins = (cdn[1].match(/plugins=([^&"]*)/) || [, ''])[1].split(',').filter(Boolean).sort();
  const key = crypto.createHash('md5').update(JSON.stringify([cfg, plugins])).digest('hex').slice(0, 8);
  if (!groups.has(key)) groups.set(key, { cfg, plugins, files: [] });
  groups.get(key).files.push(file);
}

const PLUGIN = { forms: '@tailwindcss/forms', 'container-queries': '@tailwindcss/container-queries' };
const sharedJs = path.join(dir, '*.js');
const input = path.join(__dirname, 'input.css');
for (const [key, g] of groups) {
  const config = { ...g.cfg, content: [...g.files.map(f => path.join(dir, f)), sharedJs] };
  const cfgPath = path.join(tmp, key + '.config.js');
  fs.writeFileSync(cfgPath, 'module.exports = ' + JSON.stringify(config) + ';\nmodule.exports.plugins = ['
    + g.plugins.map(p => `require(${JSON.stringify(require.resolve(PLUGIN[p], { paths: [appDir] }))})`).join(',') + '];\n');
  const built = path.join(tmp, key + '.css');
  execFileSync(path.join(appDir, 'node_modules/.bin/tailwindcss'), ['-i', input, '-o', built, '-c', cfgPath, '--minify'], { stdio: 'pipe' });
  // Named by content: a page that starts using a new class gets a new file
  // name, so the service worker's cached copy can't serve stale CSS.
  const css = fs.readFileSync(built);
  const out = 'tw-' + crypto.createHash('md5').update(css).digest('hex').slice(0, 10) + '.css';
  fs.writeFileSync(path.join(dir, out), css);
  for (const file of g.files) {
    const p = path.join(dir, file);
    // Last in <head>, where the Play CDN puts its generated <style>: utilities
    // then win over the page's own <style> rules and theme.js's styles, as before.
    const html = fs.readFileSync(p, 'utf8').replace(CFG_RE, '').replace(CDN_RE, '')
      .replace('</head>', `<link rel="stylesheet" href="${out}">\n</head>`);
    fs.writeFileSync(p, html);
  }
}
fs.rmSync(tmp, { recursive: true, force: true });
const pages = [...groups.values()].reduce((n, g) => n + g.files.length, 0);
console.log(`Tailwind: ${pages} pages -> ${groups.size} stylesheets`);
