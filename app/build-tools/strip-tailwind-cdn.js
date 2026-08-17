// Post-processes every bundled page in app/www: removes the runtime
// Tailwind Play CDN <script> tag and each page's inline
// <script id="tailwind-config">...</script> block, replacing both with a
// <link> to the single precompiled tailwind-built.css (see
// build-static-css.js / merge-tailwind-config.js). Only touches the
// packaged app's copies — the live GitHub Pages site is untouched and
// keeps using the Play CDN as before.
const fs = require('fs');
const path = require('path');

const dirArg = process.argv.find(a => a.startsWith('--dir='));
const wwwDir = dirArg
  ? path.resolve(process.cwd(), dirArg.slice('--dir='.length))
  : path.resolve(__dirname, '../www');
const files = fs.readdirSync(wwwDir).filter(f => f.endsWith('.html'));

let changed = 0;
for (const file of files) {
  const filePath = path.join(wwwDir, file);
  let content = fs.readFileSync(filePath, 'utf8');
  const before = content;

  // Remove the Play CDN script tag (with or without the ?plugins= query)
  content = content.replace(/<script src="https:\/\/cdn\.tailwindcss\.com[^"]*"><\/script>\s*\n?/, '');

  // Remove the inline <script id="tailwind-config">...</script> block
  content = content.replace(/<script id="tailwind-config">[\s\S]*?<\/script>\s*\n?/, '');

  // Insert the static stylesheet right after <head>
  if (content.includes('<link rel="stylesheet" href="tailwind-built.css">')) {
    // already has it somehow, skip re-inserting
  } else if (content.includes('<head>')) {
    content = content.replace('<head>', '<head>\n<link rel="stylesheet" href="tailwind-built.css">');
  }

  if (content !== before) {
    fs.writeFileSync(filePath, content);
    changed++;
  }
}
console.log(`Rewrote ${changed}/${files.length} pages to use tailwind-built.css`);
