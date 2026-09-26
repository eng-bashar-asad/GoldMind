// Makes the packaged app work with no internet: the Supabase library and the
// icon font are served from the app itself instead of a CDN. Only touches the
// bundled copies in app/www (the website keeps using the CDNs).
const fs = require('fs');
const path = require('path');

const www = path.resolve(__dirname, '../www');
const nm = path.resolve(__dirname, '../node_modules');

fs.copyFileSync(path.join(nm, '@supabase/supabase-js/dist/umd/supabase.js'), path.join(www, 'supabase.js'));
fs.mkdirSync(path.join(www, 'material-symbols'), { recursive: true });
for (const f of ['outlined.css', 'material-symbols-outlined.woff2']) {
  fs.copyFileSync(path.join(nm, 'material-symbols', f), path.join(www, 'material-symbols', f));
}

let changed = 0;
for (const file of fs.readdirSync(www).filter(f => f.endsWith('.html'))) {
  const p = path.join(www, file);
  const before = fs.readFileSync(p, 'utf8');
  let html = before.replace(/<script src="https:\/\/cdn\.jsdelivr\.net\/npm\/@supabase\/supabase-js@2[^"]*"><\/script>/g, '<script src="supabase.js"></script>');
  if (/Material\+Symbols\+Outlined/.test(html) && !html.includes('material-symbols/outlined.css')) {
    // first in <head>, so each page's own icon size/style rules still win
    html = html.replace(/<head>/, '<head>\n<link rel="stylesheet" href="material-symbols/outlined.css">');
  }
  if (html !== before) { fs.writeFileSync(p, html); changed++; }
}
console.log(`Localized CDN libraries in ${changed} pages`);
