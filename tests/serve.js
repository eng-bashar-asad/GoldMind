// Tiny static server for the site root (tests only).
const http = require('http'), fs = require('fs'), path = require('path');
const root = path.resolve(__dirname, '..');
const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.json': 'application/json', '.png': 'image/png', '.svg': 'image/svg+xml', '.css': 'text/css' };
http.createServer((req, res) => {
  const file = path.join(root, decodeURIComponent(req.url.split('?')[0]));
  if (!file.startsWith(root) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream' });
  // tests stub the CDN libraries, so their integrity hashes can't match: drop them here only
  if (path.extname(file) === '.html') return res.end(fs.readFileSync(file, 'utf8').replace(/ integrity="sha384-[^"]+"/g, ''));
  fs.createReadStream(file).pipe(res);
}).listen(process.env.PORT || 4173);
