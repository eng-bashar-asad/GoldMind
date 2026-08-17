// Scans every top-level *.html page for its inline `tailwind.config = {...}`
// block and merges all of their theme.extend.colors / fontFamily into one
// shared config. Used to precompile a single static CSS file for the
// packaged app (see build-static-css.js) instead of shipping the runtime
// Play CDN script, which recompiles Tailwind from scratch on every single
// page load and was a real, measurable source of the app feeling slow.
const fs = require('fs');
const path = require('path');

const repoDir = path.resolve(__dirname, '../..');
const outPath = path.join(__dirname, 'tailwind.config.js');

function extractBalancedObject(src, startIdx) {
  let depth = 0;
  for (let i = startIdx; i < src.length; i++) {
    if (src[i] === '{') depth++;
    else if (src[i] === '}') {
      depth--;
      if (depth === 0) return src.slice(startIdx, i + 1);
    }
  }
  return null;
}

const files = fs.readdirSync(repoDir).filter(f => f.endsWith('.html'));
const mergedColors = {};
const mergedFonts = {};
let parsed = 0;

for (const file of files) {
  const content = fs.readFileSync(path.join(repoDir, file), 'utf8');
  const idx = content.indexOf('tailwind.config');
  if (idx === -1) continue;
  const eq = content.indexOf('=', idx);
  const braceStart = content.indexOf('{', eq);
  if (braceStart === -1) continue;
  const objSrc = extractBalancedObject(content, braceStart);
  if (!objSrc) continue;
  try {
    const cfg = new Function('return ' + objSrc)();
    const extend = cfg && cfg.theme && cfg.theme.extend;
    if (extend && extend.colors) Object.assign(mergedColors, extend.colors);
    if (extend && extend.fontFamily) Object.assign(mergedFonts, extend.fontFamily);
    parsed++;
  } catch (e) {
    console.error('WARN: could not parse tailwind.config in', file, '-', e.message);
  }
}

const config = {
  darkMode: 'class',
  content: [path.join(repoDir, '*.html')],
  theme: { extend: { colors: mergedColors, fontFamily: mergedFonts } }
};

fs.writeFileSync(outPath, 'module.exports = ' + JSON.stringify(config, null, 2) + ';\n');
console.log(`Merged tailwind config from ${parsed}/${files.length} pages -> ${outPath}`);
