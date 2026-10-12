// Audit only (UI_OUT=dir): text that is nearly invisible on its background, per dark theme.
const { test } = require('@playwright/test');
const fs = require('fs'), path = require('path');
const { install } = require('./fake-backend');
test.skip(!process.env.UI_OUT, 'audit only');
const pages = process.env.PAGES ? process.env.PAGES.split(',') : fs.readdirSync(path.join(__dirname, '..')).filter(f => /\.html$/.test(f) && !/_\d+\.html$/.test(f));
for (const th of ['cosmic-steel', 'velvet-wine']) for (const f of pages) test(th + ' ' + f, async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await install(page, { generic: true, realCdn: true });
  await page.addInitScript(t => { try { localStorage.setItem('goldmind_theme', t); } catch (e) {} }, th);
  page.on('dialog', d => d.dismiss().catch(() => {}));
  await page.goto('/' + f).catch(() => {}); await page.waitForTimeout(3000);
  const bad = await page.evaluate(() => {
    const rgb = s => { const m = (s || '').match(/[\d.]+/g); if (!m) return null; const v = m.map(Number); return /color\(/.test(s) ? [v[0] * 255, v[1] * 255, v[2] * 255, v[3]] : v; };
    const lum = c => { const a = c.slice(0, 3).map(v => { v /= 255; return v <= .03928 ? v / 12.92 : Math.pow((v + .055) / 1.055, 2.4); }); return .2126 * a[0] + .7152 * a[1] + .0722 * a[2]; };
    const bgOf = el => { for (let e = el; e; e = e.parentElement) { const cs = getComputedStyle(e); if (cs.backgroundImage && cs.backgroundImage !== 'none') return null; const c = rgb(cs.backgroundColor); if (c && (c[3] === undefined || c[3] > .5)) return c; } return [255, 255, 255]; };
    const out = [];
    document.querySelectorAll('body *').forEach(el => {
      if (!el.offsetParent && getComputedStyle(el).position !== 'fixed') return;
      const own = [...el.childNodes].some(n => n.nodeType === 3 && n.textContent.trim()) || /^(INPUT|SELECT|TEXTAREA)$/.test(el.tagName);
      if (!own) return;
      const cs = getComputedStyle(el); if (cs.visibility === 'hidden' || +cs.opacity < .3) return;
      const fg = rgb(cs.color), bg = bgOf(el); if (!fg || !bg) return;
      const L1 = lum(fg), L2 = lum(bg), r = (Math.max(L1, L2) + .05) / (Math.min(L1, L2) + .05);
      if (r < 1.6) out.push({ tag: el.tagName, id: el.id, cls: String(el.className).slice(0, 60), text: (el.innerText || el.value || el.placeholder || '').trim().slice(0, 40), fg: cs.color, ratio: +r.toFixed(2) });
    });
    return out.slice(0, 30);
  });
  if (bad.length) fs.appendFileSync(process.env.UI_OUT + '/contrast.jsonl', JSON.stringify({ th, f, bad }) + '\n');
});
